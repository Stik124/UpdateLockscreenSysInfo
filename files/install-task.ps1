
# install-task.ps1 - Создание задачи планировщика
$basePath = "C:\Program Files\UpdateLockScreen"
$background = Join-Path $basePath "background.jpg"
$lockscreenfinal = Join-Path $basePath "LockScreenFinal"
$imgOriginal = Join-Path $basePath "lockscreen_original.jpg"
$updateScript = Join-Path $basePath "update-lockscreen.ps1"
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

# Генерация update-lockscreen.ps1
$scriptContent = @'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$basePath = "C:\Program Files\UpdateLockScreen"
$imgOriginal = Join-Path $basePath "lockscreen_original.jpg"
$lockscreenfinal = Join-Path $basePath "LockScreenFinal"
$imageDest = Join-Path $lockscreenfinal "lockscreen.png"

if (-not (Test-Path $lockscreenfinal)) {
    New-Item -Path $lockscreenfinal -ItemType Directory -Force | Out-Null
}

# Получаем разрешение экрана
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$screenWidth = $screen.Bounds.Width
$screenHeight = $screen.Bounds.Height

# Загружаем и ресайзим изображение
$originalImg = [System.Drawing.Image]::FromFile($imgOriginal)
$resizedImg = New-Object System.Drawing.Bitmap($screenWidth, $screenHeight)

$gResize = [System.Drawing.Graphics]::FromImage($resizedImg)
$gResize.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gResize.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gResize.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gResize.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$gResize.DrawImage($originalImg, 0, 0, $screenWidth, $screenHeight)
$gResize.Dispose()
$originalImg.Dispose()

# Определяем позицию текста
$osInfo = Get-CimInstance Win32_OperatingSystem
$buildNumber = [int]$osInfo.BuildNumber
$leftClockBuilds = @(10240, 10586, 14393, 15063, 16299, 17134, 17763, 18362, 18363, 19041, 19042, 19043, 19044, 19045)

$smallResolutionThreshold = 1400
$isSmallResolution = $screenWidth -lt $smallResolutionThreshold

if ($leftClockBuilds -contains $buildNumber) {
    if ($isSmallResolution) {
        $leftMargin = [int]($screenWidth * 0.12)
        $topMargin = [int]($screenHeight * 0.08)
    } else {
        $leftMargin = [int]($screenWidth * 0.03)
        $topMargin = [int]($screenHeight * 0.05)
    }
    $position = "TopLeft"
} else {
    if ($isSmallResolution) {
        $leftMargin = [int]($screenWidth * 0.12)
        $bottomMargin = [int]($screenHeight * 0.08)
    } else {
        $leftMargin = [int]($screenWidth * 0.03)
        $bottomMargin = [int]($screenHeight * 0.05)
    }
    $position = "BottomLeft"
}

# Собираем информацию
$hostname = $env:COMPUTERNAME
$user = $env:USERNAME
$cs = Get-CimInstance Win32_ComputerSystem
$domain = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }

# Сетевые адаптеры
$results = @()
$adapters = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {
    $_.InterfaceIndex -ne $null -and $_.Name -ne $null -and $_.NetEnabled -eq $true
}

foreach ($adapter in $adapters) {
    try {
        $ipAddresses = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.*' }

        $netAdapter = Get-NetAdapter -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
        
        foreach ($ip in $ipAddresses) {
            $interfaceName = $adapter.NetConnectionID
            if (-not $interfaceName) { $interfaceName = $adapter.Name }

            $speed = if ($netAdapter -and $netAdapter.LinkSpeed) { 
                $netAdapter.LinkSpeed 
            } else { 
                "нет данных" 
            }

            $results += [PSCustomObject]@{
                IPAddress     = $ip.IPAddress
                InterfaceName = $interfaceName
                AdapterName   = $adapter.Name
                Speed         = $speed
            }
        }
    }
    catch { continue }
}

# Формируем текст
$textLines = @()
$textLines += ("{0,-13} {1}" -f "Имя ПК:", $hostname)
$textLines += ("{0,-13} {1}" -f "Пользователь:", $user)
$textLines += ("{0,-13} {1}" -f "Домен:", $domain)
$textLines += ""

