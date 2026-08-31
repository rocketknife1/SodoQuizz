@echo off
chcp 65001 >nul
cd /d "%~dp0.."
set ADB=C:\Users\drago\AppData\Local\Android\Sdk\platform-tools\adb.exe
echo Dezinstalez jocul de pe telefon (ca sa nu re-urce date dupa reset)...
"%ADB%" uninstall com.dragosssx.guessit
pause
