import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { involvesLiveSupport } from "./liveSupport"; // TEMP: live support
import { sendPushToUser } from "./push";
import { firestoreTriggerRegion } from "./region";
import { containsBlockedTerm, logAutoModeration } from "./wordFilter";

// ── Group chats ─────────────────────────────────────────────────────────────
// Anyone can start a group with people they already have an accepted chat
// with. Groups live in their own collection, not chat_rooms, so app versions
// from before groups never list them as broken one-to-one chats.
//
//   group_chats/{groupId}
//     name, photoUrl, createdBy, admins[], participants[],
//     lastMessage, lastMessageSenderId, lastMessageSenderName, lastMessageAt,
//     lastRead { uid: Timestamp }, mutedBy { uid: true }, createdAt
//   group_chats/{groupId}/messages/{id}
//     senderId, senderName, type (text | image | location | system),
//     text, createdAt, (+ imageUrl / lat,lng for those types)
//
// Membership only changes here; firestore.rules lets members write messages,
// their own lastRead entry and their own mute, nothing else.

const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;
const db = () => getFirestore();

export const MAX_GROUP_MEMBERS = 50;
const MAX_NAME_LENGTH = 50;
// New groups one person can create per rolling day.
const DAILY_GROUP_LIMIT = 10;
const DAY_MS = 24 * 60 * 60 * 1000;

type Data = Record<string, unknown>;

const strList = (v: unknown): string[] =>
  Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) throw new HttpsError("unauthenticated", "Sign in required.");
  return auth.uid;
}

function requireGroupId(v: unknown): string {
  if (typeof v !== "string" || !v || v.includes("/")) {
    throw new HttpsError("invalid-argument", "groupId is required.");
  }
  return v;
}

function cleanName(v: unknown): string {
  const name = typeof v === "string" ? v.replace(/\s+/g, " ").trim() : "";
  if (!name) throw new HttpsError("invalid-argument", "Give the group a name.");
  if (name.length > MAX_NAME_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `Group names can be up to ${MAX_NAME_LENGTH} characters.`
    );
  }
  return name;
}

function cleanUidList(v: unknown, self: string): string[] {
  const uids = [...new Set(strList(v))].filter(
    (u) => u && u !== self && !u.includes("/")
  );
  return uids;
}

// Group photos are uploaded by the app to Firebase Storage first.
function cleanPhotoUrl(v: unknown): string | null {
  if (v === null || v === undefined || v === "") return null;
  if (
    typeof v !== "string" ||
    v.length > 2048 ||
    !v.startsWith("https://firebasestorage.googleapis.com/")
  ) {
    throw new HttpsError("invalid-argument", "That photo can't be used.");
  }
  return v;
}

function nameOf(user: Data | undefined): string {
  return typeof user?.name === "string" && user.name.trim()
    ? user.name.trim()
    : "Someone";
}

/**
 * Everyone `uid` has an accepted one-to-one chat with: gig chats, favorites
 * and accepted direct messages. Pending or declined requests don't count.
 */
async function connectedPeers(uid: string): Promise<Set<string>> {
  const rooms = await db()
    .collection("chat_rooms")
    .where("participants", "array-contains", uid)
    .get();
  const peers = new Set<string>();
  for (const d of rooms.docs) {
    const room = d.data();
    const status = (room.requestStatus as string | undefined) ?? "accepted";
    if (status !== "accepted") continue;
    for (const p of strList(room.participants)) if (p !== uid) peers.add(p);
  }
  return peers;
}

/**
 * Loads the users `adder` wants to put in a group and rejects the whole call
 * if any of them isn't allowed. One clear error beats a silently shorter
 * member list.
 */
async function checkAddable(
  adder: string,
  adderData: Data,
  uids: string[]
): Promise<Map<string, Data>> {
  if (!uids.length) return new Map();
  const [peers, snaps] = await Promise.all([
    connectedPeers(adder),
    db().getAll(...uids.map((u) => db().collection("users").doc(u))),
  ]);
  const myBlocked = strList(adderData.blockedUsers);
  const users = new Map<string, Data>();
  for (const snap of snaps) {
    const user = snap.data();
    if (!user || user.pendingDeletion === true) {
      throw new HttpsError(
        "not-found",
        "One of these accounts is no longer available."
      );
    }
    const name = nameOf(user);
    // TEMP: live support — the support account stays out of groups.
    if (await involvesLiveSupport(snap.id, snap.id)) {
      throw new HttpsError(
        "permission-denied",
        "Giggre Support can't be added to groups."
      );
    }
    if (myBlocked.includes(snap.id) || strList(user.blockedUsers).includes(adder)) {
      throw new HttpsError("permission-denied", `You can't add ${name}.`);
    }
    if (!peers.has(snap.id)) {
      throw new HttpsError(
        "permission-denied",
        `You can only add people you've already chatted with. Message ${name} first.`
      );
    }
    users.set(snap.id, user);
  }
  return users;
}

