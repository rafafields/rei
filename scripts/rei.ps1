<#
.SYNOPSIS
  Rei launcher: opens Claude Code and the project panel in Windows Terminal, one tab per project.

.DESCRIPTION
  Reads the project list from config/projects.json (override with $env:REI_CONFIG).
  With no arguments it shows a numbered menu. If the config defines "special", a second
  pane (the data panel) is opened next to Claude in each project tab.

.EXAMPLE
  rei                 # menu
  rei my-project other-project   # one or several projects by name
  rei -All            # every project in the list
  rei -List           # show the list and exit
  rei rei -DryRun     # print what would run, launch nothing
  rei -Config         # go to the folder Rei is installed in
  rei -Customize      # run the installer again to change colours, font, projects...
  rei -Uninstall      # remove Rei from Windows Terminal and from your PowerShell profile
  rei -Help           # list the commands
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Name,
    [switch]$All,
    [switch]$List,
    [switch]$DryRun,
    [switch]$Config,
    [Alias('Customise')][switch]$Customize,
    [switch]$Uninstall,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "rei: $Message" -ForegroundColor Red
    exit 1
}

# --- management commands (they work even before there is a project list) ---------------------
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ($Help) {
    Write-Host ''
    Write-Host 'rei - Windows Terminal + Claude Code workspace' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Open projects'
    Write-Host '  rei                      menu of your projects'
    Write-Host '  rei <name> [<name>...]   open one or several projects by name'
    Write-Host '  rei -All                 open every project'
    Write-Host '  rei -List                list the projects and exit'
    Write-Host '  rei <name> -DryRun       print what would run, open nothing'
    Write-Host ''
    Write-Host 'Manage Rei'
    Write-Host '  rei -Config              go to the folder where Rei is installed'
    Write-Host '                           (config/projects.json, theme/, scripts/)'
    Write-Host '  rei -Customize           run the installer again: projects, colours, font,'
    Write-Host '                           panel options (your current values are the defaults)'
    Write-Host '  rei -Uninstall           remove Rei from Windows Terminal and your PowerShell profile'
    Write-Host '                           (keeps the folder and your projects)'
    Write-Host '  rei -Help                show this help'
    Write-Host ''
    return
}

if ($Config) {
    # The profile function changes directory for you; this is the fallback when the script runs directly.
    Write-Host $root
    Invoke-Item -LiteralPath $root
    return
}

if ($Customize -or $Uninstall) {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail 'Node.js is required for the installer (https://nodejs.org).' }
    $flag = if ($Uninstall) { '--uninstall' } else { '--customize' }
    $extra = if ($DryRun) { @('--dry-run') } else { @() }
    & node (Join-Path $root 'installer\index.mjs') $flag @extra
    exit $LASTEXITCODE
}

# --- config -----------------------------------------------------------------
. (Join-Path $PSScriptRoot 'common.ps1')
try { $reiConfig = Read-ReiConfig } catch { Fail $_.Exception.Message }
$projects = @($reiConfig.projects)

if ($List) {
    $projects | ForEach-Object {
        $mark = if (Test-Path -LiteralPath $_.path -PathType Container) { ' ' } else { '!' }
        '{0} {1,-16} {2}' -f $mark, $_.name, $_.path
    }
    return
}

# --- select -----------------------------------------------------------------
if ($All) {
    $selected = $projects
} elseif ($Name -and $Name.Count -gt 0) {
    $selected = foreach ($n in $Name) {
        $hit = $projects | Where-Object { $_.name -eq $n }
        if (-not $hit) { Fail "unknown project '$n'. Known: $(($projects.name) -join ', ')" }
        $hit
    }
} else {
    for ($i = 0; $i -lt $projects.Count; $i++) { '{0,2}) {1}  {2}' -f ($i + 1), $projects[$i].name, $projects[$i].path }
    $answer = Read-Host 'Project number(s), comma-separated (empty to cancel)'
    if ([string]::IsNullOrWhiteSpace($answer)) { return }
    $selected = foreach ($token in ($answer -split '[,\s]+' | Where-Object { $_ })) {
        $idx = 0
        if (-not [int]::TryParse($token, [ref]$idx) -or $idx -lt 1 -or $idx -gt $projects.Count) { Fail "invalid choice '$token'" }
        $projects[$idx - 1]
    }
}

# --- tools ------------------------------------------------------------------
$wt = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
if (-not $wt) { Fail 'Windows Terminal not found. Install it: winget install Microsoft.WindowsTerminal' }
$claudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $claudeExe) { Fail 'claude not found in PATH.' }

