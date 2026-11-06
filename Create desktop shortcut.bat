@echo off
rem Puts an PreFlight shortcut on your desktop. Run it once.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop')+'\PreFlight.lnk');" ^
  "$s.TargetPath='powershell.exe';" ^
  "$s.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0PreFlight.ps1\"';" ^
  "$s.WorkingDirectory='%~dp0';" ^
  "$s.IconLocation='%SystemRoot%\System32\shell32.dll,27';" ^
  "$s.Description='Close apps before a Safe Exam Browser test';" ^
  "$s.Save()"
echo Shortcut created on your desktop.
pause
