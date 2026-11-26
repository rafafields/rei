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
import { DEFAULT_PRIMARY, makeMapper, normaliseHex, panelColors, swatch } from './lib/palette.mjs';
import { FONTS, installedFonts, isInstalled, hasWinget, wingetInstall } from './lib/fonts.mjs';
import { LOGOS, currentLogo, logoFile, presetFile, widthOf, colourise } from './lib/logo.mjs';
import { baseThemeFile, generatedThemeFile, writeTheme } from './lib/theme.mjs';

const args = new Set(process.argv.slice(2));
const DRY = args.has('--dry-run');
const UNINSTALL = args.has('--uninstall');
const CLAUDE_ONLY = args.has('--claude');
// --customize (or --customise): the whole process again, with every customisation question and the
// current values as defaults.
const CUSTOMISE = args.has('--customize') || args.has('--customise');
const REPO_URL = 'https://github.com/rafafields/rei.git';
const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const inCheckout = fs.existsSync(path.join(here, 'scripts', 'rei.ps1'));

const cancelled = (v) => { if (p.isCancel(v)) { p.cancel('Cancelled. Nothing else was changed.'); process.exit(1); } return v; };
const norm = (s) => s.trim().replace(/^"|"$/g, '').replace(/\\/g, '/');

const COLOURS = [
  { value: DEFAULT_PRIMARY, label: 'Crimson (Rei default)' },
  { value: 'f08a24', label: 'Orange' },
  { value: 'e6b422', label: 'Gold' },
  { value: '3ecf8e', label: 'Mint' },
  { value: '2fb8d6', label: 'Cyan' },
  { value: '4f8cff', label: 'Blue' },
  { value: '9b6bff', label: 'Violet' },
  { value: 'ec5fa6', label: 'Pink' },
  { value: 'custom', label: 'Another colour (hex code)' },
];

async function askColour(message, initial) {
  const known = COLOURS.some((c) => c.value === initial);
  const pick = cancelled(await p.select({ message, initialValue: known ? initial : 'custom', options: COLOURS.map((c) => (c.value === 'custom' ? c : { ...c, hint: `#${c.value}` })) }));
  if (pick !== 'custom') return pick;
  return normaliseHex(cancelled(await p.text({
    message: 'Hex code', placeholder: '#e0364a', initialValue: known || !initial ? '' : `#${initial}`,
    validate: (v) => (normaliseHex(v) ? undefined : 'Use a hex code like #e0364a'),
  })));
}

async function askFont(prev) {
  const families = installedFonts();
  const hint = (f) => (f.family === null ? undefined : isInstalled(families, f.family) ? 'installed' : f.winget ? 'not installed, can be installed with winget' : 'not installed');
  const prevId = prev?.family ? (FONTS.find((f) => f.family === prev.family)?.id ?? 'other') : 'default';
  const id = cancelled(await p.select({ message: 'Terminal font', initialValue: prevId, options: FONTS.map((f) => ({ value: f.id, label: f.label, hint: hint(f) })) }));
  let font = FONTS.find((f) => f.id === id);
  if (id === 'other') {
    const family = cancelled(await p.text({ message: 'Font family name', placeholder: 'Fira Code', initialValue: prevId === 'other' ? prev.family : '', validate: (v) => (v.trim() ? undefined : 'Required') })).trim();
    font = { id, label: family, family };
  }
  let install = null;
  if (font.family && !isInstalled(families, font.family)) {
    if (font.winget && hasWinget()) {
      if (cancelled(await p.confirm({ message: `${font.family} is not installed. Install it with winget (${font.winget})?`, initialValue: true }))) install = font;
    } else {
      p.log.warn(`${font.family} is not installed${font.manual ? `: get it from ${font.manual}` : ''}. Alacritty will use its default font until it is.`);
    }
  }
  const size = String(cancelled(await p.text({
    message: 'Font size, e.g. 12 (leave empty to keep the current one)', initialValue: prev?.size ? String(prev.size) : '',
    validate: (v) => (!v?.trim() || (Number(v) >= 6 && Number(v) <= 40) ? undefined : 'A number between 6 and 40'),
  })) ?? '').trim();
  return { family: font.family, size: size ? Number(size) : null, install };
}

