# Theme

`theme/rei.toml` is a plain Alacritty colour file. It sets only colours (no font, no window options), so it can be imported next to any existing config:

```toml
[general]
import = ["C:/code/rei/theme/rei.toml"]
```

## Palette

Background and text are neutral; everything else is a red.

| Role | Hex |
|---|---|
| Background | `#0a0a0b` |
| Foreground (bone white) | `#e8e4d8` |
| Cursor | `#e0364a` |
| Selection background | `#4a1520` |

ANSI colours:

| Slot | Normal | Bright | Tone |
|---|---|---|---|
| black | `#1a1a1d` | `#7d7d85` | neutral |
| red | `#e0364a` | `#ff5468` | crimson |
| green | `#39ff14` | `#7cff63` | neon green |
| yellow | `#ee8e72` | `#ffab8c` | coral |
| blue | `#d4577a` | `#ec7f9e` | rose |
| magenta | `#cc4a7e` | `#e0679a` | raspberry |
| cyan | `#f2a0ae` | `#f8c0c8` | blush |
| white | `#c9c5b8` | `#f4f0e4` | neutral |

Green is the one exception to the red scheme: it stays neon so that diff additions are still distinguishable from deletions. Without it, "added" and "removed" would differ only by lightness.

Every text colour has a contrast ratio of at least 4.5:1 against the background.

## Font

The theme does not set a font; Alacritty's default is used. Set one in your own config under `[font.normal]` if you want something else.

## Example config

`config/alacritty.toml` is a ready-to-copy file that imports the theme and sets window padding (12 x 10) and opacity (1.0).
