@echo off
chcp 65001 >nul
cd /d "%~dp0.."
set ADB=C:\Users\drago\AppData\Local\Android\Sdk\platform-tools\adb.exe
echo Instalez versiunea noua pe telefon (curat)...
"%ADB%" install -r "build\app\outputs\flutter-apk\app-release.apk"
echo.
echo Daca da eroare de semnatura: mai intai
echo   "%ADB%" uninstall com.dragosssx.guessit
pause
