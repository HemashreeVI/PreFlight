<#
  PreFlight - close the apps Safe Exam Browser asks you to quit, in one click.

  How it works
  - Lists apps running in YOUR Windows session, grouped by type.
  - Apps that exam browsers usually block are ticked for you.
  - Apps you add from SEB's list are remembered and always ticked.
  - Windows itself, drivers, security software and SEB are never listed.
  - Closing is gentle first (apps can ask to save), then forced.

  Works on Windows 10 and 11 with the built-in Windows PowerShell 5.1. Nothing to install.
#>

param([switch]$Elevated)

$ErrorActionPreference = 'Stop'
$AppName = 'PreFlight'
if ($env:APPDATA) { $SettingsDir = Join-Path $env:APPDATA $AppName } else { $SettingsDir = Join-Path $HOME ".$AppName" }
$SettingsFile = Join-Path $SettingsDir 'settings.json'

# ---------------------------------------------------------------------------
# Known apps. Keys are process names in lower case, without ".exe".
# ---------------------------------------------------------------------------
$Categories = [ordered]@{
  'Chat and calls'          = @{ Tick = $true;  Apps = @{
      discord='Discord'; discordptb='Discord PTB'; discordcanary='Discord Canary'; teams='Microsoft Teams (classic)'; 'ms-teams'='Microsoft Teams'; msteams='Microsoft Teams'
      slack='Slack'; zoom='Zoom'; skype='Skype'; whatsapp='WhatsApp'; telegram='Telegram'; signal='Signal'
      ciscowebexstart='Webex'; webexmta='Webex'; ciscocollabhost='Webex'; webex='Webex'; viber='Viber'; messenger='Messenger'; element='Element'; lync='Skype for Business'
      phoneexperiencehost='Phone Link'; yourphone='Phone Link'; googlemeet='Google Meet'; gotomeeting='GoTo Meeting'; g2mcomm='GoTo Meeting' } }
  'Screen capture and recording' = @{ Tick = $true; Apps = @{
      obs64='OBS Studio'; obs32='OBS Studio'; obs='OBS Studio'; sharex='ShareX'; lightshot='Lightshot'; snippingtool='Snipping Tool'; screenclippinghost='Snipping Tool'
      screensketch='Snip & Sketch'; bandicam='Bandicam'; bdcam='Bandicam'; camtasia='Camtasia'; camrecorder='Camtasia Recorder'; camstudio='CamStudio'
      flashbackrecorder='FlashBack'; greenshot='Greenshot'; snagit32='Snagit'; snagiteditor='Snagit'; snagitcapture='Snagit'; loom='Loom'; screenrec='ScreenRec'; apowerrec='ApowerREC'
      fraps='Fraps'; gamebar='Xbox Game Bar'; gamebarftserver='Xbox Game Bar'; 'nvidia share'='NVIDIA overlay'; 'nvidia overlay'='NVIDIA overlay'
      radeonsoftware='AMD Radeon overlay'; picpick='PicPick'; flameshot='Flameshot'; screenpresso='Screenpresso'; icecreamscreenrecorder='Icecream Screen Recorder' } }
  'Remote access'           = @{ Tick = $true;  Apps = @{
      teamviewer='TeamViewer'; anydesk='AnyDesk'; remoting_host='Chrome Remote Desktop'; rustdesk='RustDesk'; parsecd='Parsec'; ultraviewer_desktop='UltraViewer'; ultraviewer='UltraViewer'
      supremo='Supremo'; splashtopstreamer='Splashtop'; srstreamer='Splashtop'; mstsc='Remote Desktop'; vncviewer='VNC Viewer'; vncserver='VNC Server'; winvnc='VNC'; tvnserver='TightVNC'
      quickassist='Quick Assist'; zohoassist='Zoho Assist'; ammyy_admin='Ammyy Admin'; logmein='LogMeIn' } }
  'Other browsers'          = @{ Tick = $true;  Apps = @{
      chrome='Google Chrome'; msedge='Microsoft Edge'; firefox='Firefox'; brave='Brave'; opera='Opera'; opera_gx='Opera GX'; vivaldi='Vivaldi'; iexplore='Internet Explorer'
      arc='Arc'; yandex='Yandex Browser'; waterfox='Waterfox'; librewolf='LibreWolf'; tor='Tor Browser'; chromium='Chromium' } }
  'AI assistants and helpers' = @{ Tick = $true; Apps = @{
      chatgpt='ChatGPT'; claude='Claude'; copilot='Microsoft Copilot'; 'microsoft.copilot'='Microsoft Copilot'; perplexity='Perplexity'; grammarly='Grammarly'; 'grammarly.desktop'='Grammarly'
      gemini='Gemini'; notion='Notion'; 'notion calendar'='Notion Calendar'; obsidian='Obsidian'; onenote='OneNote'; ditto='Ditto clipboard'; clipclip='ClipClip'
      autohotkey='AutoHotkey'; autohotkey64='AutoHotkey'; autohotkeyu64='AutoHotkey'; autohotkeyux='AutoHotkey'; powertoys='PowerToys'; 'powertoys.powerlauncher'='PowerToys Run' } }
  'Virtual cameras and audio' = @{ Tick = $true; Apps = @{
      manycam='ManyCam'; 'xsplit.core'='XSplit'; xsplitbroadcaster='XSplit'; snapcamera='Snap Camera'; voicemod='Voicemod'; 'nvidia broadcast'='NVIDIA Broadcast'
      obsvirtualcam='OBS Virtual Camera'; droidcamapp='DroidCam'; epoccam='EpocCam'; iriun='Iriun Webcam'; camo='Camo' } }
}

