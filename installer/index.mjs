#!/usr/bin/env node
import * as p from '@clack/prompts';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { checkRequirements, powershell, profilePath } from './lib/system.mjs';
import { alacrittyConfigPath, addImport, removeImport, backup } from './lib/alacritty.mjs';
import { readConfig, buildConfig, writeConfig } from './lib/config.mjs';
import { uninstallBlock, hasBlock, installScript } from './lib/profile.mjs';

const args = new Set(process.argv.slice(2));
const DRY = args.has('--dry-run');
const UNINSTALL = args.has('--uninstall');
const REPO_URL = 'https://github.com/rafafields/rei.git';
const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const inCheckout = fs.existsSync(path.join(here, 'scripts', 'rei.ps1'));

const cancelled = (v) => { if (p.isCancel(v)) { p.cancel('Cancelled. Nothing else was changed.'); process.exit(1); } return v; };
const norm = (s) => s.trim().replace(/^"|"$/g, '').replace(/\\/g, '/');

async function main() {
  p.intro(`Rei (零) installer${DRY ? ' — dry run' : ''}${UNINSTALL ? ' — uninstall' : ''}`);
  if (process.platform !== 'win32') { p.cancel('Rei only works on Windows.'); process.exit(1); }

  const repo = await locateRepo();
  if (UNINSTALL) return uninstall(repo);

  // 1. requirements
  const reqs = checkRequirements();
  p.note(reqs.map((r) => `${r.ok ? '✔' : '✘'} ${r.name}${r.ok ? '' : `  →  ${r.help}`}`).join('\n'), 'Requirements');
  if (reqs.some((r) => !r.ok)) {
    if (!cancelled(await p.confirm({ message: 'Something is missing. Continue anyway?', initialValue: false }))) {
      p.cancel('Install what is missing and run this again.');
      process.exit(1);
    }
  }

  // 2. projects
  const existing = readConfig(repo);
  let projects = existing?.projects ?? [];
  if (projects.length) {
    p.log.info(`Found config/projects.json with ${projects.length} project(s): ${projects.map((x) => x.name).join(', ')}`);
    const keep = cancelled(await p.confirm({ message: 'Keep them?', initialValue: true }));
    if (!keep) projects = [];
  }
  while (true) {
    if (projects.length && !cancelled(await p.confirm({ message: 'Add another project?', initialValue: false }))) break;
    const dir = norm(cancelled(await p.text({
      message: 'Project folder',
      placeholder: 'C:/code/my-project',
      validate: (v) => (fs.existsSync(v.trim().replace(/^"|"$/g, '')) ? undefined : 'That folder does not exist'),
    })));
    const name = cancelled(await p.text({
      message: 'Name for the command', initialValue: path.basename(dir).toLowerCase(),
      validate: (v) => (!v.trim() ? 'Required' : /\s/.test(v) ? 'No spaces' : projects.some((x) => x.name === v.trim()) ? 'Already used' : undefined),
    }));
    const check = cancelled(await p.text({ message: 'Check command (optional, key "c" in the panel)', placeholder: 'npm test', defaultValue: '' }));
    projects.push({ name: name.trim(), path: dir, ...(check.trim() ? { check: check.trim() } : {}) });
    if (!cancelled(await p.confirm({ message: 'Add another project?', initialValue: false }))) break;
  }
  if (!projects.length) { p.cancel('At least one project is needed.'); process.exit(1); }

  // 3. options
  const ratio = existing?.layout?.claudeRatio ?? 0.75;
  const custom = cancelled(await p.confirm({ message: 'Customise layout and panel? (defaults are fine)', initialValue: false }));
  let opts = { ratio, system: existing?.panel?.system !== false, statusLine: existing?.statusLine !== false, logo: existing?.panel?.logo !== null };
  if (custom) {
    const r = cancelled(await p.select({ message: 'Share of the screen for Claude Code', initialValue: ratio, options: [
      { value: 0.6, label: '60 %' }, { value: 0.7, label: '70 %' }, { value: 0.75, label: '75 % (3/4)' }, { value: 0.8, label: '80 %' }] }));
    const feats = cancelled(await p.multiselect({ message: 'Show', required: false,
      initialValues: ['system', 'logo', 'statusLine'].filter((k) => opts[k]),
      options: [{ value: 'system', label: 'Memory and disk in the panel' }, { value: 'logo', label: 'Logo in the panel' }, { value: 'statusLine', label: 'Rei status line in Claude Code' }] }));
    opts = { ratio: r, system: feats.includes('system'), logo: feats.includes('logo'), statusLine: feats.includes('statusLine') };
  }

  const keys = cancelled(await p.confirm({ message: 'Install Rei key bindings? (Shift+Enter new line, Ctrl+Backspace/Delete delete words, selection copies to clipboard)', initialValue: true }));

  const bar = cancelled(await p.select({ message: 'Progress bar style (panel and status line)', initialValue: existing?.bar === '/' ? '/' : '|', options: [
    { value: '|', label: '|||||||||| 60%' }, { value: '/', label: '////////// 60%' }] }));

  // 4. summary
  const themeFile = path.join(repo, 'theme', 'rei.toml');
  const keysFile = path.join(repo, 'theme', 'keys.toml');
  const alaFile = alacrittyConfigPath();
  const plan = [
    `Write ${path.join(repo, 'config', 'projects.json')} (${projects.length} project(s))`,
    `${fs.existsSync(alaFile) ? 'Add the theme import to' : 'Create'} ${alaFile}${fs.existsSync(alaFile) ? ' (backup first)' : ''}`,
    `${hasBlock(profilePath() || '') ? 'Update' : 'Add'} the rei function in your PowerShell profile`,
  ];
  p.note(plan.map((l) => `• ${l}`).join('\n'), DRY ? 'Would do (dry run)' : 'About to do');
  if (DRY) { p.outro('Dry run: nothing was changed.'); return; }
  if (!cancelled(await p.confirm({ message: 'Go ahead?', initialValue: true }))) { p.cancel('Nothing was changed.'); process.exit(0); }

  // 5. apply
  const s = p.spinner();
  s.start('Applying');
  writeConfig(repo, buildConfig({ projects, ...opts, bar }));
  const old = fs.existsSync(alaFile) ? fs.readFileSync(alaFile, 'utf8') : '';
  let next = addImport(old, themeFile);
  next = keys ? addImport(next, keysFile) : removeImport(next, keysFile);
  if (next !== old) {
    const b = backup(alaFile);
    fs.mkdirSync(path.dirname(alaFile), { recursive: true });
    fs.writeFileSync(alaFile, next, 'utf8');
    if (b) p.log.info(`Backup: ${b}`);
  }
  const ps = powershell(['-File', installScript(repo)]);
  s.stop(ps.status === 0 ? 'Done' : 'Finished with a profile error');
  if (ps.status !== 0) p.log.error((ps.stderr || ps.stdout).trim());

  // 6. Claude Code
  p.log.success('Open a new PowerShell window and run: rei');
  if (cancelled(await p.confirm({ message: 'Open Claude Code in the repo to customise Rei (palette, panel, status line)?', initialValue: false }))) {
    spawnSync('claude', ['Read CLAUDE.md, then ask me what I want to change in Rei.'], { cwd: repo, stdio: 'inherit', shell: true });
  }
  p.outro('Rei is ready.');
}

