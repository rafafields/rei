import { spawnSync } from 'node:child_process';

/**
 * Fonts offered by the installer. `winget` is only set where the package exists in the winget
 * source (checked with `winget show --id <id> --exact`); the others are installed by hand.
 */
export const FONTS = [
  { id: 'default', label: 'Keep the Windows Terminal default', family: null },
  { id: 'jetbrains', label: 'JetBrains Mono (Nerd Font)', family: 'JetBrainsMono Nerd Font', winget: 'DEVCOM.JetBrainsMonoNerdFont',
    // Windows lists the Nerd Font v3 under its short names (NF, NFM, NFP), not the long one.
    aliases: ['JetBrainsMono NF', 'JetBrainsMono NFM', 'JetBrainsMono NFP', 'JetBrainsMono Nerd Font Mono', 'JetBrainsMono Nerd Font Propo'] },
  { id: 'cascadia', label: 'Cascadia Code', family: 'Cascadia Code', manual: 'https://github.com/microsoft/cascadia-code/releases' },
  { id: 'consolas', label: 'Consolas', family: 'Consolas' },
  { id: 'other', label: 'Another font (type its name)', family: null },
];

/** Lowercase names of the font families Windows knows about, or null if they cannot be listed. */
export function installedFonts() {
  const r = spawnSync('powershell', ['-NoProfile', '-Command',
    'Add-Type -AssemblyName System.Drawing; (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }'],
  { encoding: 'utf8' });
  if (r.status !== 0) return null;
  return new Set(r.stdout.split(/\r?\n/).map((s) => s.trim().toLowerCase()).filter(Boolean));
}

/** `family` or any of its `aliases` is among the installed families (or the list is unknown). */
export const isInstalled = (families, family, aliases = []) => !families || [family, ...aliases].some((n) => families.has(n.toLowerCase()));

export const hasWinget = () => spawnSync('where.exe', ['winget'], { encoding: 'utf8' }).status === 0;

export function wingetInstall(id) {
  return spawnSync('winget', ['install', '--id', id, '--exact', '--source', 'winget',
    '--accept-package-agreements', '--accept-source-agreements'], { stdio: 'inherit' }).status === 0;
}
