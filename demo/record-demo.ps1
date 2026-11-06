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
using System.Runtime.InteropServices;
public static class W {
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

# ---- smooth, visible mouse ----
function Move-Mouse([int]$x, [int]$y, [int]$ms = 700) {
  $p = New-Object W+POINT; [void][W]::GetCursorPos([ref]$p)
  $steps = [math]::Max(12, [int]($ms / 16))
  for ($i = 1; $i -le $steps; $i++) {
    $t = $i / $steps; $e = 1 - [math]::Pow(1 - $t, 3)
    [void][W]::SetCursorPos([int]($p.X + ($x - $p.X) * $e), [int]($p.Y + ($y - $p.Y) * $e))
    Start-Sleep -Milliseconds 16
  }
}
function Click-At([int]$x, [int]$y) {
  Move-Mouse $x $y
  Start-Sleep -Milliseconds 250
  [W]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 70; [W]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero)
}
function Click-El($el) {
  $r = $el.Current.BoundingRectangle
  Click-At ([int]($r.X + $r.Width / 2)) ([int]($r.Y + $r.Height / 2))
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
function Find-In($parent, [scriptblock]$match, $type = $null, [int]$timeout = 15) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeout) {
    $all = $parent.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $all) {
      try {
        if ($type -and $e.Current.ControlType -ne $type) { continue }
        if (& $match $e.Current.Name) { return $e }
      } catch { }
    }
    Start-Sleep -Milliseconds 300
  }
  throw "Element not found"
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
  $add = Find-In $pf { param($n) $n -like 'Add SEB*' } ([Windows.Automation.ControlType]::Button)
  Click-El $add
  $dlg = Find-Top { param($n) $n -like 'Add apps from Safe Exam Browser*' } 15
  Start-Sleep 1
  $edit = Find-In $dlg { param($n) $true } ([Windows.Automation.ControlType]::Edit)
  Click-El $edit
  Start-Sleep -Milliseconds 400
  foreach ($c in 'notepad.exe'.ToCharArray()) { [Windows.Forms.SendKeys]::SendWait([string]$c); Start-Sleep -Milliseconds 110 }
  Start-Sleep 1
  Shot '03-add-list'
  $save = Find-In $dlg { param($n) $n -eq 'Save' } ([Windows.Automation.ControlType]::Button)
  Click-El $save
  Start-Sleep 2.5
  Shot '04-ticked'

  # Close everything
  $close = Find-In $pf { param($n) $n -like 'Close * app*' } ([Windows.Automation.ControlType]::Button)
  Start-Sleep 1
  Click-El $close
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
}
"Recorded: $Out ($([math]::Round((Get-Item $Out).Length / 1MB, 1)) MB)"
"Still running afterwards: " + ((Get-Process | Where-Object { $_.ProcessName -in 'Discord','WhatsApp','Zoom','AnyDesk','obs64','notepad','chrome','msedge' }).ProcessName -join ', ')
