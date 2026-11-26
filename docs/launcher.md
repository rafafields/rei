# Launcher and layout

`scripts/rei.ps1` is the `rei` command. Every selected project becomes a tab of one shared Windows Terminal window (named `rei`): a second `rei` command adds its projects as tabs to that window instead of opening another. Each tab is titled with the kanji 零 and the project name, and holds two panes in the project's directory: Claude Code on the left and the panel on the right.

## Command line

```
rei [name ...] [-All] [-List] [-DryRun]
rei -Config | -Customize | -Uninstall | -Help
```

| Argument | Effect |
|---|---|
| none | Numbered menu. Accepts several numbers, comma-separated. |
| `name ...` | Launch these projects. An unknown name fails and lists the known ones. |
| `-All` | Launch every project in the list. |
| `-List` | Print the list. A `!` marks a directory that does not exist. |
| `-DryRun` | Print the `wt` command line it would run; launch nothing. |
| `-Config` | Change your current directory to the folder Rei is installed in (the `rei` function in your profile does this; run as a script it prints the path and opens it in Explorer). |
| `-Customize` | Run the installer again (`installer/index.mjs --customize`): projects, colours, font and panel options, with your current values as defaults. Needs Node. |
| `-Uninstall` | Run the uninstaller (`--uninstall`): removes the theme imports and the profile block, keeps the folder and your projects. |
| `-Help` | Print this list of commands. |

A project whose directory does not exist is skipped with a warning. If Windows Terminal (`wt`) or `claude` cannot be found, the command stops with a message.

## Configuration file

Read from `config/projects.json`, or from the path in the `REI_CONFIG` environment variable.

```json
{
  "layout": { "claudeRatio": 0.75 },
  "special": null,
  "statusLine": true,
  "panel": { "system": true },
  "projects": [
    { "name": "my-project", "path": "C:/code/my-project", "check": "npm test", "dev": true }
  ]
}
```

Everything except `projects` is optional.

| Key | Default | Meaning |
|---|---|---|
| `projects[].name` | required | Name used on the command line. |
| `projects[].path` | required | Working directory for both panes. |
| `projects[].check` | none | Command the panel runs when you press `c`. |
| `projects[].dev` | auto | Force "development project" on or off. Auto-detected from `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `*.csproj` and similar files. |
| `layout.claudeRatio` | `0.75` | Share of the tab for Claude Code (0.3 to 0.9). The panel gets the rest. |
| `layout.maximized` | `true` | `false` opens the window at Windows Terminal's default size instead of maximized. |
| `special` | built-in panel | An array to run your own command in the second pane, or `false` for no second pane. |
| `statusLine` | `true` | `false` stops `rei` from passing its status line to Claude Code. |
| `panel.system` | `true` | `false` hides memory and disk in the panel. |
| `bar` | `"block"` | Progress bar style in the panel and the status line: `"block"` (full blocks), `"|"` or `"/"`. |
| `panel.sections` | git, ports, check, system | Which panel sections show and in what order. See [sections.md](sections.md). |
| `colors` | Rei reds | Colours of the panel and status line (`accent`, `bad`, `warn`, `info`, `branch`, `ok`, `barOn`, `barOff`, hex without `#`). Written by the installer from the main and secondary colours you pick; you can edit them by hand. |
| `theme` | none | What the installer chose (`primary`, `secondary`, `font.family`, `font.size`), kept so `rei -Customize` can offer it again. |

## Layout

`rei` builds a single `wt` command line and starts it:

```
wt -w rei --maximized new-tab -p Rei --title "零 <name>" --suppressApplicationTitle -d <dir> claude --settings <file> ; split-pane -V -s 0.25 -p "Rei Panel" ... panel.ps1 -Name <name> ; move-focus left ; ... ; focus-tab -p
```

- `-w rei`: a named window. The first `rei` command creates it; later ones (from any terminal) add tabs to it. Close the window and the next `rei` creates a new one. `--maximized` only applies when the window is created.
- `--title "零 <name>"` with `--suppressApplicationTitle`: the tab label is the kanji and the project name, and neither Claude Code nor the panel renames it.
- `split-pane -V -s 0.25`: the panel is a native vertical split with the share left by `layout.claudeRatio`. Drag the divider with the mouse; `Alt+Shift+Arrows` resizes it from the keyboard.
- `-p Rei`: the profile installed by the installer (colours, font, padding), used only if the fragment exists. The panel pane uses `Rei Panel`, the same profile with text at 85 % of the size (10 pt when the font is 12 pt); run `rei -Customize` once to install it.
- After the tabs are created, the first tab of this command is focused (`focus-tab -p` once per extra tab) and the cursor is in Claude Code in every tab.

`claude` is started from its full path (`Get-Command claude`), so it also works when it is a `.exe` outside the profile's `PATH`.

## Install the command

`scripts/install.ps1` adds a `rei` function to your PowerShell profile between `# >>> rei >>>` and `# <<< rei <<<` markers. Running it again updates the block instead of duplicating it.
