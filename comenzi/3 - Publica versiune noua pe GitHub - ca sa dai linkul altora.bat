@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo Publica versiunea noua pe GitHub Releases.
set /p VER="  Numar de versiune (ex. v1.0.2): "
call gh release create %VER% ^
  "build\app\outputs\flutter-apk\app-release.apk" ^
  "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" ^
  --title "%VER%" ^
  --notes "Timp real: resursele de la admin, redenumirile, anunturile, blocarile, mesajele si cererile de prietenie ajung instant, fara repornire. Oricine isi poate schimba numele. Ban reversibil. Mod nou: Piatra-Hartie-Foarfeca (alegere secreta, primul la 10, cu miza). Curatenie de cod."
echo.
echo   Copiaza textul de mai sus si trimite-l lui Claude.
pause
