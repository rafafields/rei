import fs from 'node:fs';
import path from 'node:path';

export function alacrittyConfigPath() {
  return path.join(process.env.APPDATA || '', 'alacritty', 'alacritty.toml');
}

const toToml = (p) => p.replace(/\\/g, '/');
const IMPORT_RE = /^(\s*import\s*=\s*)\[([\s\S]*?)\]/m;

/** Pure: returns the new file text with the theme import added (or unchanged). */
export function addImport(text, themePath) {
  const item = JSON.stringify(toToml(themePath));
  if (text.includes(item)) return text;
  const m = text.match(IMPORT_RE);
  if (m) {
    const inner = m[2].trim();
    const joined = inner ? `${inner.replace(/,\s*$/, '')}, ${item}` : item;
    return text.replace(IMPORT_RE, `${m[1]}[${joined}]`);
  }
  if (/^\[general\]\s*$/m.test(text)) {
    return text.replace(/^\[general\]\s*$/m, `[general]\nimport = [${item}]`);
  }
  const sep = text.length && !text.endsWith('\n') ? '\n' : '';
  return `${text}${sep}${text.length ? '\n' : ''}[general]\nimport = [${item}]\n`;
}

/** Pure: removes the theme import, leaving everything else. */
export function removeImport(text, themePath) {
  const item = JSON.stringify(toToml(themePath));
  if (!text.includes(item)) return text;
  return text.replace(IMPORT_RE, (all, head, inner) => {
    const kept = inner.split(',').map((s) => s.trim()).filter((s) => s && s !== item);
    return `${head}[${kept.join(', ')}]`;
  });
}

export function backup(file) {
  if (!fs.existsSync(file)) return null;
  const dest = `${file}.bak-rei-${new Date().toISOString().replace(/[:.]/g, '-')}`;
  fs.copyFileSync(file, dest);
  return dest;
}
