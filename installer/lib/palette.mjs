// Colour maths for the installer: turns the default red theme into the user's colours.
// Pure functions only, so they can be tested without a terminal.

export const BG = '0a0a0b';
export const DEFAULT_PRIMARY = 'e0364a';
const DEFAULT_SECONDARY = 'd4577a';
// Colours of the default theme that belong to the "secondary" family (pink and blush).
const SECONDARY_GROUP = new Set(['d4577a', 'cc4a7e', 'f2a0ae', 'ec7f9e', 'e0679a', 'f8c0c8']);

/** Accepts "#e0364a", "e0364a" or "#e34"; returns six lowercase hex digits or null. */
export function normaliseHex(input) {
  let s = String(input ?? '').trim().replace(/^#/, '').toLowerCase();
  if (/^[0-9a-f]{3}$/.test(s)) s = s.split('').map((c) => c + c).join('');
  return /^[0-9a-f]{6}$/.test(s) ? s : null;
}

export const hexToRgb = (h) => [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
export const rgbToHex = (r, g, b) => [r, g, b].map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('');

export function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  const l = (max + min) / 2;
  let h = 0, s = 0;
  if (d) {
    s = d / (1 - Math.abs(2 * l - 1));
    if (max === r) h = ((g - b) / d) % 6; else if (max === g) h = (b - r) / d + 2; else h = (r - g) / d + 4;
    h = (h * 60 + 360) % 360;
  }
  return [h, s, l];
}

export function hslToRgb(h, s, l) {
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
}

const hue = (hex) => rgbToHsl(...hexToRgb(hex))[0];
const lum = (hex) => {
  const [r, g, b] = hexToRgb(hex).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
export const contrast = (a, b = BG) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

/** HSV saturation: near-whites and greys come out close to 0, unlike HSL. */
function chroma(hex) { const [r, g, b] = hexToRgb(hex); const max = Math.max(r, g, b); return max ? (max - Math.min(r, g, b)) / max : 0; }

/** Raises the lightness until the colour reads on the background (>= 4.5:1). */
export function ensureContrast(hex, min = 4.5) {
  if (contrast(hex) >= min) return hex;
  let [h, s, l] = rgbToHsl(...hexToRgb(hex));
  while (l < 0.97 && contrast(rgbToHex(...hslToRgb(h, s, l))) < min) l += 0.02;
  return rgbToHex(...hslToRgb(h, s, l));
}

/**
 * Returns { map(hex), primary } for a main colour and an optional secondary one.
 * Every non-neutral, non-green colour of the default theme is rotated to the new hue; the default
 * crimson becomes exactly the main colour. Text colours keep a 4.5:1 contrast with the background.
 */
export function makeMapper({ primary = DEFAULT_PRIMARY, secondary = null } = {}) {
  const p = normaliseHex(primary) ?? DEFAULT_PRIMARY;
  const s = secondary ? normaliseHex(secondary) : null;
  const primaryOk = ensureContrast(p);
  const pDelta = hue(primaryOk) - hue(DEFAULT_PRIMARY);
  const sDelta = s ? hue(ensureContrast(s)) - hue(DEFAULT_SECONDARY) : pDelta;
  const rotate = (hex, delta) => {
    const [h, sat, l] = rgbToHsl(...hexToRgb(hex));
    return rgbToHex(...hslToRgb((h + delta + 360) % 360, sat, l));
  };
  const map = (input) => {
    const hex = normaliseHex(input);
    if (!hex) return input;
    const h = hue(hex);
    if (chroma(hex) < 0.15 || (h >= 70 && h <= 170)) return hex; // neutrals and the neon green stay
    if (hex === DEFAULT_PRIMARY) return primaryOk;
    const out = rotate(hex, SECONDARY_GROUP.has(hex) && s ? sDelta : pDelta);
    return contrast(hex) >= 4.5 ? ensureContrast(out) : out;
  };
  return { map, primary: primaryOk, adjusted: primaryOk !== p };
}

/** Rewrites every #rrggbb in a theme file through the mapper. */
export function retintTheme(text, mapper) {
  return text.replace(/#([0-9a-fA-F]{6})\b/g, (_, hex) => `#${mapper.map(hex.toLowerCase())}`);
}

/** The panel and status line colours, in the keys read by scripts/common.ps1. */
export function panelColors(mapper) {
  const base = { accent: 'e0364a', bad: 'e0364a', warn: 'e8603c', info: 'ee8e72', branch: 'd4577a', ok: 'f2a0ae', barOn: 'e0364a', barOff: '5c1a26' };
  return Object.fromEntries(Object.entries(base).map(([k, v]) => [k, mapper.map(v)]));
}

export const ansi = (hex) => { const [r, g, b] = hexToRgb(hex); return `\x1b[38;2;${r};${g};${b}m`; };
export const swatch = (hex) => { const [r, g, b] = hexToRgb(hex); return `\x1b[48;2;${r};${g};${b}m  \x1b[0m`; };
