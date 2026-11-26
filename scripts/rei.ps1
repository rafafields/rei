<#
.SYNOPSIS
  Rei launcher: opens an Alacritty window running Claude Code in a project's directory.

.DESCRIPTION
  Reads the project list from config/projects.json (override with $env:REI_CONFIG).
  With no arguments it shows a numbered menu. If the config defines "special", a second
  window (the data panel) is opened next to Claude for each project.

.EXAMPLE
  rei                 # menu
  rei my-project other-project   # one or several projects by name
  rei -All            # every project in the list
  rei -List           # show the list and exit
  rei rei -DryRun     # print what would run, launch nothing
  rei -Config         # go to the folder Rei is installed in
  rei -Customize      # run the installer again to change colours, font, logo, projects...
  rei -Uninstall      # remove Rei from Alacritty and from your PowerShell profile
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
    Write-Host 'rei - Alacritty + Claude Code workspace' -ForegroundColor Red
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
    Write-Host '                           (config/projects.json, config/logo.txt, theme/, scripts/)'
    Write-Host '  rei -Customize           run the installer again: projects, colours, font, logo,'
    Write-Host '                           panel options (your current values are the defaults)'
    Write-Host '  rei -Uninstall           remove Rei from Alacritty and your PowerShell profile'
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
try { $config = Read-ReiConfig } catch { Fail $_.Exception.Message }
$projects = @($config.projects)

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
$alacritty = (Get-Command alacritty -ErrorAction SilentlyContinue).Source
if (-not $alacritty -and (Test-Path 'C:\Program Files\Alacritty\alacritty.exe')) { $alacritty = 'C:\Program Files\Alacritty\alacritty.exe' }
if (-not $alacritty) { Fail 'Alacritty not found. Install it or add it to PATH.' }
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Fail 'claude not found in PATH.' }

function Quote([string]$s) { if ($s -match '[\s"]') { '"' + ($s -replace '"', '\"') + '"' } else { $s } }

. (Join-Path $PSScriptRoot 'layout.ps1')
$ratio = if ($config.layout -and $config.layout.claudeRatio) { [double]$config.layout.claudeRatio } else { 0.75 }
if ($ratio -lt 0.3 -or $ratio -gt 0.9) { Fail "layout.claudeRatio must be between 0.3 and 0.9 (got $ratio)" }
# Draggable divider between the two windows: on by default, "layout": { "divider": false } turns it off.
$hasPanel = -not ($config.special -is [bool] -and -not $config.special)
$wantDivider = -not ($config.layout -and $config.layout.divider -is [bool] -and -not $config.layout.divider)
$gap = if ($hasPanel -and $wantDivider) { 10 } else { 0 }

function Open-Window([string]$Title, [string]$Dir, [string[]]$Command, $Slot) {
    $argList = @('--title', $Title, '--working-directory', $Dir, '-e') + $Command
    $line = ($argList | ForEach-Object { Quote $_ }) -join ' '
    if ($DryRun) {
        Write-Host ("[dry-run] alacritty {0}`n          -> x={1} y={2} w={3} h={4}" -f $line, $Slot.X, $Slot.Y, $Slot.W, $Slot.H)
        return $null
    }
    $proc = Start-Process -FilePath $alacritty -ArgumentList $line -PassThru
    $handle = Wait-ReiWindow $proc.Id
    if ($handle -eq [IntPtr]::Zero) {
        Write-Host "rei: window '$Title' did not appear in time; left unplaced." -ForegroundColor Yellow
        return $null
    }
    Set-ReiWindowRect $handle $Slot
    return $handle
}

# Starts the divider for a pair of windows. It exits by itself when either window closes.
function Start-Divider($Left, $Right, $Slot) {
    $script = Join-Path $PSScriptRoot 'splitter.ps1'
    if ($DryRun) {
        Write-Host ("[dry-run] divider between the two windows -> x={0} y={1} w={2} h={3}" -f $Slot.X, $Slot.Y, $Slot.W, $Slot.H)
        return
    }
    if (-not $Left -or -not $Right) { return }
    $argText = '-NoLogo -NoProfile -STA -WindowStyle Hidden -File "{0}" -Left {1} -Right {2} -Gap {3}' -f $script, $Left.ToInt64(), $Right.ToInt64(), $gap
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argText -WindowStyle Hidden | Out-Null
}

# --- Claude settings: Rei status line, only for sessions started by rei --------------
# Passed with `claude --settings <file>`, so your own ~/.claude/settings.json (and any other
# status line you use elsewhere) is left untouched. Disable with "statusLine": false in the config.
$claudeCommand = @('claude')
if (-not ($config.statusLine -is [bool] -and -not $config.statusLine)) {
    $statusScript = (Resolve-Path (Join-Path $PSScriptRoot 'statusline.ps1')).Path.Replace([string][char]92, '/')
    $settingsFile = Join-Path $PSScriptRoot '..\config\claude-settings.json'
    $settings = @{ statusLine = @{ type = 'command'; command = "powershell -NoProfile -File $statusScript"; refreshInterval = 120 } }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path $settingsFile) | Out-Null
        [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($settingsFile), ($settings | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    }
    $claudeCommand = @('claude', '--settings', [System.IO.Path]::GetFullPath($settingsFile))
}

# --- launch -----------------------------------------------------------------
$slots = Get-ReiSlots $ratio $gap
foreach ($p in $selected) {
    if (-not (Test-Path -LiteralPath $p.path -PathType Container)) {
        Write-Host "rei: skipping '$($p.name)': directory does not exist: $($p.path)" -ForegroundColor Yellow
        continue
    }
    $dir = (Resolve-Path -LiteralPath $p.path).Path
    $claudeWindow = Open-Window "Rei - $($p.name)" $dir $claudeCommand $slots.Claude
    # "special": omitted = the built-in panel; an array = your own command; false = no second window.
    if ($config.special -is [bool] -and -not $config.special) { continue }
    $special = if ($config.special) {
        @($config.special)
    } else {
        @('powershell.exe', '-NoLogo', '-NoProfile', '-File', (Join-Path $PSScriptRoot 'panel.ps1'), '-Name', $p.name)
    }
    $panelWindow = Open-Window "Rei panel - $($p.name)" $dir $special $slots.Panel
    if ($gap -gt 0) { Start-Divider $claudeWindow $panelWindow $slots.Divider }
}
