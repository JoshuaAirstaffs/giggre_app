// Firestore document triggers have to run in a region compatible with the
// database's location, and the two Firebase projects differ:
//
//   dev  (simpleproject-8ff7a) — Firestore in asia-east2 → asia-east2 triggers
//   prod (giggre-prod)         — Firestore in nam5       → us-central1 triggers
//
// A hardcoded region therefore works on exactly one of them. Deployed to the
// other, document triggers either fail outright or are created and never
// fire, which looks identical to a feature that simply doesn't work.
const DEV_PROJECT_ID = "simpleproject-8ff7a";

// Set by the CLI during deploy-time function discovery, and by the runtime in
// production. index.ts already relies on this for its secret gating.
export function currentProjectId(): string | undefined {
  return process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT;
}

export function isDevProject(): boolean {
  return currentProjectId() === DEV_PROJECT_ID;
}

/// The region every Firestore trigger in this codebase should run in.
/// Resolved at deploy time from the project being deployed to.
export function firestoreTriggerRegion(): string {
  return isDevProject() ? "asia-east2" : "us-central1";
}
