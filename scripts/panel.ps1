<#
.SYNOPSIS
  Rei panel: the narrow "special" terminal that sits next to Claude Code.

.DESCRIPTION
  The panel itself only draws a header (kanji, project name and path), the sections, and a footer.
  Everything in between is a section: a small script that returns a title and some lines.
  Built-in sections (scripts/sections/): git, ports, check, system. Your own go in config/widgets/.
  Which sections show, and in what order, is "panel.sections" in the config.
  Each section runs in the background with a time limit; a broken one shows an error line and
  never takes the panel down. Keys: c = run check, q or Esc = quit.
  The file is ASCII-only on purpose (Windows PowerShell 5.1 reads BOM-less files as ANSI).

.EXAMPLE
  panel.ps1 -Name rei
  panel.ps1 -Name rei -Once -Width 40          # render once to stdout (for testing)
  panel.ps1 -Name rei -TestSection git         # validate one section and print what it returns
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [switch]$Once,
    [int]$Width = 0,
    [ValidateSet('', 'running', 'fail')][string]$PreviewCheck = '',   # testing: render with this check state
    [int]$Frames = 0,                                                 # testing: run the real painter N times and exit
    [string]$TestSection = ''                                         # testing: validate one section
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'sections.ps1')

try { $config = Read-ReiConfig } catch { Write-Host "rei panel: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 5; exit 1 }
$project = @($config.projects) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
if (-not $project) { Write-Host "rei panel: unknown project '$Name'" -ForegroundColor Red; Start-Sleep 5; exit 1 }
$dir = $project.path -replace '/', '\'
$checkCommand = $project.check

# --- theme and settings ---------------------------------------------------------------------
$e = [char]27
$C = Get-ReiColors
$rule = [string][char]0x2500
$kanji = [string][char]0x96F6
$barChar = Get-ReiBarChar

$panelCfg = $config.panel
$showSystem = -not ($panelCfg -and $panelCfg.system -is [bool] -and -not $panelCfg.system)
# Dev project: explicit "dev" in the project entry, else detected from common marker files.
$isDev = if ($project.dev -is [bool]) { $project.dev } else {
    $markers = 'package.json', 'pyproject.toml', 'requirements.txt', 'go.mod', 'Cargo.toml', 'pom.xml', 'build.gradle', 'composer.json', 'Gemfile', 'deno.json'
    [bool](($markers | Where-Object { Test-Path -LiteralPath (Join-Path $dir $_) }) -or (Get-ChildItem -LiteralPath $dir -Filter *.csproj -ErrorAction SilentlyContinue | Select-Object -First 1))
}

function Get-Width { if ($Width -gt 0) { return $Width }; try { [Console]::WindowWidth } catch { 40 } }
function Get-Height { try { [Console]::WindowHeight } catch { 50 } }

# --- check (owned by the panel because of the c key; shown by the "check" section) ----------
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

# --- sections -------------------------------------------------------------------------------
$sections = @(Get-ReiSectionList $config)
$script:secState = New-ReiSectionState $sections

# Everything a section may read. Sections get a copy of the plain values, never the panel's variables.
function New-SectionContext {
    @{
        Name = $Name; Path = $dir; IsDev = $isDev; Width = ((Get-Width) - 2)
        Colors = $C; BarChar = $barChar; ShowSystem = $showSystem; CheckCommand = $checkCommand
        CheckState = @{ State = $script:check.State; Code = $script:check.Code; At = $script:check.At }
    }
}
$newContext = { New-SectionContext }

function Mark-Stale([string]$SectionName) {
    if ($script:secState.ContainsKey($SectionName)) { $script:secState[$SectionName].Stale = $true }
}
function Mark-AllStale { foreach ($k in @($script:secState.Keys)) { $script:secState[$k].Stale = $true } }

# Blocks until every section has a first result (or the limit passes): used before the first paint.
function Wait-Sections([double]$Limit = 4) {
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $Limit) {
        [void](Update-ReiSections $sections $script:secState $newContext)
        if (-not ($script:secState.Values | Where-Object { $null -eq $_.Result })) { return }
        Start-Sleep -Milliseconds 40
    }
}

# --- render ---------------------------------------------------------------------------------
function Build-Frame([int]$w) {
    $lines = New-Object System.Collections.Generic.List[string]
    $inner = $w - 2
    $lines.Add("$($C.Bold)$($C.Accent)$kanji$($C.Reset) $($C.Text)$(Cut $Name ($inner - 4))$($C.Reset)")
    $lines.Add("$($C.Dim)$(CutLeft $dir $inner)$($C.Reset)")

    foreach ($s in $sections) {
        $res = $script:secState[$s.Name].Result
        if (-not $res -or $res.State -eq 'hidden') { continue }
        $title = if ($res.State -eq 'ok') { $res.Title } else { $s.Name.ToUpper() }
        $lines.Add('')
        $lines.Add("$($C.Dim)$title $($rule * [math]::Max(0, $inner - $title.Length - 1))$($C.Reset)")
        if ($res.State -eq 'ok') { foreach ($l in $res.Lines) { $lines.Add($l) } }
        else { $lines.Add("$($C.Bad)$(Cut $res.Message $inner)$($C.Reset)") }
    }

    $lines.Add('')
    $hint = if ($checkCommand) { 'c check  q salir' } else { 'q salir' }
    $lines.Add("$($C.Dim)$(Get-Date -Format 'HH:mm:ss')  $hint$($C.Reset)")
    $lines
}

