# Installer

An interactive assistant built with [@clack/prompts](https://github.com/bombshell-dev/clack). Needs Node 18 or later.

```powershell
npx github:rafafields/rei            # clones the repo and installs
node installer/index.mjs             # from an existing checkout
node installer/index.mjs --dry-run   # show what it would do, change nothing
node installer/index.mjs --uninstall # remove the theme import and the profile block
node installer/index.mjs --customise # only open Claude Code to customise the panel again
```

## What it does

1. Checks Windows, Alacritty, PowerShell 5.1, Claude Code and git, and says how to install what is missing.
2. Asks where to install (or uses the checkout it runs from) and clones the repo if needed.
3. Asks for your projects (folder is validated, optional check command) and writes `config/projects.json`.
4. Optionally asks for the layout ratio, memory and disk in the panel, the logo and the status line.
5. Shows a summary and asks for confirmation before touching anything.
6. Adds the theme import to `%APPDATA%\alacritty\alacritty.toml` (creates the file if missing, otherwise merges the import and keeps a `.bak-rei-*` copy).
7. Runs `scripts/install.ps1` to add the `rei` function to your PowerShell profile.
8. Offers (on by default) to open Claude Code in the repo with one instruction: follow [customise-with-claude.md](customise-with-claude.md). Claude asks what you want to see in the panel, says what each section will read before writing it, creates it in `config/widgets/`, validates it with `-TestSection` and lists what it changed and how to undo it. See [sections.md](sections.md) for the rules it follows.

Running it again changes options without duplicating anything: the import is only added if absent and the profile block is replaced between its markers.

## Uninstall

Removes the theme import and the profile block. It keeps the repo folder and `config/projects.json`.
