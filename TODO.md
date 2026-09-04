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

## Decizii care te așteaptă pe tine

- **Magazin cu bani reali (IAP).** Ordinea obligatorie:
  1. integrez `in_app_purchase` + permisiunea `com.android.vending.BILLING`
     și leg butoanele de SDK-ul real (nu e o seară de lucru);
  2. urci un build cu asta în Play Console;
  3. **abia atunci** creezi produsele cu ID-urile din `shop.dart` — sunt
     permanente, nu se redenumesc și nu se refolosesc după ștergere;
  4. testezi cu cont licențiat.

  La deschidere se schimbă DOUĂ comutatoare, nu unul: `premiumShopRevealed`
  (vizibilitatea) și `realMoneyStoreEnabled` (plățile efective). Adăugarea
  plăților obligă și **reretrimiterea formularului Data safety**.

- **`users/{uid}` — balanța rămâne scriabilă de proprietar, dar acum se
  VEDE.** Din 2026-09-04 există `onBalanceAudit` (functions/index.js): notează
  salturile implauzibile în `security_flags/{uid}`, iar panoul de Admin le
  arată deasupra balanței, în fișa jucătorului.

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
