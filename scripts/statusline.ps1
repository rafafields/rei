<#
.SYNOPSIS
  Rei status line for Claude Code (reads the session JSON on stdin, prints one line).

.DESCRIPTION
  directory | branch +added -removed (uncommitted lines) | model | context % | next weekly reset
  The weekly reset only exists for claude.ai subscriptions (rate_limits.seven_day); without it
  the segment is left out. ASCII-only file: Windows PowerShell 5.1 reads BOM-less files as ANSI.
  Test:  '{"model":{"display_name":"Opus"},"cwd":"C:/code/rei","context_window":{"used_percentage":25}}' | powershell -NoProfile -File statusline.ps1
#>
$ErrorActionPreference = 'SilentlyContinue'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$raw = [Console]::In.ReadToEnd()
try { $j = $raw | ConvertFrom-Json } catch { Write-Host 'rei'; exit 0 }

# --- theme (shared palette in common.ps1) ---------------------------------------------------
. (Join-Path $PSScriptRoot 'common.ps1')
$e = [char]27
$C = Get-ReiColors
$R = $C.Reset; $B = $C.Bold
$Text = $C.Text; $Soft = $C.Soft; $Dim = $C.Dim; $Red = $C.Bad; $Green = $C.Ok; $Yellow = $C.Warn; $Cyan = $C.Branch
$ellipsis = [string][char]0x2026
$sep = " $Dim$([char]0x2502)$R "

function Cut([string]$s, [int]$w) { if ($s.Length -le $w) { $s } else { $s.Substring(0, [math]::Max(1, $w - 1)) + $ellipsis } }

$cols = 0; [void][int]::TryParse($env:COLUMNS, [ref]$cols)
$narrow = ($cols -gt 0 -and $cols -lt 90)

$cwd = if ($j.workspace.current_dir) { [string]$j.workspace.current_dir } else { [string]$j.cwd }
$segments = New-Object System.Collections.Generic.List[string]

# 1) directory name
if ($cwd) {
    $leaf = Split-Path -Path ($cwd -replace '/', '\') -Leaf
    if (-not $leaf) { $leaf = $cwd }
    $segments.Add("$B$Text$(Cut $leaf 28)$R")
}

# 2) branch + uncommitted lines
if ($cwd -and (Test-Path -LiteralPath $cwd -PathType Container)) {
    $branch = & git --no-optional-locks -C $cwd rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $branch) {
        if ($branch -eq 'HEAD') { $branch = & git --no-optional-locks -C $cwd rev-parse --short HEAD 2>$null }
        $add = 0; $del = 0
        foreach ($l in (& git --no-optional-locks -C $cwd diff --numstat HEAD 2>$null)) {
            $p = $l -split "`t"
            if ($p.Count -ge 2 -and $p[0] -match '^\d+$' -and $p[1] -match '^\d+$') { $add += [int]$p[0]; $del += [int]$p[1] }
        }
        $s = "$Cyan$(Cut $branch 28)$R"
        if ($add -eq 0 -and $del -eq 0) { $s += " ${Dim}limpio$R" }
        else { $s += " $Green+$add$R $Red-$del$R" }
        $segments.Add($s)
    }
}

# 3) model
if ($j.model.display_name) { $segments.Add("$Soft$($j.model.display_name)$R") }

# 4) context window used (nullable early in the session)
$used = $j.context_window.used_percentage
if ($null -ne $used) {
    $pct = [int][math]::Round([double]$used)
    $col = if ($pct -ge 80) { $Red } elseif ($pct -ge 60) { $Yellow } else { $Green }
    $segments.Add("${Dim}ctx $col$pct%$R")
} else {
    $segments.Add("${Dim}ctx --$R")
}

# 5) next weekly reset (subscriptions only; resets_at is epoch SECONDS)
$resetsAt = $j.rate_limits.seven_day.resets_at
if ($null -ne $resetsAt) {
    $when = [DateTimeOffset]::FromUnixTimeSeconds([int64]$resetsAt).ToLocalTime()
    $left = $when - [DateTimeOffset]::Now
    if ($left.TotalSeconds -gt 0) {
        $rel = if ($left.TotalDays -ge 1) { '{0}d {1}h' -f [int][math]::Floor($left.TotalDays), $left.Hours }
               elseif ($left.TotalHours -ge 1) { '{0}h {1}m' -f [int][math]::Floor($left.TotalHours), $left.Minutes }
               else { '{0}m' -f [math]::Max(1, [int][math]::Ceiling($left.TotalMinutes)) }
        $day = (Get-Culture).DateTimeFormat.GetAbbreviatedDayName($when.DayOfWeek)
        # NB: PowerShell variables are case-insensitive, so this must not be called $text ($Text is the colour)
        $resetLabel = if ($narrow) { $rel } else { "$rel $Dim($day $($when.ToString('HH:mm')))" }
        $segments.Add("${Dim}reset sem. $Text$resetLabel$R")
    }
}

Write-Host ($segments -join $sep)
exit 0
