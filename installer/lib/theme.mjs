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
const PANEL_GUID = '{7e3f6b1a-4c2d-4f0e-9a58-5d1b0c2e6a02}';
const DEFAULT_SIZE = 12; // Windows Terminal's own default

/** The panel text is a bit smaller than Claude's: 85 % of the font size, in half points. */
export const panelFontSize = (size) => Math.max(6, Math.round((size || DEFAULT_SIZE) * 0.85 * 2) / 2);

/** Pure: the fragment text (profiles "Rei" and "Rei Panel" + colour scheme "Rei") with the user's colours and font. */
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
  // Same look, smaller text, hidden from the new-tab menu: used by the panel pane only.
  const panel = { ...profile, name: 'Rei Panel', guid: PANEL_GUID, hidden: true, font: { ...face, size: panelFontSize(font.size) } };
  return JSON.stringify({ profiles: [profile, panel], schemes: [scheme] }, null, 2) + '\n';
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
