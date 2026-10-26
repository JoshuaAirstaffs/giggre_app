import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { firestoreTriggerRegion } from "./region";

// ── Exchange rates (USD base) ──────────────────────────────────────────────
// Gig Points / Gig Wallet settings (conversion rates, min/max/daily limits)
// are entered in USD. A wallet holds its own currency (PHP for users located
// in the Philippines, USD otherwise), so amounts are converted with:
//
//   general_config/fx_rates {
//     base: "USD",
//     rates:    { USD: 1, PHP: 56.12 }   live, fetched by refreshFxRates
//     override: { PHP: 56.00 | null }    optional admin override (wins)
//     source, fetchedAt, updatedAt
//   }
//
// The live rate is fetched every 6 hours (Frankfurter, ECB reference rates;
// fallback open.er-api.com — both keyless). Every request locks the rate it
// used, so later rate changes never alter a pending or past request.

const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;
const db = () => admin.firestore();
const FX_DOC = () => db().collection("general_config").doc("fx_rates");
export const SUPPORTED = ["USD", "PHP"] as const;

export interface Fx {
  /** Units of the currency per 1 USD, after any admin override. */
  rates: Record<string, number>;
  fetchedAt: Date | null;
  source: string | null;
}

const pos = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? v : null);

/** Effective rates: override ?? live. Throws if a needed rate is missing. */
export async function loadFx(): Promise<Fx> {
  const d = (await FX_DOC().get()).data() ?? {};
  const live = (d.rates ?? {}) as Record<string, unknown>;
  const over = (d.override ?? {}) as Record<string, unknown>;
  const rates: Record<string, number> = { USD: 1 };
  for (const c of SUPPORTED) {
    const r = pos(over[c]) ?? pos(live[c]);
    if (r) rates[c] = r;
  }
  return { rates, fetchedAt: (d.fetchedAt as admin.firestore.Timestamp | undefined)?.toDate() ?? null, source: d.source ?? null };
}

/** Units of [ccy] per 1 USD. Unsupported currencies are treated as USD. */
export function perUsd(fx: Fx, ccy: string): number {
  if (ccy === "USD" || !SUPPORTED.includes(ccy as (typeof SUPPORTED)[number])) return 1;
  const r = fx.rates[ccy];
  if (!r) throw new HttpsError("unavailable", `The ${ccy} exchange rate isn't available right now. Try again later.`);
  return r;
}

const round2 = (n: number) => Math.round(n * 100) / 100;
/** USD → ccy, rounded to the cent. */
export const fromUsd = (fx: Fx, usd: number, ccy: string) => round2(usd * perUsd(fx, ccy));
/** Convert between two currencies; rounds DOWN so a conversion never pays out a fraction more. */
export const convertDown = (fx: Fx, amount: number, from: string, to: string) =>
  from === to ? round2(amount) : Math.floor((amount / perUsd(fx, from)) * perUsd(fx, to) * 100 + 1e-9) / 100;

async function fetchJson(url: string): Promise<Record<string, unknown>> {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 10_000);
  try {
    const res = await fetch(url, { signal: ctl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return (await res.json()) as Record<string, unknown>;
  } finally {
    clearTimeout(t);
  }
}

/** Fetch USD→PHP from Frankfurter, falling back to open.er-api.com. */
async function fetchLive(): Promise<{ PHP: number; source: string }> {
  try {
    const j = await fetchJson("https://api.frankfurter.dev/v1/latest?base=USD&symbols=PHP");
    const php = pos((j.rates as Record<string, unknown> | undefined)?.PHP);
    if (php) return { PHP: php, source: `frankfurter (ECB) ${j.date ?? ""}`.trim() };
    throw new Error("no PHP rate");
  } catch (err) {
    logger.warn("[fx] frankfurter failed, trying fallback", { error: String(err) });
  }
  const j = await fetchJson("https://open.er-api.com/v6/latest/USD");
  const php = pos((j.rates as Record<string, unknown> | undefined)?.PHP);
  if (!php) throw new Error("fallback returned no PHP rate");
  return { PHP: php, source: "open.er-api.com" };
}

async function refresh(): Promise<{ PHP: number; source: string }> {
  const live = await fetchLive();
  // Sanity band: ignore a rate that moved more than 20% from the last one.
  const prev = pos(((await FX_DOC().get()).data()?.rates ?? {}).PHP);
  if (prev && Math.abs(live.PHP - prev) / prev > 0.2) {
    throw new Error(`PHP rate ${live.PHP} is >20% away from ${prev}; not saved`);
  }
  await FX_DOC().set({
    base: "USD",
    rates: { USD: 1, PHP: Math.round(live.PHP * 10000) / 10000 },
    source: live.source,
    fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  logger.info("[fx] rates refreshed", live);
  return live;
}

export const refreshFxRates = onSchedule(
  { schedule: "every 6 hours", region: firestoreTriggerRegion(), timeZone: "Asia/Manila" },
  async () => {
    try {
      await refresh();
    } catch (err) {
      logger.error("[fx] scheduled refresh failed — keeping the last rate", { error: String(err) });
    }
  },
);

/** Admin "Refresh now" button (any active admin). */
export const adminRefreshFxRates = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const a = (await db().collection("admins").doc(uid).get()).data();
  if (!a || a.isActive !== true || a.isPending !== false) throw new HttpsError("permission-denied", "Admins only.");
  try {
    return await refresh();
  } catch (err) {
    throw new HttpsError("unavailable", `Couldn't fetch the live rate: ${String(err)}`);
  }
});
