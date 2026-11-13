import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { firestoreTriggerRegion } from "./region";

// ── GSIN Library: GSINS + GSKU codes for gigs ──────────────────────────────
// Admin-only identifiers (giggre-admin → GSIN Library, and the GSINS / GSKU
// columns on Marketplace → Gigs → All Gigs). Never shown in the app.
//
//   GSINS  G + CATEGORY PREFIX (3) + SEQ (6)       e.g. GADS000001
//          one per TASK TYPE — the n-th task type created in that category.
//   GSKU   T + SUB-CATEGORY PREFIX (2) + TASK TYPE PREFIX (2)
//            + EXPERT LEVEL RANK (1) + PRIORITY SERVICE (2) + SEQ (5+)
//          e.g. TVAAS1QG00001 — one per GIG (one GSINS : many GSKUs).
//          Level: entry 1 · intermediate 2 · expert 3 · none (Quick Gig) 0.
//          Service: QG Quick Gig · PG Open (posted) Gig · FG Offered Gig.
//          SEQ counts gigs per task type (all levels / services), 5 digits
//          minimum, growing past 99999.
//
// Catalog (admin-written; ids are the prefixes so they can't collide and a
// code never changes meaning):
//   gsin_categories/{CAT}            { name, prefix, gsinsSeq, createdAt }
//   gsin_subcategories/{SC}          { name, prefix, categoryId, createdAt }
//   gsin_task_types/{SC+TT}          { name, prefix, categoryId, subcategoryId,
//                                      gsins, gskuSeq, skillIds[], createdAt }
//   skills/{id}.taskTypeId           links an existing skill to a task type
//
// A gig's task type: gig.taskTypeId (Quick Gig picker / admin), else its
// skill (open_gigs.requiredSkills[0], offered_gigs.skillRequired) mapped
// through the skill → task type link. Codes are written on the gig by this
// file only (firestore.rules blocks clients from setting gsins / gsku):
//   { taskTypeId, gsins, gsku, gskuAssignedAt }

const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;
const db = () => admin.firestore();
const FV = admin.firestore.FieldValue;

export const GIG_COLLECTIONS = { quick_gigs: "QG", open_gigs: "PG", offered_gigs: "FG" } as const;
type GigCollection = keyof typeof GIG_COLLECTIONS;
const isGigCollection = (c: unknown): c is GigCollection =>
  typeof c === "string" && Object.prototype.hasOwnProperty.call(GIG_COLLECTIONS, c);

const CAT_RE = /^[A-Z]{3}$/;
const TWO_RE = /^[A-Z]{2}$/;
const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");

export function levelRank(level: unknown): number {
  switch (str(level).toLowerCase()) {
    case "entry": case "entry level": case "beginner": return 1;
    case "intermediate": return 2;
    case "expert": return 3;
    default: return 0;
  }
}

const pad = (n: number, w: number) => String(n).padStart(w, "0");
export const gsinsCode = (catPrefix: string, seq: number) => `G${catPrefix}${pad(seq, 6)}`;
export const gskuCode = (sub: string, task: string, level: number, svc: string, seq: number) =>
  `T${sub}${task}${level}${svc}${pad(seq, 5)}`;

/** The gig's skill name (open: requiredSkills[0], offered: skillRequired). */
function skillOf(gig: FirebaseFirestore.DocumentData): string {
  if (Array.isArray(gig.requiredSkills) && gig.requiredSkills.length) return str(gig.requiredSkills[0]);
  return str(gig.skillRequired) || str(gig.requiredSkill) || str(gig.skill);
}

/**
 * lowercased skill name → task type ids linked to it. A skill can belong to
 * many task types (gsin_task_types.skillIds is the source of truth; the old
 * one-per-skill skills/{id}.taskTypeId is still honoured).
 */
type SkillTaskMap = Map<string, Set<string>>;
async function skillTaskMap(): Promise<SkillTaskMap> {
  const [skills, taskTypes] = await Promise.all([
    db().collection("skills").get(),
    db().collection("gsin_task_types").get(),
  ]);
  const nameById = new Map<string, string>();
  const m: SkillTaskMap = new Map();
  const add = (name: string, tt: string) => {
    if (!name || !tt) return;
    if (!m.has(name)) m.set(name, new Set());
    m.get(name)!.add(tt);
  };
  for (const d of skills.docs) {
    const name = str(d.data().name).toLowerCase();
    nameById.set(d.id, name);
    add(name, str(d.data().taskTypeId)); // legacy single link
  }
  for (const t of taskTypes.docs) {
    const ids: unknown[] = Array.isArray(t.data().skillIds) ? t.data().skillIds : [];
    for (const sid of ids) add(nameById.get(str(sid)) ?? "", t.id);
  }
  return m;
}

