@echo off
chcp 65001 >nul
title RESET COMPLET - sterge absolut tot - SodoQuizz
cd /d "%~dp0"

echo.
echo ============================================================
echo   RESET COMPLET - "ca si cum tocmai am scos aplicatia"
echo ============================================================
echo.
echo Sterge TOT din Firebase: fiecare profil, fiecare cont, fiecare
echo meci, prietenie, mesaj, raport, cadou in asteptare — absolut
echo tot ce exista azi in "sodoquizz". Dupa asta, oricine se
echo conecteaza porneste de la zero, ca un jucator complet nou.
echo.
echo   ATENTIE — asta e SCRIPTUL CEL MAI DISTRUCTIV din tot
echo   proiectul. Nu se poate anula. Nu atinge progresul salvat pe
echo   telefoane (e local), dar daca un telefon se reconecteaza
echo   dupa reset, isi RE-URCA singur progresul in cloud — deci
echo   pentru un reset care ramane curat, dezinstaleaza intai
echo   aplicatia de pe orice telefon de test.
echo.
echo   Se sterge inclusiv contul TAU de admin din Authentication —
echo   ramai admin la relogare (regula verifica emailul, nu uid-ul).
echo.

python tools\reset_all.py
if errorlevel 1 goto :eroare

echo.
echo ============================================================
echo.

REM Totul deja gol -> scriptul a scris "gol deja" la Firestore SI
REM "niciun cont" la Authentication; nu mai intrebam nimic.
python -c "import sys,os;sys.path.insert(0,'tools');import reset_all as r;s=r.session();t,_=r.collect_targets(s);a=r.list_accounts(s);sys.exit(3 if not t and not a else 0)" 2>nul
if errorlevel 3 goto :gata

echo   Verifica numerele de mai sus. Odata apasat DA, nu mai exista
echo   drum inapoi — nici un backup automat, nici un "undo".
echo.
set /p RASPUNS="  Sterg ABSOLUT TOT? Scrie DA ca sa confirmi: "
echo.

if /i "%RASPUNS%"=="DA" goto :sterge

echo   Anulat. Nu s-a sters nimic.
goto :gata

:sterge
python tools\reset_all.py --sterge
goto :gata

:eroare
echo.
echo   Ceva n-a mers. Mesajul de mai sus spune ce.
echo   Daca scrie ca lipseste service-account.json, cheia trebuie
echo   pusa in tools\ - vezi comentariul din tools\purge_accounts.py.

:gata
echo.
pause
