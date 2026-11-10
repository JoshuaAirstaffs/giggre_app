import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { firestoreTriggerRegion } from "./region";
import { postLedgerEntry } from "./wallet";
import { walletCurrency, currencySymbol, findUser } from "./gigPointsRequests";
import { sendPushToUser } from "./push";

// ── Promo codes (giggre-admin → Marketing → Promotions) ─────────────────────
//
//   promo_codes/{CODE}                     the code (doc id = uppercase code)
//   promo_codes/{CODE}/redemptions/{uid}   one per user (a code works once per user)
//   promo_vouchers/{id}                    cashback vouchers waiting for a gig
//
// Kinds of reward:
//   gig_points     +N Gig Points, straight away
//   wallet_credit  +₱/$ to the Gig Wallet (amount per currency), straight away
//   gig_cashback   a voucher: when the host's next gig is completed, Giggre
//                  credits X% of the gig pay (capped) or a fixed amount to their
//                  Gig Wallet. Hosts pay workers directly, so a cashback is the
//                  way to "discount" a gig.
//
// Controls: active (pause), start/end dates, total redemption limit, once per
// user, audience (new accounts within N days, worker/host, verified only,
// region PH/US by wallet currency).
//
// Access levels:
//   public      anyone signed in (region still applies). Optionally "listed":
//               shown under "Available promos" in the app/website through
//               promo_public/{CODE} (a safe, read-only summary).
//   private     a targeted group — needs at least one audience rule. Admin can
//               "Send to group": every matching user gets it in "For you"
//               (promo_offers) plus an in-app notification and push.
//   restricted  single-use codes, each assigned to one user (assignedUid) —
//               apologies, VIP rewards. Created per user by
//               adminCreateRestrictedCodes and delivered the same way.
//
//   promo_offers/{CODE}_{uid}   codes delivered to a user (owner-read)
//   promo_public/{CODE}         listed public codes (signed-in read)
//
// Clients never read or write these docs directly (firestore.rules): users
// redeem through redeemPromoCode, admins save through adminSavePromoCode.

const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;
const db = () => admin.firestore();
const FV = admin.firestore.FieldValue;
const ADMIN_PERMISSION = "promotions";

export const PROMO_TYPES = ["gig_points", "wallet_credit", "gig_cashback"] as const;
export type PromoType = (typeof PROMO_TYPES)[number];
export const ACCESS_LEVELS = ["public", "private", "restricted"] as const;
export type Access = (typeof ACCESS_LEVELS)[number];
const CURRENCIES = ["PHP", "USD"] as const;
type Ccy = (typeof CURRENCIES)[number];
type PerCcy = Partial<Record<Ccy, number | null>>;