/**
 * The gig's task type: the one the host picked, else the single task type
 * linked to its skill. When the skill is linked to several task types it's
 * ambiguous — `candidates` lists them so an admin can pick.
 */
async function resolveTaskType(gig: FirebaseFirestore.DocumentData, skills?: SkillTaskMap): Promise<{ id: string | null; candidates: string[] }> {
  const direct = str(gig.taskTypeId);
  if (direct) return { id: direct, candidates: [] };
  const skill = skillOf(gig).toLowerCase();
  if (!skill) return { id: null, candidates: [] };
  const ids = [...((skills ?? (await skillTaskMap())).get(skill) ?? [])].sort();
  return ids.length === 1 ? { id: ids[0], candidates: [] } : { id: null, candidates: ids };
}

type AssignResult =
  | { status: "assigned"; gsins: string; gsku: string; taskTypeId: string }
  | { status: "kept"; gsins: string; gsku: string }
  | { status: "no_task_type"; candidates?: string[] };

/**
 * Gives a gig its GSINS + GSKU. Keeps existing codes unless `force` (admin
 * reassignment to another task type). One transaction: the task type's
 * gskuSeq counter is the single source of the running number.
 */
export async function assignGigCodes(
  collection: GigCollection,
  gigId: string,
  opts: { taskTypeId?: string | null; force?: boolean; skills?: SkillTaskMap } = {},
): Promise<AssignResult> {
  const gigRef = db().collection(collection).doc(gigId);
  const pre = (await gigRef.get()).data();
  if (!pre) throw new HttpsError("not-found", "Gig not found.");
  let taskTypeId = opts.taskTypeId ?? null;
  if (!taskTypeId) {
    const r = await resolveTaskType(pre, opts.skills);
    if (!r.id) {
      // Skill linked to several task types → remember them so All Gigs can
      // show "Pick task type" with these first.
      if (r.candidates.length > 1) await gigRef.update({ gsinCandidates: r.candidates }).catch(() => {});
      return { status: "no_task_type", candidates: r.candidates };
    }
    taskTypeId = r.id;
  }

  return db().runTransaction(async (tx) => {
    const gigSnap = await tx.get(gigRef);
    const gig = gigSnap.data();
    if (!gig) throw new HttpsError("not-found", "Gig not found.");
    if (gig.gsku && !opts.force) return { status: "kept", gsins: gig.gsins, gsku: gig.gsku } as AssignResult;
    if (gig.gsku && opts.force && gig.taskTypeId === taskTypeId) {
      return { status: "kept", gsins: gig.gsins, gsku: gig.gsku } as AssignResult;
    }
    const ttRef = db().collection("gsin_task_types").doc(taskTypeId);
    const tt = (await tx.get(ttRef)).data();
    if (!tt) throw new HttpsError("not-found", `Task type ${taskTypeId} doesn't exist.`);
    const sub = (await tx.get(db().collection("gsin_subcategories").doc(str(tt.subcategoryId)))).data();
    if (!sub || !TWO_RE.test(str(sub.prefix)) || !TWO_RE.test(str(tt.prefix)) || !str(tt.gsins)) {
      throw new HttpsError("failed-precondition", `Task type ${taskTypeId} is incomplete (prefixes / GSINS).`);
    }
    const seq = (Number(tt.gskuSeq) || 0) + 1;
    const gsku = gskuCode(str(sub.prefix), str(tt.prefix), levelRank(gig.experienceLevel), GIG_COLLECTIONS[collection], seq);
    tx.update(ttRef, { gskuSeq: seq, updatedAt: FV.serverTimestamp() });
    tx.update(gigRef, {
      taskTypeId, gsins: str(tt.gsins), gsku, gskuAssignedAt: FV.serverTimestamp(), gsinCandidates: FV.delete(),
      ...(gig.gsku ? { previousGsku: FV.arrayUnion(gig.gsku) } : {}),
    });
    return { status: "assigned", gsins: str(tt.gsins), gsku, taskTypeId } as AssignResult;
  });
}

// ── New gigs get their codes automatically ─────────────────────────────────

function makeGskuTrigger(collection: GigCollection) {
  return onDocumentCreated({ ...OPTS, document: `${collection}/{gigId}` }, async (event) => {
    try {
      const r = await assignGigCodes(collection, event.params.gigId);
      if (r.status === "no_task_type") logger.info("[gsin] no task type yet", { collection, gigId: event.params.gigId });
    } catch (err) {
      // e.g. deleted by the word filter right after creation
      logger.warn("[gsin] assign failed", { collection, gigId: event.params.gigId, error: String(err) });
    }
  });
}

export const onQuickGigAssignGsku = makeGskuTrigger("quick_gigs");
export const onOpenGigAssignGsku = makeGskuTrigger("open_gigs");
export const onOfferedGigAssignGsku = makeGskuTrigger("offered_gigs");

