Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$basePath       = "C:\Program Files\UpdateLockScreen"
$background     = Join-Path $basePath "background.jpg"
$finalFolder    = Join-Path $basePath "LockScreenFinal"
$finalImage     = Join-Path $finalFolder "lockscreen.png"

# Создаём папку
if (-not (Test-Path $finalFolder)) { New-Item -Path $finalFolder -ItemType Directory -Force | Out-Null }

# Получаем разрешение экрана — работает даже от SYSTEM в 99% случаев
$screen      = [System.Windows.Forms.Screen]::PrimaryScreen
$screenWidth = $screen.Bounds.Width
$screenHeight= $screen.Bounds.Height

# Если вдруг не сработало (редко) — берём из WMI
if ($screenWidth -le 800) {
    $video = Get-CimInstance Win32_VideoController | Where-Object CurrentHorizontalResolution | Select-Object -First 1
    if ($video) {
        $screenWidth  = $video.CurrentHorizontalResolution
        $screenHeight = $video.CurrentVerticalResolution
    }
}

# Загружаем и растягиваем background.jpg сразу под экран
$originalImg = [System.Drawing.Image]::FromFile($background)
$resizedImg  = New-Object System.Drawing.Bitmap($screenWidth, $screenHeight)

$g = [System.Drawing.Graphics]::FromImage($resizedImg)
$g.InterpolationMode    = 'HighQualityBicubic'
$g.SmoothingMode        = 'HighQuality'
$g.PixelOffsetMode      = 'HighQuality'
$g.CompositingQuality   = 'HighQuality'
$g.DrawImage($originalImg, 0, 0, $screenWidth, $screenHeight)
$g.Dispose()
$originalImg.Dispose()

# === ТВОЯ ЛОГИКА ТЕКСТА ПОЛНОСТЬЮ СОХРАНЕНА ===
$osInfo = Get-CimInstance Win32_OperatingSystem
$buildNumber = [int]$osInfo.BuildNumber
$leftClockBuilds = @(10240,10586,14393,15063,16299,17134,17763,18362,18363,19041,19042,19043,19044,19045)

$isSmallResolution = $screenWidth -lt 1400

if ($leftClockBuilds -contains $buildNumber) {
    $leftMargin = if ($isSmallResolution) { [int]($screenWidth * 0.12) } else { [int]($screenWidth * 0.03) }
    $topMargin  = if ($isSmallResolution) { [int]($screenHeight * 0.08) } else { [int]($screenHeight * 0.05) }
    $position = "TopLeft"
} else {
    $leftMargin   = if ($isSmallResolution) { [int]($screenWidth * 0.12) } else { [int]($screenWidth * 0.03) }
    $bottomMargin = if ($isSmallResolution) { [int]($screenHeight * 0.08) } else { [int]($screenHeight * 0.05) }
    $position = "BottomLeft"
}

# Правильное имя пользователя (не SYSTEM!)
$user = (Get-CimInstance Win32_ComputerSystem).UserName -split '\\' | Select-Object -Last 1
if (-not $user) { $user = $env:USERNAME }

$hostname = $env:COMPUTERNAME
$cs = Get-CimInstance Win32_ComputerSystem
$domain = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }

# Сетевые адаптеры — полностью твой код
$results = @()
$adapters = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true -and $_.NetConnectionID }

foreach ($adapter in $adapters) {
    $ips = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" }
    $speed = (Get-NetAdapter -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue).LinkSpeed -replace ' Gb.*','Гб/с' -replace ' Mb.*','Мб/с'
    foreach ($ip in $ips) {
        $results += [PSCustomObject]@{
            IPAddress     = $ip.IPAddress
            InterfaceName = $adapter.NetConnectionID
            AdapterName   = $adapter.Name
            Speed         = $speed
        }
    }
}

$textLines = @()
$textLines += ("{0,-13} {1}" -f "Имя ПК:", $hostname)
$textLines += ("{0,-13} {1}" -f "Пользователь:", $user)
$textLines += ("{0,-13} {1}" -f "Домен:", $domain)
$textLines += ""

if ($results.Count -gt 0) {
    $textLines += "Сетевые адаптеры:"
    $textLines += ""

    if ($isSmallResolution) {
        $w1=15; $w2=12; $w3=20; $w4=12
    } else {
        $w1=16; $w2=20; $w3=35; $w4=16
    }

    $textLines += ("{0,-$w1} {1,-$w2} {2,-$w3} {3,-$w4}" -f "IP адрес","Интерфейс","Адаптер","Скорость")
    $textLines += ("{0,-$w1} {1,-$w2} {2,-$w3} {3,-$w4}" -f ("-"*$w1),("-"*$w2),("-"*$w3),("-"*$w4))

    foreach ($r in $results) {
        $a = if ($r.AdapterName.Length -gt ($w3-2)) { $r.AdapterName.Substring(0,$w3-5)+"..." } else { $r.AdapterName }
        $i = if ($r.InterfaceName.Length -gt ($w2-2)) { $r.InterfaceName.Substring(0,$w2-5)+"..." } else { $r.InterfaceName }
        $textLines += ("{0,-$w1} {1,-$w2} {2,-$w3} {3,-$w4}" -f $r.IPAddress, $i, $a, $r.Speed)
    }
} else {
    $textLines += "Активные сетевые адаптеры не найдены"
}

# === РИСОВАНИЕ ТЕКСТА — ТВОЯ ЛОГИКА 1 в 1 ===
$gText = [System.Drawing.Graphics]::FromImage($resizedImg)
$gText.SmoothingMode       = 'AntiAlias'
$gText.TextRenderingHint   = 'ClearTypeGridFit'

$fontSize = if ($isSmallResolution) { [Math]::Max([int]($screenWidth/100),8) } else { [Math]::Max([int]($screenWidth/110),12) }
$font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)

# Автоподгонка шрифта
$temp = [System.Drawing.Graphics]::FromImage($resizedImg)
$maxW = 0
foreach ($line in $textLines) { $maxW = [Math]::Max($maxW, $temp.MeasureString($line,$font).Width) }
$temp.Dispose()

if ($maxW -gt ($screenWidth - $leftMargin*2)) {
    $fontSize = [Math]::Max([int]($fontSize*0.9),7)
    $font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)
}

$textBrush   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,0,0,0))

$lineHeight = [int]($fontSize * 1.3)
$x = $leftMargin
$y = if ($position -eq "BottomLeft") { $screenHeight - ($lineHeight * $textLines.Count) - $bottomMargin } else { $topMargin }

foreach ($line in $textLines) {
    $gText.DrawString($line, $font, $shadowBrush, $x+1, $y+1)
    $gText.DrawString($line, $font, $textBrush,   $x,   $y)
    $y += $lineHeight
}

# Сохраняем сразу финальный PNG
$resizedImg.Save($finalImage, [System.Drawing.Imaging.ImageFormat]::Png)

# Освобождаем
$gText.Dispose()
$resizedImg.Dispose()
$font.Dispose()
$textBrush.Dispose()
$shadowBrush.Dispose()

Write-Host "Готово! $finalImage — $($screenWidth)x$screenHeight"
