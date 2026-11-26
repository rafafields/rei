# Customising Rei with Claude Code

This is the brief Claude Code follows when the installer opens it in the repo. It is also the way to redo it later: run `claude` in this folder and say "follow docs/customise-with-claude.md".

## For Claude

Goal: make the right-hand panel show what *this* user wants to see, without breaking anything. Talk to the user in the language they write in.

1. **Read first.** `CLAUDE.md` and `docs/sections.md`. The contract and the rules there are not optional.
2. **Ask what they want in the panel.** One or two questions at a time, not a form. Start open ("what would you like to see at a glance next to Claude Code?") and, if they are stuck, offer concrete ideas that fit how they work: open tasks from a notes folder or a file, CI and pull-request state with `gh`, commits made today, how long since the last commit, the version or health of a local service, the output of any command they already run. Do not suggest more than they ask for: a narrow column fills up fast.
3. **Before writing anything, say exactly what each section will read and where**: which files, which commands, whether it needs the network or a token. Get a yes. If it needs credentials, prefer a tool that is already logged in (`gh`, `git`) over storing a token, and never print secrets in the panel.
4. **Create one file per section in `config/widgets/`** (create the folder if it is missing), following `docs/sections.md`: ASCII only, a `param($ctx)` signature, lines cut to `$ctx.Width`, read-only, fast. Anything slow or networked gets a long `every` (30 seconds or more).
5. **Wire it in** by adding the section name to `panel.sections` in `config/projects.json`. If the key does not exist yet, start from the defaults (`git`, `ports`, `check`, `system`) and put the new ones where the user wants them. Edit the file, never overwrite it, and keep the user's projects.
6. **Test every section**: `scripts\panel.ps1 -Name <project> -TestSection <name>` until it prints OK. Show the user what it returned. If it is hidden for this project, say why.
7. **Check the whole thing** with `scripts\panel.ps1 -Name <project> -Once -Width 40`, then tell the user to open `rei <project>` to see it live.
8. **Offer the rest**, once: palette (`rei -Customize` asks for main and secondary colours; by hand, `theme/rei.toml` and `scripts/common.ps1` kept in sync), status line segments (`scripts/statusline.ps1`).
9. **Finish with a short list**: the files you created or changed, and how to undo each (delete the file in `config/widgets/` and remove its name from `panel.sections`).

Never edit `scripts/panel.ps1` or `scripts/sections.ps1` to add a section, never touch the Windows Terminal settings, the Rei fragment or the PowerShell profile (the installer does that), and never commit `config/`.
