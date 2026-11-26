# Rei (零)

A terminal workspace for [Claude Code](https://claude.com/claude-code) on Windows, built on [Windows Terminal](https://aka.ms/terminal).

One command opens each project as a tab of one Windows Terminal window, named after the project. Inside every tab:

- **Claude Code** on the left, 3/4 of the tab, with a custom status line.
- **A narrow panel** on the right, 1/4 of the tab, showing the state of the project: git, running ports, system load.

Everything is wrapped in a dark theme where every colour that is not neutral is a shade of red.

> Status: early. Windows 11, Windows Terminal and Windows PowerShell 5.1.

## What is in the box

| Piece | What it does | Docs |
|---|---|---|
| `theme/rei.json` | Windows Terminal colour scheme (installed as a fragment) | [docs/theme.md](docs/theme.md) |
| `scripts/rei.ps1` | The `rei` command: opens the tabs and panes | [docs/launcher.md](docs/launcher.md) |
| `scripts/panel.ps1` | The right-hand panel, made of sections you can add to | [docs/panel.md](docs/panel.md), [docs/sections.md](docs/sections.md) |
| `scripts/statusline.ps1` | Claude Code status line | [docs/statusline.md](docs/statusline.md) |
| `installer/` | Interactive installer (Node) | [docs/installer.md](docs/installer.md) |

## Requirements

- Windows 10 or 11
- [Windows Terminal](https://aka.ms/terminal) (`wt` on `PATH`; included in Windows 11)
- Windows PowerShell 5.1 (included with Windows)
- [Claude Code](https://claude.com/claude-code) on `PATH`
- Git

## Install

With Node 18 or later, the assistant does all of the steps below ([docs/installer.md](docs/installer.md)):

```powershell
npx github:rafafields/rei
```

By hand:

```powershell
git clone https://github.com/rafafields/rei.git C:\code\rei
cd C:\code\rei

# 1. Your project list
Copy-Item config\projects.example.json config\projects.json
notepad config\projects.json

# 2. The `rei` command in your PowerShell profile
.\scripts\install.ps1

# 3. The theme: copy it as a Windows Terminal fragment (no change to your settings.json)
node installer\index.mjs   # recommended: also handles colours and font
```

Restart Windows Terminal so it loads the "Rei" profile and colour scheme.

Open a new PowerShell window so the `rei` function is loaded.

## Use

```powershell
rei                      # numbered menu
rei my-project           # one project, by name
rei -All                 # every project in the list
rei -List                # show the list
rei my-project -DryRun   # print what would run, launch nothing
rei -Config              # go to the folder where Rei is installed
rei -Customize           # run the installer again: colours, font, projects...
rei -Uninstall           # remove Rei's terminal profile and your PowerShell profile block
rei -Help                # list the commands
```

Keys in the panel: `c` runs the project's check (if it has one), `q` or `Esc` quits.

## Configuration

`config/projects.json` (not committed; your paths stay on your machine):

```json
{
  "projects": [
    { "name": "my-project", "path": "C:/code/my-project", "check": "npm test" }
  ]
}
```

All options are in [docs/launcher.md](docs/launcher.md).

## Known limits

- Each `rei` command opens its own window; projects launched together are tabs of that window.
- The Shift+Enter, Ctrl+Backspace and Ctrl+Delete bindings of the old Alacritty setup are not carried over (Windows Terminal keeps them in your own `settings.json`).
- The panel only detects servers whose command line contains the project path.
- The weekly reset in the status line only exists for claude.ai subscriptions.

## License

[MIT](LICENSE)
