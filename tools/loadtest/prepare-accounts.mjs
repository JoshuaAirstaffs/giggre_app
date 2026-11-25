#!/usr/bin/env node
// Pre-creates the synthetic login accounts for a billable environment in one
// bulk import, instead of thousands of sign-ups from one computer (Firebase
// Auth allows only ~100 new accounts per hour per IP, so seeding a stage on
// 'staging' fails with TOO_MANY_ATTEMPTS_TRY_LATER).
//
// Writes state/accounts-import.json (gitignored) with the same e-mails and
// passwords the runner derives (seed.mjs passwordFn, LOADTEST_PASSWORD_SALT),
// hashed with bcrypt. Import it with the Firebase CLI — that uses your own
// `firebase login`, no service-account key needed:
//
//   node prepare-accounts.mjs --users 5000
//   firebase auth:import state/accounts-import.json --hash-algo=BCRYPT --project dev
//
// Seeding then just signs in to these accounts (EMAIL_EXISTS → sign in).
// 5000 covers stages 1 and 2 (same e-mails: lt-w-000123@… / lt-h-000124@…).
// New-user registrations during a run still sign up live (stage 1: ~40).
import { writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import bcrypt from 'bcryptjs';
import { loadConfig, STATE_DIR } from './src/config.mjs';
import { passwordFn } from './src/seed.mjs';
import { pad } from './src/synthetic.mjs';

const args = process.argv.slice(2);
const opt = (n) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : undefined; };
const users = Number(opt('users') ?? 5000);
const envName = opt('env') ?? 'staging';

const cfg = loadConfig();
const env = cfg.environments[envName];
if (!env || env.hosts) throw new Error(`'${envName}' is not a billable environment; the emulator doesn't need this.`);
if (env.locked) throw new Error(`'${envName}' is locked.`);
const password = passwordFn(env); // throws if LOADTEST_PASSWORD_SALT isn't set
const hostShare = cfg.workload.roles.host;
const domain = cfg.safety.syntheticEmailDomain;

const out = [];
const t0 = Date.now();
for (let i = 0; i < users; i++) {
  // Same role rule and e-mail as synthetic.mjs identity().
  const role = Math.floor((i + 1) * hostShare) > Math.floor(i * hostShare) ? 'host' : 'worker';
  const email = `lt-${role[0]}-${pad(i)}@${domain}`;
  const hash = bcrypt.hashSync(password(email), 6);
  out.push({ localId: `lt${role[0]}${pad(i)}`, email, emailVerified: false, passwordHash: Buffer.from(hash).toString('base64'), displayName: `LT ${role} ${pad(i)}` });
  if ((i + 1) % 500 === 0) process.stdout.write(`  ${i + 1}/${users}\n`);
}
mkdirSync(STATE_DIR, { recursive: true });
const file = path.join(STATE_DIR, 'accounts-import.json');
writeFileSync(file, JSON.stringify({ users: out }));
console.log(`\nWrote ${out.length} accounts to ${path.relative(process.cwd(), file)} in ${((Date.now() - t0) / 1000).toFixed(1)}s.`);
console.log(`Now import them (uses your firebase login):\n  firebase.cmd auth:import ${path.relative(process.cwd(), file)} --hash-algo=BCRYPT --project ${envName === 'staging' ? 'dev' : env.projectId}`);
console.log('Delete that file after importing (it holds password hashes for the test accounts).');
