# update-lockscreen.ps1
Add-Type -AssemblyName System.Drawing

$basePath = "C:\Program Files\UpdateLockScreen"
$imgOriginal = Join-Path $basePath "lockscreen_original.jpg"
$lockscreenfinal = Join-Path $basePath "LockScreenFinal"
$imageDest = Join-Path $lockscreenfinal "lockscreen.png"
$logFile = Join-Path $basePath "update-lockscreen.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Write-Log "=== Start execution ==="

if (-not (Test-Path $lockscreenfinal)) {
    New-Item -Path $lockscreenfinal -ItemType Directory -Force | Out-Null
    Write-Log "Created folder: $lockscreenfinal"
}

if (-not (Test-Path $imgOriginal)) {
    Write-Log "ERROR: File not found $imgOriginal"
    exit 1
}

# Get screen resolution with fallback
try {
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $screenWidth = $screen.Bounds.Width
    $screenHeight = $screen.Bounds.Height
    Write-Log "Screen resolution: ${screenWidth}x${screenHeight}"
} catch {
    Write-Log "WARNING: Could not get screen resolution via System.Windows.Forms"
    Write-Log "Error: $($_.Exception.Message)"
    
    try {
        $monitor = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop | Select-Object -First 1
        $screenWidth = $monitor.MaxHorizontalImageSize * 8
        $screenHeight = $monitor.MaxVerticalImageSize * 8
        Write-Log "Resolution from WMI: ${screenWidth}x${screenHeight}"
    } catch {
        Write-Log "WARNING: WMI failed, using default 1920x1080"
        $screenWidth = 1920
        $screenHeight = 1080
    }
}

# Load original image
try {
    $originalImg = [System.Drawing.Image]::FromFile($imgOriginal)
    $originalWidth = $originalImg.Width
    $originalHeight = $originalImg.Height
    
    Write-Log "Original image size: ${originalWidth}x${originalHeight}"
    
    # Calculate scaling to FILL screen (with crop if needed)
    $scaleX = $screenWidth / $originalWidth
    $scaleY = $screenHeight / $originalHeight
    $scale = [Math]::Max($scaleX, $scaleY)  # Use MAX to fill entire screen
    
    $scaledWidth = [int]($originalWidth * $scale)
    $scaledHeight = [int]($originalHeight * $scale)
    
    Write-Log "Scaled size: ${scaledWidth}x${scaledHeight}, scale: $scale"
    
    # Center the image
    $offsetX = [int](($screenWidth - $scaledWidth) / 2)
    $offsetY = [int](($screenHeight - $scaledHeight) / 2)
    
    Write-Log "Offset: X=$offsetX, Y=$offsetY"
    
    # Create final image
    $resizedImg = New-Object System.Drawing.Bitmap($screenWidth, $screenHeight)
    
    $gResize = [System.Drawing.Graphics]::FromImage($resizedImg)
    $gResize.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gResize.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gResize.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gResize.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    
    # Fill background with black (in case of aspect ratio mismatch)
    $gResize.Clear([System.Drawing.Color]::Black)
    
    # Draw scaled image
    $destRect = New-Object System.Drawing.Rectangle($offsetX, $offsetY, $scaledWidth, $scaledHeight)
    $srcRect = New-Object System.Drawing.Rectangle(0, 0, $originalWidth, $originalHeight)
    
    $gResize.DrawImage($originalImg, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    $gResize.Dispose()
    $originalImg.Dispose()
    
    Write-Log "Image loaded and resized with proper scaling"
} catch {
    Write-Log "ERROR loading image: $($_.Exception.Message)"
    exit 1
}

# Determine text position
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

Write-Log "Text position: $position, left margin: $leftMargin"

# Collect system information - get ACTUAL logged in user
$loggedInUser = $null
try {
    # Method 1: Get from current session
    $sessions = quser 2>$null | Select-Object -Skip 1
    foreach ($session in $sessions) {
        if ($session -match '(\S+)\s+(\S+)\s+(\d+)\s+Active') {
            $loggedInUser = $matches[1]
            break
        }
    }
    
    # Method 2: Fallback to registry
    if (-not $loggedInUser) {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
        if (Test-Path $regPath) {
            $lastUser = Get-ItemProperty -Path $regPath -Name "LastLoggedOnUser" -ErrorAction SilentlyContinue
            if ($lastUser) {
                $loggedInUser = $lastUser.LastLoggedOnUser -replace '^.*\\', ''
            }
        }
    }
    
    # Method 3: Ultimate fallback
    if (-not $loggedInUser) {
        $loggedInUser = $env:USERNAME
    }
} catch {
    $loggedInUser = $env:USERNAME
}

$hostname = $env:COMPUTERNAME
$cs = Get-CimInstance Win32_ComputerSystem
$domain = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }

Write-Log "Hostname: $hostname, User: $loggedInUser, Domain: $domain"

# Network adapters
$results = @()
$adapters = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {
    $_.InterfaceIndex -ne $null -and $_.Name -ne $null -and $_.NetEnabled -eq $true
}

Write-Log "Found active adapters: $($adapters.Count)"

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
            
            Write-Log "  - $($ip.IPAddress) | $interfaceName | $($adapter.Name)"
        }
    }
    catch { 
        Write-Log "  Error processing adapter $($adapter.Name): $($_.Exception.Message)"
        continue 
    }
}

# Build text lines
$textLines = @()
$textLines += ("{0,-13} {1}" -f "PC Name:", $hostname)
$textLines += ("{0,-13} {1}" -f "User:", $loggedInUser)
$textLines += ("{0,-13} {1}" -f "Domain:", $domain)
$textLines += ""

if ($results.Count -gt 0) {
    $textLines += "Network Adapters:"
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
        "IP Address", "Interface", "Adapter", "Speed")
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
    $textLines += "No active network adapters found"
}

Write-Log "Text lines: $($textLines.Count)"

# Draw text on image
try {
    $gText = [System.Drawing.Graphics]::FromImage($resizedImg)
    $gText.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gText.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    if ($isSmallResolution) {
        $fontSize = [Math]::Max([int]($screenWidth / 100), 8)
    } else {
        $fontSize = [Math]::Max([int]($screenWidth / 110), 12)
    }

    $font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)

    # Auto-adjust font size if text is too wide
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

    Write-Log "Font size: $fontSize"

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

    Write-Log "Text drawn successfully"

    # Save image
    $resizedImg.Save($imageDest, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Log "Image saved: $imageDest"

    # Cleanup resources
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

    # Save image
    $resizedImg.Save($imageDest, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Log "Image saved: $imageDest"
    
    # Verify file was created
    if (Test-Path $imageDest) {
        $fileSize = (Get-Item $imageDest).Length
        Write-Log "SUCCESS: File created, size: $fileSize bytes"
    } else {
        Write-Log "ERROR: File was NOT created!"
    }

    # Cleanup resources
    $gText.Dispose()
