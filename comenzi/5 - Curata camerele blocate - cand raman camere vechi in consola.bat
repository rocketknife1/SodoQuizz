@echo off
chcp 65001 >nul
title Curata camerele multiplayer blocate - SodoQuizz
cd /d "%~dp0.."

echo.
echo ============================================================
echo   CURATARE CAMERE MULTIPLAYER BLOCATE
echo ============================================================
echo.
echo Colectia `matches` tine camerele meciurilor IN DESFASURARE.
echo O camera se sterge singura doar daca ultimul jucator apasa
echo butonul de iesire. Daca lumea inchide aplicatia din task
echo switcher sau pierde netul, camera ramane acolo pe veci.
echo.
echo   Nu strica nimic in joc - camerele vechi nu apar nicaieri
echo   si nu intra in matchmaking. Doar se aduna in consola.
echo.
echo   ATENTIE: un meci care CHIAR se joaca acum e tot o camera.
echo   De-asta implicit se sterg doar cele mai vechi de 6 ore.
echo.

python tools\purge_stale_matches.py --lista
if errorlevel 1 goto :eroare

echo.
echo ============================================================
echo.

REM Nimic vechi -> scriptul a scris "Nimic de facut", iesim fara
REM sa mai intrebam nimic.
python -c "import sys,os;sys.path.insert(0,'tools');import purge_stale_matches as p;s=p._session();sys.exit(0 if p.older_than(p.rooms(s), p.ORE_IMPLICIT) else 3)" 2>nul
if errorlevel 3 goto :gata

echo   Alege:
echo     [V] Sterg camerele mai vechi de 6 ore  (recomandat)
echo     [T] Sterg TOATE camerele, chiar si cele de acum
echo     [N] Nu sterg nimic
echo.
set /p RASPUNS="  Ce fac? (V/T/N): "
echo.

if /i "%RASPUNS%"=="V" goto :vechi
if /i "%RASPUNS%"=="T" goto :tot

echo   Anulat. Nu s-a sters nimic.
goto :gata

:vechi
python tools\purge_stale_matches.py --sterge
goto :gata

:tot
echo   ATENTIE: daca cineva joaca acum, ii rupi meciul.
set /p SIGUR="  Sigur? Scrie DA ca sa confirmi: "
if /i not "%SIGUR%"=="DA" (
  echo   Anulat.
  goto :gata
)
python tools\purge_stale_matches.py --toate --sterge
goto :gata

:eroare
echo.
echo   Ceva n-a mers. Mesajul de mai sus spune ce.
echo   Daca scrie ca lipseste service-account.json, cheia trebuie
echo   pusa in tools\ - e aceeasi cheie ca la "Curata conturi Auth.bat".

:gata
echo.
pause