if ($results.Count -gt 0) {
    $textLines += "Сетевые адаптеры:"
    $textLines += ""
    
    if ($isSmallResolution) {
        $ipColumnWidth = 15
        $interfaceColumnWidth = 12
        $adapterColumnWidth = 20
        $speedColumnWidth = 12
    } else {
        $ipColumnWidth = 16
        $interfaceColumnWidth = 20
        $adapterColumnWidth = 35
        $speedColumnWidth = 16
    }
    
    $headerLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
        "IP адрес", "Интерфейс", "Адаптер", "Скорость")
    $separatorLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
        ("-" * $ipColumnWidth), ("-" * $interfaceColumnWidth), ("-" * $adapterColumnWidth), ("-" * $speedColumnWidth))
    
    $textLines += $headerLine
    $textLines += $separatorLine
    
    foreach ($r in $results) {
        $adapterNameShort = if ($r.AdapterName.Length -gt ($adapterColumnWidth - 2)) { 
            $r.AdapterName.Substring(0, $adapterColumnWidth - 3) + "..." 
        } else { 
            $r.AdapterName 
        }
        
        $interfaceNameShort = if ($r.InterfaceName.Length -gt ($interfaceColumnWidth - 2)) { 
            $r.InterfaceName.Substring(0, $interfaceColumnWidth - 3) + "..." 
        } else { 
            $r.InterfaceName 
        }
        
        $dataLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
            $r.IPAddress, $interfaceNameShort, $adapterNameShort, $r.Speed)
        
        $textLines += $dataLine
    }
} else {
    $textLines += "Активные сетевые адаптеры не найдены"
}

# Рисуем текст
$gText = [System.Drawing.Graphics]::FromImage($resizedImg)
$gText.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gText.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

if ($isSmallResolution) {
    $fontSize = [Math]::Max([int]($screenWidth / 100), 8)
} else {
    $fontSize = [Math]::Max([int]($screenWidth / 110), 12)
}

$font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)

# Автоподстройка размера шрифта
$tempGraphics = [System.Drawing.Graphics]::FromImage($resizedImg)
$maxTextWidth = 0
foreach ($line in $textLines) {
    $size = $tempGraphics.MeasureString($line, $font)
    if ($size.Width -gt $maxTextWidth) {
        $maxTextWidth = $size.Width
    }
}
$tempGraphics.Dispose()

$safeZoneWidth = $screenWidth - ($leftMargin * 2)
if ($maxTextWidth -gt $safeZoneWidth) {
    $newFontSize = [Math]::Max([int]($fontSize * 0.9), 7)
    if ($newFontSize -lt $fontSize) {
        $fontSize = $newFontSize
        $font.Dispose()
        $font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)
    }
}

$textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255))
$shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 0, 0, 0))

$lineHeight = [int]($fontSize * 1.3)
$x = $leftMargin

if ($position -eq "BottomLeft") {
    $yStart = $screenHeight - ($lineHeight * $textLines.Count) - $bottomMargin
} else {
    $yStart = $topMargin
}

foreach ($line in $textLines) {
    $posX = [float]$x
    $posY = [float]$yStart
    
    $gText.DrawString($line, $font, $shadowBrush, [System.Drawing.PointF]::new($posX + 1, $posY + 1))
    $gText.DrawString($line, $font, $textBrush, [System.Drawing.PointF]::new($posX, $posY))
    
    $yStart += $lineHeight
}

# Сохраняем
$resizedImg.Save($imageDest, [System.Drawing.Imaging.ImageFormat]::Png)

# Освобождаем ресурсы
$gText.Dispose()
$resizedImg.Dispose()
$font.Dispose()
$textBrush.Dispose()
$shadowBrush.Dispose()
'@

Set-Content -Path $updateScript -Value $scriptContent -Encoding UTF8

# Создаём VBS
$vbsContent = @'
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""C:\Program Files\UpdateLockScreen\update-lockscreen.ps1""", 0, False
'@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII

# Создание задачи планировщика
$startTime = (Get-Date).AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss")

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>Avdeev D.V.</Author>
    <Description>Задача по генерации информации на экран блокировки</Description>
    <URI>\UpdateLockScreen</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled></LogonTrigger>
    <TimeTrigger>
      <Repetition><Interval>PT1H</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
      <StartBoundary>$startTime</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
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
    Write-Host "Задача планировщика создана успешно"
} else {
    Write-Error "Не удалось создать задачу планировщика"
    exit 1
}