const CODE_RE = /^[A-Z0-9][A-Z0-9_-]{3,23}$/;
const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
const money = (n: number) => Math.round(n * 100) / 100;
const fmtMoney = (n: number, ccy: string) =>
  `${currencySymbol(ccy)}${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const toMs = (v: unknown): number | null =>
  v instanceof admin.firestore.Timestamp ? v.toMillis() : typeof v === "number" ? v : null;

interface Actor { uid: string; name: string; email: string | null }

async function requirePromoAdmin(uid: string | undefined): Promise<Actor> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const a = (await db().collection("admins").doc(uid).get()).data();
  if (!a || a.isActive !== true || a.isPending !== false) throw new HttpsError("permission-denied", "Admins only.");
  const perms: unknown[] = Array.isArray(a.permissions) ? a.permissions : [];
  if (a.role !== "super_admin" && !perms.includes(ADMIN_PERMISSION)) {
    throw new HttpsError("permission-denied", "You need the Promotions permission.");
  }
  return { uid, name: str(a.name) || str(a.email) || "Admin", email: str(a.email) || null };
}

async function log(actor: Actor, action: string, description: string, code: string, other: Record<string, unknown> = {}) {
  try {
    await db().collection("activityLogs").add({
      actorId: actor.uid, actorName: actor.name, actorEmail: actor.email,
      module: "promotions", action, description, targetSection: null, targetId: code, targetName: code,
      affectedFiles: [], meta: { from: null, to: null, other }, createdAt: FV.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[promos] activity log failed", { error: String(err) });
  }
}

// ── Validation of an admin's code definition ───────────────────────────────

function num(v: unknown, { min = 0, max = Infinity, int = false } = {}): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n < min || n > max || (int && !Number.isInteger(n))) {
    throw new HttpsError("invalid-argument", `Value ${String(v)} is out of range.`);
  }
  return n;
}

function perCcy(v: unknown, opts: { min?: number; max?: number }): PerCcy {
  const o = (v ?? {}) as Record<string, unknown>;
  return { PHP: num(o.PHP, opts), USD: num(o.USD, opts) };
}

const hasAny = (p: PerCcy) => CURRENCIES.some((c) => (p[c] ?? 0) > 0);

function parseDefinition(d: Record<string, unknown>) {
  const code = str(d.code).toUpperCase();
  if (!CODE_RE.test(code)) {
    throw new HttpsError("invalid-argument", "Code must be 4–24 letters, numbers, - or _ (starting with a letter or number).");
  }
  const type = str(d.type) as PromoType;
  if (!PROMO_TYPES.includes(type)) throw new HttpsError("invalid-argument", "Pick a promo type.");
  const name = str(d.name);
  if (name.length < 2 || name.length > 80) throw new HttpsError("invalid-argument", "Give the promo a name (2–80 characters).");
  const description = str(d.description).slice(0, 300);

  const reward: Record<string, unknown> = {};
  if (type === "gig_points") {
    const points = num(d.points, { min: 1, max: 100000, int: true });
    if (!points) throw new HttpsError("invalid-argument", "Enter the Gig Points to give (1–100,000).");
    reward.points = points;
  } else if (type === "wallet_credit") {
    const amount = perCcy(d.amount, { min: 0, max: 100000 });
    if (!hasAny(amount)) throw new HttpsError("invalid-argument", "Enter a wallet amount for ₱ and/or $.");
    reward.amount = amount;
  } else {
    const mode = str(d.cashbackMode) === "fixed" ? "fixed" : "percent";
    reward.cashbackMode = mode;
    if (mode === "percent") {
      const percent = num(d.percent, { min: 1, max: 100 });
      if (!percent) throw new HttpsError("invalid-argument", "Enter the cashback percent (1–100).");
      const maxCashback = perCcy(d.maxCashback, { min: 0, max: 100000 });
      if (!hasAny(maxCashback)) throw new HttpsError("invalid-argument", "Enter a maximum cashback for ₱ and/or $.");
      reward.percent = percent;
      reward.maxCashback = maxCashback;
    } else {
      const amount = perCcy(d.amount, { min: 0, max: 100000 });
      if (!hasAny(amount)) throw new HttpsError("invalid-argument", "Enter the cashback amount for ₱ and/or $.");
      reward.amount = amount;
    }
    reward.minGigAmount = perCcy(d.minGigAmount, { min: 0, max: 1000000 });
    reward.voucherDays = num(d.voucherDays, { min: 1, max: 365, int: true }) ?? 30;
  }

  const startsAt = num(d.startsAt, { min: 0 });
  const endsAt = num(d.endsAt, { min: 0 });
  if (startsAt && endsAt && endsAt <= startsAt) throw new HttpsError("invalid-argument", "End date must be after the start date.");
  const maxRedemptions = num(d.maxRedemptions, { min: 1, max: 10_000_000, int: true });

  const access = (ACCESS_LEVELS as readonly string[]).includes(str(d.access)) ? (str(d.access) as Access) : "public";
  const a = (d.audience ?? {}) as Record<string, unknown>;
  const role = ["worker", "host"].includes(str(a.role)) ? str(a.role) : "any";
  const region = ["PH", "US"].includes(str(a.region)) ? str(a.region) : "any";
  const audience = {
    role,
    region,
    verifiedOnly: a.verifiedOnly === true,
    newUserDays: num(a.newUserDays, { min: 1, max: 365, int: true }),
  };
  if (access === "public") {
    // Broadly available — only the region (which currency) still applies.
    audience.role = "any";
    audience.verifiedOnly = false;
    audience.newUserDays = null;
  }
  if (access === "private" && audience.role === "any" && audience.region === "any" && !audience.verifiedOnly && !audience.newUserDays) {
    throw new HttpsError("invalid-argument", "A private code targets a group — pick at least one rule (worker/host, region, verified or new accounts).");
  }

  return {
    code, type, name, description, reward, audience, maxRedemptions, access,
    listed: access === "public" && d.listed === true,
    startsAt: startsAt ? admin.firestore.Timestamp.fromMillis(startsAt) : null,
    endsAt: endsAt ? admin.firestore.Timestamp.fromMillis(endsAt) : null,
  };
}

// ── Admin callables ────────────────────────────────────────────────────────

/** Create (or edit, with `editing: true`) a promo code. */
export const adminSavePromoCode = onCall(OPTS, async (request) => {
  const actor = await requirePromoAdmin(request.auth?.uid);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const def = parseDefinition(d);
  const ref = db().collection("promo_codes").doc(def.code);
  const editing = d.editing === true;

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!editing && snap.exists) throw new HttpsError("already-exists", `${def.code} already exists.`);
    if (editing && !snap.exists) throw new HttpsError("not-found", `${def.code} doesn't exist.`);
    const used = Number(snap.data()?.redemptionCount ?? 0);
    const prevAccess = (snap.data()?.access as Access | undefined) ?? "public";
    if (!editing && def.access === "restricted") {
      throw new HttpsError("invalid-argument", "Restricted codes are made per user — use \"Restricted codes\".");
    }
    if (editing && (prevAccess === "restricted") !== (def.access === "restricted")) {
      throw new HttpsError("failed-precondition", "A restricted code can't become public/private (or the other way round).");
    }
    if (editing && used > 0 && snap.data()?.type !== def.type) {
      throw new HttpsError("failed-precondition", "This code has been redeemed — its type can't change.");
    }
    if (editing && def.maxRedemptions != null && def.maxRedemptions < used) {
      throw new HttpsError("failed-precondition", `Already redeemed ${used} times — the limit can't be lower.`);
    }
    const now = FV.serverTimestamp();
    tx.set(ref, {
      ...def,
      ...(editing ? {} : { active: true, redemptionCount: 0, createdAt: now, createdBy: actor.uid, createdByName: actor.name }),
      updatedAt: now,
      updatedBy: actor.uid,
    }, { merge: true });
  });
  await syncPublicListing(def.code);
  await log(actor, editing ? "promo_updated" : "promo_created", `${editing ? "Updated" : "Created"} ${def.access} promo code ${def.code} (${def.type})`, def.code, { type: def.type, access: def.access });
  return { code: def.code };
});

