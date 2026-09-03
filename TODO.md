# Ce urmează

Doar ce e DESCHIS, plus notele de care am nevoie ca să lucrez.
Ce s-a rezolvat stă în git + memorii, NU aici.
Ultima curățare: 2026-09-03.

---

## Notificări — RĂMĂȘIȚE MICI

Notificările (locale + push prin Cloud Functions), insigna de pe planetă,
sunetul moale, tap-ul care rutează în aplicație, butonul mare de invitație —
toate gata. **NEVERIFICAT pe telefon** noul flux data-only (telefonul e la
încărcat); Functions NEDEPLOYATE. De reprobat: mesaj + invitație în cameră,
cu aplicația închisă, si tap-ul să intre direct în cameră.

- ~~Fusul orar la notificările locale~~ **FĂCUT** (`e8cd20f`) — `flutter_timezone`
  citește IANA din sistem.
- **Notificarea locală nu se anulează** dacă jucătorul consumă lucrul înainte
  să sune alarma (ex. intră în joc și învârte roata cu 10 minute înainte).
  `rescheduleAll` la fiecare trecere în fundal o corectează parțial — rămâne
  fereastra în care aplicația e în prim-plan după consum.
- **Push-ul pe web nu există** — ar cere cheie VAPID și service worker separat.
  Doar Android primește notificări.
- La tap pe notificarea de mesaj se deschide lista de prieteni, nu firul
  direct cu omul respectiv.

## Reconectare în meci (cerut 2026-09-03) — DE FĂCUT

Dacă cineva e într-un meci multiplayer în desfășurare și pierde legătura
(minimizează aplicația, cade internetul, îl omoară sistemul), la revenire să
apară un buton **„Reconectează"** care îl bagă înapoi în meciul în curs.

De declanșat la: revenirea aplicației în prim-plan (`AppLifecycleState.resumed`)
sau revenirea conexiunii. De verificat că meciul chiar mai există și că e încă
în desfășurare — camerele se șterg când pleacă ultimul jucător, iar
`purge_stale_matches.py` mătură ce rămâne agățat.

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

Deployate în `europe-west1`, patru declanșatoare (vezi `functions/index.js`).
Firebase avertizează la fiecare deploy:

- **Node.js 20 e depreciat**, se scoate din funcțiune pe **2026-10-30**. După
  data aia nu se mai poate deploya fără upgrade. De urcat la Node 22 în
  `functions/package.json` + `firebase.json` înainte de termen.
- `firebase-functions` e o versiune veche; upgrade-ul aduce **modificări
  incompatibile**, deci nu se face pe fugă odată cu altceva.

Comanda de deploy (PowerShell refuză shim-ul `.ps1`, de-aia `.cmd`):
```
firebase.cmd deploy --only functions --project sodoquizz
```
