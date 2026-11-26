import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { makeMapper, normaliseHex, panelColors, contrast, retintTheme } from '../lib/palette.mjs';
import { buildConfig } from '../lib/config.mjs';
import { buildFragment, panelFontSize } from '../lib/theme.mjs';

const base = fs.readFileSync(new URL('../../theme/rei.json', import.meta.url), 'utf8');

test('normaliseHex', () => {
  assert.equal(normaliseHex('#E0364A'), 'e0364a');
  assert.equal(normaliseHex('e34'), 'ee3344');
  assert.equal(normaliseHex('nope'), null);
});

test('default palette changes nothing', () => {
  const m = makeMapper({});
  assert.equal(retintTheme(base, m), base);
  assert.deepEqual(panelColors(m).accent, 'e0364a');
});

test('main colour replaces the crimson exactly; neutrals and green stay', () => {
  const m = makeMapper({ primary: '#4f8cff' });
  const out = retintTheme(base, m);
  assert.match(out, /"cursorColor": "#4f8cff"/i);
  assert.match(out, /"green": "#39ff14"/);
  assert.match(out, /"background": "#0a0a0b"/);
  assert.match(out, /"foreground": "#e8e4d8"/);
  assert.ok(!out.includes('#e0364a'));
});

test('text colours keep 4.5:1 against the background after a hue change', () => {
  for (const primary of ['4f8cff', '9b6bff', '2fb8d6', 'f08a24', '102a6b']) {
    const m = makeMapper({ primary });
    for (const hex of ['e0364a', 'ee8e72', 'd4577a', 'f2a0ae', 'ff5468', 'e8603c']) {
      assert.ok(contrast(m.map(hex)) >= 4.5, `${primary}: ${hex} -> ${m.map(hex)}`);
    }
  }
});

test('a too-dark main colour is lifted and reported', () => {
  const m = makeMapper({ primary: '102a6b' });
  assert.equal(m.adjusted, true);
  assert.ok(contrast(m.primary) >= 4.5);
});

test('secondary colour only moves the pink family', () => {
  const m = makeMapper({ primary: 'e0364a', secondary: '3ecf8e' });
  assert.equal(m.map('e0364a'), 'e0364a');
  assert.equal(m.map('ee8e72'), 'ee8e72');
  assert.notEqual(m.map('d4577a'), 'd4577a');
  assert.notEqual(m.map('f2a0ae'), 'f2a0ae');
});

test('buildFragment makes a valid Rei profile and scheme, with the font', () => {
  const frag = JSON.parse(buildFragment(base, makeMapper({ primary: '4f8cff' }), { family: 'Cascadia Code', size: 12 }));
  assert.equal(frag.profiles[0].name, 'Rei');
  assert.equal(frag.profiles[0].colorScheme, frag.schemes[0].name);
  assert.deepEqual(frag.profiles[0].font, { face: 'Cascadia Code', size: 12 });
  assert.equal(frag.schemes[0].cursorColor, '#4f8cff');
  const plain = JSON.parse(buildFragment(base, makeMapper({}), {}));
  assert.ok(!('font' in plain.profiles[0]));
});

test('buildConfig keeps keys it does not own', () => {
  const existing = { panel: { sections: ['git', 'today'], logo: 'C:/x/logo.txt' }, special: false, projects: [{ name: 'a', path: 'C:/a' }] };
  const out = buildConfig(existing, { projects: existing.projects, ratio: 0.75, system: true, statusLine: true, bar: 'block', colors: null, theme: null });
  assert.deepEqual(out.panel, { sections: ['git', 'today'] });
  assert.equal(out.special, false);
  assert.ok(!('colors' in out) && !('theme' in out) && !('layout' in out) && !('bar' in out));
});

test('buildConfig drops a leftover panel.logo', () => {
  const out = buildConfig({ panel: { logo: null } }, { projects: [], ratio: 0.75, system: true, statusLine: true, bar: 'block' });
  assert.ok(!('panel' in out));
});

test('the Rei Panel profile has a smaller font than Rei', () => {
  const frag = JSON.parse(buildFragment(base, makeMapper({}), { family: 'Cascadia Code', size: 14 }));
  const [main, panel] = frag.profiles;
  assert.equal(panel.name, 'Rei Panel');
  assert.notEqual(panel.guid, main.guid);
  assert.deepEqual(panel.font, { face: 'Cascadia Code', size: 12 });
  assert.equal(panel.hidden, true);
  assert.equal(panelFontSize(null), 10);
  assert.equal(panelFontSize(6), 6);
  const plain = JSON.parse(buildFragment(base, makeMapper({}), {}));
  assert.deepEqual(plain.profiles[1].font, { size: 10 });
});
