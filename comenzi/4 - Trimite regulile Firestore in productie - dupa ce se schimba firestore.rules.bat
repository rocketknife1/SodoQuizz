@echo off
chcp 65001 >nul
title Deploy reguli + indexuri Firestore - SodoQuizz
cd /d "%~dp0.."
echo ============================================================
echo   TRIMITE REGULILE SI INDEXURILE FIRESTORE IN PRODUCTIE
echo ============================================================
echo.
echo   "Regulile" (firestore.rules) = cine are voie sa citeasca /
echo   scrie ce in baza de date. "Indexurile" (firestore.indexes.json)
echo   = ce interogari cu sortare pe doua campuri sunt permise
echo   (fara ele, clasamentele apar goale).
echo.
echo   Se ruleaza DOAR dupa ce eu ti-am zis ca am schimbat unul
echo   din cele doua fisiere. Daca n-am zis nimic, nu e nevoie.
echo.
echo   Nu atinge datele jucatorilor. Efect imediat.
echo.
call firebase.cmd deploy --only firestore:rules,firestore:indexes --project sodoquizz
echo.
echo ============================================================
echo   Gata. Daca a scris "Deploy complete", e trimis.
echo   Daca a scris erori, copiaza tot textul si trimite-mi-l.
echo ============================================================
pause