/** Pause / resume a code. */
export const adminSetPromoActive = onCall(OPTS, async (request) => {
  const actor = await requirePromoAdmin(request.auth?.uid);
  const code = str((request.data ?? {}).code).toUpperCase();
  const active = (request.data ?? {}).active === true;
  const ref = db().collection("promo_codes").doc(code);
  if (!(await ref.get()).exists) throw new HttpsError("not-found", "Code not found.");
  await ref.update({ active, updatedAt: FV.serverTimestamp(), updatedBy: actor.uid });
  await syncPublicListing(code);
  await log(actor, active ? "promo_resumed" : "promo_paused", `${active ? "Resumed" : "Paused"} promo code ${code}`, code);
  return { active };
});

/** Delete a code that nobody has redeemed (otherwise pause it). */
export const adminDeletePromoCode = onCall(OPTS, async (request) => {
  const actor = await requirePromoAdmin(request.auth?.uid);
  const code = str((request.data ?? {}).code).toUpperCase();
  const ref = db().collection("promo_codes").doc(code);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Code not found.");
  if (Number(snap.data()?.redemptionCount ?? 0) > 0) {
    throw new HttpsError("failed-precondition", "This code has redemptions — pause it instead of deleting.");
  }
  await ref.delete();
  await syncPublicListing(code);
  // Undelivered offers of a deleted code would only error when tapped.
  const offers = await db().collection("promo_offers").where("code", "==", code).limit(500).get();
  if (!offers.empty) {
    const batch = db().batch();
    offers.docs.forEach((o) => batch.delete(o.ref));
    await batch.commit();
  }
  await log(actor, "promo_deleted", `Deleted promo code ${code}`, code);
  return { deleted: true };
});

// ── Redeem (app + website) ─────────────────────────────────────────────────

const isVerified = (u: FirebaseFirestore.DocumentData) => u.isVerified === "verified" || u.isVerified === true;