# Never listed, never closed. Windows, drivers, security software, the exam browser, and this tool.
$Protected = @(
  'idle','system','registry','smss','csrss','wininit','winlogon','services','lsass','lsaiso','svchost','dwm','explorer','fontdrvhost','sihost','taskhostw',
  'ctfmon','runtimebroker','searchhost','searchapp','searchui','searchindexer','startmenuexperiencehost','shellexperiencehost','textinputhost','applicationframehost',
  'systemsettings','systemsettingsbroker','securityhealthsystray','securityhealthservice','securityhealthhost','msmpeng','nissrv','mpdefendercoreservice','smartscreen',
  'audiodg','conhost','dllhost','wmiprvse','spoolsv','lockapp','logonui','userinit','useroobebroker','memory compression','wudfhost','wlanext','dashost','sgrmbroker',
  'aggregatorhost','backgroundtaskhost','widgets','widgetservice','crossdeviceresume','gamingservices','gameinputsvc','nvcontainer','nvdisplay.container','igfxem',
  'igfxhk','igfxtray','igfxext','rtkaudservice64','rtkaudiouniversalservice','realtekaudioservice','atiesrxx','atieclxx','amdrsserv','dax3api','waasmedicagent',
  'tabtip','inputpersonalization','windowsinternal.composableshell.experiences.textinput.inputapp','securityhealthui','msedgewebview2','openconsole','windowsterminal',
  'powershell','pwsh','powershell_ise','cmd','safeexambrowser','safeexambrowser.client','safeexambrowser.service','safeexambrowser.configuration','safeexambrowser.runtime',
  'preflight','onedrive','filecoauth','avp','avgui','avastui','avastsvc','mbam','mbamtray','nortonsecurity','ns','mcuicnt','bdagent','vsserv','sophosui','eset','egui','ekrn',
  'unsecapp','compattelrunner','mousocoreworker','tiworker','trustedinstaller','msiexec','consent','phonelink.backgroundtask'
)

# ---------------------------------------------------------------------------
# Settings: apps the user always wants closed, apps they never want listed.
# ---------------------------------------------------------------------------
function Get-Settings {
  $s = @{ Always = @(); Never = @() }
  if (Test-Path $SettingsFile) {
    try {
      $j = Get-Content $SettingsFile -Raw | ConvertFrom-Json
      if ($j.Always) { $s.Always = @($j.Always | ForEach-Object { "$_".ToLower() }) }
      if ($j.Never)  { $s.Never  = @($j.Never  | ForEach-Object { "$_".ToLower() }) }
    } catch { }
  }
  return $s
}
function Save-Settings($s) {
  if (-not (Test-Path $SettingsDir)) { New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null }
  [pscustomobject]@{ Always = @($s.Always | Sort-Object -Unique); Never = @($s.Never | Sort-Object -Unique) } |
    ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8
}

# Turn "Discord.exe, Teams.exe" (or one per line) into clean process names.
function ConvertTo-ProcessNames([string]$text) {
  return @($text -split '[,;\r\n]+' | ForEach-Object { $_.Trim().Trim('"').ToLower() -replace '\.exe$','' } | Where-Object { $_ } | Sort-Object -Unique)
}

