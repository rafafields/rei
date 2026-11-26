# Panel sections

The panel draws a header (kanji, project name, path), a list of **sections** and a clock. Everything between header and clock is a section: a small PowerShell script that returns a title and some lines.

Built-in sections live in `scripts/sections/`: `git`, `ports`, `check`, `system`. Your own go in `config/widgets/` (git-ignored, so they stay on your machine). A name in `config/widgets/` is only used when there is no built-in with that name.

## Choosing and ordering

```json
{ "panel": { "sections": ["git", "tasks", { "name": "ci", "every": 30 }, "system"] } }
```

Sections show in this order. `every` is the refresh interval in seconds (defaults: git 5, ports 10, check 1, system 5, anything else 10). Without `panel.sections` you get `git`, `ports`, `check`, `system`.

## The contract

A section is a script with one parameter and one return value.

```powershell
param($ctx)
$C = $ctx.Colors
@{ Title = 'TASKS'; Lines = @("$($C.Ok)3 en curso$($C.Reset)", "$($C.Dim)$(Cut 'una linea larga' $ctx.Width)$($C.Reset)") }
```

Return one of:

| Return | Effect |
|---|---|
| `@{ Title = '...'; Lines = @('...') }` | Shown under a `TITLE ----` rule. Lines may contain colour codes. |
| `@{ Hidden = $true }` (or no lines) | Not shown. Use it when the section does not apply to this project. |

`$ctx` has:

| Field | Meaning |
|---|---|
| `Name`, `Path` | Project name and folder. |
| `Width` | Columns available for one line. No line may be wider (use `Cut`). |
| `Colors` | `Text Soft Dim Accent Bad Warn Info Branch Ok BarOn BarOff Reset Bold`. Same palette as the rest of Rei. |
| `BarChar` | `|` or `/`, the user's progress bar character. |
| `IsDev`, `ShowSystem`, `CheckCommand`, `CheckState` | Project facts the built-in sections use. |

Available helpers: `Cut text width`, `CutLeft text width`, `Format-Ago date`, `Format-ReiBar percent width char` (strong red on a soft red track), `Get-ReiColors`.

## Rules (the panel enforces what it can)

- **ASCII only in the file.** Windows PowerShell 5.1 reads BOM-less files as ANSI. For a non-ASCII character use `[char]0x96F6`.
- **No line wider than `$ctx.Width`.**
- **Fast.** A section has 10 seconds; after that the panel stops waiting and shows `sin respuesta`. Anything that needs the network or a slow tool should have a long `every`.
- **Read-only.** A section reports; it must not change the project, the config or the user's files.
- **No secrets in the output.** The panel is a screen people can see.
- An error, a timeout or a wrong return value shows a red line under the section name. The rest of the panel keeps working.

Sections run in their own runspace, so they do not share variables with the panel. A section is rerun from scratch each time.

## Testing a section

```powershell
scripts\panel.ps1 -Name my-project -TestSection tasks
```

Runs the section once, prints what it returns and checks: the file exists, ASCII only, returns a valid result, finishes in time, no line wider than the limit. Exit code 0 means OK, 1 means it failed and says why. Do not call a section done until this passes.
