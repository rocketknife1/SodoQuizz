# Ce urmează

Doar ce e DESCHIS, plus notele de care am nevoie ca să lucrez.
Ce s-a rezolvat stă în git + memorii, NU aici.
Ultima curățare: 2026-09-03 (a doua).

---

## Notificări — RĂMĂȘIȚE MICI

Fluxul data-only e VERIFICAT pe telefon (2026-09-03): mesaj FCM → notificare
desenată de aplicație pe canalul propriu → tap → firul direct cu omul.
Functions deployate (Node 22). Rămâne de probat doar invitația în cameră.

- **Push-ul pe web nu există** — ar cere cheie VAPID și service worker separat.
  Doar Android primește notificări.
- Dacă push-ul „nu merge" la un test, verifică ÎNTÂI permisiunea, nu codul:
  `dumpsys package com.dragosssx.guessit | grep POST_NOTIFICATIONS`. Un
  `granted=false` cu flag `USER_FIXED` nu se mai poate cere din aplicație —
  se dă cu `adb shell pm grant`. La fel, o reinstalare clean invalidează
  token-ul FCM vechi, iar Functions îl șterg ca „mort" la prima trimitere.

---

## Mesaje admin ↔ jucător — GATA, verificat capăt-la-capăt (2026-09-03)

Reguli și Functions DEPLOYATE. Probat pe telefon (admin) + web (jucător):
mesaj jucător → push la admin → tap → firul direct; răspuns admin → ajunge la
jucător; tab „Mesaje" în Admin; bulina pe SETĂRI.

Rămâne doar: **reinstalează APK-ul pe telefon** — cel de acolo e de la 19:50 și
nu are ultimele două reparații (insigna de pe SETĂRI, cache-ul funcției).

Trei bug-uri prinse DOAR probând pe ecran, niciunul vizibil la analyze/teste:
1. `StreamBuilder` verifica doar `data == null`; un stream Firestore respins nu
   emite niciodată, deci ecranul rămânea pe spinner la infinit;
2. funcția Cloud memora EȘECUL rezolvării uid-ului de admin (`_adminUid = null`
   + gardă `!== undefined`) și rămânea oarbă pe toată viața instanței, ieșind
   fără niciun log — mesajele ajungeau, push-ul nu mai pleca deloc;
3. `SolidMenuButton` desena `badge` doar pe varianta fără subtitlu; Home trimite
   `subtitle: ''`, deci insigna era acceptată și ignorată TĂCUT. Acum are test
   de widget dedicat (`test/solid_menu_button_badge_test.dart`).

Uid-ul adminului NU se mai caută în Auth (`getUserByEmail` pică — contul e legat
prin Google, iar emailul e doar în token): aplicația adminului îl publică
singură în `config/admin`, nescriabil de altcineva și necitibil din client.

---

## De curățat, când ai chef

`python tools/purge_accounts.py --sterge` — două conturi Guest de test
(`Jucator381`, `Jucator422`) sunt la coadă pentru ștergerea din Firebase
Authentication. În Firestore nu mai au nicio dată legată de ele, deci nu
grăbește nimic.

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


- **App Check pe „Enforce".** Web-ul trimite deja token. Mai rămâne:
  1. închide canalul GitHub APK (scoate linkul din `LINKS.md` + Discord, mută
     testerii pe Play closed testing) — APK-ul sideloaded ia oricum
     `UNRECOGNIZED_VERSION`, nu există fix;
  2. Firebase Console → App Check → metrics: confirmă procentul de cereri
     verificate (ultima verificare: 2% verified / 98% unverified — flipul ar
     rupe aproape tot);
  3. flip Firestore pe Enforce.

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

- **„Timp în Plus" în modurile sincrone.** A fost scos fiindcă nu funcționa:
  secundele erau o valoare locală, dar runda se închide când expiră
  cronometrul ORICĂRUI client. A rămas doar la Clasic. Dacă îl vrei înapoi,
  trebuie scris în documentul meciului ca să prelungească runda pentru toți —
  altă mecanică, nu o reparație.

- **`users/{uid}` — balanța de monede/gems e scriabilă integral de
  proprietar.** Nu se poate strânge cu reguli fără să rupă jocul: clientul
  scrie salvarea întreagă, iar salturile legitime (pachet cumpărat, jackpot la
  roată) sunt mari. Închiderea reală cere ca balanța să fie scrisă DOAR de
  Cloud Functions, adică rescrierea stratului de economie, care azi e
  local-first. Merită făcut abia când jocul face bani reali.

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

## Cloud Functions — întreținere (adăugat 2026-09-03)

Deployate în `europe-west1`, CINCI declanșatoare (vezi `functions/index.js`);
al cincilea, `onAdminMessage`, e scris dar NEDEPLOYAT.
Firebase avertizează la fiecare deploy:

- **Node 22** e deja setat în `functions/package.json` + `firebase.json`
  (era 20, depreciat, scos pe 2026-10-30). Rămâne DOAR redeploy-ul ca să intre
  în vigoare — `firebase.cmd deploy --only functions --project sodoquizz`.
- `firebase-functions` (`^6.1.0`) e ok deocamdată; un upgrade major aduce
  **modificări incompatibile**, deci nu se face pe fugă odată cu altceva.

Comanda de deploy (PowerShell refuză shim-ul `.ps1`, de-aia `.cmd`):
```
firebase.cmd deploy --only functions --project sodoquizz
```