function systemMessage(text: string): Data {
  return {
    type: "system",
    senderId: "",
    senderName: "",
    text,
    createdAt: FieldValue.serverTimestamp(),
  };
}

function joinNames(names: string[]): string {
  if (names.length <= 1) return names[0] ?? "";
  if (names.length === 2) return `${names[0]} and ${names[1]}`;
  if (names.length === 3) return `${names[0]}, ${names[1]} and ${names[2]}`;
  return `${names[0]}, ${names[1]} and ${names.length - 2} others`;
}

async function loadMember(
  groupId: string,
  uid: string
): Promise<{ ref: FirebaseFirestore.DocumentReference; group: Data }> {
  const ref = db().collection("group_chats").doc(groupId);
  const snap = await ref.get();
  const group = snap.data();
  if (!group || !strList(group.participants).includes(uid)) {
    throw new HttpsError("not-found", "This group isn't available.");
  }
  return { ref, group };
}

function requireAdmin(group: Data, uid: string): void {
  if (!strList(group.admins).includes(uid)) {
    throw new HttpsError(
      "permission-denied",
      "Only group admins can do that."
    );
  }
}

async function userData(uid: string): Promise<Data> {
  const snap = await db().collection("users").doc(uid).get();
  const data = snap.data();
  if (!data) throw new HttpsError("failed-precondition", "Your profile is missing.");
  return data;
}

