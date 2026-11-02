import {
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { sendPushToUser } from "./push";
import { firestoreTriggerRegion } from "./region";

// ── User search + direct messages ───────────────────────────────────────────
// Anyone can find anyone by name (users can opt out) and start a direct chat.
// Two pieces keep that from leaking data or turning into spam:
//
//   publicProfiles/{uid}  — the only thing search reads: name, photo,
//     verification and rating averages. Mirrored from users/{uid} here, so
//     search can never hand out an email, phone or location.
//   startDirectChat       — the only way a search chat is created. Rooms are
//     `dm_<uid>_<uid>` (same id scheme as worker_message_action.dart) and
//     start as a message *request* the other person accepts or declines,
//     unless the two already know each other (a favorite or a shared gig).
//
// The rules side (firestore.rules) stops clients creating these rooms or
// flipping request fields themselves.

// Same hoisting reason as gigPoints.ts / ratings.ts: setGlobalOptions in
// index.ts runs after this module is evaluated.
const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;

const db = () => getFirestore();

// New requests one person can start per rolling day. Chats with people they
// already know don't count.
const DAILY_REQUEST_LIMIT = 20;
const DAY_MS = 24 * 60 * 60 * 1000;

// Longest prefix stored per word — longer queries are cut to this before
// matching (see user_search_service.dart).
const MAX_PREFIX = 15;

/** Lowercase, accents removed, single-spaced — must match the client. */
export function normalizeName(name: string): string {
  return name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Every prefix of every word, plus prefixes of the full name, so "jos",
 * "vil" and "joshua v" all find "Joshua Villa" with one array-contains.
 */
export function nameSearchKeys(name: string): string[] {
  const full = normalizeName(name);
  if (!full) return [];
  const keys = new Set<string>();
  const addPrefixes = (s: string) => {
    for (let i = 1; i <= Math.min(s.length, MAX_PREFIX); i++) {
      keys.add(s.slice(0, i));
    }
  };
  for (const word of full.split(" ")) addPrefixes(word);
  addPrefixes(full);
  return [...keys];
}

type Data = Record<string, unknown>;

function ratingSummary(v: unknown): { average: number; count: number } | null {
  if (!v || typeof v !== "object") return null;
  const r = v as Data;
  const count = typeof r.count === "number" ? r.count : 0;
  const average = typeof r.average === "number" ? r.average : 0;
  return count > 0 ? { average, count } : null;
}

function isSearchable(user: Data): boolean {
  return user.searchable !== false && user.pendingDeletion !== true;
}

export function publicProfileOf(user: Data): Data {
  const name = typeof user.name === "string" ? user.name.trim() : "";
  return {
    name,
    nameKeys: nameSearchKeys(name),
    photoUrl: typeof user.photoUrl === "string" ? user.photoUrl : null,
    avatarId: user.avatarId ?? null,
    isVerified: user.isVerified === "verified",
    ratingWorker: ratingSummary(user.ratingWorker),
    ratingHost: ratingSummary(user.ratingHost),
    searchable: isSearchable(user) && name.length > 0,
  };
}

function sameProfile(a: Data, b: Data): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

// users/{uid} is written constantly (location, tokens, balances); only a
// change to a mirrored field costs a publicProfiles write.
export const syncPublicProfile = onDocumentWritten(
  { ...OPTS, document: "users/{uid}" },
  async (event) => {
    const { uid } = event.params;
    const ref = db().collection("publicProfiles").doc(uid);
    const after = event.data?.after.data();
    if (!after) {
      await ref.delete();
      return;
    }
    const next = publicProfileOf(after);
    const before = event.data?.before.data();
    // Unchanged mirrored fields skip the write, but only once the profile
    // exists: users from before this function have none, and their first
    // write of any kind (location, online status) has to create it.
    if (
      before &&
      sameProfile(publicProfileOf(before), next) &&
      (await ref.get()).exists
    ) {
      return;
    }
    await ref.set({
      ...next,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
);

// One-off fill for users who existed before syncPublicProfile was deployed.
// Admin only; idempotent, so it can be re-run. Pass {startAfter} with the
// returned cursor until done is true.
export const backfillPublicProfiles = onCall(OPTS, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) throw new HttpsError("unauthenticated", "Sign in required.");
  const adminDoc = (await db().collection("admins").doc(callerUid).get()).data();
  if (!adminDoc || adminDoc.isActive !== true || adminDoc.isPending !== false) {
    throw new HttpsError("permission-denied", "Admins only.");
  }

  const startAfter = request.data?.startAfter;
  let query = db()
    .collection("users")
    .orderBy(FieldPath.documentId())
    .limit(400);
  if (typeof startAfter === "string" && startAfter) {
    query = query.startAfter(startAfter);
  }
  const page = await query.get();
  const batch = db().batch();
  for (const doc of page.docs) {
    batch.set(db().collection("publicProfiles").doc(doc.id), {
      ...publicProfileOf(doc.data()),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  const last = page.docs[page.docs.length - 1];
  return {
    written: page.size,
    cursor: last?.id ?? null,
    done: page.size < 400,
  };
});

export function directRoomId(a: string, b: string): string {
  return `dm_${[a, b].sort().join("_")}`;
}

/** A favorite either way, or a gig chat between them, means they've met. */
async function alreadyConnected(
  uid: string,
  peerUid: string,
  me: Data,
  peer: Data
): Promise<boolean> {
  const favs = (u: Data) =>
    Array.isArray(u.favoriteWorkerIds) ? (u.favoriteWorkerIds as unknown[]) : [];
  if (favs(me).includes(peerUid) || favs(peer).includes(uid)) return true;

  const rooms = await db()
    .collection("chat_rooms")
    .where("participants", "array-contains", uid)
    .get();
  return rooms.docs.some((d) => {
    const room = d.data();
    const participants = (room.participants as unknown[]) ?? [];
    return (
      d.id.startsWith("gig_") &&
      typeof room.gigId === "string" &&
      room.gigId.length > 0 &&
      participants.includes(peerUid)
    );
  });
}

/**
 * Opens (creating if needed) the direct chat with `peerUid` and returns its
 * room id and request state. Errors carry a message the app shows as is.
 */
export const startDirectChat = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const peerUid = request.data?.peerUid;
  if (typeof peerUid !== "string" || !peerUid || peerUid.includes("/")) {
    throw new HttpsError("invalid-argument", "peerUid is required.");
  }
  if (peerUid === uid) {
    throw new HttpsError("invalid-argument", "You can't message yourself.");
  }

  const [meSnap, peerSnap] = await Promise.all([
    db().collection("users").doc(uid).get(),
    db().collection("users").doc(peerUid).get(),
  ]);
  const me = meSnap.data();
  const peer = peerSnap.data();
  if (!me) throw new HttpsError("failed-precondition", "Your profile is missing.");
  if (!peer || peer.pendingDeletion === true) {
    throw new HttpsError("not-found", "This account is no longer available.");
  }

  const blocked = (u: Data) =>
    Array.isArray(u.blockedUsers) ? (u.blockedUsers as unknown[]) : [];
  if (blocked(peer).includes(uid) || blocked(me).includes(peerUid)) {
    throw new HttpsError(
      "permission-denied",
      "You can't message this person."
    );
  }

  const roomId = directRoomId(uid, peerUid);
  const roomRef = db().collection("chat_rooms").doc(roomId);
  const existing = await roomRef.get();
  if (existing.exists) {
    const room = existing.data() as Data;
    return {
      roomId,
      // Rooms from before requests existed (favorites) are open chats
      requestStatus: (room.requestStatus as string) ?? "accepted",
      peerName: peer.name ?? "",
    };
  }

  const connected = await alreadyConnected(uid, peerUid, me, peer);
  if (!connected && !isSearchable(peer)) {
    // Opted out of search: reachable only by people they already know
    throw new HttpsError(
      "permission-denied",
      "This person isn't accepting new messages."
    );
  }

  const quotaRef = db().collection("dmQuota").doc(uid);
  const requestStatus = connected ? "accepted" : "pending";
  const myName = typeof me.name === "string" ? me.name : "";
  const peerName = typeof peer.name === "string" ? peer.name : "";

  await db().runTransaction(async (tx) => {
    const [roomNow, quotaSnap] = await Promise.all([
      tx.get(roomRef),
      tx.get(quotaRef),
    ]);
    if (roomNow.exists) return;

    if (!connected) {
      const quota = quotaSnap.data() ?? {};
      const now = Date.now();
      const windowStart =
        quota.windowStart instanceof Timestamp
          ? quota.windowStart.toMillis()
          : 0;
      const fresh = now - windowStart >= DAY_MS;
      const count = fresh ? 0 : Number(quota.count ?? 0);
      if (count >= DAILY_REQUEST_LIMIT) {
        throw new HttpsError(
          "resource-exhausted",
          "You've sent a lot of new message requests today. Try again tomorrow."
        );
      }
      tx.set(quotaRef, {
        windowStart: fresh
          ? Timestamp.fromMillis(now)
          : quota.windowStart,
        count: count + 1,
      });
    }

    tx.create(roomRef, {
      gigId: "",
      // Listed and opened like the other one-to-one chats
      isGigChat: true,
      isDirect: true,
      participants: [uid, peerUid],
      sendTo: peerName,
      createdByUid: uid,
      createdByName: myName,
      subject: "Direct message",
      status: "open",
      requestStatus,
      requestedBy: uid,
      requestTo: peerUid,
      lastMessage: "",
      lastMessageSender: "",
      lastMessageSenderId: "",
      lastMessageAt: null,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return { roomId, requestStatus, peerName };
});

// Tells the person who asked that they can now chat.
export const onMessageRequestAccepted = onDocumentUpdated(
  { ...OPTS, document: "chat_rooms/{roomId}" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.requestStatus !== "pending" || after.requestStatus !== "accepted") {
      return;
    }
    const requester = after.requestedBy as string | undefined;
    if (!requester) return;
    const accepterName = (after.sendTo as string) || "Someone";
    await sendPushToUser(requester, {
      title: accepterName,
      body: "Accepted your message request",
      channelId: "gig_chat_v2",
      data: {
        type: "chat_message",
        roomId: event.params.roomId,
        gigId: "",
        peerUid: (after.requestTo as string) ?? "",
        peerName: accepterName,
      },
    });
  }
);
