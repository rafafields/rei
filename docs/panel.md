# Panel

`scripts/panel.ps1 -Name <project>` is the narrow window that `rei` opens next to Claude Code. It repaints in place on the terminal's alternate screen using absolute cursor positioning, so it never scrolls, and it rewrites only the lines that changed.

## How it is built

The panel draws the header and the clock. Everything in between is a **section** (a small script returning a title and lines), run in the background with a time limit, so a broken section shows an error line and never takes the panel down. You can pick, order and add sections: see [sections.md](sections.md).

## What it shows

Always:

| Item | Source |
|---|---|
| Logo | `config/logo.txt` or `panel.logo` (optional) |
| Project name and path | the config |
| Branch | `git status --porcelain=v2 --branch` |
| New, modified and deleted files | the same command; each file counts once (deleted wins over new, new over modified) |
| Ahead and behind the remote | the same command |
| Last commit (hash, age, subject) | `git log -1` |

Only when it applies:

| Item | Shown when | Source |
|---|---|---|
| Listening ports | the project is a development project | `Get-NetTCPConnection`, matched to processes whose command line contains the project path |
| Memory and disk | `panel.system` is not `false` | `Win32_OperatingSystem` and the drive of the project |
| Check result | a check is running or has failed | the project's `check` command |

Labels in the panel are in Spanish.

## Refresh

Each section refreshes on its own interval (git and memory every 5 seconds, ports every 10, check every second; `every` in the config overrides it). The clock line updates every second. Resizing the window forces a full repaint.

## Keys

| Key | Action |
|---|---|
| `c` | Run the project's `check` command in a background job. |
| `q`, `Esc` | Quit. |

The check never runs by itself. It stays invisible while it passes and appears only when it is running or has failed, with its exit code.

## Colours

Shared with the status line (`Get-ReiColors` in `scripts/common.ps1`): light pink for good, vermilion for warnings, crimson for errors and the accent, coral for ports, rose for the branch.

## Limits

- A server is only detected if its command line includes the project path. A `npm run dev` started from the project folder usually does not.
- The panel is built for a narrow window (about 40 columns). It truncates long values with an ellipsis.

## Testing without a terminal

```powershell
scripts\panel.ps1 -Name my-project -Once -Width 40            # render once to stdout
scripts\panel.ps1 -Name my-project -Once -PreviewCheck fail   # preview the check states
scripts\panel.ps1 -Name my-project -Frames 3 -Width 40        # run the real painter and print the bytes
scripts\panel.ps1 -Name my-project -TestSection git           # validate one section
```