// ── Host changed the gig's skill (Edit gig, app or website) ────────────────
// The task type comes from the skill, so it follows the new skill:
//   • the current task type is still linked to the new skill → keep it
//   • the new skill links to exactly one task type → switch to it (new GSKU;
//     the old one goes to previousGsku)
//   • none / several → clear the codes (old GSKU kept in previousGsku); with
//     several, gsinCandidates lets an admin pick in All Gigs
// Only skill changes trigger this, and it never writes a skill field, so its
// own update can't re-trigger it.

export async function followSkillChange(
  collection: GigCollection,
  gigId: string,
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
): Promise<string> {
  const newSkill = skillOf(after).toLowerCase();
  if (!newSkill || newSkill === skillOf(before).toLowerCase()) return "skill_unchanged";
  const linked = [...((await skillTaskMap()).get(newSkill) ?? [])].sort();
  const current = str(after.taskTypeId);
  if (current && linked.includes(current)) return "kept";
  if (linked.length === 1) {
    const r = await assignGigCodes(collection, gigId, { taskTypeId: linked[0], force: true });
    return r.status;
  }
  const gigRef = db().collection(collection).doc(gigId);
  await gigRef.update({
    taskTypeId: FV.delete(), gsins: FV.delete(), gsku: FV.delete(), gskuAssignedAt: FV.delete(),
    gsinCandidates: linked.length > 1 ? linked : FV.delete(),
    ...(str(after.gsku) ? { previousGsku: FV.arrayUnion(str(after.gsku)) } : {}),
  });
  return linked.length > 1 ? "needs_pick" : "no_task_type";
}

function makeSkillChangeTrigger(collection: GigCollection) {
  return onDocumentUpdated({ ...OPTS, document: `${collection}/{gigId}` }, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (skillOf(before).toLowerCase() === skillOf(after).toLowerCase()) return;
    try {
      const r = await followSkillChange(collection, event.params.gigId, before, after);
      logger.info("[gsin] skill changed", { collection, gigId: event.params.gigId, from: skillOf(before), to: skillOf(after), result: r });
    } catch (err) {
      logger.warn("[gsin] skill change re-assign failed", { collection, gigId: event.params.gigId, error: String(err) });
    }
  });
}

// Quick Gigs can't be edited, so only Open and Offered.
export const onOpenGigSkillChanged = makeSkillChangeTrigger("open_gigs");
export const onOfferedGigSkillChanged = makeSkillChangeTrigger("offered_gigs");

// ── Admin callables ────────────────────────────────────────────────────────

async function requireGsinAdmin(uid: string | undefined, also: string[] = []) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const a = (await db().collection("admins").doc(uid).get()).data();
  if (!a || a.isActive !== true || a.isPending !== false) throw new HttpsError("permission-denied", "Admins only.");
  const perms: unknown[] = Array.isArray(a.permissions) ? a.permissions : [];
  if (a.role !== "super_admin" && ![ "library-gsin", ...also ].some((p) => perms.includes(p))) {
    throw new HttpsError("permission-denied", "You need the GSIN Library permission.");
  }
  return { uid, name: str(a.name) || str(a.email) || "Admin", email: str(a.email) || null };
}

