// Removes synthetic load-test data.
//
// Emulator: wipes the isolated demo project (nothing else can be affected).
// Other environments: signs in as each synthetic user from the population
// files and deletes only what that user created and the rules let them
// delete (their gigs carrying the load-test marker, messages they sent, their
// user doc, their Auth account). Rule-protected leftovers (chat_rooms,
// notifications, publicProfiles) are listed for a person to remove with the
// Firebase CLI. Requires a typed confirmation on a real terminal.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { STATE_DIR, REPORTS_DIR } from './config.mjs';
import { wipeEmulator, emulatorUp, signIn, runQuery, deleteDocRest, listDocs, deleteSelf, endpoints } from './rest.mjs';
import { passwordFn } from './seed.mjs';
import { confirmOnTty } from './tty.mjs';

export async function cleanup({ cfg, envName, log }) {
  const env = cfg.environments[envName];
  if (!env) throw new Error(`Unknown environment ${envName}`);
  if (env.locked || env.projectId === 'giggre-prod') throw new Error('Refusing: production is locked.');

  if (endpoints(env).emu) {
    if (!(await emulatorUp(env))) throw new Error('Emulator not running; nothing to clean (emulator data is in memory and is gone when it stops).');
    await wipeEmulator(env);
    log(`Emulator project ${env.projectId} wiped.`);
    return;
  }

  const files = readdirSync(STATE_DIR).filter((f) => f.startsWith(`population-${envName}-`));
  const people = files.flatMap((f) => JSON.parse(readFileSync(path.join(STATE_DIR, f), 'utf8')).people.filter((p) => p.uid));
  const marker = cfg.safety.syntheticMarkerField;
  const phrase = `DELETE ${people.length} SYNTHETIC USERS IN ${env.projectId}`;
  log(`This deletes data created by ${people.length} synthetic accounts (emails @${cfg.safety.syntheticEmailDomain}) in ${env.projectId}.`);
  await confirmOnTty(phrase);

  const leftovers = [];
  const password = passwordFn(env);
  let n = 0;
  for (const p of people) {
    if (!p.email.endsWith(`@${cfg.safety.syntheticEmailDomain}`)) continue; // never touch a non-synthetic address
    let tok;
    try { tok = (await signIn(env, p.email, password(p.email))).idToken; } catch { continue; }
    for (const col of ['open_gigs', 'offered_gigs', 'quick_gigs']) {
      for (const d of await runQuery(env, col, { hostId: p.uid }, tok)) {
        if (!d.data[marker]) continue; // only gigs this tool created
        const rel = d.name.split('/documents/')[1];
        await deleteDocRest(env, rel, tok).catch(() => leftovers.push(rel));
      }
    }
    for (const room of await runQuery(env, 'chat_rooms', { createdByUid: p.uid }, tok).catch(() => [])) {
      const rel = room.name.split('/documents/')[1];
      for (const msg of await listDocs(env, `${rel}/messages`, tok).catch(() => [])) {
        await deleteDocRest(env, `${rel}/messages/${msg.id}`, tok).catch(() => {});
      }
      leftovers.push(rel); // room docs are admin-delete only
    }
    await deleteDocRest(env, `users/${p.uid}`, tok).catch(() => leftovers.push(`users/${p.uid}`));
    leftovers.push(`publicProfiles/${p.uid}`);
    await deleteSelf(env, tok).catch(() => {});
    if (++n % 200 === 0) log(`  ${n}/${people.length}`);
  }
  const out = path.join(REPORTS_DIR, `cleanup-leftovers-${envName}-${Date.now()}.txt`);
  writeFileSync(out, `# Rule-protected synthetic docs left in ${env.projectId}.\n# A person can remove them with: firebase firestore:delete --project ${env.projectId} <path>\n${leftovers.join('\n')}\n`);
  log(`Done. ${leftovers.length} rule-protected paths listed in ${out} (notifications created for synthetic hosts are also synthetic; filter by userId from the population files).`);
}
