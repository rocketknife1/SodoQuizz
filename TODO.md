# Ce urmează

Doar ce e DESCHIS. Ce s-a rezolvat stă în git + memorii, nu aici.
Ultima curățare: 2026-09-02.

## De probat pe viu (cu 2-3 jucători reali)

Toate au trecut `flutter analyze` + `flutter test`, o parte și recenzie
independentă — dar niciunul n-a fost jucat cu jucători reali.

- **Piatră-Hârtie-Foarfecă, finalul de meci.** Probat cu 2 jucători:
  selectorul, miza, crearea camerei, intrarea cu cod și rezolvarea rundei
  merg. NEPROBAT: finalul la 10 puncte, plafonul de 30 de runde și plata
  premiilor — ar fi cerut 10 runde jucate. Citit static la recenzia din
  2026-09-01 și e corect (meciul se închide în aceeași tranzacție care scrie
  scorurile), dar citit ≠ jucat.
- **Power-up-uri în Tanks / Obby / Scaunul Electric.** `reflect`,
  `allyShield` și Double Shot ating tranzacția de rezolvare a rundei. Cere 4
  jucători reali la Tanks. Include și reparațiile din `d471a03`: inventarul
  care acum apare și în faza de țintire, și regula „una pe rundă".
- **Acceptarea unei cereri de prietenie.** Gaura reparată în `2e2baa6` (cine
  îți ACCEPTĂ cererea nu-ți apărea în listă până nu ieșeai și intrai la loc)
  are test unitar, dar re-confirmarea vizuală n-a fost dusă la capăt —
  contextele de browser reutilizau identitatea anonimă între rulări. De
  reprobat cu un prieten real.

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
  3. **Limitele noi n-au fost testate prin execuție pe partea de RESPINGERE.**
     S-a confirmat pe viu doar că nu strică jocul: două conturi noi în
     browsere separate și-au creat profilul și au trimis heartbeat fără
     nicio eroare de permisiune. Testele de reguli sunt scrise
     (`scratchpad/rulestest/test.mjs`, 11 cazuri) dar emulatorul Firebase
     cere JDK 21, iar mașina are Java 8. De rulat după un upgrade de JDK.
- **App Check pe „Enforce" — analizat 2026-09-02, NU se poate flipa acum.**
  La Enforce, o cerere fără token App Check valid e refuzată de Firestore.
  Starea celor trei canale:
  - **Browser (github.io), canalul PRINCIPAL din LINKS.md** — nu trimite
    NICIUN token: workflow-ul de deploy n-avea `APPCHECK_RECAPTCHA_KEY`, deci
    `activateAppCheck()` ieșea pe web fără să facă nimic. Acum workflow-ul
    pasează cheia (ca secret de repo), dar **secretul încă nu există** —
    trebuie luat din Firebase Console → App Check → aplicația web și adăugat
    la Settings → Secrets → Actions ca `APPCHECK_RECAPTCHA_KEY`. Până atunci,
    web = zero protecție și Enforce l-ar rupe complet.
  - **APK din GitHub Releases (link în LINKS.md + Discord)** — ia
    `UNRECOGNIZED_VERSION`: e semnat cu cheia de upload, iar Play Integrity
    vouchează doar binare distribuite de Play. Nu există fix — ori se renunță
    la canalul ăsta (toți testerii Android → Play closed testing, care dă
    binarul semnat de Play), ori se acceptă că sideload = fără online.
  - **Play closed testing** — Play Integrity merge, singurul canal OK azi.
  **Pas următor, gratuit și informativ:** Firebase Console → App Check arată
  ce procent din cereri vin deja verificate, pe API, în ultimele zile. Dacă
  aproape tot traficul e browser + sideload (probabil), flipul rupe aproape
  tot — de amânat până distribuția se mută pe Play. `project_guess_it_app_check`.
  **Ce a scăzut valoarea flipului:** din 3 motive pentru App Check din
  `app_check_service.dart`, unul (leaderboard scriabil) e acum acoperit de
  regulile din 2026-09-02, altul (`completed_matches`) era deja restrâns.
  Rămân vandalizarea meciurilor și balanța din `users/{uid}` — reale, dar cu
  impact mic până la bani reali.

## Datorie tehnică, fără grabă

- **Granularitatea reconstrucției.** 221 `setState` față de 8
  `ValueListenableBuilder` în tot proiectul. Ecranele grele merită mutate
  treptat pe reconstrucție țintită. Nu mai e urgent după reparațiile de
  cronometre din `0e71b19`.
- **Flutter 3.27.4 e din ianuarie 2025.** Un upgrade aduce îmbunătățirile de
  Impeller acumulate de atunci. Operație separată, poate rupe pluginuri — nu
  de făcut pe fugă.
