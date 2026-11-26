# Installer

An interactive assistant built with [@clack/prompts](https://github.com/bombshell-dev/clack). Needs Node 18 or later.

```powershell
npx github:rafafields/rei            # clones the repo and installs
node installer/index.mjs             # from an existing checkout
node installer/index.mjs --dry-run   # show what it would do, change nothing
node installer/index.mjs --uninstall # remove the Rei fragment and the profile block
node installer/index.mjs --customize # the whole process again, with every customisation question (this is `rei -Customize`)
node installer/index.mjs --claude    # only open Claude Code to customise the panel again
```

## What it does

1. Checks Windows, Windows Terminal, PowerShell 5.1, Claude Code and git, and says how to install what is missing.
2. Asks where to install (or uses the checkout it runs from) and clones the repo if needed.
3. Asks for your projects (folder is validated, optional check command) and writes `config/projects.json`.
4. Asks for the **main colour** (a list or any hex code) and, if you want, **secondary colours**. Every non-neutral colour of the theme is rotated to your hue (the neon green of diffs stays) and text colours keep a 4.5:1 contrast. A too-dark colour is lifted and the installer tells you.
5. Asks for the **font** (and size). If it is not installed it offers to install it with `winget` (JetBrains Mono Nerd Font is the one winget has). Cascadia Code and Consolas ship with Windows; any other name can be typed in.
6. Optionally asks for the layout ratio, memory and disk in the panel, the logo and the status line.
7. If the logo is on, **shows it** in your main colour and asks if you want to customise it: Braille (default), ASCII letters, or your own text file. It is written to `config/logo.txt`.
8. Shows a summary and asks for confirmation before touching anything.
9. Writes the Windows Terminal fragment (profile and colour scheme "Rei", with your colours and font) to `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\rei\rei.json`. Your `settings.json` is not touched. Restart Windows Terminal afterwards.
10. Runs `scripts/install.ps1` to add the `rei` function to your PowerShell profile (it also handles `rei -Config`).
11. Asks whether to open Claude Code in the repo (on by default), with one instruction: follow [customise-with-claude.md](customise-with-claude.md). Claude asks what you want to see in the panel, says what each section will read before writing it, creates it in `config/widgets/`, validates it with `-TestSection` and lists what it changed and how to undo it. See [sections.md](sections.md) for the rules it follows.

Running it again changes options without duplicating anything: the fragment is overwritten and the profile block is replaced between its markers.

## Uninstall

`rei -Uninstall` (or `--uninstall`) asks for confirmation, then removes the fragment and the profile block. It keeps the repo folder and `config/projects.json`; delete the folder yourself if you want it gone.

## Tests

`npm test` runs the pure parts (colour maths, config merge, fragment building).
