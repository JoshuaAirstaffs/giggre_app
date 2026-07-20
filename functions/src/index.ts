import { setGlobalOptions } from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { sendPushToUser, broadcastToAllUsers } from "./push";

admin.initializeApp();

// Matches this project's Firestore database location (asia-east2) so
// triggers don't take a cross-region network hop to reach it.
setGlobalOptions({ region: "asia-east2", maxInstances: 10 });

// Shared secret checked against the x-release-secret header on
// publishVersionAnnouncement, so only trusted deploy tooling can trigger a
// tester-wide broadcast. Set via:
//   firebase functions:secrets:set RELEASE_ANNOUNCE_SECRET --project dev
const releaseAnnounceSecret = defineSecret("RELEASE_ANNOUNCE_SECRET");

// ── Chat messages ───────────────────────────────────────────────────────────
// Mirrors the participant/support-room resolution the client used to do in
// CurrentUserProvider._listenToGigChatMessages.
export const onChatMessageCreated = onDocumentCreated(
  "chat_rooms/{roomId}/messages/{messageId}",
  async (event) => {
    const msg = event.data?.data();
    if (!msg) return;
    const senderId = msg.senderId as string | undefined;
    if (!senderId) return;

    const { roomId } = event.params;
    const roomSnap = await admin
      .firestore()
      .collection("chat_rooms")
      .doc(roomId)
      .get();
    const room = roomSnap.data();
    if (!room) return;

    const participants: string[] = room.participants ?? [];
    const isSupport = room.isSupport === true;

    const recipients = participants.length
      ? participants.filter((p) => p !== senderId)
      : isSupport && room.userId && room.userId !== senderId
      ? [room.userId as string]
      : [];
    if (!recipients.length) return;

    const gigId = (room.gigId as string) ?? "";
    const createdByUid = (room.createdByUid as string) ?? "";
    const createdByName = (room.createdByName as string) ?? "";
    const sendTo = (room.sendTo as string) ?? "Someone";
    const senderName =
      senderId === createdByUid && createdByName ? createdByName : sendTo;
    const text = (msg.text as string) || "New message";

    await Promise.all(
      recipients.map((uid) =>
        sendPushToUser(uid, {
          title: senderName,
          body: text,
          channelId: "gig_chat_v2",
          data: {
            type: "chat_message",
            roomId,
            gigId,
            peerUid: senderId,
            peerName: senderName,
          },
        })
      )
    );
  }
);

// ── Nearby workers (open gig posted) ────────────────────────────────────────
// Mirrors the Haversine distance calc already used client-side in
// quick_gig_matching_service.dart, so "nearby" means the same thing here as
// it does for quick-gig auto-dispatch matching.
const NEARBY_WORKER_RADIUS_KM = 10;