async function log(actor: { uid: string; name: string; email: string | null }, action: string, description: string, targetId: string, other: Record<string, unknown>) {
  try {
    await db().collection("activityLogs").add({
      actorId: actor.uid, actorName: actor.name, actorEmail: actor.email,
      module: "library-gsin", action, description, targetSection: null, targetId, targetName: targetId,
      affectedFiles: [], meta: { from: null, to: null, other }, createdAt: FV.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[gsin] activity log failed", { error: String(err) });
  }
}

/**
 * Creates a task type and gives it the category's next GSINS.
 * { categoryId, subcategoryId, name, prefix } → { id, gsins }
 */
export const adminCreateGsinTaskType = onCall(OPTS, async (request) => {
  const actor = await requireGsinAdmin(request.auth?.uid);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const name = str(d.name);
  const prefix = str(d.prefix).toUpperCase();
  const subcategoryId = str(d.subcategoryId).toUpperCase();
  if (name.length < 2 || name.length > 80) throw new HttpsError("invalid-argument", "Enter a task type name (2–80 characters).");
  if (!TWO_RE.test(prefix)) throw new HttpsError("invalid-argument", "Task type prefix must be 2 letters (A–Z).");
  if (!TWO_RE.test(subcategoryId)) throw new HttpsError("invalid-argument", "Pick a sub-category.");
  const skillIds = Array.isArray(d.skillIds) ? (d.skillIds as unknown[]).map(str).filter(Boolean).slice(0, 50) : [];

  const id = `${subcategoryId}${prefix}`;
  const result = await db().runTransaction(async (tx) => {
    const subRef = db().collection("gsin_subcategories").doc(subcategoryId);
    const sub = (await tx.get(subRef)).data();
    if (!sub) throw new HttpsError("not-found", "Sub-category not found.");
    const categoryId = str(sub.categoryId);
    if (!CAT_RE.test(categoryId)) throw new HttpsError("failed-precondition", "Sub-category has no category.");
    const catRef = db().collection("gsin_categories").doc(categoryId);
    const cat = (await tx.get(catRef)).data();
    if (!cat) throw new HttpsError("not-found", "Category not found.");
    const ttRef = db().collection("gsin_task_types").doc(id);
    if ((await tx.get(ttRef)).exists) {
      throw new HttpsError("already-exists", `${sub.name ?? subcategoryId} already has a task type with prefix ${prefix}.`);
    }
    const seq = (Number(cat.gsinsSeq) || 0) + 1;
    if (seq > 999999) throw new HttpsError("resource-exhausted", "This category has used all GSINS numbers.");
    const gsins = gsinsCode(categoryId, seq);
    tx.update(catRef, { gsinsSeq: seq, updatedAt: FV.serverTimestamp() });
    tx.create(ttRef, {
      name, prefix, categoryId, subcategoryId, gsins, gskuSeq: 0, skillIds,
      createdAt: FV.serverTimestamp(), createdBy: actor.uid, updatedAt: FV.serverTimestamp(),
    });
    return { id, gsins };
  });
  await log(actor, "gsin_task_type_created", `Created task type ${name} (${id}) — GSINS ${result.gsins}`, id, { skillIds });
  return result;
});

/** Admin sets / changes a gig's task type → (new) GSKU. { collection, gigId, taskTypeId } */
export const adminAssignGigTaskType = onCall(OPTS, async (request) => {
  const actor = await requireGsinAdmin(request.auth?.uid, ["live-gigs"]);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const collection = d.collection;
  const gigId = str(d.gigId);
  const taskTypeId = str(d.taskTypeId).toUpperCase();
  if (!isGigCollection(collection)) throw new HttpsError("invalid-argument", "Unknown gig collection.");
  if (!gigId || gigId.includes("/")) throw new HttpsError("invalid-argument", "gigId is required.");
  if (!/^[A-Z]{4}$/.test(taskTypeId)) throw new HttpsError("invalid-argument", "Pick a task type.");
  const r = await assignGigCodes(collection, gigId, { taskTypeId, force: true });
  if (r.status !== "no_task_type") {
    await log(actor, "gsin_gig_assigned", `Set ${collection}/${gigId} to task type ${taskTypeId} — ${r.gsku}`, gigId, { collection, taskTypeId, gsku: r.gsku });
  }
  return r;
});

/**
 * Gives codes to existing gigs that don't have one yet (task type from the
 * gig's skill). Processes up to `limit` gigs per call (default 300) so a
 * big backlog runs in a few clicks. → { assigned, noTaskType, failed, remaining }
 */
export const adminBackfillGigCodes = onCall({ ...OPTS, timeoutSeconds: 300 }, async (request) => {
  const actor = await requireGsinAdmin(request.auth?.uid, ["live-gigs"]);
  const limit = Math.min(Math.max(Number((request.data ?? {}).limit) || 300, 1), 1000);
  let assigned = 0, noTaskType = 0, needsPick = 0, failed = 0, remaining = 0;
  const skills = await skillTaskMap();
  for (const collection of Object.keys(GIG_COLLECTIONS) as GigCollection[]) {
    const snap = await db().collection(collection).get();
    for (const doc of snap.docs) {
      if (doc.data().gsku) continue;
      const { id: taskTypeId, candidates } = await resolveTaskType(doc.data(), skills);
      if (!taskTypeId) {
        // admin assigns these from All Gigs
        if (candidates.length > 1) {
          needsPick++;
          const prev: unknown[] = Array.isArray(doc.data().gsinCandidates) ? doc.data().gsinCandidates : [];
          if (prev.join() !== candidates.join()) await doc.ref.update({ gsinCandidates: candidates }).catch(() => {});
        } else {
          noTaskType++;
        }
        continue;
      }
      if (assigned + failed >= limit) {
        remaining++;
        continue;
      }
      try {
        const r = await assignGigCodes(collection, doc.id, { taskTypeId });
        if (r.status === "assigned") assigned++;
      } catch (err) {
        failed++;
        logger.warn("[gsin] backfill failed", { collection, gigId: doc.id, error: String(err) });
      }
    }
  }
  await log(actor, "gsin_backfill", `Backfilled GSKU codes — ${assigned} assigned, ${needsPick} need a pick (skill in several task types), ${noTaskType} without a task type, ${failed} failed`, "gigs", { assigned, needsPick, noTaskType, failed, remaining });
  return { assigned, needsPick, noTaskType, failed, remaining };
});
