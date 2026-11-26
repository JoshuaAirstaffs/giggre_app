// Reads a line from the controlling terminal (/dev/tty), not stdin. A
// non-interactive shell (CI, an agent's tool call) has no controlling
// terminal, so these prompts can only be answered by a person.
import { openSync, closeSync, createReadStream, createWriteStream } from 'node:fs';
import readline from 'node:readline';

export async function askOnTty(promptText) {
  // On Windows there is no /dev/tty; the console is two separate devices.
  let inFd, outFd;
  try {
    if (process.platform === 'win32') {
      // A bare 'CONIN$' is resolved relative to cwd by Node before hitting the
      // Win32 API, which breaks the special device name. The \\.\ device
      // namespace prefix forces an absolute, cwd-independent device path.
      inFd = openSync('\\\\.\\CONIN$', 'r');
      outFd = openSync('\\\\.\\CONOUT$', 'w');
    } else {
      inFd = outFd = openSync('/dev/tty', 'r+');
    }
  } catch {
    throw new Error('No interactive terminal. This step must be typed by a person: run the command yourself in a terminal (not through an agent).');
  }
  const input = createReadStream(null, { fd: inFd, autoClose: false });
  const output = createWriteStream(null, { fd: outFd, autoClose: false });
  const rl = readline.createInterface({ input, output, terminal: true });
  try {
    return await new Promise((resolve) => rl.question(promptText, resolve));
  } finally {
    rl.close();
    input.destroy();
    output.destroy();
    try { closeSync(inFd); } catch { /* already closed */ }
    if (outFd !== inFd) { try { closeSync(outFd); } catch { /* already closed */ } }
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
