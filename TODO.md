# Ce urmează

Doar ce e DESCHIS, plus notele de care am nevoie ca să lucrez.
Ce s-a rezolvat stă în git + memorii, NU aici.
Ultima curățare: 2026-09-03.

---

## Notificări pe telefon (cerut 2026-09-03) — DE FĂCUT

Azi **nu există nicio notificare pe telefon**. Tot ce se numește „notificare"
în cod e clopoțelul din aplicație (`NotificationService` = panoul in-app).
Nu e nici `flutter_local_notifications`, nici `firebase_messaging`, nici
permisiunea `POST_NOTIFICATIONS`.

Cererea se împarte în trei bucăți, cu dependențe reale între ele:

### ~~Piesa 1 — notificări LOCALE~~ FĂCUTĂ (`b44495c`, verificată pe telefon)

Roata, questurile, Clippy (pe resetul ZILNIC, nu la 5 minute) și planeta.
Sunet propriu, notificarea rămâne în bară. Rămân de scos, când e ocazia, două
lucruri de rafinat: fusul orar e ghicit din decalaj (`Europe/Bucharest` sau
UTC) în loc să fie citit ca IANA, iar notificarea nu se anulează când
jucătorul consumă lucrul înainte să sune alarma.

Plus, tot aici: **sunetul propriu al aplicației** la orice notificare (canal
Android dedicat cu sunet custom — sunetul se leagă de CANAL, nu de mesaj,
deci canalul trebuie creat corect din prima; schimbarea sunetului mai târziu
cere canal nou, cel vechi păstrează sunetul cu care a fost creat).

**Cerință explicită (2026-09-03): notificarea RĂMÂNE în bara de notificări**,
nu apare și dispare. Concret: `autoCancel: false` ca să nu se șteargă la tap,
importanță `high` ca să apară și ca banner peste ecran, și id stabil per tip
de notificare ca una nouă să o înlocuiască pe cea veche în loc să adune un
teanc. De hotărât pe parcurs dacă „rămâne" înseamnă și `ongoing: true` (nu
poate fi ștearsă cu degetul) — aia e mai agresivă și se folosește de obicei
doar pentru lucruri în desfășurare, nu pentru anunțuri.

### Piesa 2 — overlay pe planetă (pur UI, independent)

Peste planeta din Home:
- „Ready" când se poate juca;
- în cooldown: cât mai are până e gata + câte rulări mai ai („1 din 2").

Datele există deja: `StorageService.planetCooldownRemaining()`,
`StorageService.planetRunsLeft()`, `planetRunsPerCycle` /
`planetRunsPerCycleWithAd` (`core/progression.dart`, cooldown 12h).

### Piesa 3 — notificări PUSH (cere Cloud Functions)

Astea vin din acțiunea ALTUI jucător, când aplicația ta e închisă:
- ți-a scris cineva un mesaj;
- cerere de prietenie;
- anunț de sistem de la admin;
- **invitație în cameră** — inviți un prieten offline, îi apare notificare, iar
  la tap **intră direct în camera aia** de multiplayer.

⚠️ **Blocajul real:** un client NU poate trimite FCM altui client. Trimiterea
cere cheia de server / Admin SDK, adică **Cloud Functions**. Toată
documentația proiectului spune „fără Cloud Functions", dar asta **s-a
schimbat**: contul e acum pe **Blaze (free trial)**, deci Functions se pot
deploya. E infrastructură nouă, nu o seară de lucru.

Pentru „tap pe notificare → intri în cameră" există deja jumătate din
mecanică: pachetul `app_links` e în `pubspec.yaml`, iar schema custom
`guessit://` era deja gândită pentru invitațiile de prietenie (vezi memoria
`project_guess_it_friend_invite_link`), doar că n-a fost construită.

**Ordinea recomandată:** Piesa 1 → Piesa 2 → Piesa 3. Primele două n-au nevoie
de nimic din afară și dau imediat 5 din lucrurile cerute; a treia e proiect
separat, cu Functions.

---

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

- **Regulile Firestore care închid vandalizarea meciurilor.** Codul e pushat
  (web-ul are deja `playerIds`), regulile din `firestore.rules` **nu sunt
  deployate**. Ordinea e obligatorie:
  1. urci în Play Console AAB-ul (`flutter build appbundle --release
     --dart-define=REAL_ADS=true`) și aștepți să se propage la testeri;
  2. abia apoi `comenzi/4 - Trimite regulile Firestore in productie...bat`.

  Invers, un tester pe Android cu build vechi care intră într-o cameră creată
  de un client nou nu s-ar adăuga în `playerIds` și ar fi refuzat la prima
  rundă. Meciurile vechi, fără câmp, merg mai departe — regula are ieșire
  pentru ele.

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
