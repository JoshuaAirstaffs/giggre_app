import {
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { FieldPath, getFirestore } from "firebase-admin/firestore";
import { sendPushToUser } from "./push";
import { firestoreTriggerRegion } from "./region";

// ── Open Gig applications: one active gig at a time ─────────────────────────
//
// A worker can apply to several Open Gigs. Once they're actually working one
// (any of the statuses below), their other pending applications are
// withdrawn, so other hosts don't pick a worker who is already busy.
//
// Applications live in open_gigs/{gigId}.applicants as {workerId, workerName}
// maps, which can't be looked up by worker id alone. syncApplicantIds keeps a
// plain `applicantIds` list next to it, so "every gig this worker applied to"
// is one array-contains query. It runs on the server, so every app version
// (including ones already on phones) is covered.

const OPTS = { region: firestoreTriggerRegion(), maxInstances: 100 } as const;

// Same as the app's kWorkerActiveGigStatuses minus 'cancellation_requested'
// (only reachable from one of these). Quick Gig's 'in_progress' is a pending
// offer the worker can still decline, so it does NOT withdraw anything; the
// later move to 'navigating' (accept) does.
const ACTIVE = new Set(["navigating", "arrived", "working", "task_complete", "payment"]);

const GIG_COLLECTIONS = ["quick_gigs", "open_gigs", "offered_gigs"] as const;
type GigCollection = (typeof GIG_COLLECTIONS)[number];

function applicantIdsOf(applicants: unknown): string[] {
  if (!Array.isArray(applicants)) return [];
  const ids = new Set<string>();
  for (const a of applicants) {
    const id = (a as { workerId?: unknown } | null)?.workerId;
    if (typeof id === "string" && id) ids.add(id);
  }
  return [...ids].sort();
}

function sameIds(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

export const syncApplicantIds = onDocumentWritten(
  { ...OPTS, document: "open_gigs/{gigId}" },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data() ?? {};
    const want = applicantIdsOf(data.applicants);
    const have = Array.isArray(data.applicantIds) ?
      [...(data.applicantIds as string[])].sort() :
      [];
    if (sameIds(want, have)) return;
    await after.ref.update({ applicantIds: want });
  }
);

/**
 * Removes [uid]'s pending applications from every Open Gig except the one
 * they're now working ([keep]). Returns how many were withdrawn.
 *
 * Finds them by `applicantIds`, plus an exact {workerId, workerName} match
 * for gigs whose applicantIds haven't been filled in yet (applied to before
 * syncApplicantIds existed and not updated since).
 */
async function withdrawOtherApplications(
  uid: string,
  keep: { collection: GigCollection; gigId: string },
  nameHints: string[]
): Promise<number> {
  const db = getFirestore();
  const gigs = db.collection("open_gigs");

  const queries = [gigs.where("applicantIds", "array-contains", uid).get()];
  for (const name of new Set(nameHints.filter((n) => n))) {
    queries.push(
      gigs.where("applicants", "array-contains", { workerId: uid, workerName: name }).get()
    );
  }
  const snaps = await Promise.all(queries);

  const ids = new Set<string>();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (keep.collection === "open_gigs" && doc.id === keep.gigId) continue;
      ids.add(doc.id);
    }
  }

  let withdrawn = 0;
  for (const id of ids) {
    try {
      const removed = await db.runTransaction(async (tx) => {
        const ref = gigs.doc(id);
        const snap = await tx.get(ref);
        const applicants = (snap.get("applicants") as unknown[] | undefined) ?? [];
        const remaining = applicants.filter(
          (a) => (a as { workerId?: unknown } | null)?.workerId !== uid
        );
        if (remaining.length === applicants.length) return false;
        tx.update(ref, new FieldPath("applicants"), remaining, new FieldPath("applicantIds"), applicantIdsOf(remaining));
        return true;
      });
      if (removed) withdrawn++;
    } catch (e) {
      console.error("[withdrawOtherApplications] failed", { uid, gigId: id, e: String(e) });
    }
  }
  return withdrawn;
}

async function onWorkerStarted(
  uid: string,
  keep: { collection: GigCollection; gigId: string },
  gigTitle: string,
  nameHints: string[]
) {
  const n = await withdrawOtherApplications(uid, keep, nameHints);
  if (n === 0) return;
  const title = gigTitle.trim() ? `"${gigTitle.trim()}"` : "a gig";
  await sendPushToUser(uid, {
    title: n === 1 ? "Other application withdrawn" : "Other applications withdrawn",
    body: `You got ${title}, so we withdrew your ${n === 1 ? "other application" : `${n} other applications`}.`,
    channelId: "gig_assignments_v2",
    data: { type: "applications_withdrawn", gigId: keep.gigId },
  });
}

// Single-worker gigs: the worker is on the gig doc itself.
function makeGigTrigger(collection: GigCollection) {
  return onDocumentWritten({ ...OPTS, document: `${collection}/{gigId}` }, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after || !ACTIVE.has(after.status)) return;
    if (before && ACTIVE.has(before.status)) return;
    const uid = (after.assignedWorkerId as string) || (after.workerId as string);
    if (!uid) return;
    await onWorkerStarted(
      uid,
      { collection, gigId: event.params.gigId },
      (after.title as string) ?? "",
      [after.assignedWorkerName as string, after.workerName as string]
    );
  });
}

// Multi-worker gigs: each worker has their own workers/{workerId} doc.
function makeSlotTrigger(collection: GigCollection) {
  return onDocumentWritten(
    { ...OPTS, document: `${collection}/{gigId}/workers/{workerId}` },
    async (event) => {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!after || !ACTIVE.has(after.status)) return;
      if (before && ACTIVE.has(before.status)) return;
      const uid = event.params.workerId as string;
      let gigTitle = "";
      try {
        const gig = await getFirestore().collection(collection).doc(event.params.gigId).get();
        gigTitle = (gig.get("title") as string) ?? "";
      } catch {
        // Title is cosmetic; still withdraw.
      }
      await onWorkerStarted(
        uid,
        { collection, gigId: event.params.gigId },
        gigTitle,
        [after.workerName as string]
      );
    }
  );
}

export const withdrawOnQuickGigStart = makeGigTrigger("quick_gigs");
export const withdrawOnOpenGigStart = makeGigTrigger("open_gigs");
export const withdrawOnOfferedGigStart = makeGigTrigger("offered_gigs");
export const withdrawOnQuickGigSlotStart = makeSlotTrigger("quick_gigs");
export const withdrawOnOpenGigSlotStart = makeSlotTrigger("open_gigs");
export const withdrawOnOfferedGigSlotStart = makeSlotTrigger("offered_gigs");
