@echo off
chcp 65001 >nul
title Curata jurnalul de meciuri terminate - Sodo Quizz
cd /d "%~dp0.."

echo.
echo ============================================================
echo   CURATARE JURNAL DE MECIURI TERMINATE
echo ============================================================
echo.
echo Colectia `completed_matches` tine cate un rand per meci
echo multiplayer incheiat. Nu tine progresul nimanui: e folosita
echo DOAR pentru contorul "meciuri jucate" din panoul de admin.
echo.
echo   ATENTIE: dupa stergere, contorul ala pica la zero.
echo   Jucatorii, monedele, clasamentul si statisticile lor
echo   personale sunt in alta parte si NU se ating.
echo.

python tools\purge_completed_matches.py --lista
if errorlevel 1 goto :eroare

echo.
echo ============================================================
echo.

REM Jurnal gol -> scriptul a scris "Nimic de facut", iesim fara sa
REM mai intrebam nimic.
python -c "import sys,os;sys.path.insert(0,'tools');import purge_completed_matches as p;s=p._session();sys.exit(0 if p.completed(s) else 3)" 2>nul
if errorlevel 3 goto :gata

echo   Alege:
echo     [T] Sterg TOT jurnalul
echo     [V] Sterg doar meciurile mai vechi de 7 zile
echo     [N] Nu sterg nimic
echo.
set /p RASPUNS="  Ce fac? (T/V/N): "
echo.

if /i "%RASPUNS%"=="T" goto :tot
if /i "%RASPUNS%"=="V" goto :vechi

echo   Anulat. Nu s-a sters nimic.
goto :gata

:tot
python tools\purge_completed_matches.py --sterge
goto :gata

:vechi
python tools\purge_completed_matches.py --zile 7 --sterge
goto :gata

:eroare
echo.
echo   Ceva n-a mers. Mesajul de mai sus spune ce.
echo   Daca scrie ca lipseste service-account.json, cheia trebuie
echo   pusa in tools\ - e aceeasi cheie ca la "Curata conturi Auth.bat".

:gata
echo.
pause