async function main() {
  p.intro(`Rei (零) installer${DRY ? ' — dry run' : ''}${UNINSTALL ? ' — uninstall' : ''}${CUSTOMISE ? ' — customise' : ''}`);
  if (process.platform !== 'win32') { p.cancel('Rei only works on Windows.'); process.exit(1); }

  const repo = await locateRepo();
  if (UNINSTALL) return uninstall(repo);
  if (CLAUDE_ONLY) {
    if (DRY) { p.outro('Dry run: would open Claude Code in the repo with docs/customise-with-claude.md.'); return; }
    launchClaude(repo);
    p.outro('Done.');
    return;
  }

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
    if (!cancelled(await p.confirm({ message: 'Keep them?', initialValue: true }))) projects = [];
  }
  // One question per round: "add one?" only when there are projects already, "add another?" after each.
  let more = projects.length === 0 || cancelled(await p.confirm({ message: 'Add a project?', initialValue: false }));
  while (more) {
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
    more = cancelled(await p.confirm({ message: 'Add another project?', initialValue: false }));
  }
  if (!projects.length) { p.cancel('At least one project is needed.'); process.exit(1); }

  // 3. colours
  const prevTheme = existing?.theme ?? {};
  const primary = await askColour('Main colour', prevTheme.primary ?? DEFAULT_PRIMARY);
  let secondary = null;
  if (cancelled(await p.confirm({ message: 'Choose secondary colours too? (otherwise they are derived from the main one)', initialValue: !!prevTheme.secondary }))) {
    secondary = await askColour('Secondary colour (git branch, "ok" marks, pink and cyan of the terminal)', prevTheme.secondary ?? 'd4577a');
  }
  const mapper = makeMapper({ primary, secondary });
  p.log.step(`Main ${swatch(mapper.primary)} #${mapper.primary}${secondary ? `   Secondary ${swatch(secondary)} #${secondary}` : ''}`);
  if (mapper.adjusted) p.log.warn(`#${primary} is too dark to read on a near-black background; using #${mapper.primary} instead.`);

  // 4. font
  const font = await askFont(prevTheme.font);

  // 5. options and modules
  const ratio = existing?.layout?.claudeRatio ?? 0.75;
  const custom = CUSTOMISE || cancelled(await p.confirm({ message: 'Customise layout and panel? (defaults are fine)', initialValue: false }));
  let opts = { ratio, system: existing?.panel?.system !== false, statusLine: existing?.statusLine !== false, logo: !(existing?.panel && 'logo' in existing.panel && existing.panel.logo === null) };
  if (custom) {
    const r = cancelled(await p.select({ message: 'Share of the screen for Claude Code', initialValue: ratio, options: [
      { value: 0.6, label: '60 %' }, { value: 0.7, label: '70 %' }, { value: 0.75, label: '75 % (3/4)' }, { value: 0.8, label: '80 %' }] }));
    const feats = cancelled(await p.multiselect({ message: 'Show', required: false,
      initialValues: ['system', 'logo', 'statusLine'].filter((k) => opts[k]),
      options: [{ value: 'system', label: 'Memory and disk in the panel' }, { value: 'logo', label: 'Logo in the panel' }, { value: 'statusLine', label: 'Rei status line in Claude Code' }] }));
    opts = { ratio: r, system: feats.includes('system'), logo: feats.includes('logo'), statusLine: feats.includes('statusLine') };
  }

  // 6. logo: show it (after the modules, in the chosen colour) and offer to change it
  let newLogo = null;
  if (opts.logo) newLogo = await askLogo(repo, existing, mapper.primary);

  const keys = cancelled(await p.confirm({ message: 'Install Rei key bindings? (Shift+Enter new line, Ctrl+Backspace/Delete delete words, selection copies to clipboard)', initialValue: true }));

  const bar = cancelled(await p.select({ message: 'Progress bar style (panel and status line)', initialValue: ['/', '|'].includes(existing?.bar) ? existing.bar : 'block', options: [
    { value: 'block', label: '██████░░░░ 60%  (blocks)' }, { value: '|', label: '||||||.... 60%' }, { value: '/', label: '//////.... 60%' }] }));

  // 7. summary
  const baseTheme = baseThemeFile(repo);
  const genTheme = generatedThemeFile(repo);
  const keysFile = path.join(repo, 'theme', 'keys.toml');
  const alaFile = alacrittyConfigPath();
  const customTheme = mapper.primary !== DEFAULT_PRIMARY || !!secondary || !!font.family || !!font.size;
  const themeFile = customTheme ? genTheme : baseTheme;
  const plan = [
    `Write ${path.join(repo, 'config', 'projects.json')} (${projects.length} project(s))`,
    ...(customTheme ? [`Generate ${genTheme} with your colours${font.family || font.size ? ' and font' : ''}`] : []),
    ...(font.install ? [`Install the font ${font.install.family} with winget`] : []),
    ...(newLogo ? [`Write the logo to ${logoFile(repo)}`] : []),
    `${fs.existsSync(alaFile) ? 'Add the theme import to' : 'Create'} ${alaFile}${fs.existsSync(alaFile) ? ' (backup first)' : ''}`,
    `${hasBlock(profilePath() || '') ? 'Update' : 'Add'} the rei function in your PowerShell profile`,
  ];
  p.note(plan.map((l) => `• ${l}`).join('\n'), DRY ? 'Would do (dry run)' : 'About to do');
  if (DRY) { p.outro('Dry run: nothing was changed.'); return; }
  if (!cancelled(await p.confirm({ message: 'Go ahead?', initialValue: true }))) { p.cancel('Nothing was changed.'); process.exit(0); }

  // 8. apply
  if (font.install) {
    p.log.step(`Installing ${font.install.family} with winget`);
    if (!wingetInstall(font.install.winget)) p.log.warn('winget could not install the font. The theme still uses it; install it by hand and restart Alacritty.');
  }
  const s = p.spinner();
  s.start('Applying');
  const theme = customTheme ? { primary: mapper.primary, ...(secondary ? { secondary } : {}), ...(font.family || font.size ? { font: { ...(font.family ? { family: font.family } : {}), ...(font.size ? { size: font.size } : {}) } } : {}) } : null;
  if (newLogo) { fs.mkdirSync(path.dirname(logoFile(repo)), { recursive: true }); fs.writeFileSync(logoFile(repo), newLogo.text + '\n', 'utf8'); }
  writeConfig(repo, buildConfig(existing, { projects, ...opts, resetLogoPath: !!newLogo, bar, colors: customTheme ? panelColors(mapper) : null, theme }));
  if (customTheme) writeTheme(repo, mapper, { family: font.family, size: font.size });
  const old = fs.existsSync(alaFile) ? fs.readFileSync(alaFile, 'utf8') : '';
  let next = addImport(removeImport(removeImport(old, baseTheme), genTheme), themeFile);
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

  // 9. Claude Code
  p.log.success('Open a new PowerShell window and run: rei');
  if (cancelled(await p.confirm({ message: 'Open Claude Code to set up the panel for you? It asks what you want to see and builds it (checked and reversible).', initialValue: true }))) {
    launchClaude(repo);
  }
  p.outro('Rei is ready. To change anything later, run: rei -Customize');
}

