@echo off
chcp 65001 >nul
title Rapoartele jucatorilor - SodoQuizz
cd /d "%~dp0.."

echo.
echo ============================================================
echo   RAPOARTELE JUCATORILOR
echo ============================================================
echo.
echo   Aduna toate rapoartele din joc intr-un singur loc:
echo     - blocaje / crash-uri  (butonul "Trimite raportul")
echo     - intrebari gresite     (raspuns / poza / typo)
echo     - jucator raporteaza jucator (limbaj, comportament)
echo.
echo   Le scrie si intr-un fisier (rapoarte\ULTIMUL.md) ca sa
echo   ramana. Cand vrei sa repar ceva dintr-un raport, spune-mi
echo   si il citesc de acolo.
echo.

python tools\view_reports.py %*

echo.
echo ============================================================
echo   Gata. Fisierul e in folderul "rapoarte".
echo   Ca sa vezi doar cele NErezolvate:  trage bat-ul asta si
echo   adauga  --noi  la sfarsit, sau spune-mi si rulez eu.
echo ============================================================
pause
