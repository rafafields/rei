# Rei: instructions for Claude Code

Rei (零) is a terminal workspace for Windows: Windows Terminal, one tab per project, with Claude Code on the left, a project panel on the right. Scripts are Windows PowerShell 5.1 (no PowerShell 7 syntax: no `&&`, `??`, ternaries). Only `installer/` is Node.

## What the user may ask you to change

| Request | Where |
|---|---|
| Colours / palette | `theme/rei.json` (Windows Terminal colour scheme) **and** `scripts/common.ps1` (panel and status line). Keep both in sync. The installer turns `theme/rei.json` into a Windows Terminal fragment (`%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\rei\rei.json`) with the user's colours and font, and writes `colors` in `config/projects.json`; `rei -Customize` regenerates them. Edit the source, then tell the user to re-run it. Every non-neutral colour is a shade of red unless the user says otherwise. |
| What the panel shows | Add or edit a **section** in `config/widgets/` and list it in `panel.sections`. Read `docs/sections.md` first and follow its rules. Never edit `scripts/panel.ps1` or `scripts/sections.ps1` for this. |
| Status line segments | `scripts/statusline.ps1` |
| Logo | `config/logo.txt` (the user's; ignored by git). The defaults live in `theme/logos/`. |
| Layout ratio, projects, panel options | `config/projects.json` (see `docs/launcher.md`) |

## Rules

- `config/projects.json` is the user's data and is git-ignored: edit it, never overwrite it or commit it.
- Do not touch Windows Terminal's `settings.json`, the Rei fragment or the PowerShell profile directly. Use `node installer/index.mjs` (it writes the fragment and replaces only the marked profile block).
- A new section is done only when `scripts\panel.ps1 -Name <project> -TestSection <name>` prints OK.
- After changing a script, run `rei <project> -DryRun` to check it still parses and lays out.
- Update the matching file in `docs/` when behaviour changes.
