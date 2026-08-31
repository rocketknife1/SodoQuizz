@echo off
cd /d "%~dp0.."
echo ============================================
echo   Deploy reguli Firestore (banned_players + completed_matches)
echo ============================================
echo.
call firebase.cmd deploy --only firestore:rules
echo.
echo ============================================
echo   Gata. Copiaza tot textul de mai sus si trimite-l lui Claude.
echo ============================================
pause