# ---------------------------------------------------------------------------
# Scan: one row per app (all instances of a process name together).
# ---------------------------------------------------------------------------
function Get-AppGroups {
  $settings = Get-Settings
  $mySession = (Get-Process -Id $PID).SessionId
  $known = @{}
  foreach ($cat in $Categories.Keys) { foreach ($k in $Categories[$cat].Apps.Keys) { $known[$k] = $cat } }

  $byName = @{}
  foreach ($p in Get-Process) {
    try {
      if ($p.Id -eq $PID -or $p.Id -le 4) { continue }
      if ($p.SessionId -ne $mySession) { continue }          # services and other users
      $n = $p.ProcessName.ToLower()
      if ($Protected -contains $n) { continue }
      if ($settings.Never -contains $n) { continue }
      if (-not $byName.ContainsKey($n)) { $byName[$n] = New-Object System.Collections.ArrayList }
      [void]$byName[$n].Add($p)
    } catch { }
  }

  $groups = New-Object System.Collections.ArrayList
  foreach ($n in $byName.Keys) {
    $procs = $byName[$n]
    $hasWindow = $false; $title = ''; $desc = ''
    $mem = 0
    foreach ($p in $procs) {
      try { $mem += $p.WorkingSet64 } catch { }
      try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hasWindow = $true; if (-not $title) { $title = $p.MainWindowTitle } } } catch { }
      if (-not $desc) { try { $desc = $p.Description } catch { } }
    }

    $cat = $null; $label = $null; $tick = $false
    if ($settings.Always -contains $n) {
      $cat = 'Your list (from Safe Exam Browser)'; $tick = $true
      if ($known.ContainsKey($n)) { $label = $Categories[$known[$n]].Apps[$n] }
    } elseif ($known.ContainsKey($n)) {
      $cat = $known[$n]; $label = $Categories[$cat].Apps[$n]; $tick = [bool]$Categories[$cat].Tick
    } elseif ($hasWindow) {
      $cat = 'Other open apps'
    } else {
      continue   # background helpers without a window: leave them alone unless the user adds them
    }
    if (-not $label) { if ($desc) { $label = $desc } elseif ($title) { $label = $title } else { $label = $procs[0].ProcessName } }

    [void]$groups.Add([pscustomobject]@{
      Name = $n; Label = $label; Category = $cat; Tick = $tick; Instances = $procs.Count
      MemoryMB = [math]::Round($mem / 1MB); HasWindow = $hasWindow
    })
  }

  $order = @('Your list (from Safe Exam Browser)') + @($Categories.Keys) + @('Other open apps')
  return @($groups | Sort-Object @{ Expression = { $order.IndexOf($_.Category) } }, Label)
}

# ---------------------------------------------------------------------------
# Close: gently first (WM_CLOSE to the main window so apps can ask to save),
# then force whatever is still running. Returns names that could not be closed.
# ---------------------------------------------------------------------------
function Close-Apps([string[]]$names, [bool]$gentle = $true, [int]$waitMs = 3500, [scriptblock]$pump = $null) {
  $targets = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName.ToLower() -and $_.Id -ne $PID })
  if ($gentle) {
    foreach ($p in $targets) { try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } } catch { } }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $waitMs) {
      $alive = @($targets | Where-Object { try { -not $_.HasExited } catch { $false } })
      if ($alive.Count -eq 0) { break }
      if ($pump) { & $pump }
      Start-Sleep -Milliseconds 150
    }
  }
  $failed = New-Object System.Collections.ArrayList
  $denied = $false
  foreach ($p in $targets) {
    try {
      if (-not $p.HasExited) { $p.Kill() }
    } catch {
      try { if (-not $p.HasExited) { if (-not ($failed -contains $p.ProcessName)) { [void]$failed.Add($p.ProcessName) }; if ("$_" -match 'denied') { $denied = $true } } } catch { }
    }
  }
  Start-Sleep -Milliseconds 300
  # Apps that respawn a helper (e.g. Teams, Discord) sometimes need a second pass.
  foreach ($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName.ToLower() -and $_.Id -ne $PID })) {
    try { $p.Kill() } catch { if (-not ($failed -contains $p.ProcessName)) { [void]$failed.Add($p.ProcessName) }; if ("$_" -match 'denied') { $denied = $true } }
  }
  return [pscustomobject]@{ Failed = @($failed); AccessDenied = $denied }
}

function Find-SEB {
  $paths = @(
    "$env:ProgramFiles\SafeExamBrowser\Application\SafeExamBrowser.exe",
    "${env:ProgramFiles(x86)}\SafeExamBrowser\Application\SafeExamBrowser.exe",
    "$env:ProgramFiles\SafeExamBrowser\SafeExamBrowser.exe",
    "${env:ProgramFiles(x86)}\SafeExamBrowser\SafeExamBrowser.exe"
  )
  foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $p } }
  return $null
}

