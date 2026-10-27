// Giggre AI support v1 — callable Cloud Function.
//
// - Text chat only, answers from knowledge-base.md
// - 10 messages per hour per user (counter only, no message content stored)
// - Chat history lives on the phone; the app sends recent history each call
// - Returns { answer, escalate, remaining, resetAt }
//
// Requires firebase-admin to be initialized in index.ts (initializeApp()).
// getFirestore() is only called inside the handler, so the import hoisting
// above index.ts's initializeApp() is safe here.

import * as fs from "fs";
import * as path from "path";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import Anthropic from "@anthropic-ai/sdk";

const anthropicKey = defineSecret("ANTHROPIC_API_KEY");

// ---- Settings -------------------------------------------------------------

const MODEL = "claude-haiku-5-5";
const MAX_OUTPUT_TOKENS = 1500;
const LIMIT_PER_WINDOW = 10;
const WINDOW_MS = 60 * 60 * 1000; // 1 hour
const MAX_MESSAGE_CHARS = 1000;
const MAX_HISTORY_MESSAGES = 10;
const MAX_HISTORY_CHARS = 2000; // per message
const ESCALATE_TOKEN = "[ESCALATE]";

// The .md files live in src/ next to this file, but tsc emits this file to
// lib/ and doesn't copy them, so resolve them from src/ (deployed as part of
// the functions source — firebase.json's "ignore" doesn't exclude them).
const SOURCE_DIR = path.join(__dirname, "..", "src");

// Loaded once per instance, not per request.
const SUPPORT_RULES = fs.readFileSync(path.join(SOURCE_DIR, "support-rules.md"), "utf8");
const KNOWLEDGE_BASE = fs.readFileSync(path.join(SOURCE_DIR, "knowledge-base.md"), "utf8");

type Turn = { role: "user" | "assistant"; content: string };

// ---- Input validation -----------------------------------------------------

function cleanMessage(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  if (!text || text.length > MAX_MESSAGE_CHARS) return null;
  return text;
}

// Keep only well-formed turns, newest last, starting with a user turn
// and alternating user/assistant, as the API expects.
function cleanHistory(value: unknown): Turn[] {
  if (!Array.isArray(value)) return [];
  const turns: Turn[] = value
    .filter(
      (m) =>
        m &&
        (m.role === "user" || m.role === "assistant") &&
        typeof m.content === "string" &&
        m.content.trim()
    )
    .map((m) => ({ role: m.role, content: m.content.slice(0, MAX_HISTORY_CHARS) }))
    .slice(-MAX_HISTORY_MESSAGES);

  const result: Turn[] = [];
  for (const turn of turns) {
    const expected = result.length % 2 === 0 ? "user" : "assistant";
    if (turn.role === expected) result.push(turn);
  }
  // The new message is a user turn, so history must end on an assistant turn.
  if (result.length && result[result.length - 1].role === "user") result.pop();
  return result;
}

// ---- Rate limit -----------------------------------------------------------
// Stored at supportAiUsage/{uid}: { windowStart: number, count: number }.
// Only the counter is stored, never message content.
// The window starts with the user's first message and lasts one hour.

async function reserveMessage(
  uid: string
): Promise<{ allowed: boolean; remaining: number; resetAt: number }> {
  const db = getFirestore();
  const ref = db.collection("supportAiUsage").doc(uid);
  const now = Date.now();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    let { windowStart = 0, count = 0 } = (snap.exists ? snap.data() : {}) as {
      windowStart?: number;
      count?: number;
    };

    if (now - windowStart >= WINDOW_MS) {
      windowStart = now;
      count = 0;
    }

    const resetAt = windowStart + WINDOW_MS;
    if (count >= LIMIT_PER_WINDOW) {
      return { allowed: false, remaining: 0, resetAt };
    }

    tx.set(ref, { windowStart, count: count + 1 });
    return { allowed: true, remaining: LIMIT_PER_WINDOW - count - 1, resetAt };
  });
}

