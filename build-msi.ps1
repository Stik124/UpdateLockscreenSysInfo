param(
    [string]$Version = "1.0.0." + $env:GITHUB_RUN_NUMBER,
    [string]$OutputPath = ".\Dist"
)

Write-Host "Version: $Version"
Write-Host "Сборка MSI..." -ForegroundColor Green

# Создаем выходную директорию
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$CANDLE = "candle.exe"
$LIGHT = "light.exe"

Write-Host "Cleaning..." -ForegroundColor Yellow
Remove-Item "*.wixobj" -ErrorAction SilentlyContinue
Remove-Item "*.wixpdb" -ErrorAction SilentlyContinue

# Проверяем файлы
$required = @("files\install-script.ps1", "files\uninstall-script.ps1", "files\background.jpg")
foreach ($f in $required) {
    if (!(Test-Path $f)) {
        Write-Error "Не найден файл: $f"
        exit 1
    }
}
Write-Host "Все файлы найдены" -ForegroundColor Green

# Подставляем версию в Product.wxs
(Get-Content Product.wxs) -replace 'VERSION_PLACEHOLDER', $Version | Set-Content Product.build.wxs

Write-Host "Компиляция..." -ForegroundColor Yellow
& $CANDLE Product.build.wxs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Ошибка компиляции candle.exe. Проверьте Product.build.wxs"
    exit 1
}
Write-Host "Компиляция успешна" -ForegroundColor Green

Write-Host "Линковка..." -ForegroundColor Yellow
& $LIGHT -ext WixUtilExtension -out "$OutputPath\UpdateLockScreen-$Version.msi" "Product.build.wixobj"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Ошибка линковки light.exe. Проверьте наличие WixUtilExtension"
    exit 1
}
Write-Host "MSI успешно собран: $OutputPath\UpdateLockScreen-$Version.msi" -ForegroundColor Green

# Очистка
Remove-Item "*.wixobj" -ErrorAction SilentlyContinue
Remove-Item "*.wixpdb" -ErrorAction SilentlyContinue

# Информация о файле
if (Test-Path "$OutputPath\UpdateLockScreen-$Version.msi") {
    $msiFile = Get-Item "$OutputPath\UpdateLockScreen-$Version.msi"
    Write-Host "Размер: $([math]::Round($msiFile.Length/1KB, 2)) KB" -ForegroundColor Yellow
}
