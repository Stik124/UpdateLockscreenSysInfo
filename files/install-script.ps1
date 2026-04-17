
# --- install-script.ps1
# Пути
$basePath = "C:\Program Files\UpdateLockScreen"
$background = Join-Path $basePath "background.jpg"
$outputImage = Join-Path $basePath "lockscreen.jpg"
$lockscreenfinal = Join-Path $basePath "LockScreenFinal"
#$imgSourceDir   = "C:\Windows\Web\Screen"
$imgOriginal    = Join-Path $basePath "lockscreen_original.jpg"
$updateScript   = Join-Path $basePath "update-lockscreen.ps1"
$vbsPath        = Join-Path $basePath "run-hidden-update-lockscreen.vbs"
$taskName       = "UpdateLockScreen"


# --- 1. Создаём папки ---
New-Item -Path $lockscreenfinal -ItemType Directory -Force | Out-Null

# --- 4. Берём подготовленную картинку ---

Write-Host "Использем подготовленное изображение..."

#if (!(Test-Path $background)) {
#    Write-Error "Файл background.jpg не найден в $basePath"
#    exit 1
#}

Copy-Item -Path $background -Destination $imgOriginal -Force

# --- 4. Задаем экран блокировки

REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP
REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP /v LockScreenImagePath /t REG_SZ /d "C:\Program Files\UpdateLockScreen\LockScreenFinal\lockscreen.png" /f
REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP /v LockScreenImageUrl /t REG_SZ /d "C:\Program Files\UpdateLockScreen\LockScreenFinal\lockscreen.png" /f
REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP /v LockScreenImageStatus /t REG_DWORD /d 1 /f

######################################################################################################
# --- 5. Генерация update-lockscreen.ps1 ---
$scriptContent = @'
Add-Type -AssemblyName System.Drawing

$basePath = "C:\Program Files\UpdateLockScreen"
$imgOriginal = Join-Path $basePath "lockscreen_original.jpg"
$lockscreenfinal = Join-Path $basePath "LockScreenFinal"
$imageDest = Join-Path $lockscreenfinal "lockscreen.jpg"

if (-not (Test-Path $lockscreenfinal)) {
    New-Item -Path $lockscreenfinal -ItemType Directory -Force | Out-Null
}

# Получаем разрешение основного монитора
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$screenWidth = $screen.Bounds.Width
$screenHeight = $screen.Bounds.Height

# Загружаем и изменяем изображение под разрешение экрана с высоким качеством
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

# Определяем позицию текста на основе разрешения
$osInfo = Get-CimInstance Win32_OperatingSystem
$buildNumber = [int]$osInfo.BuildNumber

$leftClockBuilds = @(10240, 10586, 14393, 15063, 16299, 17134, 17763, 18362, 18363, 19041, 19042, 19043, 19044, 19045)

# Настройка порога маленького разрешения
$smallResolutionThreshold = 1400

# Определяем маленькое разрешение
$isSmallResolution = $screenWidth -lt $smallResolutionThreshold

# РАЗНЫЕ НАСТРОЙКИ ДЛЯ МАЛЕНЬКИХ И БОЛЬШИХ РАЗРЕШЕНИЙ (УВЕЛИЧЕНЫ ОТСТУПЫ)
if ($leftClockBuilds -contains $buildNumber) {
    if ($isSmallResolution) {
        $leftMargin = [int]($screenWidth * 0.12)   # 12% для маленьких (увеличили)
        $topMargin = [int]($screenHeight * 0.08)
    } else {
        $leftMargin = [int]($screenWidth * 0.03)   # 3% для больших
        $topMargin = [int]($screenHeight * 0.05)
    }
    $position = "TopLeft"
} else {
    if ($isSmallResolution) {
        $leftMargin = [int]($screenWidth * 0.12)   # 12% для маленьких (увеличили)
        $bottomMargin = [int]($screenHeight * 0.08)
    } else {
        $leftMargin = [int]($screenWidth * 0.03)
        $bottomMargin = [int]($screenHeight * 0.05)
    }
    $position = "BottomLeft"
}

$hostname = $env:COMPUTERNAME
$user = $env:USERNAME

# --- Домен или рабочая группа ---
$cs = Get-CimInstance Win32_ComputerSystem
$domain = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }

# --- Сетевые адаптеры ---
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

            #  ПРОСТОЙ FALLBACK "НЕТ ДАННЫХ"
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

