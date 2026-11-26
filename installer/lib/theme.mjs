import fs from 'node:fs';
import path from 'node:path';
import { retintTheme } from './palette.mjs';

export const baseSchemeFile = (repo) => path.join(repo, 'theme', 'rei.json');

/**
 * Windows Terminal reads JSON "fragments" from here, so Rei adds its profile and colour scheme
 * without touching the user's settings.json.
 */
export function fragmentFile() {
  return path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'Windows Terminal', 'Fragments', 'rei', 'rei.json');
}

const GUID = '{7e3f6b1a-4c2d-4f0e-9a58-5d1b0c2e6a01}';

/** Pure: the fragment text (profile "Rei" + colour scheme "Rei") with the user's colours and font. */
export function buildFragment(baseText, mapper, font = {}) {
  const scheme = JSON.parse(retintTheme(baseText, mapper));
  const face = font.family ? { face: font.family } : {};
  const size = font.size ? { size: font.size } : {};
  const profile = {
    name: 'Rei',
    guid: GUID,
    commandline: 'powershell.exe -NoLogo',
    colorScheme: scheme.name,
    padding: '12, 10, 12, 10',
    ...(font.family || font.size ? { font: { ...face, ...size } } : {}),
  };
  return JSON.stringify({ profiles: [profile], schemes: [scheme] }, null, 2) + '\n';
}

export function writeFragment(repo, mapper, font) {
  const out = fragmentFile();
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, buildFragment(fs.readFileSync(baseSchemeFile(repo), 'utf8'), mapper, font), 'utf8');
  return out;
}

export function removeFragment() {
  const out = fragmentFile();
  if (!fs.existsSync(out)) return false;
  fs.rmSync(out);
  try { fs.rmdirSync(path.dirname(out)); } catch { /* not empty: leave it */ }
  return true;
}