function distanceKm(
  a: admin.firestore.GeoPoint,
  b: admin.firestore.GeoPoint
): number {
  const R = 6371;
  const lat1 = (a.latitude * Math.PI) / 180;
  const lat2 = (b.latitude * Math.PI) / 180;
  const dLat = ((b.latitude - a.latitude) * Math.PI) / 180;
  const dLon = ((b.longitude - a.longitude) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

// A worker's real skill set lives in skillsXP's keys (what the client calls
// _skills — see gig_worker_screen.dart), not the legacy/unused `skills`
// array field. Matching is case/whitespace-insensitive, same as the client's
// own _matchesSkill helper in gig_map_section.dart.
function hasMatchingSkill(
  requiredSkills: string[],
  workerSkillsXP: Record<string, unknown> | undefined
): boolean {
  if (!requiredSkills.length) return true;
  const workerSkills = Object.keys(workerSkillsXP ?? {}).map((s) =>
    s.toLowerCase().trim()
  );
  return requiredSkills.some((s) => workerSkills.includes(s.toLowerCase().trim()));
}

export const onOpenGigPosted = onDocumentCreated(
  "open_gigs/{gigId}",
  async (event) => {
    const gig = event.data?.data();
    if (!gig) return;
    const gigLocation = gig.location as admin.firestore.GeoPoint | undefined;
    if (!gigLocation) return;

    const hostId = gig.hostId as string | undefined;
    const requiredSkills = (gig.requiredSkills as string[] | undefined) ?? [];

    // Only workers who've marked themselves available get pinged, matching
    // the same filter quick-gig auto-dispatch already uses.
    const workersSnap = await admin
      .firestore()
      .collection("users")
      .where("availableForGigs", "==", true)
      .get();

    const nearbyWorkerIds = workersSnap.docs
      .filter((doc) => doc.id !== hostId)
      .filter((doc) => {
        const data = doc.data();
        const geo = data.location as admin.firestore.GeoPoint | undefined;
        if (!geo || distanceKm(gigLocation, geo) > NEARBY_WORKER_RADIUS_KM) {
          return false;
        }
        return hasMatchingSkill(requiredSkills, data.skillsXP);
      })
      .map((doc) => doc.id);

    await Promise.all(
      nearbyWorkerIds.map((uid) =>
        sendPushToUser(uid, {
          title: "New Gig Nearby",
          body: "A new gig matches your skills. Check it out!",
          channelId: "nearby_gigs_v2",
          data: { type: "nearby_gig", gigId: event.params.gigId },
        })
      )
    );
  }
);

// ── New applicant (host side) ───────────────────────────────────────────────
export const onApplicantNotificationCreated = onDocumentCreated(
  "notifications/{notifId}",
  async (event) => {
    const data = event.data?.data();
    if (!data || data.category !== "new_applicant") return;
    const hostUid = data.userId as string | undefined;
    if (!hostUid) return;

    const workerName = (data.workerName as string) ?? "Someone";
    const gigTitle = (data.gigTitle as string) ?? "your gig";
    const gigId = (data.gigId as string) ?? "";

    await sendPushToUser(hostUid, {
      title: "New Application",
      body: `${workerName} applied to your gig "${gigTitle}"`,
      channelId: "gig_applications_v4",
      data: { type: "new_applicant", gigId },
    });
  }
);

// ── Gig offer (worker side) ─────────────────────────────────────────────────
export const onGigOfferCreated = onDocumentCreated(
  "offered_gigs/{gigId}",
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== "offered") return;
    const workerId = data.workerId as string | undefined;
    if (!workerId) return;

    const hostName = (data.hostName as string) ?? "A host";
    const gigTitle = (data.title as string) ?? "a gig";

    await sendPushToUser(workerId, {
      title: "New Gig Offer",
      body: `${hostName} offered you the gig "${gigTitle}"`,
      channelId: "gig_offers_v3",
      data: { type: "gig_offered", gigId: event.params.gigId },
    });
  }
);

// ── Support ticket status change ────────────────────────────────────────────
export const onTicketUpdated = onDocumentUpdated(
  "support_tickets/{ticketId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;

    const uid = after.userId as string | undefined;
    if (!uid) return;

    await sendPushToUser(uid, {
      title: "Ticket Updated",
      body: `Your ticket "${after.subject}" is now ${after.status}`,
      channelId: "ticket_updates_v2",
      data: { type: "ticket_updated" },
    });
  }
);

// ── Verification status (admin decision) ────────────────────────────────────
// Fires when an admin approves/rejects a user's verification request in
// Firestore (users/{uid}.isVerified). Ignores the 'pending'/'unverified'
// transitions the user themselves triggers from VerificationScreen.
export const onVerificationStatusChanged = onDocumentUpdated(
  "users/{uid}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const prevStatus = before.isVerified as string | undefined;
    const newStatus = after.isVerified as string | undefined;
    if (prevStatus === newStatus) return;
    if (newStatus !== "verified" && newStatus !== "rejected") return;

    const uid = event.params.uid;
    const isApproved = newStatus === "verified";
    await sendPushToUser(uid, {
      title: isApproved ? "Verification Approved" : "Verification Rejected",
      body: isApproved
        ? "You're verified! You can now take on gigs that require it."
        : "Your verification request was rejected. Please review and resubmit your documents.",
      channelId: "verification_status_v1",
      data: { type: "verification_status", status: newStatus },
    });
  }
);

