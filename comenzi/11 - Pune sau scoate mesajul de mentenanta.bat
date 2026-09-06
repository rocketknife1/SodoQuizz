@echo off
chcp 65001 >nul
title Mesaj de mentenanta - SodoQuizz
cd /d "%~dp0.."

echo.
echo ============================================================
echo   MESAJUL DE MENTENANTA (ecranul "Revenim imediat")
echo ============================================================
echo.
echo   Cand e APRINS, TOTI jucatorii vad un ecran peste joc cu
echo   mesajul tau si o bara care se misca. Nu pot juca pana nu-l
echo   stingi. Se foloseste cand faci ceva pe server si nu vrei
echo   pe nimeni in joc intre timp.
echo.
echo   Aplicatiile deja deschise il iau in cel mult ~1 ora, sau
echo   imediat daca jucatorul reporneste aplicatia.
echo.

python tools\maintenance.py
if errorlevel 1 goto :eroare

echo.
echo   Alege:
echo     [A] Aprind mentenanta  (o sa-mi ceara mesajul)
echo     [S] Sting mentenanta   (jocul revine pentru toti)
echo     [N] Nu fac nimic
echo.
set /p RASPUNS="  Ce fac? (A/S/N): "
echo.

if /i "%RASPUNS%"=="A" goto :aprinde
if /i "%RASPUNS%"=="S" goto :stinge

echo   Nu s-a schimbat nimic.
goto :gata

:aprinde
echo.
set /p MESAJ="  Scrie mesajul (ex: Revenim in 30 de minute): "
echo.
python tools\maintenance.py --pune "%MESAJ%"
goto :gata

:stinge
python tools\maintenance.py --scoate
goto :gata

:eroare
echo.
echo   Ceva n-a mers. Copiaza textul de mai sus si trimite-mi-l.
echo   Daca scrie ca lipseste service-account.json, vezi
echo   CITESTE-MA din folderul asta.

:gata
echo.
pause