# --- Формируем текст для картинки ---
$textLines = @()

# ЕДИНЫЙ СТИЛЬ ДЛЯ ВСЕХ РАЗРЕШЕНИЙ
$textLines += ("{0,-13} {1}" -f "Имя ПК:", $hostname)
$textLines += ("{0,-13} {1}" -f "Пользователь:", $user)
$textLines += ("{0,-13} {1}" -f "Домен:", $domain)
$textLines += ""

if ($results.Count -gt 0) {
    $textLines += "Сетевые адаптеры:"
    $textLines += ""
    
    if ($isSmallResolution) {
        # КОМПАКТНЫЙ ФОРМАТ ДЛЯ МАЛЕНЬКИХ ЭКРАНОВ (ТАКОЙ ЖЕ СТИЛЬ)
        $ipColumnWidth = 15
        $interfaceColumnWidth = 12
        $adapterColumnWidth = 20
        $speedColumnWidth = 12
        
        # ЗАГОЛОВКИ ТАБЛИЦЫ
        $headerLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
            "IP адрес", "Интерфейс", "Адаптер", "Скорость")
        $separatorLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
            ("-" * $ipColumnWidth), 
            ("-" * $interfaceColumnWidth),
            ("-" * $adapterColumnWidth),
            ("-" * $speedColumnWidth))
        
        $textLines += $headerLine
        $textLines += $separatorLine
        
        # ДАННЫЕ АДАПТЕРОВ
        foreach ($r in $results) {
            # Обрезаем длинные названия адаптеров
            $adapterNameShort = if ($r.AdapterName.Length -gt ($adapterColumnWidth - 2)) { 
                $r.AdapterName.Substring(0, $adapterColumnWidth - 3) + "..." 
            } else { 
                $r.AdapterName 
            }
            
            # Обрезаем длинные названия интерфейсов
            $interfaceNameShort = if ($r.InterfaceName.Length -gt ($interfaceColumnWidth - 2)) { 
                $r.InterfaceName.Substring(0, $interfaceColumnWidth - 3) + "..." 
            } else { 
                $r.InterfaceName 
            }
            
            # ВЫРАВНИВАЕМ КАЖДУЮ КОЛОНКУ
            $dataLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
                $r.IPAddress, 
                $interfaceNameShort,
                $adapterNameShort,
                $r.Speed)
            
            $textLines += $dataLine
        }
    } else {
        # ПОЛНЫЙ ФОРМАТ ДЛЯ БОЛЬШИХ ЭКРАНОВ
        $ipColumnWidth = 16
        $interfaceColumnWidth = 20
        $adapterColumnWidth = 35
        $speedColumnWidth = 16
        
        # ЗАГОЛОВКИ ТАБЛИЦЫ
        $headerLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
            "IP адрес", "Интерфейс", "Адаптер", "Скорость")
        $separatorLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
            ("-" * $ipColumnWidth), 
            ("-" * $interfaceColumnWidth),
            ("-" * $adapterColumnWidth),
            ("-" * $speedColumnWidth))
        
        $textLines += $headerLine
        $textLines += $separatorLine
        
        # ДАННЫЕ АДАПТЕРОВ
        foreach ($r in $results) {
            # Обрезаем длинные названия адаптеров
            $adapterNameShort = if ($r.AdapterName.Length -gt ($adapterColumnWidth - 2)) { 
                $r.AdapterName.Substring(0, $adapterColumnWidth - 3) + "..." 
            } else { 
                $r.AdapterName 
            }
            
            # Обрезаем длинные названия интерфейсов
            $interfaceNameShort = if ($r.InterfaceName.Length -gt ($interfaceColumnWidth - 2)) { 
                $r.InterfaceName.Substring(0, $interfaceColumnWidth - 3) + "..." 
            } else { 
                $r.InterfaceName 
            }
            
            # ВЫРАВНИВАЕМ КАЖДУЮ КОЛОНКУ
            $dataLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
                $r.IPAddress, 
                $interfaceNameShort,
                $adapterNameShort,
                $r.Speed)
            
            $textLines += $dataLine
        }
    }
} else {
    $textLines += "Активные сетевые адаптеры не найдены"
}

# --- Рисуем текст с ОПТИМАЛЬНЫМ КАЧЕСТВОМ И ЧЕТКОСТЬЮ ---
$gText = [System.Drawing.Graphics]::FromImage($resizedImg)

