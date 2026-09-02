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

## Animații pentru power-up-uri (cerut 2026-09-02)

Fiecare putere să aibă animația ei, unde se poate — azi efectul se vede doar
în cifre. Cerute explicit:

- **Double Shot**: proiectilul pleacă și **se desparte în două**, lovind
  ambele tancuri alese. Dacă unul evită (dodge), se vede tancul ferindu-se
  ȘI celălalt încasând — ambele momente prinse pe ecran.
- **Scut**: se vede din start scutul PE tanc, iar lovitura face vizibil
  `0 dmg` din cauza protecției.
- **Reflect**: proiectilul lovește tancul cu reflect, ricoșează și se
  întoarce spre trăgător, care încasează vizibil — ambele momente pe ecran.

Notă: decizia despre scut e luată și implementată — scutul la Quizz Tanks
blochează acum TOATE loviturile din rundă (inclusiv ambele proiectile ale
unui Double Shot). Animația de scut trebuie să arate asta corect: `0 dmg` la
fiecare lovitură primită, nu doar la prima.

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
  2. `matches/{id}` — `allow update: if request.auth != null` lasă ORICE cont
     autentificat să scrie în meciul oricui, iar `read` permite listarea, deci
     id-urile se pot afla. Vandalizarea meciurilor străine e posibilă.
     Restrângerea la participanți e ieftină DACĂ documentul meciului ține un
     câmp `playerIds`: regula devine `request.auth.uid in
     resource.data.playerIds`, fără nicio citire în plus. Varianta cu
     `exists(.../players/$(uid))` funcționează la fel, dar costă o citire
     facturată la FIECARE actualizare de rundă — pe calea cea mai fierbinte
     din joc.
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
