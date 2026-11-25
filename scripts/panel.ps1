<#
.SYNOPSIS
  Rei panel: the narrow "special" terminal that sits next to Claude Code.

.DESCRIPTION
  Always shown : project name and path, git state (branch, changes, ahead/behind, last commit).
  Only when it applies: listening ports of processes started from the project, and a failing
  or running check (project "check" command in the config; press c to run it).
  Refreshes every few seconds. Keys: c = run check, q or Esc = quit.
  The file is ASCII-only on purpose (Windows PowerShell 5.1 reads BOM-less files as ANSI).

.EXAMPLE
  panel.ps1 -Name rei
  panel.ps1 -Name rei -Once -Width 40     # render once to stdout (for testing)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [switch]$Once,
    [int]$Width = 0,
    [int]$RefreshSeconds = 5,
    [ValidateSet('', 'running', 'fail')][string]$PreviewCheck = '',
    [int]$Frames = 0   # testing: run the real painter N times with no keyboard and exit   # testing: render with this check state
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'common.ps1')

try { $config = Read-ReiConfig } catch { Write-Host "rei panel: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 5; exit 1 }
$project = @($config.projects) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
if (-not $project) { Write-Host "rei panel: unknown project '$Name'" -ForegroundColor Red; Start-Sleep 5; exit 1 }
$dir = $project.path -replace '/', '\'
$checkCommand = $project.check

# --- theme (shared palette in common.ps1) ----------------------------------------------------
$e = [char]27
$C = Get-ReiColors
$ellipsis = [string][char]0x2026
$rule = [string][char]0x2500

function Cut([string]$s, [int]$w) { if ($w -lt 2) { return '' }; if ($s.Length -le $w) { $s } else { $s.Substring(0, $w - 1) + $ellipsis } }
function CutLeft([string]$s, [int]$w) { if ($w -lt 2) { return '' }; if ($s.Length -le $w) { $s } else { $ellipsis + $s.Substring($s.Length - $w + 1) } }

function Format-Ago([datetime]$when) {
    $span = (Get-Date) - $when
    if ($span.TotalMinutes -lt 1) { return 'ahora' }
    if ($span.TotalHours -lt 1) { return "hace $([int]$span.TotalMinutes) min" }
    if ($span.TotalDays -lt 1) { return "hace $([int]$span.TotalHours) h" }
    if ($span.TotalDays -lt 60) { return "hace $([int]$span.TotalDays) d" }
    "hace $([int]($span.TotalDays / 30)) meses"
}

# --- panel settings (all optional, under "panel" in the config) ----------------------
$panelCfg = $config.panel
$showSystem = -not ($panelCfg -and $panelCfg.system -is [bool] -and -not $panelCfg.system)
$logoPath = if ($panelCfg -and $panelCfg.logo) { [string]$panelCfg.logo } else { Join-Path $PSScriptRoot '..\config\logo.txt' }
$logoLines = @()
if (Test-Path -LiteralPath $logoPath) { $logoLines = @(Get-Content -LiteralPath $logoPath -Encoding UTF8 | ForEach-Object { $_.TrimEnd() }) }
$logoWidth = if ($logoLines.Count) { ($logoLines | Measure-Object -Property Length -Maximum).Maximum } else { 0 }

# Dev project: explicit "dev" in the project entry, else detected from common marker files.
$isDev = if ($project.dev -is [bool]) { $project.dev } else {
    $markers = 'package.json', 'pyproject.toml', 'requirements.txt', 'go.mod', 'Cargo.toml', 'pom.xml', 'build.gradle', 'composer.json', 'Gemfile', 'deno.json'
    [bool](($markers | Where-Object { Test-Path -LiteralPath (Join-Path $dir $_) }) -or (Get-ChildItem -LiteralPath $dir -Filter *.csproj -ErrorAction SilentlyContinue | Select-Object -First 1))
}

# --- data ---------------------------------------------------------------------------
function Get-GitInfo {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @{ State = 'nodir' } }
    $out = & git -C $dir status --porcelain=v2 --branch 2>$null
    if ($LASTEXITCODE -ne 0) { return @{ State = 'norepo' } }
    $info = @{ State = 'ok'; Branch = '?'; Ahead = 0; Behind = 0; Upstream = $false; New = 0; Modified = 0; Deleted = 0; Conflicts = 0 }
    foreach ($line in $out) {
        if ($line -like '# branch.head *') { $info.Branch = $line.Substring(14) }
        elseif ($line -like '# branch.ab *') {
            $info.Upstream = $true
            if ($line -match '\+(\d+) -(\d+)') { $info.Ahead = [int]$Matches[1]; $info.Behind = [int]$Matches[2] }
        }
        elseif ($line.StartsWith('? ')) { $info.New++ }
        elseif ($line.StartsWith('u ')) { $info.Conflicts++ }
        elseif ($line -match '^[12] (.)(.)') {
            # one file counts once: deleted wins over new, new wins over modified
            if ($Matches[1] -eq 'D' -or $Matches[2] -eq 'D') { $info.Deleted++ }
            elseif ($Matches[1] -eq 'A') { $info.New++ }
            else { $info.Modified++ }
        }
    }
    $last = & git -C $dir log -1 --format='%h%x09%cI%x09%s' 2>$null
    if ($LASTEXITCODE -eq 0 -and $last) {
        $parts = $last -split "`t", 3
        $info.Hash = $parts[0]; $info.When = [datetime]::Parse($parts[1]); $info.Subject = $parts[2]
    }
    $info
}