/** Shows the current logo and, if the user wants, replaces it. Returns { text } when it changed. */
async function askLogo(repo, existing, colour) {
  const cur = currentLogo(repo, existing);
  if (cur) p.note(colourise(cur.text, colour), `Logo (${widthOf(cur.text)} columns wide)`);
  else p.log.warn('No logo file found.');
  if (!cancelled(await p.confirm({ message: 'Customise the logo?', initialValue: !cur }))) return null;
  const pick = cancelled(await p.select({ message: 'Logo', options: [
    ...LOGOS.map((l) => ({ value: l.id, label: l.label })),
    { value: 'file', label: 'My own text file (ASCII or braille)' },
  ] }));
  let text;
  if (pick === 'file') {
    const f = norm(cancelled(await p.text({ message: 'Path to the file', validate: (v) => (fs.existsSync(v.trim().replace(/^"|"$/g, '')) && fs.statSync(v.trim().replace(/^"|"$/g, '')).isFile() ? undefined : 'That file does not exist') })));
    text = fs.readFileSync(f, 'utf8').replace(/\s+$/, '');
  } else {
    text = fs.readFileSync(presetFile(repo, pick), 'utf8').replace(/\s+$/, '');
  }
  p.note(colourise(text, colour), `New logo (${widthOf(text)} columns wide; the panel hides it if it does not fit)`);
  return { text };
}

// The prompt is one line with no inner quotes so it survives cmd.exe; the real brief is in the repo.
function launchClaude(repo) {
  if (!checkRequirements().find((r) => r.name === 'Claude Code')?.ok) {
    p.log.warn('Claude Code is not installed: npm install -g @anthropic-ai/claude-code');
    return;
  }
  p.log.info('Opening Claude Code. It will ask what you want in the panel; leave it with /exit when done.');
  spawnSync('claude', ['"Follow docs/customise-with-claude.md to customise Rei for me."'], { cwd: repo, stdio: 'inherit', shell: true });
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
    `Remove the Rei imports (theme, generated theme, keys) from ${alaFile}`,
    `Remove the rei block from ${prof}`,
    `Keep ${repo} and config/projects.json (your data)`,
  ];
  p.note(plan.map((l) => `• ${l}`).join('\n'), DRY ? 'Would do (dry run)' : 'About to do');
  if (DRY) { p.outro('Dry run: nothing was changed.'); return; }
  if (!cancelled(await p.confirm({ message: 'Uninstall Rei?', initialValue: false }))) { p.cancel('Nothing was changed.'); return; }
  if (fs.existsSync(alaFile)) {
    const old = fs.readFileSync(alaFile, 'utf8');
    let next = old;
    for (const f of [baseThemeFile(repo), generatedThemeFile(repo), path.join(repo, 'theme', 'keys.toml')]) next = removeImport(next, f);
    if (next !== old) { const b = backup(alaFile); fs.writeFileSync(alaFile, next, 'utf8'); if (b) p.log.info(`Backup: ${b}`); }
  }
  if (prof) uninstallBlock(prof);
  p.outro(`Uninstalled. Delete ${repo} yourself if you want it gone, and open a new PowerShell window.`);
}

main().catch((e) => { p.cancel(String(e?.stack || e)); process.exit(1); });
