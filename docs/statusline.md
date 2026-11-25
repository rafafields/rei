# Status line

`scripts/statusline.ps1` is a Claude Code [status line](https://code.claude.com/docs/en/statusline). Claude Code runs it and sends the session as JSON on stdin; it prints one line.

```
my-project │ main +12 -3 │ Opus │ ctx 42% │ reset sem. 2d 5h (vie. 22:03)
```

| Segment | Source |
|---|---|
| Directory name | `workspace.current_dir` |
| Branch and `+N -M` | `git rev-parse` and `git diff --numstat HEAD`: lines added and removed that are not committed yet. Untracked files are not counted. Shows `limpio` when clean. |
| Model | `model.display_name` |
| Context window used | `context_window.used_percentage` (green below 60 %, then vermilion, crimson from 80 %). `--` while it is null. |
| Next weekly reset | `rate_limits.seven_day.resets_at`, a Unix timestamp in seconds. Shown as time left plus the local day and hour. The segment label (`reset sem.`, `limpio`) is in Spanish and the day name follows the system language. |

The weekly reset is only sent for claude.ai Pro, Max and Ultra subscriptions, and only after the first API response. Without it that segment is left out. On narrow terminals (under 90 columns) the day and hour are dropped.

The script never fails: invalid input prints `rei`, and outside a git repository the branch segment is omitted.

## How it is enabled

`rei` writes `config/claude-settings.json`:

```json
{ "statusLine": { "type": "command", "command": "powershell -NoProfile -File <repo>/scripts/statusline.ps1", "refreshInterval": 120 } }
```

and starts Claude Code with `claude --settings config/claude-settings.json`. Only sessions started by `rei` use it; your `~/.claude/settings.json` is not modified. Set `"statusLine": false` in the config to turn it off.

To use it in every session instead, put the same `statusLine` object in your own settings file.

## Notes

- Each run starts PowerShell, so it takes roughly half a second.
- Claude Code shows nothing until the folder's workspace trust has been accepted.
- If your own user settings already define a `statusLine`, check that the one from `--settings` is the one that appears.

## Test it

```powershell
'{"model":{"display_name":"Opus"},"cwd":"C:/code/my-project","context_window":{"used_percentage":25}}' | powershell -NoProfile -File scripts\statusline.ps1
```