$script:prevFrame = @()
# Paints with absolute cursor positioning on the alternate screen: no newlines, so it can never
# scroll or leave copies behind, and only the lines that changed are rewritten.
function Write-Frame([switch]$Force) {
    $w = Get-Width
    $rows = Get-Height
    $lines = @(Build-Frame $w | Select-Object -First $rows)
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

# --- section test: validates one section and prints what it returns --------------------------
if ($TestSection) {
    $sec = @{ Name = $TestSection; Every = 1; Path = (Resolve-ReiSectionPath $TestSection) }
    $failures = New-Object System.Collections.Generic.List[string]
    if (-not $sec.Path) {
        Write-Host "FAIL  no section named '$TestSection' in scripts\sections or config\widgets" -ForegroundColor Red
        exit 1
    }
    Write-Host "section $TestSection  ($($sec.Path))"
    $bytes = [System.IO.File]::ReadAllBytes($sec.Path)
    if ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1) {
        $failures.Add('the file has non-ASCII characters (Windows PowerShell 5.1 reads it as ANSI and garbles them; use [char]0x... instead)')
    }
    $ctx = New-SectionContext
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $res = Invoke-ReiSectionSync $sec $ctx
    $clock.Stop()
    Write-Host ("ran in {0} ms (limit {1} s)" -f $clock.ElapsedMilliseconds, $script:ReiSectionTimeout)
    if ($res.State -eq 'error') { $failures.Add($res.Message) }
    elseif ($res.State -eq 'hidden') { Write-Host 'result: hidden (the section does not apply to this project right now)' }
    else {
        Write-Host "result: title '$($res.Title)', $($res.Lines.Count) line(s), width limit $($ctx.Width)"
        $n = 0
        foreach ($l in $res.Lines) {
            $n++
            $visible = $l -replace "$e\[[0-9;]*m", ''
            Write-Host "  | $l$($C.Reset)"
            if ($visible.Length -gt $ctx.Width) { $failures.Add("line $n is $($visible.Length) columns wide, the limit is $($ctx.Width) (use Cut)") }
        }
    }
    if ($clock.ElapsedMilliseconds -gt ($sec.Every * 1000 * 3) -and $res.State -eq 'ok') {
        Write-Host "note  slow for a refresh every $($sec.Every) s; set a longer 'every' for it" -ForegroundColor Yellow
    }
    if ($failures.Count -gt 0) {
        $failures | ForEach-Object { Write-Host "FAIL  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host 'OK' -ForegroundColor Green
    return
}

# --- main -----------------------------------------------------------------------------------
if ($PreviewCheck) { $script:check.State = $PreviewCheck; $script:check.Code = 3; $script:check.At = (Get-Date).AddMinutes(-2) }

if ($Once) {
    Wait-Sections
    (Build-Frame (Get-Width)) | ForEach-Object { " $_$($C.Reset)" }
    return
}
if ($Frames -gt 0) {
    Wait-Sections
    [Console]::Write("$e[?1049h$e[?7l$e[?25l$e[2J")
    Write-Frame -Force
    for ($n = 1; $n -lt $Frames; $n++) { Start-Sleep -Milliseconds 1100; [void](Update-ReiSections $sections $script:secState $newContext); Write-Frame }
    [Console]::Write("$e[?7h$e[?25h$e[?1049l$e[0m")
    return
}

$Host.UI.RawUI.WindowTitle = "Rei panel - $Name"
# alternate screen, autowrap off, cursor hidden
[Console]::Write("$e[?1049h$e[?7l$e[?25l$e[2J")
try {
    Wait-Sections
    $lastSize = "$(Get-Width)x$(Get-Height)"
    $lastClock = ''
    Write-Frame -Force
    while ($true) {
        $redraw = $false
        if (Update-ReiSections $sections $script:secState $newContext) { $redraw = $true }
        $before = $script:check.State; Update-Check
        if ($script:check.State -ne $before) { Mark-Stale 'check'; $redraw = $true }
        $clock = Get-Date -Format 'HH:mm:ss'
        if ($clock -ne $lastClock) { $lastClock = $clock; $redraw = $true }
        $size = "$(Get-Width)x$(Get-Height)"
        if ($size -ne $lastSize) { $lastSize = $size; Mark-AllStale; Write-Frame -Force; $redraw = $false }
        if ($redraw) { Write-Frame }
        Start-Sleep -Milliseconds 150
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Q' -or $k.Key -eq 'Escape') { return }
            if ($k.Key -eq 'C') { Start-Check; Mark-Stale 'check'; Write-Frame }
        }
    }
} finally {
    [Console]::Write("$e[?7h$e[?25h$e[?1049l$e[0m")
}
