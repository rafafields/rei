# Rei: instructions for Claude Code

Rei (零) is a terminal workspace for Windows: Alacritty + Claude Code on the left, a project panel on the right. Scripts are Windows PowerShell 5.1 (no PowerShell 7 syntax: no `&&`, `??`, ternaries). Only `installer/` is Node.

## What the user may ask you to change

| Request | Where |
|---|---|
| Colours / palette | `theme/rei.toml` (Alacritty) **and** `scripts/common.ps1` (panel and status line). Keep both in sync. Every non-neutral colour is a shade of red unless the user says otherwise. |
| What the panel shows | Add or edit a **section** in `config/widgets/` and list it in `panel.sections`. Read `docs/sections.md` first and follow its rules. Never edit `scripts/panel.ps1` or `scripts/sections.ps1` for this. |
| Status line segments | `scripts/statusline.ps1` |
| Logo | `config/logo.txt` |
| Layout ratio, projects, panel options | `config/projects.json` (see `docs/launcher.md`) |

## Rules

- `config/projects.json` is the user's data and is git-ignored: edit it, never overwrite it or commit it.
- Do not touch `%APPDATA%\alacritty\alacritty.toml` or the PowerShell profile directly. Use `node installer/index.mjs` (it merges and backs up).
- A new section is done only when `scripts\panel.ps1 -Name <project> -TestSection <name>` prints OK.
- After changing a script, run `rei <project> -DryRun` to check it still parses and lays out.
- Update the matching file in `docs/` when behaviour changes.
