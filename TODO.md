# Ce urmează

Doar ce e DESCHIS. Ce s-a rezolvat stă în git + memorii, nu aici.
Ultima curățare: 2026-09-02.

## Changelog sesiune 2026-09-02 (se șterge data viitoare)

Testat pe viu cu Playwright (2–4 conturi reale, contexte Chrome separate):
Piatră-Hârtie-Foarfecă până la final (premii exacte), acceptare cerere
prietenie (bug `2e2baa6` reparat, confirmat vizual), `reflect`+`allyShield`
la Scaunul Electric, Double Shot + `reflect` la Quizz Tanks. Toate verzi.
`allyShield` la Tanks rămâne singurul neprobat (mecanism identic cu Scaunul
Electric). Detalii în commit-uri. Secțiunea „De probat pe viu" a dispărut —
era goală.

## Animații pentru power-up-uri — TOATE TREI FĂCUTE (2026-09-03)

Toate verificate pe viu, cu 4 conturi reale și `--dart-define=FORCE_POWERUP=<nume>`:

- **Reflect** (`c2ee94e`) — obuzul arcă la reflector, ricoșează din dom, se
  întoarce în trăgător care încasează.
- **Scut** (`e305f26`) — dom hexagonal în arenă cu „0" deasupra; în camera de
  apărare „SHIELD! — the dome held — 0 damage", tancul NU mai smucește.
  (Camera trăgătorului primește același flag, dar n-a fost prinsă în captură.)
- **Double Shot** (`4117fc9`) — UN obuz iese din tun, se desparte în două la
  40% din drum, fiecare arcuiește spre ținta lui; ambele ținte încasează.

