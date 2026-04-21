Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$basePath = "C:\Program Files\UpdateLockScreen"
$backgroundImg = Join-Path $basePath "background.jpg"
$lockscreenfinal = Join-Path $basePath "LockScreenFinal"
$imageDest = Join-Path $lockscreenfinal "lockscreen.png"
$logFile = Join-Path $basePath "update-lockscreen.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Write-Log "=== Start ==="

if (-not (Test-Path $lockscreenfinal)) {
    New-Item -Path $lockscreenfinal -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $backgroundImg)) {
    Write-Log "ERROR: background.jpg not found"
    exit 1
}

# Получаем разрешение основного монитора
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$screenWidth = $screen.Bounds.Width
$screenHeight = $screen.Bounds.Height

$originalImg = [System.Drawing.Image]::FromFile($backgroundImg)
$resizedImg = New-Object System.Drawing.Bitmap($screenWidth, $screenHeight)

$gResize = [System.Drawing.Graphics]::FromImage($resizedImg)
$gResize.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gResize.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gResize.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gResize.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$gResize.DrawImage($originalImg, 0, 0, $screenWidth, $screenHeight)
$gResize.Dispose()
$originalImg.Dispose()

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

Write-Log "Build: $buildNumber, Position: $position, SmallRes: $isSmallResolution"

$hostname = $env:COMPUTERNAME

$user = "Unknown"
try {
    $explorerProcess = Get-WmiObject Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
    if ($explorerProcess) {
        $owner = $explorerProcess.GetOwner()
        if ($owner.User) {
            $user = $owner.User
            Write-Log "User from explorer.exe: $user"
        }
    }
} catch {
    Write-Log "explorer.exe method failed"
}

if ($user -eq "Unknown") {
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
        $lastUser = Get-ItemProperty -Path $regPath -Name "LastLoggedOnUser" -ErrorAction Stop
        $user = ($lastUser.LastLoggedOnUser -split '\\')[-1]
        Write-Log "User from registry: $user"
    } catch {
        Write-Log "Registry method failed"
    }
}

if ($user -eq "Unknown") {
    try {
        $cs2 = Get-CimInstance Win32_ComputerSystem
        if ($cs2.UserName) {
            $user = ($cs2.UserName -split '\\')[-1]
            Write-Log "User from Win32_ComputerSystem: $user"
        }
    } catch {
        Write-Log "Win32_ComputerSystem method failed"
    }
}

$cs = Get-CimInstance Win32_ComputerSystem
$domain = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }

Write-Log "PC: $hostname, User: $user, Domain: $domain"

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
                "no data"
            }

            $results += [PSCustomObject]@{
                IPAddress     = $ip.IPAddress
                InterfaceName = $interfaceName
                AdapterName   = $adapter.Name
                Speed         = $speed
            }
        }
    } catch { continue }
}

$textLines = @()
$textLines += ("{0,-13} {1}" -f "PC Name:", $hostname)
$textLines += ("{0,-13} {1}" -f "User:", $user)
$textLines += ("{0,-13} {1}" -f "Domain:", $domain)
$textLines += ""

if ($results.Count -gt 0) {
    $textLines += "Network Adapters:"
    $textLines += ""

    if ($isSmallResolution) {
        $w1 = 15; $w2 = 12; $w3 = 20; $w4 = 12
    } else {
        $w1 = 16; $w2 = 20; $w3 = 35; $w4 = 16
    }

    $textLines += ("{0,-$w1} {1,-$w2} {2,-$w3} {3,-$w4}" -f "IP Address", "Interface", "Adapter", "Speed")
    $textLines += ("{0,-$w1} {1,-$w2} {2,-$w3} {3,-$w4}" -f ("-" * $w1), ("-" * $w2), ("-" * $w3), ("-" * $w4))

    foreach ($r in $results) {
        $adapterShort = if ($r.AdapterName.Length -gt ($w3 - 2)) {
            $r.AdapterName.Substring(0, $w3 - 3) + "..."
        } else { $r.AdapterName }

        $ifaceShort = if ($r.InterfaceName.Length -gt ($w2 - 2)) {
            $r.InterfaceName.Substring(0, $w2 - 3) + "..."
        } else { $r.InterfaceName }

        $textLines += ("{0,-$w1} {1,-$w2} {2,-$w3} {3,-$w4}" -f $r.IPAddress, $ifaceShort, $adapterShort, $r.Speed)
    }
} else {
    $textLines += "No active network adapters found"
}

$gText = [System.Drawing.Graphics]::FromImage($resizedImg)
$gText.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gText.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

if ($isSmallResolution) {
    $fontSize = [Math]::Max([int]($screenWidth / 100), 8)
} else {
    $fontSize = [Math]::Max([int]($screenWidth / 110), 12)
}

$font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)

$tempGraphics = [System.Drawing.Graphics]::FromImage($resizedImg)
$maxTextWidth = 0
foreach ($line in $textLines) {
    $size = $tempGraphics.MeasureString($line, $font)
    if ($size.Width -gt $maxTextWidth) { $maxTextWidth = $size.Width }
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

$resizedImg.Save($imageDest, [System.Drawing.Imaging.ImageFormat]::Png)

Write-Log "SUCCESS: ${screenWidth}x${screenHeight} font:${fontSize}pt user:$user"
Write-Log "=== Done ==="

$gText.Dispose()
$resizedImg.Dispose()
$font.Dispose()
$textBrush.Dispose()
$shadowBrush.Dispose()