// If the AI call fails, give the message back so errors don't use up the limit.
async function refundMessage(uid: string): Promise<void> {
  try {
    await getFirestore()
      .collection("supportAiUsage")
      .doc(uid)
      .update({ count: FieldValue.increment(-1) });
  } catch (err) {
    logger.warn("askSupport: refund failed", { uid });
  }
}

// ---- Function -------------------------------------------------------------

export const askSupport = onCall(
  {
    // Not asia-east2 like the other callables: that's Hong Kong, where the
    // Anthropic API isn't available (every call got 403 "Request not
    // allowed"). Singapore is supported and still close to PH users.
    // Must match the region in the app's support_chat_service.dart.
    region: "asia-southeast1",
    secrets: [anthropicKey],
    // The app doesn't use Firebase App Check yet (no firebase_app_check in
    // pubspec.yaml), so enforcing it here would reject every call. Turn this
    // back on once App Check is set up in the app.
    enforceAppCheck: false,
    // Callables must be publicly invokable (the handler checks req.auth). The
    // first deploy didn't grant this, so Cloud Run rejected every call with
    // 401 before it reached the function; set it so every deploy applies it.
    invoker: "public",
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  async (req) => {
    if (!req.auth) {
      throw new HttpsError("unauthenticated", "Sign in to use Giggre Help.");
    }
    const uid = req.auth.uid;

    const message = cleanMessage(req.data?.message);
    if (!message) {
      throw new HttpsError(
        "invalid-argument",
        `Message must be between 1 and ${MAX_MESSAGE_CHARS} characters.`
      );
    }
    const history = cleanHistory(req.data?.history);
    const mode = req.data?.mode === "host" ? "host" : "worker";

    const quota = await reserveMessage(uid);
    if (!quota.allowed) {
      throw new HttpsError("resource-exhausted", "Hourly message limit reached.", {
        resetAt: quota.resetAt,
      });
    }

    const client = new Anthropic({ apiKey: anthropicKey.value() });

    let response: Anthropic.Message;
    try {
      response = await client.messages.create({
        model: MODEL,
        max_tokens: MAX_OUTPUT_TOKENS,
        // Haiku 5.5 thinks by default, and thinking counts toward max_tokens —
        // it was using up the budget and cutting answers off (or leaving none).
        thinking: { type: "disabled" },
        system: [
          { type: "text", text: SUPPORT_RULES },
          // Everything up to and including this block is cached between calls.
          { type: "text", text: KNOWLEDGE_BASE, cache_control: { type: "ephemeral" } },
          // Changes per user, so it goes after the cached part.
          {
            type: "text",
            text: `The user is currently in ${mode} mode. Prefer answers for ${mode}s unless they ask about the other side.`,
          },
        ],
        messages: [...history, { role: "user", content: message }],
      });
    } catch (err) {
      await refundMessage(uid);
      const apiErr = err as {
        status?: number;
        error?: { error?: { type?: string; message?: string } };
      };
      logger.error("askSupport: Anthropic API error", {
        uid,
        status: apiErr?.status,
        type: apiErr?.error?.error?.type,
        // Anthropic's reason (e.g. which permission is missing) — never
        // contains the user's message.
        reason: apiErr?.error?.error?.message,
      });
      throw new HttpsError("unavailable", "Giggre Help is unavailable right now.");
    }

    const raw = response.content
      .filter((block): block is Anthropic.TextBlock => block.type === "text")
      .map((block) => block.text)
      .join("\n")
      .trim();

    const escalate = raw.includes(ESCALATE_TOKEN);
    const answer = raw.split(ESCALATE_TOKEN).join("").trim();

    // Usage only — no message content is logged.
    logger.info("askSupport: answered", {
      uid,
      mode,
      escalate,
      stopReason: response.stop_reason,
      inputTokens: response.usage?.input_tokens,
      outputTokens: response.usage?.output_tokens,
      cacheReadTokens: response.usage?.cache_read_input_tokens,
      cacheWriteTokens: response.usage?.cache_creation_input_tokens,
    });

    return {
      answer:
        answer ||
        "I couldn't find an answer to that. Tap “Talk to a person” and our team will help.",
      escalate: escalate || !answer,
      remaining: quota.remaining,
      resetAt: quota.resetAt,
    };
  }
);
