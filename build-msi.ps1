param(
    [string]$Version = "1.0.0." + $env:GITHUB_RUN_NUMBER,
    [string]$OutputPath = ".\Dist"
)

Write-Host "Version: $Version"
Write-Host "Building MSI..." -ForegroundColor Green

if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$CANDLE = "candle.exe"
$LIGHT = "light.exe"

Write-Host "Cleaning..." -ForegroundColor Yellow
Remove-Item "*.wixobj" -ErrorAction SilentlyContinue
Remove-Item "*.wixpdb" -ErrorAction SilentlyContinue

Write-Host "Checking required files..." -ForegroundColor Yellow
$requiredFiles = @(
    "files\install-task.ps1",
    "files\run-first-update.ps1",
    "files\uninstall-script.ps1",
    "files\background.jpg"
)

foreach ($file in $requiredFiles) {
    if (!(Test-Path $file)) {
        Write-Error "Missing: $file"
        exit 1
    }
}
Write-Host "All files found" -ForegroundColor Green

Write-Host "Generating Product.build.wxs..." -ForegroundColor Yellow
(Get-Content Product.wxs) -replace 'VERSION_PLACEHOLDER', $Version | Set-Content Product.build.wxs

Write-Host "Compiling..." -ForegroundColor Yellow
& $CANDLE Product.build.wxs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed"
    exit 1
}

Write-Host "Compilation successful" -ForegroundColor Green

Write-Host "Linking..." -ForegroundColor Yellow
& $LIGHT -ext WixUtilExtension -out "$OutputPath\UpdateLockScreen-$Version.msi" "Product.build.wixobj"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Linking failed"
    exit 1
}

Write-Host "MSI built successfully!" -ForegroundColor Green

Remove-Item "*.wixobj" -ErrorAction SilentlyContinue
Remove-Item "*.wixpdb" -ErrorAction SilentlyContinue

$msiPath = "$OutputPath\UpdateLockScreen-$Version.msi"
if (Test-Path $msiPath) {
    $msiFile = Get-Item $msiPath
    $sizeKB = [math]::Round($msiFile.Length / 1KB, 2)
    Write-Host "Size: $sizeKB KB" -ForegroundColor Yellow
    Write-Host "Path: $msiPath" -ForegroundColor Cyan
}

$requiredFiles = @(
    "files\install-task.ps1",
    "files\update-lockscreen.ps1",
    "files\run-first-update.ps1",
    "files\uninstall-script.ps1",
    "files\background.jpg"
)
