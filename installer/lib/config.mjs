import fs from 'node:fs';
import path from 'node:path';

export function readConfig(repo) {
  const f = path.join(repo, 'config', 'projects.json');
  if (!fs.existsSync(f)) return null;
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; }
}

/**
 * Pure: merges the installer's answers into the existing config. Keys the installer does not own
 * (panel.sections, special, your own additions) are kept, so running it again never wipes them.
 * The logo is gone: a leftover `panel.logo` from an older install is dropped.
 */
export function buildConfig(existing, { projects, ratio, system, statusLine, bar, colors, theme }) {
  const cfg = { ...(existing ?? {}) };
  const set = (key, value, isDefault) => { if (isDefault) delete cfg[key]; else cfg[key] = value; };
  set('bar', bar, bar !== '/' && bar !== '|');
  const layout = { ...(cfg.layout ?? {}) };
  if (ratio === 0.75) delete layout.claudeRatio; else layout.claudeRatio = ratio;
  set('layout', layout, !Object.keys(layout).length);
  set('statusLine', false, statusLine !== false);
  const panel = { ...(cfg.panel ?? {}) };
  if (system === false) panel.system = false; else delete panel.system;
  delete panel.logo;
  set('panel', panel, !Object.keys(panel).length);
  set('colors', colors, !colors);
  set('theme', theme, !theme);
  cfg.projects = projects;
  // projects last, as in the hand-written examples
  const { projects: p, ...rest } = cfg;
  return { ...rest, projects: p };
}

export function writeConfig(repo, cfg) {
  const f = path.join(repo, 'config', 'projects.json');
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + '\n', 'utf8');
  return f;
}