function eligibilityError(code: FirebaseFirestore.DocumentData, uid: string, user: FirebaseFirestore.DocumentData, ccy: string, now: number): string | null {
  if (code.access === "restricted" && code.assignedUid !== uid) return "This promo code belongs to another account.";
  if (code.active !== true) return "This promo code isn't active right now.";
  const start = toMs(code.startsAt);
  const end = toMs(code.endsAt);
  if (start && now < start) return "This promo code hasn't started yet.";
  if (end && now > end) return "This promo code has expired.";
  if (code.maxRedemptions != null && Number(code.redemptionCount ?? 0) >= Number(code.maxRedemptions)) {
    return "This promo code has been fully redeemed.";
  }
  const a = code.audience ?? {};
  if (a.region === "PH" && ccy !== "PHP") return "This promo code is only for users in the Philippines.";
  if (a.region === "US" && ccy !== "USD") return "This promo code is only for users in the US.";
  if (a.role === "worker" && user.role !== "gigworker") return "This promo code is for gig workers — switch to worker mode to use it.";
  if (a.role === "host" && user.role !== "gighost") return "This promo code is for gig hosts — switch to host mode to use it.";
  if (a.verifiedOnly === true && !isVerified(user)) return "This promo code is for verified accounts only.";
  if (a.newUserDays) {
    const created = toMs(user.createdAt);
    if (!created || now - created > Number(a.newUserDays) * 86400000) {
      return `This promo code is for new accounts (created in the last ${a.newUserDays} days).`;
    }
  }
  // The reward has to have a value in this user's currency.
  const r = code.reward ?? {};
  if (code.type === "wallet_credit" || (code.type === "gig_cashback" && r.cashbackMode === "fixed")) {
    if (!(Number(r.amount?.[ccy]) > 0)) return "This promo code isn't available in your region.";
  }
  if (code.type === "gig_cashback" && r.cashbackMode !== "fixed" && !(Number(r.maxCashback?.[ccy]) > 0)) {
    return "This promo code isn't available in your region.";
  }
  return null;
}