# Test hook: dot-source with $env:PREFLIGHT_NOGUI=1 to use the functions without the window.
if ($env:PREFLIGHT_NOGUI -eq '1') { return }

# ===========================================================================
# Window
# ===========================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Add-Type -Name Dpi -Namespace PreFlight -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' ; [PreFlight.Dpi]::SetProcessDPIAware() | Out-Null } catch { }
try { Add-Type -Name Con -Namespace PreFlight -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);'; [PreFlight.Con]::ShowWindow([PreFlight.Con]::GetConsoleWindow(), 0) | Out-Null } catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$Ink    = [Drawing.Color]::FromArgb(25, 28, 58)
$Muted  = [Drawing.Color]::FromArgb(93, 97, 128)
$Paper  = [Drawing.Color]::FromArgb(246, 247, 250)
$Blue   = [Drawing.Color]::FromArgb(59, 91, 219)
$Green  = [Drawing.Color]::FromArgb(46, 125, 50)
$Red    = [Drawing.Color]::FromArgb(200, 50, 60)
$Base   = New-Object Drawing.Font('Segoe UI', 10)
$Bold   = New-Object Drawing.Font('Segoe UI Semibold', 10)
$Title  = New-Object Drawing.Font('Segoe UI Semibold', 17)

$form = New-Object Windows.Forms.Form
$form.Text = 'PreFlight'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size(760, 660)
$form.MinimumSize = New-Object Drawing.Size(760, 480)
$form.BackColor = [Drawing.Color]::White
$form.Font = $Base
$form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
$form.AutoScaleMode = 'Dpi'
$form.KeyPreview = $true

# Header
$header = New-Object Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = 92; $header.BackColor = $Paper; $header.Padding = New-Object Windows.Forms.Padding(22, 16, 22, 10)
$h1 = New-Object Windows.Forms.Label
$h1.Text = 'Close apps before your exam'; $h1.Font = $Title; $h1.ForeColor = $Ink; $h1.AutoSize = $true; $h1.Location = New-Object Drawing.Point(20, 14)
$h2 = New-Object Windows.Forms.Label
$h2.Text = 'Ticked apps are ones Safe Exam Browser usually blocks. Tick anything else it lists, or add its names so they are always ticked.'
$h2.ForeColor = $Muted; $h2.Location = New-Object Drawing.Point(22, 52); $h2.Size = New-Object Drawing.Size(700, 36); $h2.Anchor = 'Top,Left,Right'
$header.Controls.AddRange(@($h1, $h2))

# List
$list = New-Object Windows.Forms.ListView
$list.View = 'Details'; $list.CheckBoxes = $true; $list.FullRowSelect = $true; $list.ShowGroups = $true; $list.HeaderStyle = 'Nonclickable'
$list.BorderStyle = 'None'; $list.Dock = 'Fill'; $list.Font = $Base
[void]$list.Columns.Add('App', 300)
[void]$list.Columns.Add('Process', 190)
[void]$list.Columns.Add('Processes', 90)
[void]$list.Columns.Add('Memory', 100)
$list.Columns[2].TextAlign = 'Right'; $list.Columns[3].TextAlign = 'Right'
$listWrap = New-Object Windows.Forms.Panel
$listWrap.Dock = 'Fill'; $listWrap.Padding = New-Object Windows.Forms.Padding(14, 8, 14, 0)
$listWrap.Controls.Add($list)

# Right-click menu
$menu = New-Object Windows.Forms.ContextMenuStrip
$miAlways = $menu.Items.Add('Always tick this app')
$miNever  = $menu.Items.Add('Never show this app')
[void]$menu.Items.Add('-')
$miReset  = $menu.Items.Add('Reset my lists')
$list.ContextMenuStrip = $menu

# Footer
$footer = New-Object Windows.Forms.Panel
$footer.Dock = 'Bottom'; $footer.Height = 128; $footer.BackColor = $Paper
$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(22, 12); $status.Size = New-Object Drawing.Size(700, 24); $status.Anchor = 'Top,Left,Right'; $status.ForeColor = $Muted; $status.Font = $Bold
$gentle = New-Object Windows.Forms.CheckBox
$gentle.Text = 'Let apps ask to save first'; $gentle.Checked = $true; $gentle.AutoSize = $true; $gentle.Location = New-Object Drawing.Point(22, 42); $gentle.ForeColor = $Ink
$startup = New-Object Windows.Forms.LinkLabel
$startup.Text = 'Stop apps starting with Windows'; $startup.AutoSize = $true; $startup.Location = New-Object Drawing.Point(230, 43); $startup.LinkColor = $Blue

