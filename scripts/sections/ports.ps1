# Built-in section: listening ports of processes started from the project. ASCII-only.
param($ctx)
if (-not $ctx.IsDev) { return @{ Hidden = $true } }
$C = $ctx.Colors; $inner = $ctx.Width
$needle = ($ctx.Path -replace '/', '\').TrimEnd('\').ToLowerInvariant()

$found = @{}
try { $conns = @(Get-NetTCPConnection -State Listen -ErrorAction Stop) } catch { $conns = @() }
$pids = @($conns | ForEach-Object { [int]$_.OwningProcess } | Where-Object { $_ -gt 4 } | Sort-Object -Unique)
$procs = @{}
if ($pids.Count -gt 0) {
    $filter = ($pids | ForEach-Object { "ProcessId=$_" }) -join ' OR '
    foreach ($p in @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue)) {
        $procs[[int]$p.ProcessId] = @{ Name = $p.Name; Cmd = ("$($p.CommandLine)" -replace '/', '\').ToLowerInvariant() }
    }
}
foreach ($c in $conns) {
    $p = $procs[[int]$c.OwningProcess]
    if ($p -and $p.Cmd.Contains($needle)) { $found[[int]$c.LocalPort] = $p.Name -replace '\.exe$', '' }
}

$lines = @()
if ($found.Count -eq 0) { $lines = @("$($C.Dim)ninguno activo$($C.Reset)") }
else {
    $lines = @($found.GetEnumerator() | Sort-Object Name | ForEach-Object {
        "$($C.Info):$($_.Name)$($C.Reset) $($C.Dim)$(Cut $_.Value ($inner - 7))$($C.Reset)"
    })
}
@{ Title = 'PUERTOS'; Lines = $lines }
