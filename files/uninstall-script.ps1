# uninstall-script.ps1 - Скрипт для удаления
 
Start-Sleep -Seconds 2   # небольшая пауза

$taskName = "UpdateLockScreen"
$basePath = "C:\Program Files\UpdateLockScreen"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

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

Write-Host "Удаление папки программы..." -ForegroundColor Yellow
try {
    if (Test-Path $basePath) {
		
        # Удаляем папку рекурсивно
        Remove-Item -Path $basePath -Recurse -Force -ErrorAction Stop
        Write-Host "✅ Папка программы удалена: $basePath" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ Папка программы не найдена: $basePath" -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️ Не удалось удалить папку: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "⚠️ Попытка принудительного удаления..." -ForegroundColor Yellow
    
    # Принудительное удаление через cmd
    try {
        cmd.exe /c "rd /s /q `"$basePath`" 2>nul"
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
