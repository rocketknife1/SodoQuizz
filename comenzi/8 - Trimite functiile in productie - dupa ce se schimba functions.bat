@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo ============================================
echo   Trimite functiile de server in productie
echo ============================================
echo.
echo   Astea trimit notificarile push (invitatii, mesaje) si
echo   supravegheaza balantele. Se trimit doar dupa ce s-a
echo   modificat ceva in folderul "functions".
echo.
call firebase.cmd deploy --only functions --project sodoquizz
echo.
echo ============================================
echo   Gata. Copiaza tot textul de mai sus si trimite-l lui Claude.
echo ============================================
pause
