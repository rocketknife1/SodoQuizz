# Ce urmează

Doar ce e DESCHIS, plus notele de care am nevoie ca să lucrez.
Ce s-a rezolvat stă în git + memorii, NU aici.
Ultima curățare: 2026-09-04.

---

## Notificări — TOATE VERIFICATE (2026-09-04)

Fluxul data-only e VERIFICAT pe telefon: mesaj FCM → notificare desenată de
aplicație → tap → firul direct. Functions deployate (Node 22). Firul admin↔
jucător e GATA și verificat cap-la-cap (commit-uri 640d477 + 99fbd20 + e9fdd76,
deployat). **Invitația în cameră a fost probată și ea**, prin fluxul real
(prieten adăugat pe cod → „CHEAMĂ PRIETENII" din lobby): notificarea „🎮 Te-a
invitat la o partida" a ajuns cu aplicația în fundal, iar tap-ul a intrat
DIRECT în camera corectă (2/10 jucători în lobby).

- **Push-ul pe web nu există** — ar cere cheie VAPID și service worker separat.
  Doar Android primește notificări.
- Dacă push-ul „nu merge" la un test, verifică ÎNTÂI permisiunea, nu codul:
  `dumpsys package com.dragosssx.guessit | grep POST_NOTIFICATIONS`. Un
  `granted=false` cu flag `USER_FIXED` nu se mai poate cere din aplicație —
  se dă cu `adb shell pm grant`. La fel, o reinstalare clean invalidează
  token-ul FCM vechi, iar Functions îl șterg ca „mort" la prima trimitere.
- **`adb shell am force-stop` NU e felul corect de a testa „aplicația
  închisă".** Android pune aplicația în stare *stopped* și refuză să-i mai
  livreze broadcast-uri până la o lansare manuală — FCM-ul ajunge la telefon,
  dar se anulează (`GCM: broadcast intent callback: result=CANCELLED`), deci
  pare bug de aplicație când e de fapt sistemul. Testează cu aplicația trimisă
  în fundal (HOME sau scoasă din recente), nu force-stop.

---

## Categoria Matematică — SCRISĂ, polish rămas (2026-09-04, cb1633e)

Categoria #14 în Play, prima FĂRĂ poze — arată o formulă scrisă mare. 100 de
întrebări (Formule celebre, Simboluri, Matematicieni, Calcule). Verificată pe
telefon: apare, deblocare cu Gems, cardul de formulă, reveal-ul.

Turul de conținut FĂCUT (a15952a): toate 100 revizuite, 2 greșeli reparate
(hint Moisil + un distractor malformat). Fix-ul one-line al formulelor
(`softWrap:false`) e în `cb1633e`, probat pe telefon după commit, merge.

Rămas pentru „finalizări pe viitor" (cuvintele userului):
- **poze cu matematicieni** de ghicit — arhitectura le suportă deja (întrebare
  cu `formula` gol + poză). Cere adăugarea liniei
  `assets/continut/matematica/poze/` în `pubspec.yaml`.
- **mai multe întrebări** — userul: „pe viitor urcăm la mai multe".

Generatorul (`gen_matematica.py`) e în scratchpad, nu în repo — unealtă de o
dată. Toate răspunsurile trebuie unice GLOBAL (test/question_loader_test.dart).

---

## Scăpări mici, găsite dar nereparate

- **`room_invites` se adună la nesfârșit.** `onRoomInvite` marchează invitația
  cu `pushedAt` „ca să se poată curăța" (chiar așa scrie comentariul), dar
  nimic nu o curăță vreodată. Documentele rămân după ce camera a dispărut.

  La ritmul actual sunt câteva pe an, deci nu grăbește nimic. Două variante
  când se ajunge acolo: fie funcția o **șterge** după ce a trimis push-ul
  (invitația și-a făcut treaba, iar clientul primește `matchId` în notificare,
  nu din document), fie o politică TTL în Firestore pe `createdAt`. Prima e
  trei linii și zero configurare.

---

## De pus în funcțiune (cod gata, așteaptă un pas al tău)

- **Scoate ramura tranzitorie din regula de meciuri.** `firestore.rules` are
  acum `matchLegacyPlayerDoc()` — un `exists(.../players/uid)` care lasă
  clienții VECHI (fără `playerIds`) să scrie mai departe, ca deploy-ul
  regulilor să nu depindă de propagarea pe Play. Slăbește reparația:
  subcolecția `players` e deschisă la scriere, deci un atacator hotărât își
  poate crea singur un document și trece de verificare.

  De scos după ce build-ul cu `playerIds` ajunge la toți (web e deja acolo;
  rămâne Play). După ștergere, rulează testele de reguli — cazul „meci VECHI,
  fără playerIds" va trebui și el scos.


---

## Planul de finalizare (2026-09-04/05) — unde am ajuns

Șase pași, hotărâți împreună, în ordinea asta. Ce e bifat e și verificat.

- ✅ **0. Flutter 3.27.4 → 3.47.2** — cod neatins, verificat pe telefon
- ✅ **1a. Crashlytics + Analytics** — VERIFICAT pe telefon: crash provocat din
  tabul Debug → raport ajuns în consolă cu numele funcției, clasa și versiunea
  (deci pluginul Gradle urcă simbolurile). Firebase e legat de Google Play, cu
  Crashlytics pornit.

  Probată doar calea NATIVĂ. Erorile din Dart merg prin `FlutterError.onError`
  — legată, neprobată separat; sunt acoperite oricum de ecranul de raport.
- ✅ **1b. „Trimite raportul"** — verificat cap-la-cap, raport ajuns în bază
- ✅ **2. Remote Config** — versiune minimă, mesaj de întreținere, comutatoare
  de magazin
- ✅ **3. Mărime** — APK 173 MB → **125 MB** (`tools/optimize_images.py`)
- ✅ **5. Comenzi** — scoasă cea moartă, adăugate „Construiește" și „Funcții"
- ✅ **4. Restructurare** — `admin_screen.dart` spart pe tab-uri. Restul
  fișierelor mari NU se sparg, deliberat: `multiplayer_service` e o singură
  clasă (Dart nu împarte membri de clasă în `part`), `storage_service` e o
  listă de chei. Ar fi fost mișcare de dragul mișcării.
- ✅ **6. Sisteme care lipseau** — cerere de recenzie în Play + **tutorial la
  prima pornire** (3 pași, verificat pe telefon inclusiv că nu reapare)

**Planul e încheiat și PUBLICAT** (push 2026-09-05, `c8c0052..a5ad21e`).
Ambele fluxuri GitHub au ieșit verzi, iar site-ul public a fost verificat live:
tutorialul apare la prima intrare. Mai rămâne, înainte de orice build trimis
în Play, formularul Data safety de mai jos.

---

## ⚠️ ÎNAINTE DE LANSARE — Data safety, o singură dată

**NU se face acum**, la cererea userului (2026-09-05): până la lansare se mai
schimbă lucruri, deci formularul se completează **o dată, la final**, cu lista
întreagă în față. Lista de mai jos se ADAUGĂ pe măsură ce apar lucruri noi —
ăsta e rostul ei.

Formularul devine FALS dacă se trimite build-ul fără actualizarea lui, iar o
declarație falsă în Play e o problemă de conformitate, nu un detaliu.

Ce s-a adăugat de la ultima completare și trebuie bifat:

- **Firebase Crashlytics** (2026-09-04) — jurnale de erori, model de telefon,
  versiune de sistem. Categoria Play: „Crash logs" + „Diagnostics".
- **Firebase Analytics** (2026-09-04) — evenimente de joc și un identificator
  pseudonim. Categoria: „App interactions" + „Other actions".
- **Rapoartele „Trimite raportul"** (2026-09-05) — uid, versiune, platformă,
  ecran, urma tehnică a sesiunii. Tot „Diagnostics"; **nimic scris de
  jucător**, deci NU e „User messages".
- **Firebase Remote Config** (2026-09-05) — doar CITEȘTE valori de la server,
  nu trimite nimic. De regulă nu cere nicio bifă, dar se verifică la final.

Ce era deja declarat și rămâne: emailul (Firebase Auth), numele afișat,
progresul de joc.

Când vine momentul: Play Console → App content → Data safety, o singură
trecere prin toată lista de mai sus.

---

## Decizii care te așteaptă pe tine

- **Magazin cu bani reali (IAP).** Ordinea obligatorie:
  0. **validarea bonului pe server** — vezi mai jos DE CE e pasul zero;
  0b. aprinde comutatorul **„Google Analytics: share in-app purchase and
     subscription revenue data"** din Firebase → Project settings →
     Integrations → Google Play. E lăsat OPRIT dinadins (2026-09-05): fără
     cumpărături reale ar raporta zero la nesfârșit. Legarea în sine e făcută,
     cu Crashlytics pornit;
  1. integrez `in_app_purchase` + permisiunea `com.android.vending.BILLING`
     și leg butoanele de SDK-ul real (nu e o seară de lucru);
  2. urci un build cu asta în Play Console;
  3. **abia atunci** creezi produsele cu ID-urile din `shop.dart` — sunt
     permanente, nu se redenumesc și nu se refolosesc după ștergere;
  4. testezi cu cont licențiat (License testers, în Play Console).

  La deschidere se schimbă DOUĂ comutatoare, nu unul: `premiumShopRevealed`
  (vizibilitatea) și `realMoneyStoreEnabled` (plățile efective). Adăugarea
  plăților obligă și **reretrimiterea formularului Data safety**.

  ### De ce validarea pe server e pasul ZERO, nu ultimul

  Din secunda în care vinzi gems, o monedă cumpărată și una fabricată devin
  imposibil de deosebit — `users/{uid}` e scriabil de proprietar (vezi punctul
  cu balanța). Ai vinde ceva ce oricine își poate tipări singur.

  **Dar NU cere rescrierea economiei.** Monedele câștigate din quiz pot rămâne
  liniștit locale: dacă cineva își fabrică 10.000 de monede, nu pierzi niciun
  leu. Se protejează doar ce s-a CUMPĂRAT. Concret, o Cloud Function care:
  - primește `purchaseToken`-ul de la client și îl verifică la Google cu
    `purchases.products.get` (Play Developer API v3, scope
    `androidpublisher`), cu `packageName` + `productId` + token;
  - **abia dacă Google confirmă**, acordă gems-ii/vieţile/hint-urile;
  - **ține minte token-urile deja folosite**, altfel același bon valid poate fi
    trimis de o sută de ori (replay).

  ### Capcana care te costă bani tăcut: fereastra de 3 zile

  O achiziție neconfirmată în **3 zile** e **rambursată automat, iar Google
  revocă produsul** — dar tu i-ai dat deja gems-ii. Ceasul pornește când
  starea trece din `PENDING` în `PURCHASED` (nu confirma cât e `PENDING`).
  `consumeAsync()` confirmă implicit, iar la noi **11 din 12 produse sunt
  consumabile**, deci e acoperit — dar doar dacă chiar consumi în 3 zile.

  ### Ce e consumabil și ce nu

  Consumabile (se pot cumpăra la nesfârșit): `gems_130/390/1050`,
  `lives_10/30`, `hints_25/70/175`, `bundle_starter/aventurier/campion`.
  NEconsumabil, o singură dată pe viață: **`no_ads_forever`** — ăsta cere
  obligatoriu **„Restaurează cumpărăturile"** în interfață (Play o cere), altfel
  omul care schimbă telefonul își pierde plata și îți deschide dispută.

  ### Rambursări și chargeback

  Fără asta, cineva cumpără gems, îi cheltuie, cere refund și rămâne cu tot.
  Se închide cu **Voided Purchases API** (lista comenzilor anulate/rambursate/
  contestate) plus **Real-time developer notifications** (RTDN) — la o
  notificare, ceri starea reală și retragi ce s-a acordat.

  Surse verificate 2026-09-04:
  [ciclul unei achiziții](https://developer.android.com/google/play/billing/lifecycle/one-time),
  [fraudă și abuz](https://developer.android.com/google/play/billing/security),
  [purchases.products.get](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/get).

- **`users/{uid}` — balanța rămâne scriabilă de proprietar, dar acum se
  VEDE.** Din 2026-09-04 există `onBalanceAudit` (functions/index.js): notează
  salturile implauzibile în `security_flags/{uid}`, iar panoul de Admin le
  arată deasupra balanței, în fișa jucătorului. DEPLOYAT și verificat
  cap-la-cap pe producție (creare cu 999999999 monede → semnal → card portocaliu
  pe telefon → date de test șterse).

  De ce detecție și nu blocare — motivul e în cod, nu teoretic:
  `CloudSyncService.push()` scrie documentul ÎNTREG, doar la trecerea în
  fundal, deci o scriere acoperă o sesiune întreagă și diferența legitimă
  n-are plafon. Iar dacă o regulă ar refuza scrierea, eșecul e TĂCUT
  (`catch { debugPrint }`): jucătorul ar juca mai departe cu salvarea oprită
  și ar afla la reinstalare, când pierde tot. Leacul ar fi fost mai rău decât
  boala, într-un joc unde monedele sunt azi pur virtuale.

  Ce rămâne deschis: nu OPREȘTE pe nimeni. Oprirea reală cere balanța scrisă
  doar de Cloud Functions = rescrierea stratului de economie (azi local-first),
  și merită abia când jocul face bani reali. Între timp App Check pe „Enforce"
  a închis deja calea de pe Android (un APK modificat nu mai primește token
  Play Integrity); deschisă rămâne varianta din browser.

---

## Datorie tehnică, fără grabă

- **Lanțul de build Android va trebui urcat încă o dată.** Suntem pe Gradle
  8.14 + AGP 8.11.1 + Kotlin 2.2.20 (minimul cerut de Flutter 3.47). Flutter
  avertizează deja la fiecare build că suportul pentru ele „va fi scos în
  curând" și cere **Gradle ≥ 9.1.0, AGP ≥ 9.0.1, Kotlin ≥ 2.3.20**.

  N-am urcat acum dinadins: de la **AGP 9 se citește doar DSL-ul nou**, deci
  `android/app/build.gradle` trebuie rescris, iar `android/gradle.properties`
  are acum `android.newDsl=false` și `android.builtInKotlin=false` (puse
  automat de Flutter) tocmai ca să nu fie nevoie. E un șantier separat, de
  făcut când nu se lucrează la altceva — nu odată cu o lansare.

- **Granularitatea reconstrucției.** 221 `setState` față de 8
  `ValueListenableBuilder` în tot proiectul. Ecranele grele merită mutate
  treptat pe reconstrucție țintită.
- **Flutter 3.27.4 e din ianuarie 2025.** Un upgrade aduce îmbunătățirile de
  Impeller acumulate de atunci. Poate rupe pluginuri — nu de făcut pe fugă.

---

# Note de lucru (pentru Claude)

## Testare multiplayer cu jucători automați

`<scratchpad>/rps/` ține harness-ul:
- `launch.js` (2 conturi) / `launch4.js` (4 conturi) — contexte Chrome
  SEPARATE (nu taburi: altfel toți ar fi același cont anonim), Chrome rămâne
  deschis pe CDP 9222;
- `act.js <cine> <acțiune> <args>` — un pas, apoi capturi `A.png`..`D.png`.
  `<cine>` = `A`/`B`/`AB`/`ABCD`; `PAUSE=<ms>` înainte de captură;
- scripturi de burst pentru animații (capturi dese pe toată faza de reveal).

Capcane:
- **`Join Online` e coada de producție reală** — pentru teste doar
  `Join with Code`;
- lățimea ferestrei schimbă toate coordonatele (520 la 2 jucători, 420 la 4) —
  recalibrează din capturi, nu ghici;
- layout-ul din Tanks **se mută** după activarea unui power-up: clicurile pe
  poziția veche cad pe gol, tăcut.

## Power-up-uri dirijate în teste

Picătura e determinista pe hash de `matchId`, deci nedirijabilă. Pentru teste
țintite se aplică temporar în `core/powerups.dart`:
`--dart-define=FORCE_POWERUP=<nume>` + `testForcedPowerUpActive` (face
ecranele să sară peste condiția „ai câștigat runda").
**Se scoate după fiecare rundă de test** — verifică cu
`grep -c FORCE_POWERUP build/web/main.dart.js` (trebuie 0).

## Teste pe regulile Firestore

`test/firestore_rules_test.mjs` rulează pe emulatorul local, fără nicio
scriere în producție. Emulatorul cere JDK 21+; mașina are Temurin JDK 25, dar
shim-ul `java8path` e primul pe PATH — vezi `test/README-reguli.md` pentru
comanda cu `JAVA_HOME` (nu uita `hash -r`).

## Toggle admin „vezi răspunsul corect"

`core/admin_reveal.dart` — un toggle în tabul Debug (Admin), doar pentru
contul de admin logat cu Google. Cât e pornit, varianta corectă a oricărei
întrebări cu 4 variante e conturată cu chihlimbar, ORIUNDE (singleplayer, cele
5 moduri multiplayer cu întrebări, Cultură Generală, Planeta hologramelor,
bonusul Clippy). Pur vizual — nu atinge scorul. Dublu gard: pref + emailul din
token (`adminAnswerRevealOn`), pref-ul singur nu ajunge. Cele 8 grile de
variante au primit fiecare o linie/param `adminHint`.

## Meniul principal NU derulează

Regulă dură (2026-09-03). Home e `SingleChildScrollView`, dar tot ce e pe el
trebuie să încapă pe ecran — dacă apare scroll, e bug. Nu „face loc"
mascotelor cu padding de jos: alea plutesc într-un `Stack` peste conținut, iar
padding-ul doar împinge în scroll. Micșorează ce e în flux.

## Cronometre în testele mele

La orice self-test se ridică timerele în build-ul local (`sharedRoundAnswerSeconds`,
`tanksTargetSeconds` etc.) — bucla captură→citire→decizie e mult mai lentă
decât secundele reale. Se revine la valorile normale înainte de commit.

## Verificare rapidă a datelor din producție

Scripturile din `tools/` merg pe REST + `tools/service-account.json` și se
rulează **din rădăcina repo-ului** (calea cheii e relativă la CWD). Pentru o
citire ad-hoc, importă `FIRESTORE` și `_session` din `tools/purge_accounts.py`.
Restul scripturilor din `tools/` ating date reale — se rulează întâi în mod
raportare și se confirmă cu userul.

---

## Cloud Functions — întreținere

CINCI declanșatoare în `europe-west1`, toate pe **nodejs22**, DEPLOYATE
(verificat `firebase.cmd functions:list` pe 2026-09-04): onFriendMessage,
onFriendRequest, onRoomInvite, onSystemNotification, onAdminMessage.

- `firebase-functions` (`^6.1.0`) e ok deocamdată; un upgrade major aduce
  **modificări incompatibile**, deci nu se face pe fugă odată cu altceva.
- Firebase avertizează la fiecare deploy despre `firebase-functions` vechi —
  benign, nu blochează nimic.

Comanda de deploy (PowerShell refuză shim-ul `.ps1`, de-aia `.cmd`):
```
firebase.cmd deploy --only functions --project sodoquizz
```