/** { name, memberUids[], photoUrl? } → { groupId } */
export const createGroup = onCall(OPTS, async (request) => {
  const uid = requireUid(request.auth);
  const name = cleanName(request.data?.name);
  const photoUrl = cleanPhotoUrl(request.data?.photoUrl);
  const memberUids = cleanUidList(request.data?.memberUids, uid);
  if (memberUids.length < 2) {
    throw new HttpsError(
      "invalid-argument",
      "Pick at least 2 people for a group."
    );
  }
  if (memberUids.length + 1 > MAX_GROUP_MEMBERS) {
    throw new HttpsError(
      "invalid-argument",
      `Groups can have up to ${MAX_GROUP_MEMBERS} people.`
    );
  }
  if (await containsBlockedTerm(name)) {
    throw new HttpsError("invalid-argument", "Please choose a different name.");
  }

  const me = await userData(uid);
  await checkAddable(uid, me, memberUids);

  const groupRef = db().collection("group_chats").doc();
  const quotaRef = db().collection("groupQuota").doc(uid);
  const myName = nameOf(me);
  const now = Timestamp.now();

  await db().runTransaction(async (tx) => {
    const quota = (await tx.get(quotaRef)).data() ?? {};
    const windowStart =
      quota.windowStart instanceof Timestamp ? quota.windowStart.toMillis() : 0;
    const fresh = Date.now() - windowStart >= DAY_MS;
    const count = fresh ? 0 : Number(quota.count ?? 0);
    if (count >= DAILY_GROUP_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "You've created a lot of groups today. Try again tomorrow."
      );
    }
    tx.set(quotaRef, {
      windowStart: fresh ? now : quota.windowStart,
      count: count + 1,
    });

    const participants = [uid, ...memberUids];
    tx.create(groupRef, {
      name,
      photoUrl,
      createdBy: uid,
      admins: [uid],
      participants,
      lastMessage: `${myName} created the group`,
      lastMessageSenderId: "",
      lastMessageSenderName: "",
      lastMessageAt: FieldValue.serverTimestamp(),
      // The creator has seen the "created" line; everyone else starts unread.
      lastRead: { [uid]: now },
      mutedBy: {},
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.create(
      groupRef.collection("messages").doc(),
      systemMessage(`${myName} created the group`)
    );
  });

  return { groupId: groupRef.id };
});

/** { groupId, memberUids[] } — admins only. */
export const addGroupMembers = onCall(OPTS, async (request) => {
  const uid = requireUid(request.auth);
  const groupId = requireGroupId(request.data?.groupId);
  const { ref, group } = await loadMember(groupId, uid);
  requireAdmin(group, uid);

  const current = strList(group.participants);
  const adding = cleanUidList(request.data?.memberUids, uid).filter(
    (u) => !current.includes(u)
  );
  if (!adding.length) return { added: 0 };

  const me = await userData(uid);
  const users = await checkAddable(uid, me, adding);

  await db().runTransaction(async (tx) => {
    const fresh = (await tx.get(ref)).data();
    if (!fresh) throw new HttpsError("not-found", "This group isn't available.");
    const now = strList(fresh.participants);
    const toAdd = adding.filter((u) => !now.includes(u));
    if (now.length + toAdd.length > MAX_GROUP_MEMBERS) {
      throw new HttpsError(
        "failed-precondition",
        `Groups can have up to ${MAX_GROUP_MEMBERS} people.`
      );
    }
    if (!toAdd.length) return;
    const text = `${nameOf(me)} added ${joinNames(
      toAdd.map((u) => nameOf(users.get(u)))
    )}`;
    tx.update(ref, {
      participants: FieldValue.arrayUnion(...toAdd),
      lastMessage: text,
      lastMessageSenderId: "",
      lastMessageSenderName: "",
      lastMessageAt: FieldValue.serverTimestamp(),
    });
    tx.create(ref.collection("messages").doc(), systemMessage(text));
  });

  return { added: adding.length };
});

/**
 * Takes `leaving` out of the group. If they were the last admin, the
 * longest-standing remaining member becomes admin; if nobody is left, the
 * group is deleted.
 */
async function removeFromGroup(
  ref: FirebaseFirestore.DocumentReference,
  leaving: string,
  text: string
): Promise<void> {
  let emptied = false;
  await db().runTransaction(async (tx) => {
    const group = (await tx.get(ref)).data();
    if (!group) return;
    const participants = strList(group.participants).filter((u) => u !== leaving);
    let admins = strList(group.admins).filter((u) => u !== leaving);
    if (!participants.length) {
      emptied = true;
      tx.delete(ref);
      return;
    }
    // participants keeps join order, so [0] has been here the longest.
    if (!admins.length) admins = [participants[0]];
    tx.update(ref, {
      participants,
      admins,
      [`lastRead.${leaving}`]: FieldValue.delete(),
      [`mutedBy.${leaving}`]: FieldValue.delete(),
      lastMessage: text,
      lastMessageSenderId: "",
      lastMessageSenderName: "",
      lastMessageAt: FieldValue.serverTimestamp(),
    });
    tx.create(ref.collection("messages").doc(), systemMessage(text));
  });
  if (emptied) await db().recursiveDelete(ref);
}

/** { groupId, memberUid } — admins only. */
export const removeGroupMember = onCall(OPTS, async (request) => {
  const uid = requireUid(request.auth);
  const groupId = requireGroupId(request.data?.groupId);
  const target = request.data?.memberUid;
  if (typeof target !== "string" || !target) {
    throw new HttpsError("invalid-argument", "memberUid is required.");
  }
  if (target === uid) {
    throw new HttpsError("invalid-argument", "Use Leave group instead.");
  }
  const { ref, group } = await loadMember(groupId, uid);
  requireAdmin(group, uid);
  if (!strList(group.participants).includes(target)) return { removed: false };

  const [me, them] = await Promise.all([
    userData(uid),
    db().collection("users").doc(target).get(),
  ]);
  await removeFromGroup(
    ref,
    target,
    `${nameOf(me)} removed ${nameOf(them.data())}`
  );
  return { removed: true };
});

/** { groupId } */
export const leaveGroup = onCall(OPTS, async (request) => {
  const uid = requireUid(request.auth);
  const groupId = requireGroupId(request.data?.groupId);
  const { ref } = await loadMember(groupId, uid);
  const me = await userData(uid);
  await removeFromGroup(ref, uid, `${nameOf(me)} left the group`);
  return { left: true };
});

/** { groupId, name?, photoUrl? } — admins only. */
export const updateGroup = onCall(OPTS, async (request) => {
  const uid = requireUid(request.auth);
  const groupId = requireGroupId(request.data?.groupId);
  const { ref, group } = await loadMember(groupId, uid);
  requireAdmin(group, uid);

  const changes: Data = {};
  const lines: string[] = [];
  const me = await userData(uid);
  if (request.data?.name !== undefined) {
    const name = cleanName(request.data.name);
    if (name !== group.name) {
      if (await containsBlockedTerm(name)) {
        throw new HttpsError("invalid-argument", "Please choose a different name.");
      }
      changes.name = name;
      lines.push(`${nameOf(me)} renamed the group to "${name}"`);
    }
  }
  if (request.data?.photoUrl !== undefined) {
    const photoUrl = cleanPhotoUrl(request.data.photoUrl);
    if (photoUrl !== (group.photoUrl ?? null)) {
      changes.photoUrl = photoUrl;
      lines.push(
        photoUrl
          ? `${nameOf(me)} changed the group photo`
          : `${nameOf(me)} removed the group photo`
      );
    }
  }
  if (!lines.length) return { updated: false };

  const batch = db().batch();
  batch.update(ref, {
    ...changes,
    lastMessage: lines[lines.length - 1],
    lastMessageSenderId: "",
    lastMessageSenderName: "",
    lastMessageAt: FieldValue.serverTimestamp(),
  });
  for (const line of lines) {
    batch.create(ref.collection("messages").doc(), systemMessage(line));
  }
  await batch.commit();
  return { updated: true };
});

/** { groupId, memberUid } — admins only; makes another member an admin. */
export const makeGroupAdmin = onCall(OPTS, async (request) => {
  const uid = requireUid(request.auth);
  const groupId = requireGroupId(request.data?.groupId);
  const target = request.data?.memberUid;
  const { ref, group } = await loadMember(groupId, uid);
  requireAdmin(group, uid);
  if (typeof target !== "string" || !strList(group.participants).includes(target)) {
    throw new HttpsError("invalid-argument", "That person isn't in this group.");
  }
  await ref.update({ admins: FieldValue.arrayUnion(target) });
  return { ok: true };
});

function previewOf(msg: Data): string {
  switch (msg.type) {
    case "image":
      return "📷 Photo";
    case "location":
      return "📍 Location";
    default:
      return typeof msg.text === "string" && msg.text ? msg.text : "New message";
  }
}

/**
 * Every member message: scrub blocked words, stamp the real sender name
 * (the app's copy can't be trusted), update the list preview and notify
 * everyone else who hasn't muted the group.
 */
export const onGroupMessageCreated = onDocumentCreated(
  { ...OPTS, document: "group_chats/{groupId}/messages/{messageId}" },
  async (event) => {
    const msg = event.data?.data();
    if (!msg || msg.type === "system") return;
    const senderId = msg.senderId as string | undefined;
    if (!senderId) return;
    const { groupId } = event.params;

    const [groupSnap, senderSnap] = await Promise.all([
      db().collection("group_chats").doc(groupId).get(),
      db().collection("users").doc(senderId).get(),
    ]);
    const group = groupSnap.data();
    if (!group) return;
    const senderName = nameOf(senderSnap.data());

    const fix: Data = {};
    if (msg.senderName !== senderName) fix.senderName = senderName;
    let text = typeof msg.text === "string" ? msg.text : "";
    if (text && (await containsBlockedTerm(text))) {
      text = "[Message removed for violating community guidelines]";
      fix.text = text;
    }
    if (Object.keys(fix).length) {
      await event.data?.ref.update(fix);
      if (fix.text) {
        await logAutoModeration(
          "group_chats/*/messages",
          event.params.messageId,
          "redacted",
          ["text"]
        );
      }
    }

    const preview = previewOf({ ...msg, text });
    await groupSnap.ref.update({
      lastMessage: preview,
      lastMessageSenderId: senderId,
      lastMessageSenderName: senderName,
      lastMessageAt: msg.createdAt ?? FieldValue.serverTimestamp(),
      // Sending counts as reading.
      [`lastRead.${senderId}`]:
        msg.createdAt ?? FieldValue.serverTimestamp(),
    });

    const mutedBy = (group.mutedBy as Data | undefined) ?? {};
    const recipients = strList(group.participants).filter(
      (u) => u !== senderId && mutedBy[u] !== true
    );
    const results = await Promise.allSettled(
      recipients.map((uid) =>
        sendPushToUser(uid, {
          title: typeof group.name === "string" ? group.name : "Group",
          body: `${senderName}: ${preview}`,
          channelId: "gig_chat_v2",
          data: {
            type: "group_message",
            groupId,
            senderId,
          },
        })
      )
    );
    const failed = results.filter((r) => r.status === "rejected").length;
    if (failed) logger.warn("group push failures", { groupId, failed });
  }
);
