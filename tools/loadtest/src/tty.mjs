// Reads a line from the controlling terminal (/dev/tty), not stdin. A
// non-interactive shell (CI, an agent's tool call) has no controlling
// terminal, so these prompts can only be answered by a person.
import { openSync, closeSync, createReadStream, createWriteStream } from 'node:fs';
import readline from 'node:readline';

export async function askOnTty(promptText) {
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

export async function confirmOnTty(phrase) {
  const typed = await askOnTty(`\nTo confirm, type exactly:\n\n  ${phrase}\n\n> `);
  if (typed.trim() !== phrase) throw new Error('Phrase did not match. Nothing was done.');
}
