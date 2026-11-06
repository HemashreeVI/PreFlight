# Records a real demo of PreFlight on a Windows desktop.
# Used by .github/workflows/demo.yml. It opens apps, starts PreFlight, moves the real mouse
# to click its buttons, and records the screen with ffmpeg.
param([string]$Out = "demo-raw.mp4", [string]$Shots = "shots")

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $Shots | Out-Null
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing

Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr p);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static List<IntPtr> Children(IntPtr parent) {
    var l = new List<IntPtr>();
    EnumChildWindows(parent, (h, p) => { l.Add(h); return true; }, IntPtr.Zero);
    return l;
  }
  public static string Text(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
  public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll")] public static extern bool EnumDisplaySettings(string d, int m, ref DEVMODE dm);
  [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE dm, int f);
  public static int SetRes(int w, int h) {
    DEVMODE dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (!EnumDisplaySettings(null, -1, ref dm)) return -99;
    dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x80000 | 0x100000;
    return ChangeDisplaySettings(ref dm, 0);
  }
}
'@
[W]::SetProcessDPIAware() | Out-Null
"Set resolution: " + [W]::SetRes(1600, 900)
Start-Sleep 2
$scr = [Windows.Forms.Screen]::PrimaryScreen.Bounds
"Screen: $($scr.Width)x$($scr.Height)"

function Shot($name) {
  try {
    $b = New-Object Drawing.Bitmap($scr.Width, $scr.Height)
    $g = [Drawing.Graphics]::FromImage($b); $g.CopyFromScreen(0, 0, 0, 0, $b.Size)
    $b.Save((Join-Path $Shots "$name.png")); $g.Dispose(); $b.Dispose()
  } catch { "shot failed: $_" }
}

# ---- pointer ----
# Cloud Windows machines have no mouse, so the pointer isn't drawn and synthetic clicks don't land.
# We press controls with window messages and log every pointer move; the pointer is drawn onto
# the video afterwards from this log (demo/events.csv), at the exact positions and times used here.
$Clock = [Diagnostics.Stopwatch]::new()
$Events = New-Object System.Collections.ArrayList
$script:cx = [int]($scr.Width / 2); $script:cy = [int]($scr.Height / 2)
function Log-Event($type, $x0, $y0, $x1, $y1, $ms) { [void]$Events.Add(('{0:F3},{1},{2},{3},{4},{5},{6}' -f ($Clock.Elapsed.TotalSeconds), $type, $x0, $y0, $x1, $y1, $ms)) }
function Move-Mouse([int]$x, [int]$y, [int]$ms = 700) {
  Log-Event 'move' $script:cx $script:cy $x $y $ms
  try { [void][W]::SetCursorPos($x, $y) } catch { }
  Start-Sleep -Milliseconds $ms
  $script:cx = $x; $script:cy = $y
}
function Click-At([int]$x, [int]$y) {
  Move-Mouse $x $y
  Start-Sleep -Milliseconds 250
  Log-Event 'click' $x $y $x $y 0
}

# ---- UI Automation helpers ----
$UIA = [Windows.Automation.AutomationElement]
function Find-Top([scriptblock]$match, [int]$timeout = 40) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeout) {
    $all = $UIA::RootElement.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $all) { try { if (& $match $w.Current.Name) { return $w } } catch { } }
    Start-Sleep -Milliseconds 300
  }
  throw "Window not found"
}
function Find-Ctl([IntPtr]$parent, [scriptblock]$match, [string]$cls = '', [int]$timeout = 15) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeout) {
    foreach ($h in [W]::Children($parent)) {
      if (-not [W]::IsWindowVisible($h)) { continue }
      if ($cls -and ([W]::Cls($h) -notmatch $cls)) { continue }
      if (& $match ([W]::Text($h))) { return $h }
    }
    Start-Sleep -Milliseconds 300
  }
  "Controls seen:"; foreach ($h in [W]::Children($parent)) { "  [$([W]::Cls($h))] '$([W]::Text($h))'" }
  throw "Control not found"
}
function Click-H([IntPtr]$h) {
  $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
  Click-At ([int](($r.Left + $r.Right) / 2)) ([int](($r.Top + $r.Bottom) / 2))
  [void][W]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)   # BM_CLICK
}
function Find-TopByTitle([string]$title, [int]$timeout = 15) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeout) {
    $h = [W]::FindWindow([NullString]::Value, $title); if ($h -ne [IntPtr]::Zero) { return $h }
    Start-Sleep -Milliseconds 200
  }
  throw "Window '$title' not found"
}