// ── Skill request decision (admin decision) ─────────────────────────────────
// Fires when an admin approves/rejects a worker's skill_requests doc
// (see SkillRequestForm._submit). Ignores the initial create ('pending').
export const onSkillRequestStatusChanged = onDocumentUpdated(
  "skill_requests/{requestId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const prevStatus = before.status as string | undefined;
    const newStatus = after.status as string | undefined;
    if (prevStatus === newStatus) return;
    if (newStatus !== "approved" && newStatus !== "rejected") return;

    const uid = after.userId as string | undefined;
    if (!uid) return;

    const skillName = (after.skillName as string) || "your skill";
    const isApproved = newStatus === "approved";
    const message = isApproved
      ? `Your request to add "${skillName}" has been approved.`
      : `Your request to add "${skillName}" was rejected. Check the remarks in your Toolchest.`;

    await Promise.all([
      sendPushToUser(uid, {
        title: isApproved ? "Skill Request Approved" : "Skill Request Rejected",
        body: message,
        channelId: "skill_request_status_v1",
        data: { type: "skill_request_status", status: newStatus },
      }),
      // Surfaced in WorkerNotificationsSheet's activity list (reads
      // notifications where userId == uid && category == 'skill_request').
      admin.firestore().collection("notifications").add({
        userId: uid,
        category: "skill_request",
        request_status: newStatus,
        message,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
    ]);
  }
);

// ── Worker progress milestones (host side) ──────────────────────────────────
// Fires when arrivedAt / workStartedAt / workCompletedAt transitions from
// unset to set, across all three gig collections.
const PROGRESS_MILESTONES: Array<[field: string, title: (n: string) => string, body: (n: string, t: string) => string]> = [
  ["arrivedAt", (n) => `${n} Has Arrived`, (n, t) => `${n} is ready to start "${t}"`],
  ["workStartedAt", (n) => `${n} Started Working`, (n, t) => `${n} is working on "${t}"`],
  ["workCompletedAt", (n) => `${n} Completed the Task`, (n, t) => `${n} finished "${t}" and is awaiting your confirmation`],
];

function makeWorkerProgressTrigger(collection: string) {
  return onDocumentUpdated(`${collection}/{gigId}`, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const hostId = after.hostId as string | undefined;
    if (!hostId) return;

    const workerName =
      (after.assignedWorkerName as string) ??
      (after.workerName as string) ??
      "Your worker";
    const gigTitle = (after.title as string) ?? "your gig";

    for (const [field, title, body] of PROGRESS_MILESTONES) {
      if (!before[field] && after[field]) {
        await sendPushToUser(hostId, {
          title: title(workerName),
          body: body(workerName, gigTitle),
          channelId: "gig_worker_progress_v3",
          data: { type: "worker_progress", gigId: event.params.gigId },
        });
      }
    }
  });
}

export const onQuickGigProgress = makeWorkerProgressTrigger("quick_gigs");
export const onOpenGigProgress = makeWorkerProgressTrigger("open_gigs");
export const onOfferedGigProgress = makeWorkerProgressTrigger("offered_gigs");

// ── Worker progress milestones — multi-worker gigs ──────────────────────────
// Multi-worker gigs record each worker's arrivedAt/workStartedAt/
// workCompletedAt on their own `workers/{workerId}` subcollection doc instead
// of the parent gig doc, so the trigger above never fires for them. This is
// the subcollection equivalent — one push per worker's own milestone.
function makeWorkerProgressSlotTrigger(collection: string) {
  return onDocumentUpdated(
    `${collection}/{gigId}/workers/{workerId}`,
    async (event) => {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after) return;

      const hostId = after.hostId as string | undefined;
      if (!hostId) return;

      const workerName = (after.workerName as string) ?? "Your worker";
      let gigTitle = "your gig";
      try {
        const gigSnap = await admin
          .firestore()
          .collection(collection)
          .doc(event.params.gigId)
          .get();
        gigTitle = (gigSnap.data()?.title as string) ?? gigTitle;
      } catch {
        // Best-effort — notification still fires with the generic title.
      }

      for (const [field, title, body] of PROGRESS_MILESTONES) {
        if (!before[field] && after[field]) {
          await sendPushToUser(hostId, {
            title: title(workerName),
            body: body(workerName, gigTitle),
            channelId: "gig_worker_progress_v3",
            data: {
              type: "worker_progress",
              gigId: event.params.gigId,
              workerId: event.params.workerId,
            },
          });
        }
      }
    }
  );
}

export const onQuickGigWorkerSlotProgress = makeWorkerProgressSlotTrigger("quick_gigs");
export const onOpenGigWorkerSlotProgress = makeWorkerProgressSlotTrigger("open_gigs");
export const onOfferedGigWorkerSlotProgress = makeWorkerProgressSlotTrigger("offered_gigs");

// ── Gig assigned (worker side) ──────────────────────────────────────────────
// Fires the moment a gig's status enters an "assigned" state (navigating /
// in_progress) with a worker attached, across all three gig collections.
const ASSIGNED_STATUSES = new Set(["navigating", "in_progress"]);

