import fs from 'node:fs';
import path from 'node:path';

export const BEGIN = '# >>> rei >>>';
export const END = '# <<< rei <<<';
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const re = new RegExp(String.raw`\r?\n?` + esc(BEGIN) + String.raw`[\s\S]*?` + esc(END) + String.raw`\r?\n?`);

/** Pure: removes the Rei block from profile text. */
export function removeBlock(text) {
  return text.replace(re, '\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n';
}

export function hasBlock(profile) {
  return fs.existsSync(profile) && fs.readFileSync(profile, 'utf8').includes(BEGIN);
}

export function uninstallBlock(profile) {
  if (!hasBlock(profile)) return false;
  fs.writeFileSync(profile, removeBlock(fs.readFileSync(profile, 'utf8')), 'utf8');
  return true;
}

export const installScript = (repo) => path.join(repo, 'scripts', 'install.ps1');