- **Camera trăgătorului la lovitură dublă** — FĂCUT + verificat pe viu
  (`831dc0d` + reparațiile de după). Când tragi TU în doi oameni, camera stă
  în spatele tunului cu ambele tancuri în cadru, două obuze merg fiecare la
  tancul lui, iar la impact apar două explozii distincte cu deznodământul
  fiecăreia („-8" / „-13", sau „EVITAT" dacă unul se ferește).

Harness de test: `<scratchpad>/rps/` — `launch4.js` (4 conturi), `act.js`,
plus scripturile de burst (`dburst3.js`, `shburst.js`). Patch temporar
`FORCE_POWERUP` în `core/powerups.dart` + `testForcedPowerUpActive` — se scoate
după fiecare rundă de test (grep în build ca să confirmi).

## Decizii care te așteaptă pe tine

- **„Timp în Plus" a fost scos din modurile sincrone.** Nu funcționa deloc
  acolo: secundele erau o valoare locală, dar runda se închide când expiră
  cronometrul ORICĂRUI client, deci adversarul îți tăia runda la secunda
  normală. A rămas doar la Clasic, unde fiecare are propriul termen. Dacă îl
  vrei înapoi în modurile sincrone, trebuie scris în documentul meciului ca
  să prelungească runda pentru toți — adică altă mecanică, nu o reparație.
- **Magazin cu bani reali (IAP).** Ordinea obligatorie:
  1. integrez `in_app_purchase` + permisiunea `com.android.vending.BILLING`
     și leg butoanele de SDK-ul real (nu e o seară de lucru);
  2. urci un build cu asta în Play Console;
  3. **abia atunci** creezi produsele cu ID-urile din `shop.dart` — sunt
     permanente, nu se redenumesc și nu se refolosesc după ștergere;
  4. testezi cu cont licențiat.
  La deschidere se schimbă DOUĂ comutatoare, nu unul: `premiumShopRevealed`
  (vizibilitatea, pus pe `false` pe 2026-09-02 cât e testare închisă) și
  `realMoneyStoreEnabled` (plățile efective). Adăugarea plăților obligă și
  **reretrimiterea formularului Data safety**.
- **Audit securitate #1 — DIAGNOSTIC CORECTAT 2026-09-02.** Formularea veche
  („scoruri de meci falsificabile, se repară cu o Cloud Function de validare a
  scorului") căuta problema în locul greșit. Atacul real nu are nevoie de
  niciun meci: `users/{uid}` (salvarea din cloud, cu monedele) și
  `player_profiles/{uid}` (rândul din clasament) sunt amândouă scriabile de
  proprietar. Îți setezi balanța sau punctajul direct, dintr-o singură
  scriere. O Cloud Function pe scorurile de meci ar fi lăsat ambele deschise.

  **Făcut:** `player_profiles` are acum limite în `firestore.rules` —
  `leaguePoints`/`seasonPoints` nu pot crește cu mai mult de 20 pe scriere
  (exact `winPoints`), `matchesPlayed` cu mai mult de 1, `wins` cu mai mult
  de 1, iar un profil nou trebuie să pornească de la zero. Deployat.
  Integritatea clasamentului — paguba VIZIBILĂ — e acoperită.

  **Rămâne deschis, în ordinea gravității:**
  1. `users/{uid}` — balanța de monede/gems e în continuare scriabilă
     integral de proprietar. Nu se poate strânge cu reguli fără să rupă
     jocul: clientul scrie salvarea întreagă, iar salturile legitime
     (pachet cumpărat, jackpot la roată) sunt mari. Închiderea reală cere
     ca balanța să fie scrisă DOAR de Cloud Functions, adică rescrierea
     stratului de economie, care azi e local-first (SharedPreferences +
     sincronizare). Merită făcut abia când jocul face bani reali.
  2. ~~`matches/{id}` — vandalizabil de orice cont autentificat.~~ **REPARAT
     în cod 2026-09-03, REGULILE ÎNCĂ NEDEPLOYATE.** Documentul meciului ține
     acum `playerIds`, iar regula e `request.auth.uid in
     resource.data.playerIds` (fără citire în plus). Verificat pe emulator
     (22/22), pe viu cu 2 conturi (creare + intrare + 5 runde, zero erori) și
     în Firestore de producție (câmpul chiar se scrie, cu ambele uid-uri).

     ⚠️ **ORDINEA DE PUNERE ÎN FUNCȚIUNE, obligatorie:**
     1. întâi ajunge aplicația asta la toată lumea — **web** (push pe main) și
        **Play** (build nou în closed testing, așteptat să se propage);
     2. **abia apoi** `firebase deploy --only firestore:rules`
        (`comenzi/4 - Trimite regulile Firestore in productie...bat`).

     Dacă se deployează regulile întâi, un tester pe un build vechi care intră
     într-o cameră creată de un client nou nu s-ar adăuga în `playerIds` și ar
     fi refuzat la prima rundă. Meciurile vechi, fără câmp, merg mai departe —
     regula are ieșire pentru ele.
  3. ~~Limitele noi n-au fost testate prin execuție pe partea de RESPINGERE.~~
     **FĂCUT 2026-09-02.** `test/firestore_rules_test.mjs` (14 cazuri) rulează
     pe emulatorul Firebase — mașina are deja Temurin JDK 25, doar că
     shim-ul `java8path` e primul pe PATH (vezi `test/README-reguli.md`
     pentru comanda cu `JAVA_HOME`). 14/14 verde: trișatul (leaguePoints
     999999, +21 puncte, seasonPoints umflat, meciuri/victorii inventate,
     salt de longestStreak) e refuzat, jocul normal (meci câștigat/pierdut,
     heartbeat cu merge, sezon nou) trece.
- **App Check pe „Enforce" — DECIS 2026-09-02 (userul): se renunță la canalul
  APK din GitHub Releases, toți testerii Android trec pe Play closed testing.**
  La Enforce, o cerere fără token App Check valid e refuzată de Firestore.
  `project_guess_it_app_check`.

  **Gata:** ambele aplicații sunt Registered în App Check (Android/Play
  Integrity, Web/reCAPTCHA Enterprise — clasic e blocat de Google). Codul
  folosește `ReCaptchaEnterpriseProvider`. Secretul `APPCHECK_RECAPTCHA_KEY`
  există în GitHub (adăugat 2026-09-02 14:15). Testele de reguli pe
  `player_profiles` acoperă deja unul din cele 3 motive de App Check
  (leaderboard scriabil); `completed_matches` era deja restrâns.

  **De făcut, în ordine, când e cineva să verifice:**
  1. ~~Redeploy web.~~ **FĂCUT + verificat 2026-09-02.** Redeploy prin push
     (workflow are acum și `workflow_dispatch`). Pe `rocketknife1.github.io/SodoQuizz`,
     Network arată acum: `recaptcha/enterprise/reload?k=6Lee...` → 200 și
     `content-firebaseappcheck.googleapis.com/.../exchangeRecaptchaEnterpriseToken`
     → 200. Auth + Firestore merg normal, zero erori în consolă. Web-ul chiar
     trimite token App Check acum (înainte: nimic).
  2. **Închide canalul GitHub APK.** Scoate linkul APK din `LINKS.md` +
     Discord, mută testerii pe Play closed testing (binar semnat de Play →
     Play Integrity merge). APK-ul sideloaded lua oricum `UNRECOGNIZED_VERSION`
     — nu există fix, e semnat cu cheia de upload.
  3. **Firebase Console → App Check → metrics.** Confirmă ce procent din
     cereri vin verificate. Dacă web + Play acoperă aproape tot, flipul e sigur.
  4. **Flip Firestore pe Enforce.**

  **Ce rămâne descoperit chiar și după flip:** vandalizarea meciurilor
  (`matches/{id}`) și balanța din `users/{uid}` — reale, dar cu impact mic
  până la bani reali (vezi punctele 1-2 de la Audit #1 mai sus).

## Datorie tehnică, fără grabă

- **Granularitatea reconstrucției.** 221 `setState` față de 8
  `ValueListenableBuilder` în tot proiectul. Ecranele grele merită mutate
  treptat pe reconstrucție țintită. Nu mai e urgent după reparațiile de
  cronometre din `0e71b19`.
- **Flutter 3.27.4 e din ianuarie 2025.** Un upgrade aduce îmbunătățirile de
  Impeller acumulate de atunci. Operație separată, poate rupe pluginuri — nu
  de făcut pe fugă.
