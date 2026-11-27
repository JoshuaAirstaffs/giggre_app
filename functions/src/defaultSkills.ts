import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { FieldPath, getFirestore } from "firebase-admin/firestore";
import { firestoreTriggerRegion } from "./region";

// ── Default skills ──────────────────────────────────────────────────────────
// General "anyone can do it" skills every user starts with, so a new worker
// matches gigs (and nearby-gig alerts) right away instead of starting empty.
// Every other skill still goes through a skill request + admin approval.
//
// Names must match skills/{id}.name exactly — skillsXP is keyed by skill
// name. Changing this list affects new sign-ups; existing users only get
// additions by running tools/backfill-default-skills.mjs again (it never
// removes a skill).
export const DEFAULT_SKILLS: readonly string[] = [
  // Errands & delivery
  "Errand Running",
  "Personal Shopper",
  "Grocery Delivery",
  "Courier Service",
  // Moving
  "Moving Assistance",
  "Furniture Delivery",
  "Furniture Assembly",
  // Home
  "House Cleaning",
  "Laundry",
  "Home Organization",
  "Gardening",
  // Car, pets, events
  "Car Wash",
  "Dog Walking",
  "Pet Sitting",
  "Event Setup",
  // Office & digital
  "Data Entry",
  "Virtual Assistant",
  "Administrative Assistant",
  "Social Media Management",
  "Content Writing",
  // Creative (basic level)
  "Photography",
  "Video Editing",
  "Graphic Design",
  // Tutoring
  "English Tutor",
  "Math Tutor",
];

const OPTS = { region: firestoreTriggerRegion(), maxInstances: 100 } as const;

/**
 * The default skills [skillsXP] doesn't have yet (case-insensitive, so an
 * existing "house cleaning" isn't duplicated). New ones start at XP 1, the
 * same as an approved skill request.
 */
export function missingDefaultSkills(skillsXP: unknown): string[] {
  const have = new Set(
    Object.keys(
      skillsXP && typeof skillsXP === "object" ? (skillsXP as object) : {}
    ).map((k) => k.toLowerCase().trim())
  );
  return DEFAULT_SKILLS.filter((s) => !have.has(s.toLowerCase()));
}

export const grantDefaultSkillsOnSignup = onDocumentCreated(
  { ...OPTS, document: "users/{uid}" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const missing = missingDefaultSkills(snap.get("skillsXP"));
    if (missing.length === 0) return;
    // Field paths, not "skillsXP.<name>" strings — names contain spaces.
    const args: unknown[] = [];
    for (const name of missing) args.push(new FieldPath("skillsXP", name), 1);
    const [first, firstVal, ...rest] = args;
    await getFirestore()
      .collection("users")
      .doc(event.params.uid)
      .update(first as FieldPath, firstVal, ...rest);
  }
);