function makeGigAssignedTrigger(collection: string, gigTypeLabel: string) {
  return onDocumentUpdated(`${collection}/{gigId}`, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const workerId =
      (after.assignedWorkerId as string) ?? (after.workerId as string);
    const wasAssigned = ASSIGNED_STATUSES.has(before.status);
    const isAssigned = ASSIGNED_STATUSES.has(after.status);
    if (!workerId || wasAssigned || !isAssigned) return;

    const gigTitle = (after.title as string) ?? "a gig";

    await sendPushToUser(workerId, {
      title: `You're Assigned to a ${gigTypeLabel}!`,
      body: `You've been assigned to: ${gigTitle}. Head to the location now.`,
      channelId: "gig_assignments_v2",
      data: { type: "gig_assigned", gigId: event.params.gigId },
    });
  });
}

export const onQuickGigAssigned = makeGigAssignedTrigger("quick_gigs", "Quick Gig");
export const onOpenGigAssigned = makeGigAssignedTrigger("open_gigs", "Open Gig");
export const onOfferedGigAssigned = makeGigAssignedTrigger("offered_gigs", "Offered Gig");

// ── Gig assigned — multi-worker gigs ────────────────────────────────────────
// Each worker on a multi-worker gig gets their own `workers/{workerId}` doc
// created already-assigned (Open Gig: host picks straight from applicants),
// so this fires on subcollection doc CREATE rather than a gig-doc status
// transition.
function makeGigAssignedSlotTrigger(collection: string, gigTypeLabel: string) {
  return onDocumentCreated(
    `${collection}/{gigId}/workers/{workerId}`,
    async (event) => {
      const after = event.data?.data();
      if (!after) return;
      const workerId = event.params.workerId as string;
      if (!ASSIGNED_STATUSES.has(after.status)) return;

      let gigTitle = "a gig";
      try {
        const gigSnap = await admin
          .firestore()
          .collection(collection)
          .doc(event.params.gigId)
          .get();
        gigTitle = (gigSnap.data()?.title as string) ?? gigTitle;
      } catch {
        // Best-effort — notification still fires with the generic title.
      }

      await sendPushToUser(workerId, {
        title: `You're Assigned to a ${gigTypeLabel}!`,
        body: `You've been assigned to: ${gigTitle}. Head to the location now.`,
        channelId: "gig_assignments_v2",
        data: { type: "gig_assigned", gigId: event.params.gigId },
      });
    }
  );
}

export const onQuickGigSlotAssigned = makeGigAssignedSlotTrigger("quick_gigs", "Quick Gig");
export const onOpenGigSlotAssigned = makeGigAssignedSlotTrigger("open_gigs", "Open Gig");
export const onOfferedGigSlotAssigned = makeGigAssignedSlotTrigger("offered_gigs", "Offered Gig");

// ── Offered gig declined (host side) ────────────────────────────────────────
// A host directly offers a gig to one or more specific named workers, so
// unlike Quick Gig's automated candidate-by-candidate search (where a decline
// just quietly moves on to the next candidate), a decline here is meaningful
// and actionable — the host picked that person and should know right away.
export const onOfferedGigDeclined = onDocumentUpdated(
  "offered_gigs/{gigId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === "declined" || after.status !== "declined") return;

    const hostId = after.hostId as string | undefined;
    if (!hostId) return;
    const workerName = (after.workerName as string) ?? "The worker";
    const gigTitle = (after.title as string) ?? "your gig";

    await sendPushToUser(hostId, {
      title: "Offer Declined",
      body: `${workerName} declined your offer for "${gigTitle}".`,
      channelId: "gig_offer_declined_v1",
      data: { type: "gig_offer_declined", gigId: event.params.gigId },
    });
  }
);

// Multi-worker equivalent — each named worker's decline lives on their own
// `workers/{workerId}` doc rather than the gig doc's single `status` field,
// so one worker declining never touches the others' offers.
export const onOfferedGigSlotDeclined = onDocumentUpdated(
  "offered_gigs/{gigId}/workers/{workerId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === "declined" || after.status !== "declined") return;

    const hostId = after.hostId as string | undefined;
    if (!hostId) return;
    const workerName = (after.workerName as string) ?? "A worker";

    let gigTitle = "your gig";
    try {
      const gigSnap = await admin
        .firestore()
        .collection("offered_gigs")
        .doc(event.params.gigId)
        .get();
      gigTitle = (gigSnap.data()?.title as string) ?? gigTitle;
    } catch {
      // Best-effort — notification still fires with the generic title.
    }

    await sendPushToUser(hostId, {
      title: "Offer Declined",
      body: `${workerName} declined your offer for "${gigTitle}".`,
      channelId: "gig_offer_declined_v1",
      data: {
        type: "gig_offer_declined",
        gigId: event.params.gigId,
        workerId: event.params.workerId,
      },
    });
  }
);