function New-Button($text, $x, $w, $primary) {
  $b = New-Object Windows.Forms.Button
  $b.Text = $text; $b.Location = New-Object Drawing.Point($x, 74); $b.Size = New-Object Drawing.Size($w, 38)
  $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'; $b.Anchor = 'Bottom,Left'
  if ($primary) { $b.BackColor = $Ink; $b.ForeColor = [Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0; $b.Font = $Bold }
  else { $b.BackColor = [Drawing.Color]::White; $b.ForeColor = $Ink; $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(210, 213, 225) }
  return $b
}
$btnRefresh = New-Button 'Refresh' 22 96 $false
$btnAdd     = New-Button "Add SEB's list..." 126 150 $false
$btnSEB     = New-Button 'Open Safe Exam Browser' 286 190 $false
$btnClose   = New-Button 'Close apps' 490 230 $true
$btnClose.Anchor = 'Bottom,Right'; $btnSEB.Anchor = 'Bottom,Left'
$footer.Controls.AddRange(@($status, $gentle, $startup, $btnRefresh, $btnAdd, $btnSEB, $btnClose))
$footer.Add_Resize({ $btnClose.Left = $footer.ClientSize.Width - $btnClose.Width - 22 })

$form.Controls.Add($listWrap)
$form.Controls.Add($footer)
$form.Controls.Add($header)

$SebPath = Find-SEB
$btnSEB.Enabled = [bool]$SebPath
if (-not $SebPath) { $btnSEB.Text = 'Safe Exam Browser not found' }

# ---------------------------------------------------------------------------
function Update-CloseButton {
  $n = @($list.Items | Where-Object { $_.Checked }).Count
  $btnClose.Text = if ($n -eq 0) { 'Nothing ticked' } elseif ($n -eq 1) { 'Close 1 app' } else { "Close $n apps" }
  $btnClose.Enabled = $n -gt 0
}

function Load-List {
  $form.Cursor = 'WaitCursor'
  $list.BeginUpdate()
  $list.Items.Clear(); $list.Groups.Clear()
  $groups = @(Get-AppGroups)
  $made = @{}
  foreach ($g in $groups) {
    if (-not $made.ContainsKey($g.Category)) { $made[$g.Category] = $list.Groups.Add($g.Category, $g.Category) }
    $item = New-Object Windows.Forms.ListViewItem($g.Label)
    [void]$item.SubItems.Add("$($g.Name).exe")
    [void]$item.SubItems.Add("$($g.Instances)")
    [void]$item.SubItems.Add("$($g.MemoryMB) MB")
    $item.Tag = $g.Name; $item.Checked = $g.Tick; $item.Group = $made[$g.Category]
    [void]$list.Items.Add($item)
  }
  $list.EndUpdate()
  $form.Cursor = 'Default'
  $ticked = @($groups | Where-Object { $_.Tick }).Count
  if ($groups.Count -eq 0) { $status.ForeColor = $Green; $status.Text = 'Nothing to close. You are ready for Safe Exam Browser.' }
  elseif ($ticked -eq 0) { $status.ForeColor = $Muted; $status.Text = "No blocked apps found. $($groups.Count) other app(s) are open." }
  else { $status.ForeColor = $Ink; $status.Text = "$ticked app(s) to close. Save your work in them first." }
  Update-CloseButton
}

$list.Add_ItemChecked({ Update-CloseButton })

$btnRefresh.Add_Click({ Load-List })
$form.Add_KeyDown({ if ($_.KeyCode -eq 'F5') { Load-List } })
$startup.Add_LinkClicked({ Start-Process 'ms-settings:startupapps' })
$btnSEB.Add_Click({ if ($SebPath) { Start-Process $SebPath } })

$btnClose.Add_Click({
  $names = @($list.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
  if ($names.Count -eq 0) { return }
  foreach ($c in @($btnClose, $btnRefresh, $btnAdd, $list)) { $c.Enabled = $false }
  $status.ForeColor = $Ink; $status.Text = "Closing $($names.Count) app(s)..."
  $form.Cursor = 'WaitCursor'; $form.Refresh()
  $r = Close-Apps -names $names -gentle $gentle.Checked -pump { [Windows.Forms.Application]::DoEvents() }
  $form.Cursor = 'Default'
  foreach ($c in @($btnClose, $btnRefresh, $btnAdd, $list)) { $c.Enabled = $true }
  Load-List
  if ($r.Failed.Count -gt 0) {
    $status.ForeColor = $Red
    $status.Text = "Couldn't close: $($r.Failed -join ', ')."
    if ($r.AccessDenied -and -not $Elevated) {
      $a = [Windows.Forms.MessageBox]::Show("Some apps run with administrator rights, so PreFlight needs them too to close them.`n`nRestart PreFlight as administrator?", 'PreFlight', 'YesNo', 'Question')
      if ($a -eq 'Yes') {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Elevated"
        $form.Close()
      }
    }
  } else {
    $status.ForeColor = $Green
    $status.Text = "Closed $($names.Count) app(s)." + $(if ($list.Items.Count -eq 0) { ' You are ready.' } else { '' })
  }
})

# Add names from SEB's warning
$btnAdd.Add_Click({
  $d = New-Object Windows.Forms.Form
  $d.Text = "Add apps from Safe Exam Browser's list"; $d.Size = New-Object Drawing.Size(520, 360); $d.StartPosition = 'CenterParent'
  $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.Font = $Base; $d.BackColor = [Drawing.Color]::White; $d.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96); $d.AutoScaleMode = 'Dpi'
  $l = New-Object Windows.Forms.Label
  $l.Text = "Type the names Safe Exam Browser showed you, separated by commas or one per line. PreFlight will always tick them.`n`nExample: Discord.exe, Teams.exe, chrome.exe"
  $l.Location = New-Object Drawing.Point(18, 16); $l.Size = New-Object Drawing.Size(470, 80); $l.ForeColor = $Ink
  $t = New-Object Windows.Forms.TextBox
  $t.Multiline = $true; $t.ScrollBars = 'Vertical'; $t.Location = New-Object Drawing.Point(18, 100); $t.Size = New-Object Drawing.Size(468, 150)
  $t.Text = ((Get-Settings).Always | ForEach-Object { "$_.exe" }) -join "`r`n"
  $ok = New-Object Windows.Forms.Button
  $ok.Text = 'Save'; $ok.Location = New-Object Drawing.Point(386, 266); $ok.Size = New-Object Drawing.Size(100, 34); $ok.DialogResult = 'OK'
  $ok.FlatStyle = 'Flat'; $ok.BackColor = $Ink; $ok.ForeColor = [Drawing.Color]::White; $ok.FlatAppearance.BorderSize = 0
  $cancel = New-Object Windows.Forms.Button
  $cancel.Text = 'Cancel'; $cancel.Location = New-Object Drawing.Point(276, 266); $cancel.Size = New-Object Drawing.Size(100, 34); $cancel.DialogResult = 'Cancel'; $cancel.FlatStyle = 'Flat'
  $d.Controls.AddRange(@($l, $t, $ok, $cancel)); $d.AcceptButton = $null; $d.CancelButton = $cancel
  if ($d.ShowDialog($form) -eq 'OK') {
    $s = Get-Settings
    $s.Always = @(ConvertTo-ProcessNames $t.Text | Where-Object { $Protected -notcontains $_ })
    $s.Never = @($s.Never | Where-Object { $s.Always -notcontains $_ })
    Save-Settings $s
    Load-List
  }
})

$menu.Add_Opening({
  $has = $list.SelectedItems.Count -gt 0
  $miAlways.Enabled = $has; $miNever.Enabled = $has
})
$miAlways.Add_Click({
  $s = Get-Settings
  foreach ($i in $list.SelectedItems) { $s.Always += $i.Tag; $s.Never = @($s.Never | Where-Object { $_ -ne $i.Tag }) }
  Save-Settings $s; Load-List
})
$miNever.Add_Click({
  $s = Get-Settings
  foreach ($i in $list.SelectedItems) { $s.Never += $i.Tag; $s.Always = @($s.Always | Where-Object { $_ -ne $i.Tag }) }
  Save-Settings $s; Load-List
})
$miReset.Add_Click({
  $a = [Windows.Forms.MessageBox]::Show('Forget the apps you added and the ones you hid?', 'PreFlight', 'YesNo', 'Question')
  if ($a -eq 'Yes') { Save-Settings @{ Always = @(); Never = @() }; Load-List }
})

$form.Add_Shown({ Load-List; $form.Activate() })
[void]$form.ShowDialog()
