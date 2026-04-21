# update-lockscreen.ps1
Add-Type -AssemblyName System.Drawing

$basePath = "C:\Program Files\UpdateLockScreen"
$imgOriginal = Join-Path $basePath "lockscreen_original.jpg"
$lockscreenfinal = Join-Path $basePath "LockScreenFinal"
$imageDest = Join-Path $lockscreenfinal "lockscreen.png"
$logFile = Join-Path $basePath "update-lockscreen.log"

# Функция логирования
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Write-Log "=== Start execution ==="

# Создаём папку для финального изображения
if (-not (Test-Path $lockscreenfinal)) {
    New-Item -Path $lockscreenfinal -ItemType Directory -Force | Out-Null
    Write-Log "Created folder: $lockscreenfinal"
}

# Проверяем наличие исходного изображения
if (-not (Test-Path $imgOriginal)) {
    Write-Log "ERROR: File not found $imgOriginal"
    exit 1
}

# Получаем разрешение основного монитора с fallback
try {
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $screenWidth = $screen.Bounds.Width
    $screenHeight = $screen.Bounds.Height
    Write-Log "Screen resolution from System.Windows.Forms: ${screenWidth}x${screenHeight}"
} catch {
    Write-Log "WARNING: Could not get screen resolution via System.Windows.Forms"
    Write-Log "Error: $($_.Exception.Message)"
    
    # Fallback: используем разрешение по умолчанию
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class DisplayInfo {
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);
}
'@
        $screenWidth = [DisplayInfo]::GetSystemMetrics(0)
        $screenHeight = [DisplayInfo]::GetSystemMetrics(1)
        Write-Log "Resolution from GetSystemMetrics: ${screenWidth}x${screenHeight}"
    } catch {
        Write-Log "WARNING: GetSystemMetrics failed, using default 1920x1080"
        $screenWidth = 1920
        $screenHeight = 1080
    }
}

# Загружаем и изменяем изображение под разрешение экрана с высоким качеством
try {
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
    
    Write-Log "Image loaded and resized to ${screenWidth}x${screenHeight}"
} catch {
    Write-Log "ERROR loading/resizing image: $($_.Exception.Message)"
    exit 1
}

# Определяем позицию текста на основе разрешения и билда Windows
$osInfo = Get-CimInstance Win32_OperatingSystem
$buildNumber = [int]$osInfo.BuildNumber

$leftClockBuilds = @(10240, 10586, 14393, 15063, 16299, 17134, 17763, 18362, 18363, 19041, 19042, 19043, 19044, 19045)

# Настройка порога маленького разрешения
$smallResolutionThreshold = 1400
$isSmallResolution = $screenWidth -lt $smallResolutionThreshold

# РАЗНЫЕ НАСТРОЙКИ ДЛЯ МАЛЕНЬКИХ И БОЛЬШИХ РАЗРЕШЕНИЙ
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

Write-Log "Windows Build: $buildNumber, Position: $position, Small resolution: $isSmallResolution"

# Получаем имя компьютера
$hostname = $env:COMPUTERNAME

# Получаем РЕАЛЬНОГО залогиненного пользователя (не SYSTEM)
$user = "Unknown"
try {
    # Метод 1: Через процесс explorer.exe
    $explorerProcess = Get-WmiObject Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | 
        Select-Object -First 1
    
    if ($explorerProcess) {
        $owner = $explorerProcess.GetOwner()
        if ($owner.User) {
            $user = $owner.User
            Write-Log "User found via explorer.exe: $user"
        }
    }
} catch {
    Write-Log "Could not get user from explorer.exe: $($_.Exception.Message)"
}

# Метод 2: Fallback через реестр
if ($user -eq "Unknown") {
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
        if (Test-Path $regPath) {
            $lastUser = Get-ItemProperty -Path $regPath -Name "LastLoggedOnUser" -ErrorAction Stop
            if ($lastUser) {
                $user = ($lastUser.LastLoggedOnUser -split '\\')[-1]
                Write-Log "User found via registry: $user"
            }
        }
    } catch {
        Write-Log "Could not get user from registry: $($_.Exception.Message)"
    }
}

# Метод 3: Через Win32_ComputerSystem
if ($user -eq "Unknown") {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.UserName) {
            $user = ($cs.UserName -split '\\')[-1]
            Write-Log "User found via Win32_ComputerSystem: $user"
        }
    } catch {
        Write-Log "Could not get user from Win32_ComputerSystem: $($_.Exception.Message)"
    }
}

# Домен или рабочая группа
$cs = Get-CimInstance Win32_ComputerSystem
$domain = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }

Write-Log "System info - PC: $hostname, User: $user, Domain: $domain"

