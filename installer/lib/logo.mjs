import fs from 'node:fs';
import path from 'node:path';
import { ansi } from './palette.mjs';

export const LOGOS = [
  { id: 'braille', label: 'Braille (the Rei default)', file: 'rei-braille.txt' },
  { id: 'ascii', label: 'ASCII letters: REI', file: 'rei-ascii.txt' },
];

export const logoFile = (repo) => path.join(repo, 'config', 'logo.txt');
export const presetFile = (repo, id) => path.join(repo, 'theme', 'logos', LOGOS.find((l) => l.id === id).file);

/** The logo the panel shows now: the configured path, else config/logo.txt, else the default. */
export function currentLogo(repo, cfg) {
  const candidates = [cfg?.panel?.logo, logoFile(repo), presetFile(repo, 'braille')].filter(Boolean);
  const file = candidates.find((f) => fs.existsSync(f));
  return file ? { file, text: fs.readFileSync(file, 'utf8').replace(/\s+$/, '') } : null;
}

export const widthOf = (text) => Math.max(0, ...text.split(/\r?\n/).map((l) => [...l.trimEnd()].length));
export const colourise = (text, hex) => text.split(/\r?\n/).map((l) => `${ansi(hex)}${l}\x1b[0m`).join('\n');
