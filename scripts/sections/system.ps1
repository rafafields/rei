# Built-in section: memory and disk of the machine. Hidden with "panel": { "system": false }. ASCII-only.
param($ctx)
if (-not $ctx.ShowSystem) { return @{ Hidden = $true } }
$C = $ctx.Colors; $inner = $ctx.Width; $dir = $ctx.Path
$bw = [math]::Min(12, $inner - 18)
$lines = @()

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($os) {
    $total = [double]$os.TotalVisibleMemorySize; $free = [double]$os.FreePhysicalMemory
    $pct = [int][math]::Round(100 * ($total - $free) / $total)
    $col = if ($pct -ge 90) { $C.Bad } elseif ($pct -ge 75) { $C.Warn } else { $C.Ok }
    $lines += "$($C.Dim)memoria     $(Format-ReiBar $pct $bw $col $ctx.BarChar) $col$pct%$($C.Reset)"
}
$letter = if ($dir -match '^([A-Za-z]):') { $Matches[1] } else { $env:SystemDrive.TrimEnd(':') }
$d = Get-PSDrive -Name $letter -ErrorAction SilentlyContinue
if ($d -and ($d.Used + $d.Free) -gt 0) {
    $pct = [int][math]::Round(100 * $d.Used / ($d.Used + $d.Free))
    $col = if ($pct -ge 95) { $C.Bad } elseif ($pct -ge 85) { $C.Warn } else { $C.Ok }
    $lines += "$($C.Dim)disco $($letter.ToUpper()):    $(Format-ReiBar $pct $bw $col $ctx.BarChar) $col$pct%$($C.Reset)"
}
@{ Title = 'WINDOWS'; Lines = $lines }
