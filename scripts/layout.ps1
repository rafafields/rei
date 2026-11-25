# Window placement helpers for rei (dot-sourced by rei.ps1). Windows only.
# Splits the primary monitor's work area: Claude Code on the left (default 3/4),
# the special panel on the right (the rest). Works in physical pixels (per-monitor DPI aware).

if (-not ('Rei.Win32' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Rei {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public static class Win32 {
        public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint param, out RECT rect, uint winIni);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int cmd);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT rect, int size);

        public static void EnableDpiAwareness() { SetProcessDpiAwarenessContext(new IntPtr(-4)); }

        public static RECT WorkArea() {
            RECT r; SystemParametersInfo(0x0030, 0, out r, 0); return r;
        }

        // First visible top-level window of the process that is bigger than 100x100 px
        // (Alacritty also creates a 22x22 helper window first), or IntPtr.Zero.
        public static IntPtr FindWindow(uint processId) {
            IntPtr found = IntPtr.Zero;
            EnumWindows((h, l) => {
                uint pid; GetWindowThreadProcessId(h, out pid);
                if (pid == processId && IsWindowVisible(h) && GetWindow(h, 4) == IntPtr.Zero) {
                    RECT r; GetWindowRect(h, out r);
                    if (r.Right - r.Left > 100 && r.Bottom - r.Top > 100) { found = h; return false; }
                }
                return true;
            }, IntPtr.Zero);
            return found;
        }

        public static RECT Visible(IntPtr h) {
            RECT vis;
            if (DwmGetWindowAttribute(h, 9, out vis, Marshal.SizeOf(typeof(RECT))) != 0) GetWindowRect(h, out vis);
            return vis;
        }

        // Places the VISIBLE frame of the window at x,y,w,h (compensates the invisible resize borders).
        public static void Place(IntPtr h, int x, int y, int w, int cx_unused, int hgt) {
            ShowWindow(h, 9); // SW_RESTORE
            SetWindowPos(h, IntPtr.Zero, x, y, w, hgt, 0x0004 | 0x0010); // NOZORDER | NOACTIVATE
            RECT win, vis; GetWindowRect(h, out win);
            if (DwmGetWindowAttribute(h, 9, out vis, Marshal.SizeOf(typeof(RECT))) != 0) return;
            int dl = vis.Left - win.Left, dt = vis.Top - win.Top;
            int dr = win.Right - vis.Right, db = win.Bottom - vis.Bottom;
            SetWindowPos(h, IntPtr.Zero, x - dl, y - dt, w + dl + dr, hgt + dt + db, 0x0004 | 0x0010);
        }
    }
}
'@
}

[Rei.Win32]::EnableDpiAwareness()

function Get-ReiSlots([double]$ClaudeRatio = 0.75) {
    $a = [Rei.Win32]::WorkArea()
    $width = $a.Right - $a.Left
    $height = $a.Bottom - $a.Top
    $left = [int][math]::Round($width * $ClaudeRatio)
    [pscustomobject]@{
        Claude = [pscustomobject]@{ X = $a.Left;         Y = $a.Top; W = $left;          H = $height }
        Panel  = [pscustomobject]@{ X = $a.Left + $left; Y = $a.Top; W = $width - $left; H = $height }
    }
}

function Wait-ReiWindow([int]$ProcessId, [int]$TimeoutSeconds = 10) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $h = [Rei.Win32]::FindWindow([uint32]$ProcessId)
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    return [IntPtr]::Zero
}

function Set-ReiWindowRect([IntPtr]$Handle, $Slot) {
    # Alacritty applies its own initial size shortly after the window appears, so place,
    # then re-check for ~2 s and place again if it moved.
    for ($i = 0; $i -lt 8; $i++) {
        [Rei.Win32]::Place($Handle, $Slot.X, $Slot.Y, $Slot.W, 0, $Slot.H)
        Start-Sleep -Milliseconds 250
        $v = [Rei.Win32]::Visible($Handle)
        $ok = [math]::Abs($v.Left - $Slot.X) -le 2 -and [math]::Abs($v.Top - $Slot.Y) -le 2 -and
              [math]::Abs(($v.Right - $v.Left) - $Slot.W) -le 2 -and [math]::Abs(($v.Bottom - $v.Top) - $Slot.H) -le 2
        if ($ok -and $i -ge 2) { return }
    }
}