/** { code } → { type, message, points?, amount?, currencyCode?, voucherId? } */
export const redeemPromoCode = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to use a promo code.");
  const code = str((request.data ?? {}).code).toUpperCase().replace(/\s+/g, "");
  if (!CODE_RE.test(code)) throw new HttpsError("not-found", "That promo code doesn't exist.");

  const codeRef = db().collection("promo_codes").doc(code);
  const redemptionRef = codeRef.collection("redemptions").doc(uid);
  const userRef = db().collection("users").doc(uid);
  const walletRef = db().collection("wallets").doc(uid);
  const offerRef = db().collection("promo_offers").doc(`${code}_${uid}`);

  // 1) Claim: checks + count + redemption record, atomically. Gig Points and
  //    the cashback voucher are granted in the same transaction.
  const claim = await db().runTransaction(async (tx) => {
    const [codeSnap, redSnap, userSnap, walletSnap, offerSnap] = await Promise.all([
      tx.get(codeRef), tx.get(redemptionRef), tx.get(userRef), tx.get(walletRef), tx.get(offerRef),
    ]);
    if (!codeSnap.exists) throw new HttpsError("not-found", "That promo code doesn't exist.");
    if (redSnap.exists) throw new HttpsError("already-exists", "You've already used this promo code.");
    const c = codeSnap.data()!;
    const user = userSnap.data() ?? {};
    const ccy = walletCurrency(walletSnap.data(), user);
    const why = eligibilityError(c, uid, user, ccy, Date.now());
    if (why) throw new HttpsError("failed-precondition", why);

    const now = FV.serverTimestamp();
    const r = c.reward ?? {};
    const result: Record<string, unknown> = { type: c.type, currencyCode: ccy, name: c.name };
    const record: Record<string, unknown> = {
      uid, name: str(user.name) || null, userId: str(user.userId) || null, role: str(user.role) || null,
      currencyCode: ccy, type: c.type, redeemedAt: now, status: "granted",
    };

    if (c.type === "gig_points") {
      const points = Number(r.points);
      const balanceRef = db().collection("gig_points").doc(uid);
      tx.create(balanceRef.collection("transactions").doc(`promo_${code}`), {
        type: "promo", source: "promo", status: "credited", points, promoCode: code,
        reason: `Promo code ${code}`, description: `Promo code ${code} — ${c.name}`,
        createdAt: now, creditedAt: now, updatedAt: now,
      });
      tx.set(balanceRef, {
        userId: uid, balance: FV.increment(points), lifetimeEarned: FV.increment(points), updatedAt: now,
      }, { merge: true });
      result.points = points;
      record.points = points;
      result.message = `+${points.toLocaleString("en-US")} Gig Points added.`;
    } else if (c.type === "wallet_credit") {
      const amount = money(Number(r.amount[ccy]));
      result.amount = amount;
      record.amount = amount;
      record.status = "pending_wallet"; // set to granted once the ledger entry lands
      result.message = `${fmtMoney(amount, ccy)} added to your Gig Wallet.`;
    } else {
      const voucherRef = db().collection("promo_vouchers").doc();
      const days = Number(r.voucherDays ?? 30);
      const voucher = {
        uid, promoCode: code, promoName: c.name, currencyCode: ccy,
        mode: r.cashbackMode === "fixed" ? "fixed" : "percent",
        percent: r.cashbackMode === "fixed" ? null : Number(r.percent),
        maxCashback: r.cashbackMode === "fixed" ? null : money(Number(r.maxCashback[ccy])),
        amount: r.cashbackMode === "fixed" ? money(Number(r.amount[ccy])) : null,
        minGigAmount: Number(r.minGigAmount?.[ccy] ?? 0) || 0,
        status: "active",
        createdAt: now,
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + days * 86400000),
      };
      tx.create(voucherRef, voucher);
      result.voucherId = voucherRef.id;
      record.voucherId = voucherRef.id;
      const what = voucher.mode === "fixed"
        ? fmtMoney(voucher.amount!, ccy)
        : `${voucher.percent}% (up to ${fmtMoney(voucher.maxCashback!, ccy)})`;
      result.message = `Cashback voucher added: ${what} back on your next completed gig as a host, within ${days} days.`;
    }

    tx.create(redemptionRef, record);
    if (offerSnap.exists) tx.update(offerRef, { redeemed: true, redeemedAt: now });
    tx.update(codeRef, { redemptionCount: FV.increment(1), lastRedeemedAt: now });
    return result;
  });

  // 2) Wallet credit goes through the ledger (its own transaction, idempotent
  //    by key). If it fails, undo the claim so the user can try again.
  if (claim.type === "wallet_credit") {
    try {
      await postLedgerEntry({
        uid, amount: Number(claim.amount), type: "promo",
        title: `Promo code ${code}`, idempotencyKey: `promo_${code}_${uid}`,
        currencyCode: String(claim.currencyCode), meta: { promoCode: code },
      });
      await redemptionRef.update({ status: "granted" });
    } catch (err) {
      logger.error("[promos] wallet credit failed — rolling back", { code, uid, error: String(err) });
      await db().runTransaction(async (tx) => {
        const offer = await tx.get(offerRef);
        tx.delete(redemptionRef);
        tx.update(codeRef, { redemptionCount: FV.increment(-1) });
        if (offer.exists) tx.update(offerRef, { redeemed: false, redeemedAt: null });
      }).catch(() => {});
      throw new HttpsError("internal", "Couldn't add the credit to your wallet. Please try again.");
    }
  }
  return claim;
});

// ── Cashback vouchers: paid when the host's gig is completed ───────────────

const GIG_COLLECTIONS = ["quick_gigs", "open_gigs", "offered_gigs"] as const;

/** What the host paid for a completed gig, in the gig's currency. */
function gigPaid(g: FirebaseFirestore.DocumentData): number {
  const final = Number(g.finalAmount);
  if (Number.isFinite(final) && final > 0) return final;
  const per = Number(g.ratePerSlot ?? g.budget) || 0;
  const slots = Math.max(1, Number(g.slotsCompleted) || Number(g.filledSlotCount) || 1);
  return per * slots;
}

function makeCashbackTrigger(collection: (typeof GIG_COLLECTIONS)[number]) {
  return onDocumentUpdated({ ...OPTS, document: `${collection}/{gigId}` }, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === "completed" || after.status !== "completed") return;
    const hostId = str(after.hostId);
    if (!hostId) return;
    const gigId = event.params.gigId;
    try {
      await applyCashback(collection, gigId, hostId, after);
    } catch (err) {
      logger.error("[promos] cashback failed", { collection, gigId, error: String(err) });
    }
  });
}

