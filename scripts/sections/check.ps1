# Built-in section: result of the project's check. Only visible while it runs or after it fails.
# The panel owns the check (key c) and hands its state in $ctx.CheckState. ASCII-only.
param($ctx)
$C = $ctx.Colors; $inner = $ctx.Width; $st = $ctx.CheckState
if (-not $st -or ($st.State -ne 'running' -and $st.State -ne 'fail')) { return @{ Hidden = $true } }
if ($st.State -eq 'running') { return @{ Title = 'CHECK'; Lines = @("$($C.Warn)ejecutando...$($C.Reset)") } }
@{ Title = 'CHECK'; Lines = @(
    "$($C.Bad)FALLA$($C.Reset) $($C.Dim)codigo $($st.Code), $(Format-Ago $st.At)$($C.Reset)",
    "$($C.Dim)$(Cut $ctx.CheckCommand $inner)$($C.Reset)"
) }