# Сетевые адаптеры
$results = @()
$adapters = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {
    $_.InterfaceIndex -ne $null -and $_.Name -ne $null -and $_.NetEnabled -eq $true
}

Write-Log "Found $($adapters.Count) active network adapters"

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
                "no data" 
            }

            $results += [PSCustomObject]@{
                IPAddress     = $ip.IPAddress
                InterfaceName = $interfaceName
                AdapterName   = $adapter.Name
                Speed         = $speed
            }
            
            Write-Log "  Adapter: $($ip.IPAddress) - $interfaceName - $($adapter.Name) - $speed"
        }
    }
    catch { 
        Write-Log "  Error processing adapter $($adapter.Name): $($_.Exception.Message)"
        continue 
    }
}

# Формируем текст для картинки
$textLines = @()
$textLines += ("{0,-13} {1}" -f "PC Name:", $hostname)
$textLines += ("{0,-13} {1}" -f "User:", $user)
$textLines += ("{0,-13} {1}" -f "Domain:", $domain)
$textLines += ""

if ($results.Count -gt 0) {
    $textLines += "Network Adapters:"
    $textLines += ""
    
    if ($isSmallResolution) {
        # КОМПАКТНЫЙ ФОРМАТ
        $ipColumnWidth = 15
        $interfaceColumnWidth = 12
        $adapterColumnWidth = 20
        $speedColumnWidth = 12
    } else {
        # ПОЛНЫЙ ФОРМАТ
        $ipColumnWidth = 16
        $interfaceColumnWidth = 20
        $adapterColumnWidth = 35
        $speedColumnWidth = 16
    }
    
    # ЗАГОЛОВКИ ТАБЛИЦЫ
    $headerLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
        "IP Address", "Interface", "Adapter", "Speed")
    $separatorLine = ("{0,-$ipColumnWidth} {1,-$interfaceColumnWidth} {2,-$adapterColumnWidth} {3,-$speedColumnWidth}" -f 
        ("-" * $ipColumnWidth), 
        ("-" * $interfaceColumnWidth),
        ("-" * $adapterColumnWidth),
        ("-" * $speedColumnWidth))
    
    $textLines += $headerLine
    $textLines += $separatorLine
    
    # ДАННЫЕ АДАПТЕРОВ
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
            $r.IPAddress, 
            $interfaceNameShort,
            $adapterNameShort,
            $r.Speed)
        
        $textLines += $dataLine
    }
} else {
    $textLines += "No active network adapters found"
}

Write-Log "Text lines prepared: $($textLines.Count) lines"

# Рисуем текст с ОПТИМАЛЬНЫМ КАЧЕСТВОМ И ЧЕТКОСТЬЮ
try {
    $gText = [System.Drawing.Graphics]::FromImage($resizedImg)

    # ОПТИМАЛЬНЫЕ НАСТРОЙКИ ДЛЯ ЧЕТКОСТИ
    $gText.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gText.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    # ОПТИМАЛЬНЫЙ РАЗМЕР ШРИФТА
    if ($isSmallResolution) {
        $fontSize = [Math]::Max([int]($screenWidth / 100), 8)
    } else {
        $fontSize = [Math]::Max([int]($screenWidth / 110), 12)
    }

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

    Write-Log "Font size: $fontSize pt"

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

    # РИСУЕМ ТЕКСТ
    foreach ($line in $textLines) {
        $posX = [float]$x
        $posY = [float]$yStart
        
        # МЯГКАЯ ТЕНЬ ДЛЯ КОНТРАСТА
        $gText.DrawString($line, $font, $shadowBrush, [System.Drawing.PointF]::new($posX + 1, $posY + 1))
        
        # ЧЕТКИЙ БЕЛЫЙ ТЕКСТ
        $gText.DrawString($line, $font, $textBrush, [System.Drawing.PointF]::new($posX, $posY))
        
        $yStart += $lineHeight
    }

    Write-Log "Text drawn successfully"

    # Сохраняем в PNG для максимального качества
    $resizedImg.Save($imageDest, [System.Drawing.Imaging.ImageFormat]::Png)
    
    # Проверяем что файл создан
    if (Test-Path $imageDest) {
        $fileSize = (Get-Item $imageDest).Length
        Write-Log "SUCCESS: Image saved to $imageDest, size: $fileSize bytes"
    } else {
        Write-Log "ERROR: Image file was not created!"
    }

    # Освобождаем ресурсы
    $gText.Dispose()
    $resizedImg.Dispose()
    $font.Dispose()
    $textBrush.Dispose()
    $shadowBrush.Dispose()
    
    Write-Log "=== Completed successfully ==="
} catch {
    Write-Log "ERROR drawing text: $($_.Exception.Message)"
    Write-Log "StackTrace: $($_.Exception.StackTrace)"
    exit 1
}