async function applyCashback(collection: string, gigId: string, hostId: string, gig: FirebaseFirestore.DocumentData) {
  const vouchers = await db().collection("promo_vouchers")
    .where("uid", "==", hostId).where("status", "==", "active").get();
  if (vouchers.empty) return;
  const now = Date.now();
  const gigCreated = toMs(gig.createdAt) ?? now;
  const gigCcy = str(gig.currencyCode).toUpperCase() || "USD";
  const paid = gigPaid(gig);

  // Oldest usable voucher first: not expired, same currency, gig posted after
  // the voucher was claimed, gig meets the minimum.
  const usable = vouchers.docs
    .map((d) => ({ ref: d.ref, v: d.data() }))
    .filter(({ v }) => (toMs(v.expiresAt) ?? 0) > now)
    .filter(({ v }) => v.currencyCode === gigCcy)
    .filter(({ v }) => gigCreated >= (toMs(v.createdAt) ?? 0))
    .filter(({ v }) => paid >= Number(v.minGigAmount ?? 0))
    .sort((a, b) => (toMs(a.v.createdAt) ?? 0) - (toMs(b.v.createdAt) ?? 0));
  if (!usable.length) return;
  const { ref, v } = usable[0];

  const cashback = money(v.mode === "fixed"
    ? Math.min(Number(v.amount), paid)
    : Math.min((paid * Number(v.percent)) / 100, Number(v.maxCashback)));
  if (!(cashback > 0)) return;

  // Mark used first (only one gig can take it), then credit idempotently.
  const claimed = await db().runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    if (fresh.data()?.status !== "active") return false;
    tx.update(ref, {
      status: "used", usedAt: FV.serverTimestamp(), gigCollection: collection, gigId,
      gigAmount: money(paid), cashbackAmount: cashback,
    });
    return true;
  });
  if (!claimed) return;
  await postLedgerEntry({
    uid: hostId, amount: cashback, type: "promo",
    title: `Cashback — ${v.promoCode}`, idempotencyKey: `cashback_${ref.id}`,
    currencyCode: gigCcy, meta: { promoCode: v.promoCode, voucherId: ref.id, gigCollection: collection, gigId },
  });
  try {
    await sendPushToUser(hostId, {
      title: `${fmtMoney(cashback, gigCcy)} cashback`,
      body: `Your promo ${v.promoCode} gave you ${fmtMoney(cashback, gigCcy)} back for "${str(gig.title) || "your gig"}". It's in your Gig Wallet.`,
      channelId: "wallet_v1",
      data: { type: "promo_cashback", voucherId: ref.id },
    });
  } catch (err) {
    logger.warn("[promos] cashback push failed", { error: String(err) });
  }
}

export const onQuickGigPromoCashback = makeCashbackTrigger("quick_gigs");
export const onOpenGigPromoCashback = makeCashbackTrigger("open_gigs");
export const onOfferedGigPromoCashback = makeCashbackTrigger("offered_gigs");


// ── Access levels: public listing, delivery to a group / a user ────────────

/** "+500 Gig Points" / "₱100 wallet credit" / "10% gig cashback (up to ₱200)" — for one currency, or both. */
function rewardSummary(c: FirebaseFirestore.DocumentData, ccy: string | null): string {
  const r = c.reward ?? {};
  const each = (p: PerCcy | undefined) => {
    const list = (ccy ? [ccy] : CURRENCIES).filter((k) => Number(p?.[k as Ccy]) > 0);
    return list.map((k) => fmtMoney(Number(p![k as Ccy]), k)).join(" / ");
  };
  if (c.type === "gig_points") return `+${Number(r.points).toLocaleString("en-US")} Gig Points`;
  if (c.type === "wallet_credit") return `${each(r.amount)} Gig Wallet credit`;
  if (r.cashbackMode === "fixed") return `${each(r.amount)} cashback on your next gig`;
  return `${r.percent}% cashback on your next gig (up to ${each(r.maxCashback)})`;
}