# One argument for the wt command line: quoted when needed, ';' escaped (wt uses it to chain commands).
function Quote([string]$s) {
    $s = $s -replace ';', '\;'
    if ($s -match '[\s"]') { '"' + (($s -replace '"', '\"') -replace '(\+)$', '$1$1') + '"' } else { $s }
}

$ratio = if ($reiConfig.layout -and $reiConfig.layout.claudeRatio) { [double]$reiConfig.layout.claudeRatio } else { 0.75 }
if ($ratio -lt 0.3 -or $ratio -gt 0.9) { Fail "layout.claudeRatio must be between 0.3 and 0.9 (got $ratio)" }
$hasPanel = -not ($reiConfig.special -is [bool] -and -not $reiConfig.special)
$maximized = -not ($reiConfig.layout -and $reiConfig.layout.maximized -is [bool] -and -not $reiConfig.layout.maximized)

# The installer writes a Windows Terminal fragment with the "Rei" profile (colours, font, padding).
$fragment = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\rei\rei.json'
$profileArgs = if (Test-Path -LiteralPath $fragment) { @('-p', 'Rei') } else { @() }
# The panel pane uses "Rei Panel": same look, smaller text. Only if the installed fragment has it.
$panelProfileArgs = if ((Test-Path -LiteralPath $fragment) -and ((Get-Content -LiteralPath $fragment -Raw) -match 'Rei Panel')) { @('-p', '"Rei Panel"') } else { $profileArgs }

# --- Claude settings: Rei status line, only for sessions started by rei --------------
# Passed with `claude --settings <file>`, so your own ~/.claude/settings.json (and any other
# status line you use elsewhere) is left untouched. Disable with "statusLine": false in the config.
$claudeCommand = @($claudeExe)
if (-not ($reiConfig.statusLine -is [bool] -and -not $reiConfig.statusLine)) {
    $statusScript = (Resolve-Path (Join-Path $PSScriptRoot 'statusline.ps1')).Path.Replace([string][char]92, '/')
    $settingsFile = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\config\claude-settings.json'))
    $settings = @{ statusLine = @{ type = 'command'; command = "powershell -NoProfile -ExecutionPolicy Bypass -File $statusScript"; refreshInterval = 120 } }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path $settingsFile) | Out-Null
        [System.IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    }
    $claudeCommand = @($claudeExe, '--settings', $settingsFile)
}

# --- launch -----------------------------------------------------------------
# One shared Windows Terminal window named "rei": every `rei` command adds its projects as tabs to it
# (a new window is created only if none is open). Each tab is titled with the kanji and the project
# name, with Claude on the left and the panel on the right (a native split: drag the divider).
$kanji = [string][char]0x96F6
$commands = New-Object System.Collections.Generic.List[string]
$opened = New-Object System.Collections.Generic.List[string]
foreach ($p in $selected) {
    if (-not (Test-Path -LiteralPath $p.path -PathType Container)) {
        Write-Host "rei: skipping '$($p.name)': directory does not exist: $($p.path)" -ForegroundColor Yellow
        continue
    }
    $dir = (Resolve-Path -LiteralPath $p.path).Path
    $title = Quote "$kanji $($p.name)"
    $tab = @('new-tab') + $profileArgs + @('--title', $title, '--suppressApplicationTitle', '-d', (Quote $dir)) + ($claudeCommand | ForEach-Object { Quote $_ })
    $commands.Add($tab -join ' ')
    # "special": omitted = the built-in panel; an array = your own command; false = no second pane.
    if ($hasPanel) {
        $special = if ($reiConfig.special) {
            @($reiConfig.special)
        } else {
            @('powershell.exe', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'panel.ps1'), '-Name', $p.name)
        }
        $pane = @('split-pane', '-V', '-s', ([string]::Format([cultureinfo]::InvariantCulture, '{0:0.##}', (1 - $ratio)))) + $panelProfileArgs + @('--title', $title, '--suppressApplicationTitle', '-d', (Quote $dir)) + ($special | ForEach-Object { Quote $_ })
        $commands.Add($pane -join ' ')
        $commands.Add('move-focus left')
    }
    $opened.Add($p.name)
}
if ($commands.Count -eq 0) { Fail 'nothing to open.' }
# Focus the first tab opened by this command (the window may already hold other tabs): the last one
# is focused after creating them, so step back once per extra tab.
for ($i = 1; $i -lt $opened.Count; $i++) { $commands.Add('focus-tab -p') }
$wtArgs = @('-w', 'rei') + $(if ($maximized) { @('--maximized') } else { @() })
$line = ($wtArgs -join ' ') + ' ' + ($commands -join ' ; ')

if ($DryRun) {
    Write-Host "[dry-run] wt $line"
    Write-Host ("[dry-run] tabs: {0}" -f ($opened -join ', '))
    return
}
Start-Process -FilePath $wt -ArgumentList $line