# ---- stand-in apps (copies of Notepad named like the real ones) + real browsers ----
$fake = Join-Path $env:TEMP 'pf-apps'
New-Item -ItemType Directory -Force -Path $fake, "$fake\en-US" | Out-Null
$np = "$env:WINDIR\System32\notepad.exe"
$mui = "$env:WINDIR\System32\en-US\notepad.exe.mui"
$apps = @(
  @{ exe = 'Discord';  file = 'Discord - study group' },
  @{ exe = 'WhatsApp'; file = 'WhatsApp - family' },
  @{ exe = 'Zoom';     file = 'Zoom - meeting' },
  @{ exe = 'AnyDesk';  file = 'AnyDesk - remote session' },
  @{ exe = 'obs64';    file = 'OBS Studio - recording' }
)
$x = 40; $y = 40
foreach ($a in $apps) {
  Copy-Item $np "$fake\$($a.exe).exe" -Force
  if (Test-Path $mui) { Copy-Item $mui "$fake\en-US\$($a.exe).exe.mui" -Force }
  $txt = "$fake\$($a.file).txt"; Set-Content $txt "Running in the background..."
  $p = Start-Process "$fake\$($a.exe).exe" -ArgumentList "`"$txt`"" -PassThru
  Start-Sleep -Milliseconds 900
  try { $p.Refresh(); [void][W]::MoveWindow($p.MainWindowHandle, $x, $y, 620, 380, $true) } catch { }
  $x += 150; $y += 70
}
# A notes file in real Notepad: something SEB may list that PreFlight doesn't know about.
$notes = "$fake\exam notes.txt"; Set-Content $notes "Remember: close everything before the test."
$np1 = Start-Process notepad.exe -ArgumentList "`"$notes`"" -PassThru
Start-Sleep 1; try { $np1.Refresh(); [void][W]::MoveWindow($np1.MainWindowHandle, 900, 420, 600, 360, $true) } catch { }

$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($chrome) { Start-Process $chrome -ArgumentList '--no-first-run --no-default-browser-check --window-position=760,60 --window-size=800,560 https://example.com' }
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($edge) { Start-Process $edge -ArgumentList '--no-first-run --no-default-browser-check --window-position=500,300 --window-size=800,520 https://example.org' }
Start-Sleep 6

# Minimise leftover console windows from the build machine so the desktop is clean.
Get-Process | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.ProcessName -match '^(conhost|cmd|powershell|pwsh|WindowsTerminal|OpenConsole)$' } | ForEach-Object { [void][W]::ShowWindow($_.MainWindowHandle, 6) }

# ---- start recording ----
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { throw "ffmpeg not found" }
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $ffmpeg
$psi.Arguments = "-y -f gdigrab -framerate 30 -draw_mouse 1 -i desktop -t 150 -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p `"$Out`""
$psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.CreateNoWindow = $true
$rec = [Diagnostics.Process]::Start($psi)
$Clock.Start()
Start-Sleep 2
Shot '01-cluttered'

try {
  # Show the clutter: wander over the open apps
  Move-Mouse 300 200 900; Start-Sleep 1
  Move-Mouse 900 420 900; Start-Sleep 1
  Move-Mouse 1200 700 900; Start-Sleep 1

  # Launch PreFlight the way a user does: the launcher .bat
  Start-Process "$Root\PreFlight.bat" -WorkingDirectory $Root
  $pf = Find-Top { param($n) $n -eq 'PreFlight' } 60
  try {
    $h = [IntPtr]$pf.Current.NativeWindowHandle; $r = $pf.Current.BoundingRectangle
    [void][W]::MoveWindow($h, [int](($scr.Width - $r.Width) / 2), [int](($scr.Height - $r.Height) / 2 - 20), [int]$r.Width, [int]$r.Height, $true)
    [void][W]::SetForegroundWindow($h)
  } catch { }
  Start-Sleep 3
  Shot '02-preflight'

  # Scan the ticked list
  $wr = $pf.Current.BoundingRectangle
  Move-Mouse ([int]($wr.X + 170)) ([int]($wr.Y + 190)) 900; Start-Sleep 1
  Move-Mouse ([int]($wr.X + 170)) ([int]($wr.Y + $wr.Height - 190)) 1600; Start-Sleep 1.5

  # Teach it something from SEB's list: Notepad
  $pfh = [IntPtr]$pf.Current.NativeWindowHandle
  $add = Find-Ctl $pfh { param($n) $n -like 'Add SEB*' } 'BUTTON'
  Click-H $add
  $dlgh = Find-TopByTitle "Add apps from Safe Exam Browser's list"
  Start-Sleep 1
  $edit = Find-Ctl $dlgh { param($n) $true } 'EDIT'
  $er = New-Object W+RECT; [void][W]::GetWindowRect($edit, [ref]$er)
  Click-At ([int]($er.Left + 60)) ([int]($er.Top + 20))
  Start-Sleep -Milliseconds 400
  $typed = ''
  foreach ($c in 'notepad.exe'.ToCharArray()) { $typed += $c; [void][W]::SendMessage($edit, 0x000C, [IntPtr]::Zero, $typed); Start-Sleep -Milliseconds 120 }
  Start-Sleep 1
  Shot '03-add-list'
  $save = Find-Ctl $dlgh { param($n) $n -eq 'Save' } 'BUTTON'
  Click-H $save
  Start-Sleep 2.5
  Shot '04-ticked'

  # Close everything
  $close = Find-Ctl $pfh { param($n) $n -like 'Close * app*' } 'BUTTON'
  Start-Sleep 1
  Click-H $close
  Start-Sleep 9
  Shot '05-done'

  # Show the cleared desktop with PreFlight's result
  $st = $pf.Current.BoundingRectangle
  Move-Mouse ([int]($st.X + 200)) ([int]($st.Y + $st.Height - 110)) 900
  Start-Sleep 4
} finally {
  try { $rec.StandardInput.Write('q'); $rec.StandardInput.Close() } catch { }
  if (-not $rec.WaitForExit(20000)) { try { $rec.Kill() } catch { } }
  Shot '06-end'
  Set-Content (Join-Path $Shots 'events.csv') (@('t,type,x0,y0,x1,y1,ms') + $Events)
}
"Recorded: $Out ($([math]::Round((Get-Item $Out).Length / 1MB, 1)) MB)"
"Still running afterwards: " + ((Get-Process | Where-Object { $_.ProcessName -in 'Discord','WhatsApp','Zoom','AnyDesk','obs64','notepad','chrome','msedge' }).ProcessName -join ', ')
