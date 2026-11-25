# Section runner for the Rei panel (dot-sourced by panel.ps1). Keep this file ASCII-only.
#
# A section is a script that receives one context hashtable and returns a hashtable:
#   @{ Title = 'GIT'; Lines = @('text with optional ANSI colours', ...) }   -> shown
#   @{ Hidden = $true }                                                       -> not shown
# Built-in sections live in scripts/sections/. Your own go in config/widgets/ (git-ignored).
# Each one runs in its own runspace with a time limit, so a slow or broken section can never
# freeze or break the panel: it shows an error line and the rest keeps working.

$script:ReiSectionDefaults = [ordered]@{ git = 5; ports = 10; check = 1; system = 5 }
$script:ReiSectionTimeout = 10

function Resolve-ReiSectionPath([string]$Name) {
    if ($Name -notmatch '^[A-Za-z0-9_-]+$') { return $null }
    foreach ($dir in @((Join-Path $PSScriptRoot 'sections'), (Join-Path $PSScriptRoot '..\config\widgets'))) {
        $file = Join-Path $dir "$Name.ps1"
        if (Test-Path -LiteralPath $file -PathType Leaf) { return (Resolve-Path -LiteralPath $file).Path }
    }
    $null
}

# Reads "panel.sections" (strings or { "name": ..., "every": seconds }); defaults to the built-ins.
function Get-ReiSectionList($Config) {
    $raw = @()
    if ($Config.panel -and $Config.panel.sections) { $raw = @($Config.panel.sections) }
    if ($raw.Count -eq 0) { $raw = @($script:ReiSectionDefaults.Keys) }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $raw) {
        $name = if ($entry -is [string]) { $entry } else { [string]$entry.name }
        $every = if ($entry -isnot [string] -and $entry.every) { [double]$entry.every }
                 elseif ($script:ReiSectionDefaults.Contains($name)) { [double]$script:ReiSectionDefaults[$name] }
                 else { 10.0 }
        $list.Add(@{ Name = $name; Every = [math]::Max(1, $every); Path = (Resolve-ReiSectionPath $name) })
    }
    $list
}

function Start-ReiSectionRun([string]$Path, $Context) {
    $ps = [powershell]::Create()
    $body = {
        param($common, $file, $ctx)
        $ErrorActionPreference = 'Continue'
        try { . $common; & $file $ctx } catch { @{ Error = $_.Exception.Message } }
    }
    [void]$ps.AddScript($body).AddArgument((Join-Path $PSScriptRoot 'common.ps1')).AddArgument($Path).AddArgument($Context)
    @{ PS = $ps; Handle = $ps.BeginInvoke(); Started = Get-Date }
}

function Stop-ReiSectionRun($Run) {
    try { [void]$Run.PS.BeginStop($null, $null) } catch { }
}

# Turns whatever the script returned into a validated result.
function ConvertTo-ReiSectionResult($Output, [string]$Name) {
    $r = $null
    foreach ($o in $Output) { if ($o -is [System.Collections.IDictionary]) { $r = $o } }
    if (-not $r) { return @{ State = 'error'; Message = 'no devolvio un hashtable con Title y Lines' } }
    if ($r.Contains('Error') -and $r.Error) { return @{ State = 'error'; Message = [string]$r.Error } }
    if ($r.Hidden -eq $true) { return @{ State = 'hidden' } }
    $lines = @($r.Lines | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    if ($lines.Count -eq 0) { return @{ State = 'hidden' } }
    $title = if ($r.Title) { [string]$r.Title } else { $Name.ToUpper() }
    @{ State = 'ok'; Title = $title; Lines = $lines }
}

# Returns the result when the run is finished (or timed out), $null while it is still running.
function Receive-ReiSectionRun($Run, [string]$Name, [double]$Timeout) {
    if ($Run.Handle.IsCompleted) {
        try { $out = $Run.PS.EndInvoke($Run.Handle) } catch { return @{ State = 'error'; Message = $_.Exception.Message } }
        $Run.PS.Dispose()
        return (ConvertTo-ReiSectionResult $out $Name)
    }
    if (((Get-Date) - $Run.Started).TotalSeconds -gt $Timeout) {
        Stop-ReiSectionRun $Run
        return @{ State = 'error'; Message = "sin respuesta en $([int]$Timeout) s" }
    }
    $null
}

# Blocking version: used by -Once, -TestSection and the first paint.
function Invoke-ReiSectionSync($Section, $Context, [double]$Timeout = $script:ReiSectionTimeout) {
    if (-not $Section.Path) { return @{ State = 'error'; Message = "no existe la seccion '$($Section.Name)'" } }
    $run = Start-ReiSectionRun $Section.Path $Context
    while ($true) {
        $res = Receive-ReiSectionRun $run $Section.Name $Timeout
        if ($res) { return $res }
        Start-Sleep -Milliseconds 40
    }
}

# Panel-side state: one entry per section, refreshed in the background.
function New-ReiSectionState($Sections) {
    $state = @{}
    foreach ($s in $Sections) { $state[$s.Name] = @{ Result = $null; LastRun = [datetime]::MinValue; Run = $null; Stale = $true } }
    $state
}

# Call every tick. Returns $true when any section got a new result (so the panel should repaint).
function Update-ReiSections($Sections, $State, [scriptblock]$NewContext, [double]$Timeout = $script:ReiSectionTimeout) {
    $changed = $false
    foreach ($s in $Sections) {
        $st = $State[$s.Name]
        if ($st.Run) {
            $res = Receive-ReiSectionRun $st.Run $s.Name $Timeout
            if ($res) { $st.Result = $res; $st.Run = $null; $st.LastRun = Get-Date; $changed = $true }
            continue
        }
        $due = $st.Stale -or (((Get-Date) - $st.LastRun).TotalSeconds -ge $s.Every)
        if (-not $due) { continue }
        $st.Stale = $false
        if (-not $s.Path) {
            $st.Result = @{ State = 'error'; Message = "no existe la seccion '$($s.Name)'" }
            $st.LastRun = Get-Date; $changed = $true
            continue
        }
        $st.Run = Start-ReiSectionRun $s.Path (& $NewContext)
    }
    $changed
}
