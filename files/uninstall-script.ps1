# uninstall-script.ps1
Start-Sleep -Seconds 2

$taskName = "UpdateLockScreen"
$basePath = "C:\Program Files\UpdateLockScreen"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

Write-Host "Остановка процессов..." -ForegroundColor Yellow
try {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    
    Get-Process -Name "powershell" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Path -like "*UpdateLockScreen*" -or $_.CommandLine -like "*update-lockscreen.ps1*" } | 
        Stop-Process -Force -ErrorAction SilentlyContinue
    
    Get-Process -Name "wscript" -ErrorAction SilentlyContinue | 
        Where-Object { $_.CommandLine -like "*UpdateLockScreen*" } | 
        Stop-Process -Force -ErrorAction SilentlyContinue
    
    Write-Host "Процессы остановлены" -ForegroundColor Green
    Start-Sleep -Seconds 2
} catch {
    Write-Host "Ошибка при остановке процессов: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Удаление задачи планировщика..." -ForegroundColor Yellow
try {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Задача планировщика удалена" -ForegroundColor Green
    }
} catch {
    Write-Host "Не удалось удалить задачу: $($_.Exception.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 3

Write-Host "Удаление папки программы..." -ForegroundColor Yellow
try {
    if (Test-Path $basePath) {
        Remove-Item -Path $basePath -Recurse -Force -ErrorAction Stop
        Write-Host "Папка программы удалена: $basePath" -ForegroundColor Green
    }
} catch {
    Write-Host "Не удалось удалить папку: $($_.Exception.Message)" -ForegroundColor Red
    Start-Sleep -Seconds 2
    
    try {
        cmd.exe /c "rd /s /q `"$basePath`" 2>nul"
        Start-Sleep -Seconds 1
        
        if (-not (Test-Path $basePath)) {
            Write-Host "Папка удалена принудительно" -ForegroundColor Green
        }
    } catch {
        Write-Host "Критическая ошибка при удалении папки" -ForegroundColor Red
    }
}

Write-Host "Удаление записей реестра..." -ForegroundColor Yellow
try {
    if (Test-Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force -ErrorAction Stop
        Write-Host "Записи реестра удалены" -ForegroundColor Green
    }
} catch {
    Write-Host "Не удалось удалить записи реестра" -ForegroundColor Red
}

Write-Host "Очистка завершена!" -ForegroundColor Green
