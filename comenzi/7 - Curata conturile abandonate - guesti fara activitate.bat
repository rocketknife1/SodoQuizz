@echo off
chcp 65001 >nul
title Curata conturi din Firebase Authentication - SodoQuizz
cd /d "%~dp0.."

echo.
echo ============================================================
echo   CURATARE CONTURI DIN FIREBASE AUTHENTICATION
echo ============================================================
echo.
echo Conturile de mai jos au fost deja sterse din joc (profil,
echo prieteni, salvare in cloud). A ramas doar identitatea lor
echo din Authentication, care se sterge doar de aici.
echo.

python tools\purge_accounts.py --lista
if errorlevel 1 goto :eroare

echo.
echo ============================================================
echo.

REM Nimic in coada -> scriptul a scris "Nimic de facut", iesim fara
REM sa mai intrebam nimic.
python -c "import sys,os;sys.path.insert(0,'tools');import purge_accounts as p;s=p._session();sys.exit(0 if p.queued(s) else 3)" 2>nul
if errorlevel 3 goto :gata

echo   ATENTIE: stergerea de mai jos este DEFINITIVA.
echo   Verifica lista de mai sus. Daca vezi acolo un cont care NU
echo   trebuie sters (de exemplu contul tau), raspunde N si spune-mi.
echo.
set /p RASPUNS="  Sterg conturile de mai sus din Authentication? (D/N): "
echo.

if /i "%RASPUNS%"=="D" goto :sterge
if /i "%RASPUNS%"=="DA" goto :sterge

echo   Anulat. Nu s-a sters nimic.
goto :gata

:sterge
python tools\purge_accounts.py --sterge
goto :gata

:eroare
echo.
echo   Ceva n-a mers. Mesajul de mai sus spune ce.
echo   Daca scrie ca lipseste service-account.json, cheia trebuie
echo   pusa in tools\ - vezi comentariul din purge_accounts.py.

:gata
echo.
pause
