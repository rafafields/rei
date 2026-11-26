# Theme

`theme/rei.json` is a Windows Terminal colour scheme named "Rei". The installer does not edit your `settings.json`: it writes a *fragment*, `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\rei\rei.json`, with a profile "Rei" (PowerShell, padding 12 x 10, your font) and the scheme. Restart Windows Terminal once so it picks it up. `rei` opens its tabs with `-p Rei`.

To use the colours in your own profile, copy the scheme from `theme/rei.json` into the `schemes` list of your `settings.json` and set `"colorScheme": "Rei"`.

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

The Rei profile uses Windows Terminal's default font until you choose one. The installer can pick one for you (and install it with `winget` when it is available there): it writes it to the profile in the fragment as `font.face` and `font.size`.

## Keys and selection

The Alacritty key bindings (Shift+Enter, Ctrl+Backspace, Ctrl+Delete) are not part of Rei any more: a fragment cannot define key bindings. Windows Terminal's own settings, or Claude Code's `/terminal-setup`, are the place for them.
