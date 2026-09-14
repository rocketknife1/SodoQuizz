# Ce mai e de făcut

Doar task-uri deschise. Ce s-a rezolvat stă în git + memorii, NU aici.
Notele de lucru pentru Claude sunt în memorii, nu aici.
Ultima curățare: 2026-09-07 (după feedback-ul GPT pe raport).

---

## URMĂTORUL VAL — retenție (feedback GPT, 2026-09-07)

**Diagnosticul GPT:** jocul NU mai duce lipsă de funcții. Fundația e bogată.
Problema e „care dintre funcțiile existente devine motivul principal de
revenire?" — se **consolidează**, nu se mai îngrămădește. Note GPT: Produs
8/10, Varietate 9/10, Fundație 8/10, Retenție potențială 7/10,
**Multiplayer la 0 jucători 4/10**, Securitate competitivă 6/10.

Ordinea de atac (a mea, ajustată față de a lui):

1. ✅ **Analytics de produs — funnel + per-mod** — LIVRAT 2026-09-07 (`0c5e752`).
   Pâlnia: `funnel_prima_partida / funnel_primul_multiplayer /
   funnel_prima_victorie` (o dată pe cont, `hitMilestoneOnce`) + first_open
   și retenția D1/D7 gratis de la Firebase. Multiplayer: `mp_start`,
   `mp_final {mod, castigat}`, `mp_revansa {mod, tip}` — nu era măsurat deloc.
   Abandon = `mp_start − mp_final` pe mod. `categorie_deblocata` wired.
   **De văzut în Firebase Analytics după ce intră trafic real.**

2. ✅ **Async Challenge — „Provoacă un prieten"** — LIVRAT 2026-09-07
   (`b7cb9ce`). Buton ⚔️ pe fiecare rând de prieten → joci 10 întrebări →
   share cod (`guessit://challenge/<id>`). Prietenul intră când poate,
   primește EXACT aceeași rundă → rezultat comparativ + recompense
   (120/60/0 monede + XP, plafon 5/zi). Push la creator când răspunde
   (`onChallengeAnswered`). Titlu nou „Aruncătoru' de Mănuși" la 15 câștigate.
   Reguli + funcție deployate. ✅ VERIFICAT cap-la-cap 2026-09-07 (telefon
   creează → browser intră cu codul → ACELEAȘI 10 întrebări → „YOU WON"
   1840 vs 890 → push la creator 1/1). Bug reparat pe drum (`39566d2`):
   creatorul și adversarul primeau seturi diferite de întrebări.

3. ✅ **Personal Records** — LIVRAT 2026-09-08. Tab-ul „Al tău" are acum
   secțiunea „Recordurile tale": cel mai mare scor, cel mai rapid răspuns
   corect, cea mai bună/slabă categorie (accuracy), „+X întrebări în 7
   zile" (instantaneu săptămânal, o dată/zi, FIFO 8). Tracking nou:
   `recordAnswerSpeed`, `recordCategoryAnswer`, `maybeTakeWeeklySnapshot`.

4. ✅ **Category Mastery** — LIVRAT 2026-09-08. `core/category_mastery.dart`:
   per categorie (întrebări văzute / accuracy / cel mai lung streak),
   „stăpânită" la 60 răspunsuri + 60%+. Ecran nou „Măiestrie pe categorii"
   din Profil. Titlu nou „Colecționar de Diplome" la 3 categorii
   (achievement `category_master_3`).

5. ✅ **Modul zilei în multiplayer** — LIVRAT 2026-09-08.
   `core/daily_mode.dart#modeOfDay` determinist dintr-un pool 1-la-1
   (Clasic / Higher & Lower / Piatra-Hartie). Join Online joacă modul
   zilei (nu mai alege aleator). Banner „🔥 AZI ÎN MECI RAPID" + bonus flat
   20 monede / 8 XP o dată/zi. FĂRĂ clasament separat — sezonul acoperă deja.

