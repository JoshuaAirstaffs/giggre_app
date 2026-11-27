#!/usr/bin/env node
// One-time backfill: give every existing user the default general skills
// (functions/src/defaultSkills.ts → DEFAULT_SKILLS) they don't already have.
// New sign-ups get them from the grantDefaultSkillsOnSignup trigger.
//
// Only ADDS missing skills (XP 1); never removes or changes an existing one.
// Matching is case-insensitive, so "house cleaning" isn't duplicated.
//
// Uses your Firebase CLI login (run `firebase login` first). Dry run by
// default — prints what it would change; pass --apply to write.
//
//   cd functions && npm run build && cd ..
//   node tools/backfill-default-skills.mjs --project simpleproject-8ff7a
//   node tools/backfill-default-skills.mjs --project simpleproject-8ff7a --apply
//   node tools/backfill-default-skills.mjs --project giggre-prod            # dry run
//   node tools/backfill-default-skills.mjs --project giggre-prod --apply    # prod: only with sign-off

import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
const project = args[args.indexOf("--project") + 1];
const apply = args.includes("--apply");
if (!args.includes("--project") || !project || project.startsWith("--")) {
  console.error("Usage: node tools/backfill-default-skills.mjs --project <projectId> [--apply]");
  process.exit(1);
}

const { DEFAULT_SKILLS, missingDefaultSkills } = require(
  path.join(here, "../functions/lib/defaultSkills.js")
);

// Access token from the Firebase CLI's own login.
const ft = path.join(execSync("npm root -g").toString().trim(), "firebase-tools");
const auth = require(path.join(ft, "lib/auth.js"));
const { configstore } = require(path.join(ft, "lib/configstore.js"));
const tokens = configstore.get("tokens");
if (!tokens?.refresh_token) {
  console.error("Not logged in. Run `firebase login` first.");
  process.exit(1);
}
const { access_token: token } = await auth.getAccessToken(tokens.refresh_token, []);

const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

// Firestore REST field paths: segments with spaces etc. are backtick-quoted.
const fieldPath = (name) => "skillsXP.`" + name.replace(/\\/g, "\\\\").replace(/`/g, "\\`") + "`";

console.log(`${apply ? "APPLY" : "DRY RUN"} on ${project} — ${DEFAULT_SKILLS.length} default skills`);

let pageToken = "";
let scanned = 0;
let toUpdate = 0;
let updated = 0;
let failed = 0;
const perSkill = new Map();

do {
  const url = `${base}/users?pageSize=300&mask.fieldPaths=skillsXP${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ""}`;
  const res = await fetch(url, { headers });
  const page = await res.json();
  if (!res.ok) {
    console.error("List failed:", JSON.stringify(page).slice(0, 300));
    process.exit(1);
  }
  for (const doc of page.documents ?? []) {
    scanned++;
    const xp = doc.fields?.skillsXP?.mapValue?.fields ?? {};
    const missing = missingDefaultSkills(xp);
    if (missing.length === 0) continue;
    toUpdate++;
    for (const s of missing) perSkill.set(s, (perSkill.get(s) ?? 0) + 1);
    if (!apply) continue;

    const fields = {};
    for (const s of missing) fields[s] = { integerValue: "1" };
    const mask = missing.map((s) => `updateMask.fieldPaths=${encodeURIComponent(fieldPath(s))}`).join("&");
    const r = await fetch(`https://firestore.googleapis.com/v1/${doc.name}?${mask}&currentDocument.exists=true`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({ fields: { skillsXP: { mapValue: { fields } } } }),
    });
    if (r.ok) {
      updated++;
    } else {
      failed++;
      console.error("Update failed for", doc.name.split("/").pop(), (await r.text()).slice(0, 200));
    }
  }
  pageToken = page.nextPageToken ?? "";
} while (pageToken);

console.log(`Users scanned: ${scanned}`);
console.log(`Users missing at least one default skill: ${toUpdate}`);
if (apply) console.log(`Updated: ${updated}  Failed: ${failed}`);
else console.log("Dry run — nothing written. Re-run with --apply to write.");
console.log("Skills to add (users per skill):");
for (const s of DEFAULT_SKILLS) console.log(`  ${s}: ${perSkill.get(s) ?? 0}`);