// ── Schedule-expiry auto-cancel (host side) ─────────────────────────────────
// Was previously a client-side Timer in CurrentUserProvider, which only fired
// if the host's app happened to be open at the exact expiry moment. Moving it
// to a scheduled function makes the cancellation (and its notification) fire
// reliably regardless of app state.
export const checkExpiredGigSchedules = onSchedule(
  "every 5 minutes",
  async () => {
    const now = admin.firestore.Timestamp.now();
    const db = admin.firestore();
    const collections: Array<[string, string]> = [
      ["open_gigs", "open"],
      ["offered_gigs", "offered"],
    ];

    for (const [collection, expectedStatus] of collections) {
      const expired = await db
        .collection(collection)
        .where("status", "==", expectedStatus)
        .where("scheduledDate", "<=", now)
        .get();

      for (const doc of expired.docs) {
        const hostId = doc.data().hostId as string | undefined;
        let gigTitle: string | undefined;

        await db.runTransaction(async (tx) => {
          const snap = await tx.get(doc.ref);
          const data = snap.data();
          if (!data || data.status !== expectedStatus || !data.scheduledDate) {
            return;
          }
          gigTitle = (data.title as string) ?? "your gig";
          tx.update(doc.ref, {
            status: "cancelled",
            cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
            cancellation_reason: admin.firestore.FieldValue.arrayUnion({
              reason: "No worker selected before the scheduled time",
              approved: true,
              requestedBy: "system",
            }),
          });
        });

        if (gigTitle && hostId) {
          await sendPushToUser(hostId, {
            title: "Gig Cancelled",
            body: `No worker was selected for "${gigTitle}" before its scheduled time, so the gig has been cancelled.`,
            channelId: "gig_auto_cancelled_v3",
            data: { type: "gig_auto_cancelled", gigId: doc.id },
          });
        }
      }
    }
  }
);

// ── Tester broadcasts (dev/closed-testing project only) ────────────────────
// Every user doc in the dev Firebase project (simpleproject-8ff7a) belongs to
// a closed-testing tester by definition, so broadcasts need no per-user
// filtering. Both functions below no-op if this codebase is ever deployed to
// the prod project instead.
const DEV_PROJECT_ID = "simpleproject-8ff7a";

function isDevProject(): boolean {
  const currentProject =
    process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT;
  return currentProject === DEV_PROJECT_ID;
}

// Fires at 7am, 11am, and 6pm Asia/Manila daily.
export const sendDailyTestReminder = onSchedule(
  { schedule: "0 7,11,18 * * *", timeZone: "Asia/Manila" },
  async () => {
    if (!isDevProject()) return;
    await broadcastToAllUsers({
      title: "Time to Test!",
      body: "Time to test, testers!!! Open Giggre and check out the latest build.",
      channelId: "tester_reminder_v3",
      data: { type: "tester_reminder" },
    });
  }
);

// Called manually (via curl) right after a new dev build is published —
// see functions/README.md for the exact command. Not automatic: it doesn't
// poll the Play Developer API, it just needs a nudge once you've uploaded
// the new AAB/APK to the closed-testing track.
export const publishVersionAnnouncement = onRequest(
  { secrets: [releaseAnnounceSecret] },
  async (req, res) => {
    if (!isDevProject()) {
      res.status(404).send("Not found");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }
    if (req.get("x-release-secret") !== releaseAnnounceSecret.value()) {
      res.status(401).send("Unauthorized");
      return;
    }

    const version = req.body?.version as string | undefined;
    if (!version) {
      res.status(400).send("Missing 'version' in request body");
      return;
    }
    const notes = req.body?.notes as string | undefined;

    await broadcastToAllUsers({
      title: "New Test Build Available",
      body: notes
        ? `Version ${version} is now available: ${notes}`
        : `Version ${version} is now available. Update the app to get it.`,
      channelId: "tester_reminder_v3",
      data: { type: "new_version", version },
    });

    res.status(200).json({ ok: true });
  }
);
