@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo Publica versiunea noua pe GitHub Releases.
set /p VER="  Numar de versiune (ex. v1.0.2): "
call gh release create %VER% ^
  "build\app\outputs\flutter-apk\app-release.apk" ^
  --title "%VER%" ^
  --notes "Tot ce vine din exterior ajunge instant, fara repornire: resurse de la admin, redenumiri, anunturi, blocari, mesaje, cereri de prietenie. Oricine isi poate schimba numele, inclusiv pe cont Google. Ban reversibil. Mod nou: Piatra-Hartie-Foarfeca. Animatiile merg pe renderer-ul nou (Vulkan). Colectarea recompenselor misca cifra cand jetonul aterizeaza, nu inainte."
echo.
echo   Copiaza textul de mai sus si trimite-l lui Claude.
pause