function Get-SystemInfo {
    $r = @{ MemPct = $null; DiskPct = $null }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $total = [double]$os.TotalVisibleMemorySize; $free = [double]$os.FreePhysicalMemory
        $r.MemPct = [int][math]::Round(100 * ($total - $free) / $total)
        $r.MemTotalGB = [math]::Round($total / 1MB, 1); $r.MemUsedGB = [math]::Round(($total - $free) / 1MB, 1)
    }
    $letter = if ($dir -match '^([A-Za-z]):') { $Matches[1] } else { $env:SystemDrive.TrimEnd(':') }
    $d = Get-PSDrive -Name $letter -ErrorAction SilentlyContinue
    if ($d -and ($d.Used + $d.Free) -gt 0) {
        $r.Drive = "$($letter.ToUpper()):"
        $r.DiskPct = [int][math]::Round(100 * $d.Used / ($d.Used + $d.Free))
        $r.DiskFreeGB = [math]::Round($d.Free / 1GB, 0)
    }
    $r
}

$script:sys = $null
$script:cimCache = @{}
function Get-ProjectPorts {
    $needle = $dir.TrimEnd('\').ToLowerInvariant()
    $found = @{}
    try { $conns = Get-NetTCPConnection -State Listen -ErrorAction Stop } catch { return @() }
    foreach ($c in $conns) {
        $procId = [int]$c.OwningProcess
        if ($procId -le 4) { continue }
        if (-not $script:cimCache.ContainsKey($procId)) {
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue
            $script:cimCache[$procId] = if ($cim) { @{ Name = $cim.Name; Cmd = ("$($cim.CommandLine)" -replace '/', '\').ToLowerInvariant() } } else { $null }
        }
        $p = $script:cimCache[$procId]
        if ($p -and $p.Cmd.Contains($needle)) { $found[[int]$c.LocalPort] = $p.Name -replace '\.exe$', '' }
    }
    $found.GetEnumerator() | Sort-Object Name | ForEach-Object { @{ Port = $_.Name; Proc = $_.Value } }
}

# --- check (only the failing or running state is shown) -------------------------------
$script:check = @{ State = 'none'; Code = 0; At = $null; Job = $null }
function Start-Check {
    if (-not $checkCommand -or $script:check.State -eq 'running') { return }
    $script:check.State = 'running'
    $script:check.Job = Start-Job -ScriptBlock {
        param($d, $c)
        Set-Location -LiteralPath $d
        & cmd.exe /c $c *> $null
        $LASTEXITCODE
    } -ArgumentList $dir, $checkCommand
}
function Update-Check {
    $job = $script:check.Job
    if ($job -and $job.State -ne 'Running') {
        $res = @(Receive-Job $job -ErrorAction SilentlyContinue)
        Remove-Job $job -Force
        $script:check.Job = $null
        $code = if ($res.Count -gt 0) { [int]$res[-1] } else { 1 }
        $script:check.Code = $code
        $script:check.At = Get-Date
        $script:check.State = if ($code -eq 0) { 'ok' } else { 'fail' }
    }
}

# --- render ---------------------------------------------------------------------------
function Build-Frame([int]$w, $git, $ports) {
    $lines = New-Object System.Collections.Generic.List[string]
    $inner = $w - 2
    if ($logoLines.Count -gt 0 -and $inner -ge $logoWidth) {
        foreach ($l in $logoLines) { $lines.Add("$($C.Accent)$l$($C.Reset)") }
        $lines.Add('')
    }
    $lines.Add("$($C.Bold)$($C.Accent)REI$($C.Reset) $($C.Text)$(Cut $Name ($inner - 4))$($C.Reset)")
    $lines.Add("$($C.Dim)$(CutLeft $dir $inner)$($C.Reset)")
    $lines.Add('')

    $lines.Add("$($C.Dim)GIT $($rule * [math]::Max(0, $inner - 4))$($C.Reset)")
    switch ($git.State) {
        'nodir'  { $lines.Add("$($C.Bad)$(Cut 'el directorio no existe' $inner)$($C.Reset)") }
        'norepo' { $lines.Add("$($C.Dim)$(Cut 'no es un repo git' $inner)$($C.Reset)") }
        default {
            $lines.Add("$($C.Dim)rama        $($C.Branch)$(Cut $git.Branch ($inner - 6))$($C.Reset)")
            $total = $git.New + $git.Modified + $git.Deleted + $git.Conflicts
            if ($total -eq 0) {
                $lines.Add("$($C.Dim)cambios     $($C.Ok)limpio$($C.Reset)")
            } else {
                $lines.Add("$($C.Dim)nuevos      $(if ($git.New) { $C.Ok } else { $C.Dim })$($git.New)$($C.Reset)")
                $lines.Add("$($C.Dim)modificados $(if ($git.Modified) { $C.Warn } else { $C.Dim })$($git.Modified)$($C.Reset)")
                $lines.Add("$($C.Dim)eliminados  $(if ($git.Deleted) { $C.Bad } else { $C.Dim })$($git.Deleted)$($C.Reset)")
                if ($git.Conflicts) { $lines.Add("$($C.Dim)conflictos  $($C.Bad)$($git.Conflicts)$($C.Reset)") }
            }
            if ($git.Upstream) {
                if ($git.Ahead -eq 0 -and $git.Behind -eq 0) { $lines.Add("$($C.Dim)remoto      $($C.Ok)al dia$($C.Reset)") }
                else { $lines.Add("$($C.Dim)remoto      $($C.Text)+$($git.Ahead) por subir, -$($git.Behind) por bajar$($C.Reset)") }
            } else { $lines.Add("$($C.Dim)remoto      sin rama remota$($C.Reset)") }
            if ($git.Hash) {
                $lines.Add("$($C.Dim)ultimo      $($C.Text)$($git.Hash) $($C.Dim)$(Format-Ago $git.When)$($C.Reset)")
                $lines.Add("$($C.Text)$(Cut $git.Subject $inner)$($C.Reset)")
            }
        }
    }

    if ($isDev) {
        $lines.Add('')
        $lines.Add("$($C.Dim)PUERTOS $($rule * [math]::Max(0, $inner - 8))$($C.Reset)")
        if (@($ports).Count -eq 0) { $lines.Add("$($C.Dim)ninguno activo$($C.Reset)") }
        foreach ($p in $ports) { $lines.Add("$($C.Info):$($p.Port)$($C.Reset) $($C.Dim)$(Cut $p.Proc ($inner - 7))$($C.Reset)") }
    }

    if ($script:check.State -eq 'running' -or $script:check.State -eq 'fail') {
        $lines.Add('')
        $lines.Add("$($C.Dim)CHECK $($rule * [math]::Max(0, $inner - 6))$($C.Reset)")
        if ($script:check.State -eq 'running') { $lines.Add("$($C.Warn)ejecutando...$($C.Reset)") }
        else {
            $lines.Add("$($C.Bad)FALLA$($C.Reset) $($C.Dim)codigo $($script:check.Code), $(Format-Ago $script:check.At)$($C.Reset)")
            $lines.Add("$($C.Dim)$(Cut $checkCommand $inner)$($C.Reset)")
        }
    }

    if ($showSystem -and $script:sys) {
        $sys = $script:sys
        $lines.Add('')
        $lines.Add("$($C.Dim)WINDOWS $($rule * [math]::Max(0, $inner - 8))$($C.Reset)")
        if ($sys.MemPct -ne $null) {
            $col = if ($sys.MemPct -ge 90) { $C.Bad } elseif ($sys.MemPct -ge 75) { $C.Warn } else { $C.Ok }
            $lines.Add("$($C.Dim)memoria     $col$($sys.MemPct)%$($C.Dim) $($sys.MemUsedGB)/$($sys.MemTotalGB) GB$($C.Reset)")
        }
        if ($sys.DiskPct -ne $null) {
            $col = if ($sys.DiskPct -ge 95) { $C.Bad } elseif ($sys.DiskPct -ge 85) { $C.Warn } else { $C.Ok }
            $lines.Add("$($C.Dim)disco $($sys.Drive)    $col$($sys.DiskPct)%$($C.Dim) $($sys.DiskFreeGB) GB libres$($C.Reset)")
        }
    }

    $lines.Add('')
    $hint = if ($checkCommand) { 'c check  q salir' } else { 'q salir' }
    $lines.Add("$($C.Dim)$(Get-Date -Format 'HH:mm:ss')  $hint$($C.Reset)")
    $lines
}

function Get-Width { if ($Width -gt 0) { return $Width }; try { [Console]::WindowWidth } catch { 40 } }
function Get-Height { try { [Console]::WindowHeight } catch { 50 } }

$script:prevFrame = @()
# Paints with absolute cursor positioning on the alternate screen: no newlines, so it can never
# scroll or leave copies behind, and only the lines that changed are rewritten.
function Write-Frame($git, $ports, [switch]$Force) {
    $w = Get-Width
    $rows = Get-Height
    $lines = @(Build-Frame $w $git $ports | Select-Object -First $rows)
    $sb = New-Object System.Text.StringBuilder
    if ($Force) { [void]$sb.Append("$e[2J"); $script:prevFrame = @() }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $text = " $($lines[$i])"
        if ($i -ge $script:prevFrame.Count -or $script:prevFrame[$i] -ne $text) {
            [void]$sb.Append("$e[$($i + 1);1H$text$($C.Reset)$e[K")
        }
    }
    if ($script:prevFrame.Count -gt $lines.Count) { [void]$sb.Append("$e[$($lines.Count + 1);1H$e[J") }
    $script:prevFrame = @($lines | ForEach-Object { " $_" })
    if ($sb.Length -gt 0) { [Console]::Write($sb.ToString()) }
}

# --- main ------------------------------------------------------------------------------
if ($Frames -gt 0) {
    $git = Get-GitInfo; $ports = @(Get-ProjectPorts); if ($showSystem) { $script:sys = Get-SystemInfo }
    [Console]::Write("$e[?1049h$e[?7l$e[?25l$e[2J")
    Write-Frame $git $ports -Force
    for ($n = 1; $n -lt $Frames; $n++) { Start-Sleep -Milliseconds 1100; Write-Frame $git $ports }
    [Console]::Write("$e[?7h$e[?25h$e[?1049l$e[0m")
    return
}
if ($Once) {
    if ($PreviewCheck) { $script:check.State = $PreviewCheck; $script:check.Code = 3; $script:check.At = (Get-Date).AddMinutes(-2) }
    $git = Get-GitInfo; $ports = @(Get-ProjectPorts)
    if ($showSystem) { $script:sys = Get-SystemInfo }
    (Build-Frame (Get-Width) $git $ports) | ForEach-Object { " $_$($C.Reset)" }
    return
}

$Host.UI.RawUI.WindowTitle = "Rei panel - $Name"
# alternate screen, autowrap off, cursor hidden
[Console]::Write("$e[?1049h$e[?7l$e[?25l$e[2J")
try {
    $git = Get-GitInfo; $ports = @(Get-ProjectPorts)
    if ($showSystem) { $script:sys = Get-SystemInfo }
    $lastData = Get-Date
    $lastPorts = Get-Date
    $lastSize = "$(Get-Width)x$(Get-Height)"
    $lastClock = ''
    Write-Frame $git $ports -Force
    while ($true) {
        $redraw = $false
        if (((Get-Date) - $lastData).TotalSeconds -ge $RefreshSeconds) {
            $git = Get-GitInfo; if ($showSystem) { $script:sys = Get-SystemInfo }
            $lastData = Get-Date; $redraw = $true
        }
        if (((Get-Date) - $lastPorts).TotalSeconds -ge ($RefreshSeconds * 2)) { $ports = @(Get-ProjectPorts); $lastPorts = Get-Date; $redraw = $true }
        $before = $script:check.State; Update-Check; if ($script:check.State -ne $before) { $redraw = $true }
        $clock = Get-Date -Format 'HH:mm:ss'
        if ($clock -ne $lastClock) { $lastClock = $clock; $redraw = $true }
        $size = "$(Get-Width)x$(Get-Height)"
        if ($size -ne $lastSize) { $lastSize = $size; Write-Frame $git $ports -Force; $redraw = $false }
        if ($redraw) { Write-Frame $git $ports }
        Start-Sleep -Milliseconds 150
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Q' -or $k.Key -eq 'Escape') { return }
            if ($k.Key -eq 'C') { Start-Check; Write-Frame $git $ports }
        }
    }
} finally {
    [Console]::Write("$e[?7h$e[?25h$e[?1049l$e[0m")
}
