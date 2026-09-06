# Ce urmează

Doar ce e DESCHIS, plus notele de care am nevoie ca să lucrez.
Ce s-a rezolvat stă în git + memorii, NU aici.
Ultima curățare: 2026-09-05.

---

## 🎯 RETENȚIE — „e plictisitor la un moment dat" (2026-09-05)

Feedback real de la jucători. Analiză făcută împreună cu userul + GPT + Claude,
cu acces la tot codul. **Diagnostic:** problema NU e „nu sunt destule
întrebări". E gameplay loop-ul: alegi un mod → 10 întrebări → câștigi →
repeți. Adăugarea de conținut nu repară asta.

### Ce EXISTĂ deja (ca să nu reconstruim din listă)

- **Cont/profil:** nume, avatar (5 stiluri), nivel, XP, statistici (winrate,
  meciuri, streak cel mai lung), istoric de ligă.
- **6 moduri multiplayer:** Clasic, Higher&Lower, Quizz Tanks, Obby, Scaunul
  Electric (≈Sudden Death), Piatră-Hârtie-Foarfecă.
- **Meci:** countdown, întrebare + 4 variante, timer, scoring, runde multiple,
  ecran final cu clasament, miză pe monede.
- **Multiplayer online:** lobby/cameră, invitație prieteni (pe cod +
  „CHEAMĂ PRIETENII"), matchmaking public 1v1 (fără boți), reconectare
  (`markActiveMatch`), buton REVANȘĂ, anunț „cineva a intrat în multiplayer"
  (`multiplayer_presence`).
- **15 categorii**, ≈1.494 întrebări, raportare întrebare, hash stabil (fiecare
  meci = altă ordine).
- **Progresie:** XP → nivel → economie (v3), quest-uri (zilnice + generale),
  realizări (permanente), **ligi Bronze→Diamond + sezoane lunare**,
  leaderboard.
- **Zilnic:** categoria zilei, Daily Challenge (quest), streak de login
  („2 zile la rând"), Roata (1/zi), Clippy (la 5 min), Planeta (2 rulări/12h).
- **Setări:** sunet/muzică, limbă RO/EN, block/report player, privacy,
  ștergere cont, **tutorial** (nou), ecran de întreținere (RemoteGate),
  ecran de eroare cu „Trimite raportul".

### Ce LIPSEȘTE cu adevărat — ordonat după cât mișcă retenția / cât costă

**Nivel 1 — ieftin, efect direct, de făcut înaintea oricărui mod nou:**

1. ✅ **Recompense COSMETICE pe nivel** — LIVRAT 2026-09-05 (branch
   `worktree-cosmetice-pe-nivel`, spec+plan în `docs/superpowers/`). Rame de
   avatar (5 ligi + 3 praguri de nivel) + ~10 titluri deblocate pe
   nivel/ligă/realizări. Proprietatea NU se stochează — se recalculează din
   XP/ligă/realizări. Picker cu 3 file (Avatar/Ramă/Titlu) la apăsarea pe
   avatar în Profil. Se văd în clasament (+ „Nivel N" lângă nume), profil,
   listă prieteni. `player_profiles` are 3 câmpuri noi (`equippedFrame`,
   `equippedTitle`, `level`), scrise la heartbeat; regulile testate (51/51).
   **NEVERIFICAT pe telefon** (butonul „DEBLOCHEAZĂ COSMETICELE" din Admin →
   Debug e pus pentru asta) și **NEVERIFICAT** că un al 2-lea jucător îmi
   vede rama/titlul în meci — `MatchPlayer` nu carează încă `equippedFrame`/
   `equippedTitle`, badge-ul de meci arată doar avatarul + rama proprie
   (extindere viitoare, mică). La probă pe telefon: după instalarea unui
   build nou, ramele pe NIVEL ale altor jucători pot lipsi din clasament
   până când fiecare își redeschide aplicația o dată (`level` se scrie la
   heartbeat) — normal, se auto-repară; ramele de ligă nu sunt afectate.
2. ✅ **Provocarea Zilei cu MIZĂ** — LIVRAT 2026-09-06 (commit `f39aba4`).
   Set FIX de 5 întrebări pe zi, acelaşi pentru toată lumea (determinist,
   `core/daily_challenge.dart`), o singură rulare pe zi, recompensă 40/corect
   + 150 bonus la 5/5 (max 350 monede). Clasament „de azi" global top-20 +
   locul tău (`daily_challenges/{data}/scores/{uid}`, monedele legate de scor
   prin regulă). Card în capul ecranului de Quest-uri. Rulează şi quest-ul
   `daily_challenge_done`. Reguli testate 58/58, deployate. **VERIFICAT pe telefon 2026-09-06**
   (flow complet, +80 monede la 2/5, cardul în ambele stări). Board cu ≥2
   jucători — neverificat (bază goală). Ajustabil: recompensa (o
   constantă în `dailyChallengeReward`), nr. de întrebări
   (`dailyChallengeQuestionCount`). Curăţarea colecţiilor `daily_challenges`
   vechi — niciun job încă; se adună câte un doc/jucător/zi. TTL Firestore
   sau un purge lunar când contează.
3. **Prieteni online / recent players.**
   - ✅ **Indicator „activ acum"** — LIVRAT 2026-09-06. `PlayerProfile.isRecentlyActive`
     (`lastActive` sub 5 min). Bulină verde pe avatarul prietenului + „Activ acum",
     prietenii activi sus în listă; același indicator în fișa publică din clasament.
     Zero citiri Firestore noi. NEVERIFICAT cu un prieten real activ (bază goală).
   - ✅ **„Jucători recenţi"** — LIVRAT 2026-09-06. Ecranul de rezultate
     salvează adversarii local (`StorageService.addRecentOpponents`, JSON, cap
     15). Secţiune nouă în ecranul de Prieteni: adversarii care nu-s deja
     prieteni, cu buton „Adaugă". #3 COMPLET.
   - Notă: fără heartbeat periodic; `lastActive` se rescrie doar la
     deschidere/resume/profil. Dacă „activ acum" trebuie mai precis, un
     `Timer.periodic(~90s)` în `main.dart` peste `ensureProfileHeartbeat`.
4. **Party persistentă.** Joci un meci cu un prieten → REVANȘĂ merge, dar nu
   poți sta 3-4 într-un lobby și schimba modul între meciuri. Camera se
   închide după meci.

**Nivel 2 — mediu, ține oamenii pe termen lung:**

5. **Ladder vizibil cu rating.**
   - ✅ **Rating Elo vizibil** — LIVRAT 2026-09-06. `PlayerProfile.rating`
     (start 1000, `core/elo.dart` K=24). La finalul meciului, ecranul de
     rezultate citeşte ratingul adversarilor şi calculează o deltă pe perechi
     (plafonat ±24/meci, împărţit la nr. adversari). Afişat pe profil. Reguli:
     ±30 max/scriere.
   - ⏳ **Matchmaking pe rating** — amânat: cere bază de jucători ca să conteze
     şi atinge coada de matchmaking. De făcut când sunt destui jucători
     simultan.
6. ✅ **Recompense de sfârșit de sezon** — LIVRAT 2026-09-06. Fără job
   programat: `SeasonRewardService.snapshotIfSeasonEnded()` (în `main.dart`, la
   pornire) vede că `seasonKey`-ul de pe profilul propriu e din luna trecută cu
   puncte > 0 şi îşi salvează local tier-ul atins ÎNAINTE ca primul meci din
   luna nouă să reseteze totul. Dialog pe Acasă cu revendicare — 100 monede
   Bronze → 2000 Diamond (`core/season_rewards.dart`), o dată pe sezon. Doar
   monede (nu cosmetice — alea se recalculează oricum din XP/ligă). Buton debug
   „SIMULEAZĂ SFÂRȘIT DE SEZON". NEVERIFICAT pe telefon (cere cont admin pt
   butonul debug, sau aşteptarea unei luni noi).
7. ✅ **Evenimente limitate cu leaderboard separat** — LIVRAT 2026-09-06.
   Cheia Remote Config `eveniment_activ` (JSON, vezi `core/game_event.dart`) —
   `{id, titlu, categorie, start, sfarsit, bonus}`. Când e activ: card în
   Quest-uri + ecran (descriere, zile rămase, JOACĂ, clasament), bonus la
   monede pe categoria evenimentului (`game_screen`), clasament propriu
   `events/{id}/scores/{uid}` (puncte +max 50/scriere, verificat în reguli,
   64/64 pe emulator). Buton debug „SIMULEAZĂ UN EVENIMENT". Recompense la
   final = MANUAL (admin grant) — fără Cloud Function programată (evită Blaze).
   Când vrei un eveniment real: pui cheia în consola Firebase Remote Config.
8. **Emote-uri / reacții în meci.** Un strat de „prezență" — 4-6 emote-uri pe
   care le trimiți adversarului în timpul rundei. Ieftin, face meciul social.

**Nivel 3 — scump / are nevoie de bază de jucători pe care n-o ai încă:**

9. **Moduri în echipă (2v2 / 3v3).** Toate cele 6 moduri sunt FFA. Team battle
   cere rescris logica de scoring + lobby. Merită DOAR după ce ai destui
   jucători simultan.
10. **Turnee / bracket.** Idem — n-ai destui jucători ca un bracket să se
    umple.
11. **Clanuri.** Sistem întreg (creare, invitații, chat, leaderboard de clan).
    Doar dacă jocul prinde.
12. **Spectating.** `watchMatch` există read-only, dar UI-ul de spectator e
    muncă separată. Nu urgent la 3 jucători.

**Sisteme mici, dar de bifat înainte de lansare (nu retenție, igienă):**

- Indicator de conexiune / ping în meci + „Adversarul se reconectează...".
  RECONECTAREA TA există deja (`MultiplayerService.reconnectTarget` — ecranul
  rădăcină te duce înapoi în meci). Lipsește doar semnalul invers: „adversarul
  a picat / revine".
- ✅ Profil public — GATA 2026-09-06. `showPlayerProfileSheet` (fost
  `_showBreakdown`): tap pe un jucător în clasament SAU pe avatarul unui
  prieten în lista de Prieteni → fișa lui (nivel, meciuri, winrate, cel mai
  bun streak, ramă, titlu, punctaj pe moduri, ultima dată online). Restul
  rândului de prieten rămâne pe deschiderea firului privat.
- ✅ Leaderboard între prieteni — EXISTĂ deja: tab-ul „Prieteni" din ecranul
  Clasament (`_FriendsLeaderboardTab`), lista proprie + tu, sortată pe
  punctajul de sezon. Bulletul era stale.
- Dificultate Easy/Medium/Hard pe întrebare (azi doar „claritate"/blur)

### Recomandarea mea de ordine

**1 → 2 → 3 → 7 → 6 → 5**, restul pe măsură ce jocul prinde. Punctele 1-3 sunt
mici, se văd imediat, și rezolvă exact „progresia nu înseamnă nimic + greu să
joci cu prietenii". Punctul 7 (evenimente) e cel mai bun răspuns direct la
„lumea nu stă pe joc" — un motiv nou la fiecare 3-7 zile, fără build nou.

Se iau **pe rând**, fiecare cu design înainte de cod. Nu se începe niciunul
neîntrebat.

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

## ⚠️ RECLAME REALE LA TESTERI — de reparat la următorul build de Play

Build-ul pentru Play se face cu `--dart-define=REAL_ADS=true` (vezi
docs/build.md), deci **testerii din testarea închisă văd reclame REALE**.
Lista `_testDeviceIds` din `core/ads_service.dart` protejează DOAR telefonul
de dezvoltare — chiar așa scrie și comentariul de acolo.

Venitul e zero virgulă ceva la 20 de oameni, dar riscul nu e zero: reclame
servite unui grup mic și cunoscut, care testează aplicația, e exact tiparul de
**trafic invalid** pentru care AdMob suspendă conturi.

**Ce se face:** AAB-ul pentru testarea închisă se construiește **FĂRĂ**
`REAL_ADS`:

```
flutter build appbundle --release
```

`REAL_ADS=true` se pune abia la lansarea în PRODUCȚIE. Că fluxul de reclame
merge se verifică pe telefonul de dezvoltare, care e deja înregistrat ca
dispozitiv de test și primește reclame marcate „Test Ad".

**GATA 2026-09-06:** AAB construit (fără `REAL_ADS`, semnat cu keystore-ul de
upload) la `build/app/outputs/bundle/release/app-release.aab` (126.7 MB, cod
de pe `main` la commit `b805052`). Rămâne doar să-l urci în Play Console —
**dar întâi formularul Data safety** (secțiunea de mai jos).

---

## Scăpări mici, găsite dar nereparate

- ✅ **`room_invites` se adună la nesfârșit** — REPARAT + DEPLOYAT 2026-09-06.
  `onRoomInvite` șterge acum invitația imediat după push. Verificat: clientul
  ia `matchId`/`code` din payload-ul notificării, nu citește documentul.
  **Rămâne (opțional):** o curățare unică a documentelor vechi — 
  `firebase firestore:delete room_invites --recursive --force --project sodoquizz`
  (blocat de clasificator când a încercat Claude; rulează-l tu). Câteva zeci
  de docuri, inofensive; fix-ul oprește acumularea de-acum.

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

- **Magazin cu bani reali (IAP).**

  **CÂND: înainte de a cere accesul la producție, cât ești ÎNCĂ în testarea
  închisă.** Userul credea (2026-09-05) că se adaugă abia după ce aplicația
  apare în căutarea din Play — e pe dos. Produsele se pot testa din orice
  canal, inclusiv închis
  ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/6062777?hl=en)),
  iar testerii licențiați cumpără FĂRĂ să fie taxați.

  Dacă amâni până ești public, primul om care dă bani reali e cobaiul tău.
  Dar nici nu se face acum: întâi lasă testarea închisă să-și facă treaba cu
  JOCUL, nu cu magazinul.

  Ordinea obligatorie:
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

ȘASE declanșatoare în `europe-west1`, toate pe **nodejs22**, DEPLOYATE
(redeployate 2026-09-06): onFriendMessage, onFriendRequest, onRoomInvite,
onSystemNotification, onAdminMessage, onBalanceAudit.

- `firebase-functions` (`^6.1.0`) e ok deocamdată; un upgrade major aduce
  **modificări incompatibile**, deci nu se face pe fugă odată cu altceva.
- Firebase avertizează la fiecare deploy despre `firebase-functions` vechi —
  benign, nu blochează nimic.

Comanda de deploy (PowerShell refuză shim-ul `.ps1`, de-aia `.cmd`):
```
firebase.cmd deploy --only functions --project sodoquizz
```
