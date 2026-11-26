<#
.SYNOPSIS
  Adds the `rei` function to your PowerShell profile (idempotent).
  `rei -Config` is handled by the function itself so it can change your current directory.
#>
$ErrorActionPreference = 'Stop'
$script = (Resolve-Path (Join-Path $PSScriptRoot 'rei.ps1')).Path
$begin = '# >>> rei >>>'
$end = '# <<< rei <<<'
$root = Split-Path -Parent (Split-Path -Parent $script)
$q = { param($t) $t -replace "'", "''" }
$block = @"
$begin
function rei {
    if (`$args.Count -eq 1 -and `$args[0] -eq '-Config') { Set-Location -LiteralPath '$(& $q $root)'; return }
    & '$(& $q $script)' @args
}
$end
"@
if (-not (Test-Path -LiteralPath $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
$current = Get-Content -LiteralPath $PROFILE -Raw
if ($null -eq $current) { $current = '' }
$pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
if ($current -match $pattern) {
    $new = [regex]::Replace($current, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
    Write-Host "rei: profile block updated ($PROFILE)"
} else {
    $new = $current.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
    Write-Host "rei: function added to $PROFILE"
}
Set-Content -LiteralPath $PROFILE -Value $new -Encoding UTF8