6. ✅ **Politică de abandon în multiplayer** — LIVRAT 2026-09-08.
   `core/abandon_policy.dart`: ieșire dintr-un meci ranked încă `playing`,
   fără scor final → meci PIERDUT (rating −12). 3 abandonuri într-o oră →
   Meci Rapid blocat 10 min (camerele cu cod rămân). Adversarul care
   abandonează era deja gestionat (timeout 12s la rezultate).

7. ✅ **Onboarding mai strâns** — LIVRAT 2026-09-08. Prima pornire: 4 pagini
   (ghicești poza / alegi din patru / mai repede = mai multe puncte / acum
   joacă). Versiunea de 12 pagini rămâne la „Revezi tutorialul" din Setări.

**Val 2 (după ce sunt date din analytics):**
- Server-authoritative pe partea competitivă (vezi secțiunea de decizii)
- Quality loop pe întrebări (accuracy / skip rate / report count per întrebare)
- Replay de meci + „share replay" (conținut social fără jucători online)
- UX de matchmaking („Caut adversar..." cu mesaje care escaladează la 3s/8s)
- Strategie de notificări (Prime Time, „Alex e online și a început un meci")

---

## Home — un singur „aur" vizual (feedback GPT)

Home are acum PLAY sus, dar și Roata / Clippy / Planeta / mascote care
aglomerează. GPT: un singur accent — **JOACĂ** — apoi dedesubt Daily
Challenge / Continue-Rematch / Friends Online, restul secundar.
Constrângere dură: `home_no_scroll` — tot trebuie să încapă fără scroll,
deci simplificarea e aliniată. Polish, nu blocant.

---

## Înainte de a trimite un build în Play

1. **AAB nou** — `flutter build appbundle --release` (FĂRĂ `REAL_ADS`).
   Cel vechi e din `b805052`, dinainte de tot ce s-a livrat după.
2. **Formularul Data safety** — o singură trecere, toată lista deodată:
   deja declarat (email, nume, progres) + Crashlytics („Crash logs" +
   „Diagnostics") + Analytics („App interactions" + „Other actions") +
   rapoarte bug („Diagnostics", NU „User messages") + Remote Config (doar
   citește). Play Console → App content → Data safety.
3. **Scoate `matchLegacyPlayerDoc()` din `firestore.rules`** — regulă
   tranzitorie pentru clienți vechi fără `playerIds`. De scos după ce
   build-ul cu `playerIds` ajunge la toți pe Play. Apoi rulează testele de
   reguli + scoate cazul „meci vechi fără playerIds".
4. **Sprint „documentation & release consistency"** (GPT) — README vechi,
   ecrane vechi, text Play Store, changelog, versiune. (`pubspec` +
   comentariul din `gamemodes.dart` — REPARATE 2026-09-07.)

---

## Polish (nu blochează lansarea)

- **Categoria Matematică** — poze cu matematicieni de ghicit (cere linia
  `assets/continut/matematica/poze/` în `pubspec.yaml`) + mai multe
  întrebări. Toate răspunsurile unice global (`test/question_loader_test.dart`).
- **Curățare colecții care se adună** — `daily_challenges/{dată}/scores` +
  `events/{id}/scores` cresc cu ~1 doc/jucător/zi. Purge lunar sau TTL
  Firestore când contează.
- ✅ **Titlul „Boboc"** — REZOLVAT 2026-09-08: se arată și „Boboc" /
  „Fresh Meat" pe cont nou, ca progresia de titluri să fie vizibilă.

---

## SESIUNEA 2026-09-10/11 — commitată în `1730f73` (2026-09-14)

- ✅ **Joacă cu boți** — LIVRAT 2026-09-14 (`35565d0`), probat și pe telefon (release, Tanks). Multiplayer → JOACĂ CU
  BOȚI: Clasic, Piatră-Foarfece, Tanks, Scaunul Electric, Obby vs 1-6 boți,
  dificultate 1-5, fără internet. Aceleași ecrane ca online, pe o bază din
  memorie (`data/local_firestore.dart`). Recompensă mică, plafon 5/zi, nu
  atinge clasamentul. Verificat în browser toate 5 modurile până la rezultate.
- **Fix conturi orfane** — SCRIS (auth_service.dart + multiplayer_service.dart
  + player_profile_service.dart), commitat în `1730f73`. Cauza: la revenirea din fereastra
  Google, appul rescria profilul sub identitatea guest; login-ul ștergea
  guest-ul; dacă scrierea ateriza după ștergere, profilul reînvia orfan.
  NEVERIFICAT — login-ul merge acum, dar APK-ul sideloadat n-are token App
  Check înregistrat, deci nu scrie nimic în Firestore (PERMISSION_DENIED) și
  testul nu dovedește nimic. Se verifică după tokenul fix (punctul de mai jos).
- **App Check debug token — STABIL, unul singur / platformă** — acum se
  regenerează la fiecare instalare clean și trebuie reînregistrat manual prin
  API (pierdere de timp în fiecare sesiune). De făcut: token FIX pus prin
  `--dart-define` sau string resource în `android/app/src/debug/`, înregistrat
  o dată, valabil pentru totdeauna. La fel pentru web (unul singur, nu per
  sesiune). Ținta: exact 2 token-uri în Firebase Console, permanente.
- ✅ USE_EXACT_ALARM scoasă, CI rulează toate testele, audit cod mort — commitate în `1730f73`.
- **Ștergerea tuturor jucătorilor** (cerută de user) — scriptul e gata
  (`tools/wipe_players.py`, probă făcută: 23 jucători, păstrează contul
  Google al adminului). NERULAT — clasificatorul cere ca userul să pornească
  ștergerea în masă cu `!`.
- **Figma** — pluginul e instalat dar cere autorizare (OAuth). Userul vrea
  rezolvat. Se face din `/mcp` într-o sesiune interactivă → figma →
  autentificare în browser. Claude nu poate face OAuth-ul singur.
- ✅ **Ecran negru la login Google** — REPARAT, verificat pe telefon 2026-09-14
  (APK release): `google_sign_in` 6.2.1 (fereastra veche, nu Credential
  Manager) + Impeller pe OpenGL ES. Login complet, contul apare, zero ecran
  negru. Downgrade-ul la Flutter 3.27.4 NU mai e nevoie (și nici nu se poate:
  plățile reale cer Flutter 3.44+).
- **Ordinea rămasă (2026-09-11):** APK de release pe telefon pentru animații →
  șlefuit animațiile (Rive/Lottie, Flame). Boții sunt gata.
- **Unity „doar în colțuri" (cerut de user, 2026-09-11)** — de instalat
  Unity Hub (`winget install Unity.UnityHub`) + un Editor LTS (câțiva GB,
  cere cont Unity — login-ul îl face userul). User e începător total în
  Unity. Folosire propusă: Unity NU intră în aplicație (flutter_unity_widget
  = +20-50 MB la APK și build fragil, nu merită pentru un efect). În schimb:
  efectul (ex. „evaporare" de praf/particule) se face în Unity și se EXPORTĂ
  ca secvență de cadre / sprite sheet / video scurt, care se redă în Flutter.
  Alternativa mai ușoară, de comparat înainte: particule direct în Flutter
  (Flame `ParticleSystemComponent` sau CustomPainter) ori Rive/Lottie. De
  făcut după testul animațiilor în release.
  CUM LUCREZ EU ÎN UNITY (userul NU știe Unity, nu vrea să atingă editorul):
  totul din linia de comandă — `Unity.exe -batchmode -projectPath <p>
  -executeMethod <EditorScript>.Build -quit`. Scripturi C# de editor care
  creează scena + ParticleSystem prin cod, simulează cadru cu cadru și
  randează PNG cu fundal transparent (Camera → RenderTexture → ReadPixels).
  Verificare: Read pe PNG-uri, ca la capturile de pe telefon. Singurul pas
  al userului: login în Unity Hub + activare licență Personal (o dată,
  ~10 min, ghidat). Proiectul Unity stă SEPARAT: `D:\proiecte\unity-efecte`,
  nu în SodoQuizz. În Flutter intră doar cadrele exportate.

---

## Decizii care te așteaptă pe TINE

Astea trei NU sunt fix-uri rapide — fiecare cere fie Blaze activ, fie o
decizie de timing la lansare, fie trafic real de date. Nu se ating solo,
fără o sesiune dedicată. Stare, 2026-09-08:

- **IAP / magazin cu bani reali** — 🟡 CODUL E GATA (2026-09-08), aprinderea
  depinde de tine. Ce s-a construit: `validatePurchase` (Cloud Function care
  verifică bonul la Google, anti-replay, confirmă ea însăși în cele 3 zile),
  catalog pe server (`functions/iap_products.json`) cu test de sincronizare cu
  `shop.dart`, drepturi permanente în `entitlements/{uid}` cu restaurare pe alt
  telefon, jurnal local care aplică o achiziție EXACT o dată chiar dacă moare
  aplicația la mijloc, `in_app_purchase` + permisiunea BILLING, buton
  „Restaurează achizițiile".
  RĂMÂNE LA TINE, în consolă (vezi planul complet):
  1. Activează `androidpublisher.googleapis.com` în Cloud Console.
  2. Play Console → Setup → API access → leagă proiectul `sodoquizz`, apoi dă
     acces contului de serviciu (propagare 24-48h; până atunci API-ul dă
     401/403 — e normal, nu e bug).
  3. Creează cele 13 produse cu ID-urile EXACTE din `shop.dart` (sunt
     imutabile) și activează-le.
  4. License testers + un build pe Internal testing (produsele nu se rezolvă
     fără un build publicat pe o pistă).
  5. Abia apoi aprinzi `magazin_bani_reali` din Remote Config.
  Killswitch-ul e neatins: `realMoneyStoreEnabled = false`, magazinul arată
  „În curând".

- ✅ **Miza pe monede = gambling-adjacent** — REZOLVAT 2026-09-08. Niciun
  produs plătit nu mai dă MONEDE (erau 3000/5000/12000 în pachete + 1500 la
  „fără reclame"); valoarea s-a compensat în vieți și hint-uri, la aceleași
  prețuri. Verificat că gems-urile nu se mizează nicăieri (`core/betting.dart`
  nu le conține deloc), deci lanțul bani-reali → jeton → pariu e rupt complet.
  Trei teste păzesc regula. Miza pe monede CÂȘTIGATE rămâne — e în regulă,
  n-are legătură cu bani reali.

- **Dificultate Easy/Medium/Hard** — 🟡 INFRA GATA 2026-09-08.
  `core/question_difficulty.dart` (estimare din acuratețe + timp),
  `question_stats/{id}` scris din single-player, tab „Dificultate" în Admin.
  Ce lipsește: TRAFIC. Fără jucători, `question_stats` rămâne gol. Când vine,
  dificultatea apare singură în Admin; de acolo se corectează manual cazurile
  bizare. Nimic de mai făcut solo.

- **`users/{uid}` / rating / league points scriabile de client** — 🟡 ok
  pentru closed testing, 🔴 obligatoriu la lansare serioasă. Regula de aur
  GPT: XP tolerant · cosmetice client-cache ok · **ranking competitiv →
  server** · **monedă premium → server** · **cumpărături → server** ·
  **revendicări de recompense → server**. Șantier separat, cere Blaze;
  NU e „rescrie economia", doar partea competitivă + bani-adiacentă.

---

## Blocat pe bază de jucători (RETENȚIE 9-12)

Moduri în echipă (2v2/3v3), turnee/bracket, clanuri, spectating live. GPT e
de acord: nu se construiesc acum. (Replay de meci — DA, e în Valul 2 mai sus,
e altceva decât spectating live.)

---

## Datorie tehnică (fără grabă, NU odată cu o lansare)

- **Lanțul de build Android** — Gradle 8.14 → ≥9.1, AGP 8.11.1 → ≥9.0.1,
  Kotlin 2.2.20 → ≥2.3.20. De la AGP 9 se citește doar DSL-ul nou, deci
  `android/app/build.gradle` trebuie rescris. Șantier separat.
- **Granularitatea reconstrucției** — 221 `setState` vs 8
  `ValueListenableBuilder`. Ecranele grele merită reconstrucție țintită.
- **Flutter 3.47.2** — ok acum. Upgrade-urile aduc Impeller dar pot rupe
  pluginuri. Nu pe fugă.
