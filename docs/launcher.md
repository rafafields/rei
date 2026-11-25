# Launcher and layout

`scripts/rei.ps1` is the `rei` command. For each selected project it opens two Alacritty windows in the project's directory and places them side by side.

## Command line

```
rei [name ...] [-All] [-List] [-DryRun]
```

| Argument | Effect |
|---|---|
| none | Numbered menu. Accepts several numbers, comma-separated. |
| `name ...` | Launch these projects. An unknown name fails and lists the known ones. |
| `-All` | Launch every project in the list. |
| `-List` | Print the list. A `!` marks a directory that does not exist. |
| `-DryRun` | Print the commands and target rectangles; launch nothing. |

A project whose directory does not exist is skipped with a warning. If Alacritty or `claude` cannot be found, the command stops with a message.

## Configuration file

Read from `config/projects.json`, or from the path in the `REI_CONFIG` environment variable.

```json
{
  "layout": { "claudeRatio": 0.75 },
  "special": null,
  "statusLine": true,
  "panel": { "system": true, "logo": "config/logo.txt" },
  "projects": [
    { "name": "my-project", "path": "C:/code/my-project", "check": "npm test", "dev": true }
  ]
}
```

Everything except `projects` is optional.

| Key | Default | Meaning |
|---|---|---|
| `projects[].name` | required | Name used on the command line. |
| `projects[].path` | required | Working directory for both windows. |
| `projects[].check` | none | Command the panel runs when you press `c`. |
| `projects[].dev` | auto | Force "development project" on or off. Auto-detected from `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `*.csproj` and similar files. |
| `layout.claudeRatio` | `0.75` | Share of the work area for Claude Code (0.3 to 0.9). The panel gets the rest. |
| `special` | built-in panel | An array to run your own command in the second window, or `false` for no second window. |
| `statusLine` | `true` | `false` stops `rei` from passing its status line to Claude Code. |
| `panel.system` | `true` | `false` hides memory and disk in the panel. |
| `panel.logo` | `config/logo.txt` | Path to a text file shown at the top of the panel. Hidden if the window is narrower than the file. |

## Layout

The work area of the primary monitor (the screen minus the taskbar) is split in physical pixels: Claude Code on the left, the panel on the right. The invisible resize borders that Windows 11 adds around windows are compensated so the visible frames touch.

Alacritty creates a small helper window first and applies its own initial size a moment later, so the launcher waits for the real window and re-places it for about two seconds until the size settles.

Windows are placed with the Win32 API from PowerShell (`scripts/layout.ps1`); nothing else needs to be installed.

## Several projects

Each project gets its own pair, but all pairs are placed in the same rectangles, so the last one launched ends up on top. Switch with Alt+Tab. Giving each project its own virtual desktop is not implemented: Windows has no public API for it.

## Install the command

`scripts/install.ps1` adds a `rei` function to your PowerShell profile between `# >>> rei >>>` and `# <<< rei <<<` markers. Running it again updates the block instead of duplicating it.
