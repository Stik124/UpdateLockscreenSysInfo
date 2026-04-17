# build-msi.ps1
param(
    [string]$Version = "1.0.0.$env:GITHUB_RUN_NUMBER",
    [string]$OutputPath = ".\Dist"
)

Write-Host "Сборка MSI..." -ForegroundColor Green

# Создаем выходную директорию
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force
}

# Пути к WiX
# $WIX_PATH = "C:\Program Files (x86)\WiX Toolset v3.14\bin"
# $CANDLE = Join-Path $WIX_PATH "candle.exe"
# $LIGHT = Join-Path $WIX_PATH "light.exe"
$CANDLE = "candle.exe"
$LIGHT = "light.exe"

Write-Host "Cleaning..." -ForegroundColor Yellow
Remove-Item "*.wixobj" -ErrorAction SilentlyContinue
Remove-Item "*.wixpdb" -ErrorAction SilentlyContinue

# Проверяем файлы
if (!(Test-Path "files\install-script.ps1") -or 
    !(Test-Path "files\uninstall-script.ps1") -or 
    !(Test-Path "files\background.jpg")) {
    Write-Error " Файлы не найдены! Требуются: install-script.ps1, uninstall-script.ps1, background.jpg"
    exit 1
}

Write-Host " Все файлы найдены" -ForegroundColor Green


Write-Host "Компиляция..." -ForegroundColor Yellow
& $CANDLE -dVersion=$Version "Product.wxs"

if ($LASTEXITCODE -eq 0) {
    Write-Host " Компиляция успешна" -ForegroundColor Green
    
    Write-Host "Линковка..." -ForegroundColor Yellow
    
    # Для варианта с WixQuietExec нужен WixUtilExtension
    & $LIGHT -ext WixUtilExtension -out "$OutputPath\UpdateLockScreen-$Version.msi" "Product.wixobj"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host " MSI успешно собран!" -ForegroundColor Green
        Write-Host " Файл: $OutputPath\UpdateLockScreen-$Version.msi" -ForegroundColor Cyan
        
        # Очистка
        Remove-Item "*.wixobj" -ErrorAction SilentlyContinue
        Remove-Item "*.wixpdb" -ErrorAction SilentlyContinue
        
        Write-Host " Готово! Custom Action будет выполнен при установке." -ForegroundColor Cyan
        
        # Информация
        $msiPath = "$OutputPath\UpdateLockScreen-$Version.msi"
        if (Test-Path $msiPath) {
            $msiFile = Get-Item $msiPath
            Write-Host "Размер: $([math]::Round($msiFile.Length/1KB, 2)) KB" -ForegroundColor Yellow
        }
    }
    else {
        Write-Error " Ошибка линковки"
    }
}
else {
    Write-Error " Compilation error"
}