/** Keeps promo_public/{code} in step: only active, listed, public codes. */
async function syncPublicListing(code: string) {
  const pubRef = db().collection("promo_public").doc(code);
  const c = (await db().collection("promo_codes").doc(code).get()).data();
  if (!c || c.access !== "public" || c.listed !== true || c.active !== true) {
    await pubRef.delete().catch(() => {});
    return;
  }
  await pubRef.set({
    code, name: c.name, type: c.type,
    rewardText: rewardSummary(c, null),
    rewardTextPHP: rewardSummary(c, "PHP"),
    rewardTextUSD: rewardSummary(c, "USD"),
    region: c.audience?.region ?? "any",
    startsAt: c.startsAt ?? null, endsAt: c.endsAt ?? null,
    updatedAt: FV.serverTimestamp(),
  });
}

/**
 * Puts a code in the user's "For you" list (promo_offers) and tells them —
 * in-app notification + push. Skips users who already have it. Returns true
 * when it was newly delivered.
 */
async function deliverOffer(code: string, c: FirebaseFirestore.DocumentData, uid: string, ccy: string | null, note?: string): Promise<boolean> {
  const reward = rewardSummary(c, ccy);
  const offerRef = db().collection("promo_offers").doc(`${code}_${uid}`);
  try {
    await offerRef.create({
      uid, code, name: c.name, type: c.type, access: c.access ?? "public", rewardText: reward,
      note: note ?? null, endsAt: c.endsAt ?? null, redeemed: false, createdAt: FV.serverTimestamp(),
    });
  } catch {
    return false; // already delivered
  }
  const title = c.access === "restricted" ? "A promo code just for you" : "You've got a promo code";
  const message = `${c.name}: ${reward}. Use code ${code} in Promo Code${note ? ` — ${note}` : ""}.`;
  try {
    await db().collection("notifications").add({
      userId: uid, category: "promo", title, message, promoCode: code, createdAt: FV.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[promos] notification failed", { uid, error: String(err) });
  }
  try {
    await sendPushToUser(uid, { title, body: message, channelId: "wallet_v1", data: { type: "promo_offer", code } });
  } catch (err) {
    logger.warn("[promos] offer push failed", { uid, error: String(err) });
  }
  return true;
}

/** Run `fn` over items, `n` at a time. */
async function pool<T>(items: T[], n: number, fn: (t: T) => Promise<void>) {
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) await fn(items[i++]);
  }));
}

const MAX_GROUP = 10000;

/**
 * Private codes: deliver to everyone who matches the code's audience
 * (role, verified, new accounts, region by account currency). Safe to run
 * again — users who already have it are skipped. { code } → { matched, sent }
 */
export const adminSendPromoToGroup = onCall({ ...OPTS, timeoutSeconds: 540, memory: "512MiB" }, async (request) => {
  const actor = await requirePromoAdmin(request.auth?.uid);
  const code = str((request.data ?? {}).code).toUpperCase();
  const c = (await db().collection("promo_codes").doc(code).get()).data();
  if (!c) throw new HttpsError("not-found", "Code not found.");
  if (c.access !== "private") throw new HttpsError("failed-precondition", "Only private codes are sent to a group.");
  if (c.active !== true) throw new HttpsError("failed-precondition", "Resume the code before sending it.");
  const end = toMs(c.endsAt);
  if (end && end < Date.now()) throw new HttpsError("failed-precondition", "This code has expired.");

  const a = c.audience ?? {};
  let q: FirebaseFirestore.Query = db().collection("users");
  if (a.role === "worker") q = q.where("role", "==", "gigworker");
  if (a.role === "host") q = q.where("role", "==", "gighost");
  const snap = await q.get();
  const now = Date.now();
  const targets = snap.docs.filter((d) => {
    const u = d.data();
    if (u.pendingDeletion === true) return false;
    if (a.verifiedOnly === true && !isVerified(u)) return false;
    if (a.newUserDays) {
      const created = toMs(u.createdAt);
      if (!created || now - created > Number(a.newUserDays) * 86400000) return false;
    }
    const ccy = str(u.currencyCode).toUpperCase();
    if (a.region === "PH" && ccy !== "PHP") return false;
    if (a.region === "US" && ccy !== "USD") return false;
    return true;
  });
  if (targets.length > MAX_GROUP) {
    throw new HttpsError("failed-precondition", `This group has ${targets.length.toLocaleString("en-US")} users — narrow it to ${MAX_GROUP.toLocaleString("en-US")} or fewer.`);
  }
  let sent = 0;
  await pool(targets, 20, async (d) => {
    const ccy = str(d.data().currencyCode).toUpperCase() || null;
    if (await deliverOffer(code, c, d.id, ccy)) sent++;
  });
  await db().collection("promo_codes").doc(code).update({
    sentCount: FV.increment(sent), lastSentAt: FV.serverTimestamp(),
  });
  await log(actor, "promo_sent", `Sent private promo code ${code} to ${sent} user(s) (${targets.length} matched)`, code, { matched: targets.length, sent });
  return { matched: targets.length, sent };
});

