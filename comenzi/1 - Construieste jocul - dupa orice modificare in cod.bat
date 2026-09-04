@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo ============================================
echo   Construieste jocul (APK pentru telefon)
echo ============================================
echo.
echo   Dureaza cateva minute. Nu inchide fereastra.
echo.
call flutter build apk --release --dart-define=APPCHECK_DEBUG=true
echo.
echo ============================================
echo   Gata. Daca scrie "Built ... app-release.apk", a mers.
echo   Urmatorul pas: comanda 2, ca sa-l pui pe telefon.
echo ============================================
pause
