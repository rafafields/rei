# Built-in section: git state of the project. ASCII-only.
param($ctx)
$C = $ctx.Colors; $inner = $ctx.Width; $dir = $ctx.Path
$lines = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    return @{ Title = 'GIT'; Lines = @("$($C.Bad)$(Cut 'el directorio no existe' $inner)$($C.Reset)") }
}
$out = & git -C $dir status --porcelain=v2 --branch 2>$null
if ($LASTEXITCODE -ne 0) {
    return @{ Title = 'GIT'; Lines = @("$($C.Dim)$(Cut 'no es un repo git' $inner)$($C.Reset)") }
}

$git = @{ Branch = '?'; Ahead = 0; Behind = 0; Upstream = $false; New = 0; Modified = 0; Deleted = 0; Conflicts = 0 }
foreach ($line in $out) {
    if ($line -like '# branch.head *') { $git.Branch = $line.Substring(14) }
    elseif ($line -like '# branch.ab *') {
        $git.Upstream = $true
        if ($line -match '\+(\d+) -(\d+)') { $git.Ahead = [int]$Matches[1]; $git.Behind = [int]$Matches[2] }
    }
    elseif ($line.StartsWith('? ')) { $git.New++ }
    elseif ($line.StartsWith('u ')) { $git.Conflicts++ }
    elseif ($line -match '^[12] (.)(.)') {
        # one file counts once: deleted wins over new, new wins over modified
        if ($Matches[1] -eq 'D' -or $Matches[2] -eq 'D') { $git.Deleted++ }
        elseif ($Matches[1] -eq 'A') { $git.New++ }
        else { $git.Modified++ }
    }
}

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

$last = & git -C $dir log -1 --format='%h%x09%cI%x09%s' 2>$null
if ($LASTEXITCODE -eq 0 -and $last) {
    $parts = $last -split "`t", 3
    $when = [datetime]::Parse($parts[1])
    # the conventional-commit type ("docs:", "feat(x):") is noise in a narrow column
    $subject = $parts[2] -replace '^[A-Za-z]+([(][^)]*[)])?!?:[ ]*', ''
    $lines.Add("$($C.Dim)ultimo      $($C.Text)$($parts[0]) $($C.Dim)$(Format-Ago $when)$($C.Reset)")
    $lines.Add("$($C.Text)$(Cut $subject $inner)$($C.Reset)")
}
@{ Title = 'GIT'; Lines = $lines.ToArray() }
