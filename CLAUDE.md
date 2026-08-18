# Cum lucrez pe proiectul ăsta

Notă de stil de lucru, scrisă după o sesiune pe alt proiect Flutter
(`organizator`) unde ritmul ăsta a mers bine: modificări rapide, testate
direct pe telefonul fizic, fără să aștept confirmare la fiecare pas mic.
Combină regulile de mai jos cu ce există deja aici — `docs/build.md`,
`tools/*.py`, `test/*.dart` — nu le înlocuiește.

## Principiul de bază

Nu aștept confirmare după fiecare modificare mică. Editez → construiesc →
instalez pe telefon → verific → raportez ce am găsit, într-un ciclu continuu.
Opresc și întreb doar la decizii reale (ștergere de date, push, schimbări
ireversibile), nu la fiecare pas tehnic.

„Ar trebui să meargă" nu e o concluzie. Verific pe dispozitivul real, cu
dovadă (captură de ecran, log, `dumpsys`), înainte să spun că ceva
funcționează.

## Bucla de verificare pe telefon

1. `flutter analyze` — rapid, prinde greșeli înainte să pierd timp cu build.
2. `flutter test` — pentru logica pură (`test/*.dart` — vezi
   `game_logic_test.dart`, `economy_balance_test.dart` etc., deja existente).
3. Build + instalare pe telefon, verificare vizuală/log reală.
4. Dacă ceva nu merge: nu ghicesc a doua reparație — caut cauza exactă în
   `logcat` sau `dumpsys` înainte de următoarea încercare.

Build-urile Gradle durează (15s–100s+, uneori mai mult la `assembleRelease`
sau prima compilare). Le pornesc cu `run_in_background: true` și citesc
fișierul de output când vin notificat — nu aștept cu `sleep` în buclă.

## Toolkit adb (Windows / Git Bash)

Calea adb pe mașina asta: `C:\Users\drago\AppData\Local\Android\Sdk\platform-tools\adb.exe`
(`Sdk` cu S mare — verifică, diferă uneori de alte proiecte).

**Important în Git Bash**: orice cale gen `/sdcard/...` trebuie prefixată cu
`MSYS_NO_PATHCONV=1`, altfel MSYS o transformă într-o cale Windows greșită
(`C:/Program Files/Git/sdcard/...`) și comanda eșuează silențios sau explicit.

```bash
ADB="/c/Users/drago/AppData/Local/Android/Sdk/platform-tools/adb.exe"

# instalează păstrând datele existente (NU flutter install, care dezinstalează întâi)
MSYS_NO_PATHCONV=1 "$ADB" install -r build/app/outputs/flutter-apk/app-release.apk

# captură de ecran ca dovadă vizuală
MSYS_NO_PATHCONV=1 "$ADB" shell screencap -p /sdcard/s.png
MSYS_NO_PATHCONV=1 "$ADB" pull /sdcard/s.png "<scratchpad>/s.png"
# apoi Read pe fișierul local ca să văd efectiv ecranul

# stare ecran (blocat/treaz) — esențial înainte de captură sau test cu ecran blocat
MSYS_NO_PATHCONV=1 "$ADB" shell dumpsys window | grep -iE "mAwake|mDreamingLockscreen"
MSYS_NO_PATHCONV=1 "$ADB" shell input keyevent KEYCODE_WAKEUP

# ține ecranul treaz în timpul unui test lung (frame-urile cu ecranul stins
# produc zgomot fals — vezi „debugFrameWasSentToEngine" mai jos)
MSYS_NO_PATHCONV=1 "$ADB" shell svc power stayon true    # ...true de deblocheaza manual pt debug/test

# alarme/notificări programate — util pentru orice ține de reminder-e/background
MSYS_NO_PATHCONV=1 "$ADB" shell dumpsys alarm | grep -i "com.dragosssx.guessit"
MSYS_NO_PATHCONV=1 "$ADB" shell dumpsys notification --noredact | grep -oE 'android\.title=String \([^)]*\)'

# permisiuni acordate
MSYS_NO_PATHCONV=1 "$ADB" shell dumpsys package com.dragosssx.guessit | grep "granted="

# log filtrat pe pachet, în jurul unui moment exact (nu tot logcat-ul)
MSYS_NO_PATHCONV=1 "$ADB" logcat -d -v time | awk '/HH:MM:SS/,/HH:MM:SS/' | grep -i guessit
```

Verifică ce APK e efectiv pe telefon vs. ultimul build local, când nu ești
sigur dacă ai instalat ultima versiune:

```bash
sha256sum build/app/outputs/flutter-apk/app-release.apk
MSYS_NO_PATHCONV=1 "$ADB" shell pm path com.dragosssx.guessit   # dă calea base.apk
MSYS_NO_PATHCONV=1 "$ADB" pull <calea de mai sus> installed.apk && sha256sum installed.apk
```

## Capcane găsite deja (aplică-le direct, nu le redescoperi)

- **R8/ProGuard rupe lucruri doar în `--release`, tăcut.** Minificarea poate
  șterge informație de tipuri generice de care depinde reflecția (Gson,
  serializare). Un bug de genul ăsta trece nedetectat prin `flutter test` și
  prin orice test rulat în debug — apare *doar* când testezi chiar build-ul
  de release, pe dispozitiv real. Dacă ceva depinde de reflecție/serializare
  și proiectul are `minifyEnabled true` (verifică `android/app/build.gradle`),
  testează explicit `--release`, nu doar debug.
- **`flutter test integration_test/...` dezinstalează aplicația la final** —
  chiar dacă testul însuși folosește o bază de date izolată, unealta șterge
  tot pachetul de pe telefon când termină, luând cu ea orice date locale
  reale (progres, monede, cache). **Nu rula teste de integrare pe telefonul
  cu date reale fără să întrebi explicit înainte.** Pentru verificare rapidă
  preferă comenzi `adb` directe (tap/screenshot/dumpsys), nu harness-ul de
  integration_test.
- Ecranul blocat/stins în timpul unui test automatizat produce erori false
  (`'debugFrameWasSentToEngine': is not true`) — nu e un bug real, e ecranul
  oprit. Ține-l treaz (`svc power stayon true`) cât rulează verificarea.
- Permisiunile Android cerute concurent (notificări, etc.) pot arunca
  `PlatformException(...RequestInProgress)` dacă se cer de două ori rapid
  (ex. două lansări ale aplicației în aceeași sesiune de test) — dacă apare,
  nu e neapărat bug de aplicație, verifică dacă e coliziune de request.

## Publicare — folosește ce există deja aici, nu alt canal

Acest proiect are deja pipeline: `flutter build apk --release` (unități
AdMob de test by default) → `gh release create` (vezi `docs/build.md`).
**Nu** încărca APK-uri pe hosturi terțe (gen catbox/file.io) pentru distribuție
publică — asta a fost un compromis specific altui proiect fără cont de
dezvoltator; aici există deja canalul corect (GitHub Releases + `LINKS.md`).

## Scripturile Python din `tools/`

`tools/purge_*.py`, `tools/firestore_cleanup.py` etc. ating date reale din
Firestore (conturi, meciuri). Tratează-le cu aceeași grijă ca operațiile
distructive pe telefon: rulează întâi în modul raportare (fără `--sterge`
sau echivalent) și confirmă cu utilizatorul înainte de a aplica efectiv.

## Onestitate la greșeli

Dacă o acțiune de-a mea a stricat ceva (date pierdute, build greșit
instalat), spun direct și clar, explic cauza reală (nu doar simptomul), și
schimb procesul ca să nu se repete — nu doar reinstalez și tac.
