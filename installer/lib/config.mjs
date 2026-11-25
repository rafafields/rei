import fs from 'node:fs';
import path from 'node:path';

export function readConfig(repo) {
  const f = path.join(repo, 'config', 'projects.json');
  if (!fs.existsSync(f)) return null;
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; }
}

/** Builds projects.json from answers; only non-default options are written. */
export function buildConfig({ projects, ratio, system, statusLine, logo }) {
  const cfg = {};
  if (ratio !== 0.75) cfg.layout = { claudeRatio: ratio };
  if (statusLine === false) cfg.statusLine = false;
  const panel = {};
  if (system === false) panel.system = false;
  if (logo === false) panel.logo = null;
  if (Object.keys(panel).length) cfg.panel = panel;
  cfg.projects = projects;
  return cfg;
}

export function writeConfig(repo, cfg) {
  const f = path.join(repo, 'config', 'projects.json');
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + '\n', 'utf8');
  return f;
}
