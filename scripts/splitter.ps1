<#
.SYNOPSIS
  Rei divider: a thin draggable strip between the Claude Code window and the panel window.

.DESCRIPTION
  Started by rei.ps1 once both windows exist. Dragging the strip resizes both windows at the same
  time. The strip follows the windows (if you move or resize one by hand it stays in the gap
  between them), hides while either is minimized, and exits when either one is closed.
  It never takes the keyboard focus. ASCII-only file (Windows PowerShell 5.1).

.EXAMPLE
  splitter.ps1 -Left 123456 -Right 654321 -Gap 10      # window handles as integers
#>
param(
    [Parameter(Mandatory = $true)][long]$Left,
    [Parameter(Mandatory = $true)][long]$Right,
    [int]$Gap = 10,
    [double]$MinRatio = 0.3,
    [double]$MaxRatio = 0.9,
    [string]$SelfTest = ''     # testing: path of a log file; resizes to a few positions, writes the rects, exits
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'layout.ps1')     # Win32 helpers; also switches the process to DPI-aware
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

if (-not ('Rei.SplitterForm' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -Language CSharp -TypeDefinition @'
using System;
using System.Windows.Forms;
namespace Rei {
    // Tool window (no taskbar or Alt+Tab entry) that never activates, so Claude keeps the focus.
    public class SplitterForm : Form {
        public SplitterForm() { DoubleBuffered = true; }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80 | 0x08000000; return cp; }
        }
    }
}
'@
}

$hl = [IntPtr]$Left
$hr = [IntPtr]$Right
$script:shown = $false
$script:hot = $false
$script:drag = $false
$script:lastMove = 0

$bgColor = [System.Drawing.ColorTranslator]::FromHtml('#0a0a0b')
$idleColor = [System.Drawing.ColorTranslator]::FromHtml('#8c2433')
$hotColor = [System.Drawing.ColorTranslator]::FromHtml('#ff5468')

$form = New-Object Rei.SplitterForm
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.BackColor = $bgColor
$form.Cursor = [System.Windows.Forms.Cursors]::SizeWE

# Keeps the strip in the gap between the two windows.
function Sync-Divider {
    if (-not ([Rei.Win32]::Exists($hl) -and [Rei.Win32]::Exists($hr))) { $form.Close(); return }
    if ([Rei.Win32]::Minimized($hl) -or [Rei.Win32]::Minimized($hr)) {
        if ($script:shown -and $form.Visible) { $form.Hide() }
        return
    }
    $l = [Rei.Win32]::Visible($hl); $r = [Rei.Win32]::Visible($hr)
    $x = $l.Right; $w = $r.Left - $l.Right
    if ($w -lt 4 -or $w -gt 60) { $w = $Gap }      # windows overlap or are far apart: sit on the left one's edge
    $top = $l.Top; $h = $l.Bottom - $l.Top
    if ($form.Left -ne $x -or $form.Top -ne $top -or $form.Width -ne $w -or $form.Height -ne $h) { $form.SetBounds($x, $top, $w, $h) }
    if ($script:shown -and -not $form.Visible) { $form.Show() }
}

# Puts the divider centre at screen x and resizes both windows around it.
function Move-Divider([int]$X) {
    $l = [Rei.Win32]::Visible($hl); $r = [Rei.Win32]::Visible($hr)
    $spanL = $l.Left; $spanR = $r.Right; $total = $spanR - $spanL
    if ($total -lt 400) { return }
    $half = [int][math]::Floor($Gap / 2); $rest = $Gap - $half
    $cx = [math]::Min($spanL + [int]($total * $MaxRatio), [math]::Max($spanL + [int]($total * $MinRatio), $X))
    $top = $l.Top; $h = $l.Bottom - $l.Top
    [Rei.Win32]::Place($hl, $spanL, $top, ($cx - $half) - $spanL, 0, $h)
    [Rei.Win32]::Place($hr, $cx + $rest, $top, $spanR - ($cx + $rest), 0, $h)
    $form.SetBounds($cx - $half, $top, $Gap, $h)
}

$form.Add_Paint({
    $g = $args[1].Graphics
    $color = if ($script:hot -or $script:drag) { $hotColor } else { $idleColor }
    $brush = New-Object System.Drawing.SolidBrush $color
    $w = $form.ClientSize.Width; $h = $form.ClientSize.Height
    $g.FillRectangle($brush, [int](($w - 2) / 2), 0, 2, $h)                       # the line
    $grip = [math]::Min(48, $h)
    $g.FillRectangle($brush, [int](($w - 4) / 2), [int](($h - $grip) / 2), 4, $grip)   # the handle
    $brush.Dispose()
})
$form.Add_MouseEnter({ $script:hot = $true; $form.Invalidate() })
$form.Add_MouseLeave({ $script:hot = $false; $form.Invalidate() })
$form.Add_MouseDown({ if ($args[1].Button -eq 'Left') { $script:drag = $true; $form.Invalidate() } })
$form.Add_MouseUp({ $script:drag = $false; $form.Invalidate() })
$form.Add_MouseMove({
    if (-not $script:drag) { return }
    $now = [Environment]::TickCount
    if ($now - $script:lastMove -lt 30) { return }      # about 30 resizes per second is plenty
    $script:lastMove = $now
    try { Move-Divider ([System.Windows.Forms.Control]::MousePosition.X) } catch { }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({ if (-not $script:drag) { try { Sync-Divider } catch { } } })

$form.Add_Shown({
    $script:shown = $true
    $timer.Start()
    if ($SelfTest) {
        $log = New-Object System.Collections.Generic.List[string]
        $l0 = [Rei.Win32]::Visible($hl); $r0 = [Rei.Win32]::Visible($hr)
        $span = $r0.Right - $l0.Left
        foreach ($frac in 0.5, 0.8, 0.1, 0.99) {
            Move-Divider ($l0.Left + [int]($span * $frac))
            Start-Sleep -Milliseconds 400
            Sync-Divider
            $l = [Rei.Win32]::Visible($hl); $r = [Rei.Win32]::Visible($hr)
            $log.Add(('frac={0} left={1}-{2} divider={3}-{4} right={5}-{6} ratio={7:N3}' -f $frac, $l.Left, $l.Right, $form.Left, ($form.Left + $form.Width), $r.Left, $r.Right, (($l.Right - $l0.Left) / $span)))
        }
        [System.IO.File]::WriteAllLines($SelfTest, $log)
        $form.Close()
    }
})

Sync-Divider
[System.Windows.Forms.Application]::Run($form)