async function locateRepo() {
  if (inCheckout) {
    p.log.info(`Using the checkout at ${here}`);
    return here;
  }
  const dir = path.resolve(cancelled(await p.text({ message: 'Where should Rei be installed?', initialValue: 'C:/code/rei' })));
  if (fs.existsSync(path.join(dir, 'scripts', 'rei.ps1'))) return dir;
  if (fs.existsSync(dir) && fs.readdirSync(dir).length) { p.cancel(`${dir} exists and is not a Rei checkout.`); process.exit(1); }
  if (DRY) { p.log.info(`Would clone ${REPO_URL} into ${dir}`); return dir; }
  const r = spawnSync('git', ['clone', REPO_URL, dir], { stdio: 'inherit' });
  if (r.status !== 0) { p.cancel('git clone failed.'); process.exit(1); }
  return dir;
}

async function uninstall(repo) {
  const alaFile = alacrittyConfigPath();
  const prof = profilePath();
  const plan = [
    `Remove the theme import from ${alaFile}`,
    `Remove the rei block from ${prof}`,
    `Keep ${repo} and config/projects.json (your data)`,
  ];
  p.note(plan.map((l) => `• ${l}`).join('\n'), DRY ? 'Would do (dry run)' : 'About to do');
  if (DRY) { p.outro('Dry run: nothing was changed.'); return; }
  if (!cancelled(await p.confirm({ message: 'Go ahead?', initialValue: true }))) { p.cancel('Nothing was changed.'); return; }
  if (fs.existsSync(alaFile)) {
    const old = fs.readFileSync(alaFile, 'utf8');
    const next = removeImport(removeImport(old, path.join(repo, 'theme', 'rei.toml')), path.join(repo, 'theme', 'keys.toml'));
    if (next !== old) { backup(alaFile); fs.writeFileSync(alaFile, next, 'utf8'); }
  }
  if (prof) uninstallBlock(prof);
  p.outro('Uninstalled. Delete the folder yourself if you want it gone.');
}

main().catch((e) => { p.cancel(String(e?.stack || e)); process.exit(1); });
