# install-task.ps1
$basePath = "C:\Program Files\UpdateLockScreen"
$background = Join-Path $basePath "background.jpg"
$lockscreenfinal = Join-Path $basePath "LockScreenFinal"
$imgOriginal = Join-Path $basePath "lockscreen_original.jpg"
$vbsPath = Join-Path $basePath "run-hidden-update-lockscreen.vbs"
$taskName = "UpdateLockScreen"

# Удаляем старую задачу
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Создаём папки
New-Item -Path $lockscreenfinal -ItemType Directory -Force | Out-Null

# Копируем фоновое изображение
if (Test-Path $background) {
    Copy-Item -Path $background -Destination $imgOriginal -Force
}

# Реестр для экрана блокировки
REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP /f | Out-Null
REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP /v LockScreenImagePath /t REG_SZ /d "C:\Program Files\UpdateLockScreen\LockScreenFinal\lockscreen.png" /f | Out-Null
REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP /v LockScreenImageUrl /t REG_SZ /d "C:\Program Files\UpdateLockScreen\LockScreenFinal\lockscreen.png" /f | Out-Null
REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP /v LockScreenImageStatus /t REG_DWORD /d 1 /f | Out-Null

# Создаём VBS для ПОЛНОСТЬЮ скрытого запуска
$vbsContent = @'
Dim objShell, strCommand
Set objShell = CreateObject("WScript.Shell")
strCommand = "powershell.exe -WindowStyle Hidden -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ""C:\Program Files\UpdateLockScreen\update-lockscreen.ps1"""
objShell.Run strCommand, 0, False
Set objShell = Nothing
'@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII

# Создание задачи планировщика от SYSTEM
$startTime = (Get-Date).AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss")

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>Avdeev D.V.</Author>
    <Description>Update lockscreen with system info</Description>
    <URI>\UpdateLockScreen</URI>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$startTime</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"C:\Program Files\UpdateLockScreen\run-hidden-update-lockscreen.vbs"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$tempXmlPath = Join-Path $env:TEMP "$taskName.xml"
Set-Content -Path $tempXmlPath -Value $taskXml -Encoding Unicode

$result = schtasks /Create /TN $taskName /XML $tempXmlPath /F 2>&1
Remove-Item $tempXmlPath -Force -ErrorAction SilentlyContinue

# Проверка создания задачи
Start-Sleep -Seconds 2
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($taskExists) {
    Write-Host "Task created successfully"
} else {
    Write-Error "Failed to create task"
    exit 1
}
