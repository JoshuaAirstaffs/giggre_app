// Reads a line from the controlling terminal (/dev/tty), not stdin. A
// non-interactive shell (CI, an agent's tool call) has no controlling
// terminal, so these prompts can only be answered by a person.
import { openSync, closeSync, createReadStream, createWriteStream } from 'node:fs';
import readline from 'node:readline';

export async function askOnTty(promptText) {
  // Windows has no /dev/tty. There, ask on the console itself, but only when
  // stdin AND stdout are a real interactive console (PowerShell, cmd, the
  // VS Code terminal). An agent or a pipe has no TTY there either, so the
  // "a person must type this" guarantee still holds.
  if (process.platform === 'win32') {
    if (!process.stdin.isTTY || !process.stdout.isTTY) {
      throw new Error('No interactive terminal. This step must be typed by a person: run the command yourself in a terminal (not through an agent).');
    }
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    try {
      return await new Promise((resolve) => rl.question(promptText, resolve));
    } finally {
      rl.close();
    }
  }
  let fd;
  try {
    fd = openSync('/dev/tty', 'r+');
  } catch {
    throw new Error('No interactive terminal. This step must be typed by a person: run the command yourself in a terminal (not through an agent).');
  }
  const input = createReadStream(null, { fd, autoClose: false });
  const output = createWriteStream(null, { fd, autoClose: false });
  const rl = readline.createInterface({ input, output, terminal: true });
  try {
    return await new Promise((resolve) => rl.question(promptText, resolve));
  } finally {
    rl.close();
    input.destroy();
    output.destroy();
    try { closeSync(fd); } catch { /* already closed */ }
  }
}

// What a person typed, made comparable: terminal escape codes (e.g. the
// bracketed-paste markers Windows / VS Code terminals add on paste) and
// other control characters removed, spaces collapsed, upper case.
export function normalizeTyped(text) {
  return String(text ?? '')
    .replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, '')
    .replace(/[\x00-\x1f\x7f]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toUpperCase();
}

export async function confirmOnTty(phrase) {
  const typed = await askOnTty(`\nTo confirm, type exactly:\n\n  ${phrase}\n\n> `);
  if (normalizeTyped(typed) !== normalizeTyped(phrase)) throw new Error('Phrase did not match. Nothing was done.');
}
