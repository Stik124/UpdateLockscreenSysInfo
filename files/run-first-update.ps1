# run-first-update.ps1 - Асинхронный первый запуск
Start-Sleep -Seconds 3
Start-ScheduledTask -TaskName "UpdateLockScreen" -ErrorAction SilentlyContinue
