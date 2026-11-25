# Shared helpers for rei scripts (dot-sourced). Keep this file ASCII-only: Windows PowerShell 5.1
# reads BOM-less files as ANSI.

function Get-ReiConfigPath {
    if ($env:REI_CONFIG) { return $env:REI_CONFIG }
    Join-Path $PSScriptRoot '..\config\projects.json'
}

# Returns the parsed config. Throws a readable message if it is missing, invalid or incomplete.
function Read-ReiConfig {
    $path = Get-ReiConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "config not found: $path`n     Copy config\projects.example.json to config\projects.json and edit it."
    }
    try {
        $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "config is not valid JSON ($path): $($_.Exception.Message)"
    }
    if (@($config.projects).Count -eq 0) { throw "no projects in $path" }
    foreach ($p in @($config.projects)) {
        if (-not $p.name -or -not $p.path) { throw "every project needs 'name' and 'path' ($path)" }
    }
    $config
}

# Palette shared by the panel and the status line (same hex values as theme/rei.toml).
# Everything that is not neutral is a shade of red; meaning is carried by lightness and hue:
#   Ok = blush (light pink), Info = coral, Warn = vermilion, Bad = crimson, Accent = crimson, Branch = rose.
function New-ReiAnsi([string]$Hex) {
    $r = [Convert]::ToInt32($Hex.Substring(0, 2), 16); $g = [Convert]::ToInt32($Hex.Substring(2, 2), 16); $b = [Convert]::ToInt32($Hex.Substring(4, 2), 16)
    "$([char]27)[38;2;$r;$g;${b}m"
}
function Get-ReiColors {
    @{
        Reset  = "$([char]27)[0m"; Bold = "$([char]27)[1m"
        Text   = (New-ReiAnsi 'e8e4d8'); Soft = (New-ReiAnsi 'c9c5b8'); Dim = (New-ReiAnsi '7d7d85')
        Accent = (New-ReiAnsi 'e0364a'); Bad = (New-ReiAnsi 'e0364a'); Warn = (New-ReiAnsi 'e8603c')
        Info   = (New-ReiAnsi 'ee8e72'); Branch = (New-ReiAnsi 'd4577a'); Ok = (New-ReiAnsi 'f2a0ae')
    }
}
