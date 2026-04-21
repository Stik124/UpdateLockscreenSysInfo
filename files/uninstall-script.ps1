# uninstall-script.ps1 - Скрипт для удаления
 
Start-Sleep -Seconds 2

$taskName = "UpdateLockScreen"
$basePath = "C:\Program Files\UpdateLockScreen"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

Write-Host "Остановка всех процессов..." -ForegroundColor Yellow
try {
    # Останавливаем задачу если она запущена
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    
    # Убиваем все процессы PowerShell, которые могут использовать наши файлы
    Get-Process -Name "powershell" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Path -like "*UpdateLockScreen*" -or $_.CommandLine -like "*update-lockscreen.ps1*" } | 
        Stop-Process -Force -ErrorAction SilentlyContinue
    
    # Убиваем все процессы WScript
    Get-Process -Name "wscript" -ErrorAction SilentlyContinue | 
        Where-Object { $_.CommandLine -like "*UpdateLockScreen*" } | 
        Stop-Process -Force -ErrorAction SilentlyContinue
    
    Write-Host "✅ Процессы остановлены" -ForegroundColor Green
    Start-Sleep -Seconds 2
} catch {
    Write-Host "⚠️ Ошибка при остановке процессов: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Удаление задачи планировщика..." -ForegroundColor Yellow
try {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "✅ Задача планировщика удалена" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ Задача планировщика не найдена" -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️ Не удалось удалить задачу: $($_.Exception.Message)" -ForegroundColor Red
}

# Ждем чтобы все процессы точно завершились
Start-Sleep -Seconds 3

Write-Host "Удаление папки программы..." -ForegroundColor Yellow
try {
    if (Test-Path $basePath) {
        # Сначала пытаемся стандартным способом
        Remove-Item -Path $basePath -Recurse -Force -ErrorAction Stop
        Write-Host "✅ Папка программы удалена: $basePath" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ Папка программы не найдена: $basePath" -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️ Не удалось удалить папку: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "⚠️ Попытка принудительного удаления..." -ForegroundColor Yellow
    
    Start-Sleep -Seconds 2
    
    # Принудительное удаление через cmd
    try {
        cmd.exe /c "rd /s /q `"$basePath`" 2>nul"
        Start-Sleep -Seconds 1
        
        if (-not (Test-Path $basePath)) {
            Write-Host "✅ Папка удалена принудительно" -ForegroundColor Green
        } else {
            Write-Host "❌ Не удалось удалить папку даже принудительно" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Критическая ошибка при удалении папки: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Удаление записей реестра..." -ForegroundColor Yellow
try {
    if (Test-Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force -ErrorAction Stop
        Write-Host "✅ Записи реестра удалены: $registryPath" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ Записи реестра не найдены: $registryPath" -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️ Не удалось удалить записи реестра: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "ℹ️ Возможно, требуются права администратора" -ForegroundColor Yellow
}

Write-Host "Очистка завершена!" -ForegroundColor Green
