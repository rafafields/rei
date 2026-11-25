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
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Name,
    [switch]$All,
    [switch]$List,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "rei: $Message" -ForegroundColor Red
    exit 1
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

function Open-Window([string]$Title, [string]$Dir, [string[]]$Command, $Slot) {
    $argList = @('--title', $Title, '--working-directory', $Dir, '-e') + $Command
    $line = ($argList | ForEach-Object { Quote $_ }) -join ' '
    if ($DryRun) {
        Write-Host ("[dry-run] alacritty {0}`n          -> x={1} y={2} w={3} h={4}" -f $line, $Slot.X, $Slot.Y, $Slot.W, $Slot.H)
        return
    }
    $proc = Start-Process -FilePath $alacritty -ArgumentList $line -PassThru
    $handle = Wait-ReiWindow $proc.Id
    if ($handle -eq [IntPtr]::Zero) {
        Write-Host "rei: window '$Title' did not appear in time; left unplaced." -ForegroundColor Yellow
        return
    }
    Set-ReiWindowRect $handle $Slot
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
$slots = Get-ReiSlots $ratio
foreach ($p in $selected) {
    if (-not (Test-Path -LiteralPath $p.path -PathType Container)) {
        Write-Host "rei: skipping '$($p.name)': directory does not exist: $($p.path)" -ForegroundColor Yellow
        continue
    }
    $dir = (Resolve-Path -LiteralPath $p.path).Path
    Open-Window "Rei - $($p.name)" $dir $claudeCommand $slots.Claude
    # "special": omitted = the built-in panel; an array = your own command; false = no second window.
    if ($config.special -is [bool] -and -not $config.special) { continue }
    $special = if ($config.special) {
        @($config.special)
    } else {
        @('powershell.exe', '-NoLogo', '-NoProfile', '-File', (Join-Path $PSScriptRoot 'panel.ps1'), '-Name', $p.name)
    }
    Open-Window "Rei panel - $($p.name)" $dir $special $slots.Panel
}