# ОПТИМАЛЬНЫЕ НАСТРОЙКИ ДЛЯ ЧЕТКОСТИ И КАЧЕСТВА
$gText.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gText.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

# ОПТИМАЛЬНЫЙ РАЗМЕР ШРИФТА (МЕНЬШЕ ДЛЯ МАЛЕНЬКИХ ЭКРАНОВ)
if ($isSmallResolution) {
    $fontSize = [Math]::Max([int]($screenWidth / 100), 8)
} else {
    $fontSize = [Math]::Max([int]($screenWidth / 110), 12)
}

# ИСПОЛЬЗУЕМ КАЧЕСТВЕННЫЕ ШРИФТЫ
$font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)

# Проверяем ширину текста
$tempGraphics = [System.Drawing.Graphics]::FromImage($resizedImg)
$maxTextWidth = 0

foreach ($line in $textLines) {
    $size = $tempGraphics.MeasureString($line, $font)
    if ($size.Width -gt $maxTextWidth) {
        $maxTextWidth = $size.Width
    }
}
$tempGraphics.Dispose()

# Автоподстройка шрифта если нужно
$safeZoneWidth = $screenWidth - ($leftMargin * 2)
if ($maxTextWidth -gt $safeZoneWidth) {
    $newFontSize = [Math]::Max([int]($fontSize * 0.9), 7)
    if ($newFontSize -lt $fontSize) {
        $fontSize = $newFontSize
        $font.Dispose()
        $font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)
    }
}

# ЯРКИЕ ЦВЕТА С ХОРОШИМ КОНТРАСТОМ
$textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255))
$shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 0, 0, 0))

$lineHeight = [int]($fontSize * 1.3)
$x = $leftMargin

if ($position -eq "BottomLeft") {
    $yStart = $screenHeight - ($lineHeight * $textLines.Count) - $bottomMargin
} else {
    $yStart = $topMargin
}

# РИСУЕМ ТЕКСТ С ОПТИМАЛЬНЫМ КАЧЕСТВОМ
foreach ($line in $textLines) {
    $posX = [float]$x
    $posY = [float]$yStart
    
    # МЯГКАЯ ТЕНЬ ДЛЯ КОНТРАСТА
    $gText.DrawString($line, $font, $shadowBrush, [System.Drawing.PointF]::new($posX + 1, $posY + 1))
    
    # ЧЕТКИЙ БЕЛЫЙ ТЕКСТ
    $gText.DrawString($line, $font, $textBrush, [System.Drawing.PointF]::new($posX, $posY))
    
    $yStart += $lineHeight
}


# Сохраняем в PNG для максимального качества
$imageDest = $imageDest -replace '\.jpg$', '.png'
$resizedImg.Save($imageDest, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "✅ Изображение сохранено: $imageDest"
Write-Host "📐 Разрешение: ${screenWidth}x${screenHeight}"
Write-Host "🔤 Шрифт: Consolas Bold, ${fontSize}pt"
Write-Host "📱 Маленькое разрешение: $isSmallResolution"
Write-Host "📍 Левый отступ: ${leftMargin}px"

# Освобождаем ресурсы
$gText.Dispose()
$resizedImg.Dispose()
$font.Dispose()
$textBrush.Dispose()
$shadowBrush.Dispose()
'@
Set-Content -Path $updateScript -Value $scriptContent -Encoding UTF8

######################################################################################################
# --- 6. Создаём VBS для тихого запуска ---
$vbsContent = @'
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""C:\Program Files\UpdateLockScreen\update-lockscreen.ps1""", 0, False
'@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII

######################################################################################################
# --- 7. Планировщик ---
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

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
$tempXmlPath = Join-Path $env:TEMP "$taskName.xml"
Set-Content -Path $tempXmlPath -Value $taskXml -Encoding Unicode
schtasks /Create /TN $taskName /XML $tempXmlPath /F
Remove-Item $tempXmlPath -Force

######################################################################################################
# --- 8. Первый запуск сразу после установки ---
Write-Host "Запускаю первое обновление..."
# ЗАДЕРЖКА - 10 секунд для инициализации системы
# Start-Sleep -Seconds 10
Start-Process -FilePath "wscript.exe" -ArgumentList "`"$vbsPath`"" -WindowStyle Hidden -Wait
Start-ScheduledTask -TaskName "UpdateLockScreen"

Write-Host "✅ Установлено: UpdateLockScreen с таблицей сетевых адаптеров и доменом/рабочей группой!"
