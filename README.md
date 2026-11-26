# Rei (零)

A terminal workspace for [Claude Code](https://claude.com/claude-code) on Windows, built on [Alacritty](https://alacritty.org/).

One command opens a project as a pair of windows side by side:

- **Claude Code** on the left, 3/4 of the screen, with a custom status line.
- **A narrow panel** on the right, 1/4 of the screen, showing the state of the project: git, running ports, system load.

Everything is wrapped in a dark theme where every colour that is not neutral is a shade of red.

> Status: early. Tested on Windows 11 with Alacritty 0.17.0 and Windows PowerShell 5.1, one monitor.

## What is in the box

| Piece | What it does | Docs |
|---|---|---|
| `theme/rei.toml` | Alacritty colour theme | [docs/theme.md](docs/theme.md) |
| `scripts/rei.ps1` | The `rei` command: launches and places the windows | [docs/launcher.md](docs/launcher.md) |
| `scripts/panel.ps1` | The right-hand panel, made of sections you can add to | [docs/panel.md](docs/panel.md), [docs/sections.md](docs/sections.md) |
| `scripts/statusline.ps1` | Claude Code status line | [docs/statusline.md](docs/statusline.md) |
| `installer/` | Interactive installer (Node) | [docs/installer.md](docs/installer.md) |

## Requirements

- Windows 10 or 11
- [Alacritty](https://alacritty.org/) on `PATH` (or in `C:\Program Files\Alacritty`)
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

# 3. The theme: copy config\alacritty.toml to %APPDATA%\alacritty\alacritty.toml
#    and fix the import path if you cloned somewhere else
New-Item -ItemType Directory -Force "$env:APPDATA\alacritty" | Out-Null
Copy-Item config\alacritty.toml "$env:APPDATA\alacritty\alacritty.toml"
```

If `%APPDATA%\alacritty\alacritty.toml` already exists, add the import to it instead of overwriting it:

```toml
[general]
import = ["C:/code/rei/theme/rei.toml"]
```

Open a new PowerShell window so the `rei` function is loaded.

## Use

```powershell
rei                      # numbered menu
rei my-project           # one project, by name
rei -All                 # every project in the list
rei -List                # show the list
rei my-project -DryRun   # print what would run, launch nothing
rei -Config              # go to the folder where Rei is installed
rei -Customize           # run the installer again: colours, font, logo, projects...
rei -Uninstall           # remove Rei from Alacritty and your PowerShell profile
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

- One screen: the layout uses the primary monitor's work area.
- The divider is a separate window, not a real split: moving one window does not move the other.
- Launching several projects at once stacks their windows in the same place, dividers included. Per-project virtual desktops are not implemented.
- The panel only detects servers whose command line contains the project path.
- The weekly reset in the status line only exists for claude.ai subscriptions.

## License

[MIT](LICENSE)