/** Find a user for a restricted code: Giggre ID, phone or email. */
export const adminFindPromoUser = onCall(OPTS, async (request) => {
  await requirePromoAdmin(request.auth?.uid);
  const q = str((request.data ?? {}).query);
  let snap: FirebaseFirestore.DocumentSnapshot;
  if (q.includes("@")) {
    const docs = (await db().collection("users").where("email", "in", Array.from(new Set([q, q.toLowerCase()]))).limit(2).get()).docs;
    if (!docs.length) throw new HttpsError("not-found", "No Giggre user has that email.");
    snap = docs[0];
  } else {
    snap = await findUser(q);
  }
  const u = snap.data() ?? {};
  const w = (await db().collection("wallets").doc(snap.id).get()).data();
  return {
    uid: snap.id, name: str(u.name) || "Giggre user", userId: str(u.userId) || null,
    email: str(u.email) || null, role: str(u.role) || null, currencyCode: walletCurrency(w, u),
  };
});

/**
 * Restricted codes: one single-use code per chosen user, assigned to them and
 * delivered (For you + notification + push). Takes the same reward/date
 * fields as adminSavePromoCode plus { uids[], prefix?, note? }.
 * → { codes: [{ uid, code }] }
 */
export const adminCreateRestrictedCodes = onCall({ ...OPTS, timeoutSeconds: 300 }, async (request) => {
  const actor = await requirePromoAdmin(request.auth?.uid);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const uids = Array.isArray(d.uids) ? Array.from(new Set((d.uids as unknown[]).map(str).filter(Boolean))) : [];
  if (!uids.length) throw new HttpsError("invalid-argument", "Pick at least one user.");
  if (uids.length > 200) throw new HttpsError("invalid-argument", "Up to 200 users at a time.");
  const prefix = (str(d.prefix).toUpperCase().replace(/[^A-Z0-9]/g, "") || "VIP").slice(0, 10);
  const note = str(d.note).slice(0, 200) || undefined;
  // Validate the shared definition once (any valid code works as a placeholder).
  const def = parseDefinition({ ...d, code: `${prefix}-CHECK`, access: "public" });
  const batchId = db().collection("promo_codes").doc().id;
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const out: { uid: string; code: string; name: string }[] = [];

  for (const uid of uids) {
    const userSnap = await db().collection("users").doc(uid).get();
    if (!userSnap.exists) continue;
    const u = userSnap.data()!;
    let code = "";
    for (let i = 0; i < 8 && !code; i++) {
      let rand = "";
      for (let k = 0; k < 6; k++) rand += chars[Math.floor(Math.random() * chars.length)];
      const candidate = `${prefix}-${rand}`;
      const ref = db().collection("promo_codes").doc(candidate);
      try {
        await ref.create({
          ...def, code: candidate, access: "restricted", listed: false,
          audience: { role: "any", region: "any", verifiedOnly: false, newUserDays: null },
          maxRedemptions: 1, assignedUid: uid, assignedName: str(u.name) || null, assignedUserId: str(u.userId) || null,
          batchId, note: note ?? null, active: true, redemptionCount: 0,
          createdAt: FV.serverTimestamp(), createdBy: actor.uid, createdByName: actor.name, updatedAt: FV.serverTimestamp(),
        });
        code = candidate;
      } catch {
        // taken — try another
      }
    }
    if (!code) continue;
    const c = (await db().collection("promo_codes").doc(code).get()).data()!;
    const w = (await db().collection("wallets").doc(uid).get()).data();
    await deliverOffer(code, c, uid, walletCurrency(w, u), note);
    out.push({ uid, code, name: str(u.name) || "Giggre user" });
  }
  await log(actor, "promo_restricted_created", `Created ${out.length} restricted promo code(s) "${def.name}" (${def.type})`, batchId, { batchId, codes: out.map((o) => o.code) });
  return { codes: out, batchId };
});
