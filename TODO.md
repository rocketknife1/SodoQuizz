# Ce urmează

Ce rămâne deschis. Detaliile implementărilor stau în git + memorii, nu aici.
Ultima curățare: 2026-09-01.

## De probat pe viu (cu 2-3 jucători reali)

Toate au trecut `flutter analyze` + `flutter test` și, o parte, recenzie
independentă — dar niciunul n-a fost jucat cu jucători reali:

- **Piatră-Hârtie-Foarfecă, finalul de meci.** Citit static la recenzia din
  2026-09-01 și e corect: meciul se închide în ACEEAȘI tranzacție care scrie
  scorurile (nimeni nu poate citi „finished" cu scoruri pe jumătate scrise),
  cele trei ieșiri sunt acoperite (10 puncte / a rămas unul / plafonul de 30),
  iar plata trece prin `matchPrizesForRanking` ca la orice alt mod. Rămâne de
  probat pe viu. Verificat live cu 2 jucători:
  apare în selector, miza și tabelul de premii merg, camera se creează și se
  intră cu cod, runda se rezolvă corect (piatra bate foarfeca → +1, listă
  resortată), egalitatea dă 0 puncte. NEVERIFICAT: finalul la 10 puncte,
  plafonul de 30 de runde și plata premiilor (ar fi cerut 10 runde jucate).
- **Mesaje + cereri de prietenie** — PROBAT pe viu cu doi jucători în browser
  2026-09-01. Ce merge, confirmat cu capturi: cererea de prietenie apare
  singură în lista celuilalt, fără reload; mesajul trimis ajunge în fir.
  A ieșit la iveală și o gaură reală, reparată în `2e2baa6`: cine îți
  ACCEPTA cererea nu-ți apărea în listă până nu ieșeai și intrai la loc.
  **Reparația are test unitar, dar re-confirmarea ei vizuală n-a fost dusă
  la capăt** — contextele de browser reutilizează identitatea anonimă între
  rulări și starea devenise încurcată. De reprobat cu un prieten real.
- **Power-up-uri în Tanks / Obby / Scaunul Electric** (`7aff8e8` + refactorul
  `118fab7` care a mutat interfața de power-up într-un fișier comun).
  `reflect` / `allyShield` / Double Shot ating tranzacția de rezolvare a
  rundei.

## Recenzie independentă 2026-09-01 — reparat, dar NEPROBAT pe telefon

Doi recenzori pe zone diferite, pe ultimele 19 commit-uri (care nu trecuseră
prin nicio recenzie). Nimic din ce urmează n-a fost văzut pe dispozitiv real —
telefonul nu era conectat.

- **Roata: creșterea la 290 nu intrase deloc în efect.** `CustomPaint` fără
  copil își ia mărimea prin `constraints.constrain(...)`, iar `SizedBox`-ul
  rămăsese 240 — deci raza reală era 120, nu 145, și exact de-aia „1284+💎"
  tot nu încăpea. Reparat, plus eticheta trasă spre interior (0,81) și iconul
  la 0,55, ca textul lung să nu se atingă de el.
- **Roata: blur-ul de mișcare era invizibil.** Fantomele se desenau SUB discul
  real, care e complet opac și de aceeași mărime — acoperite pixel cu pixel.
  Rămânea doar costul: 4 repictări de disc întreg pe fiecare cadru. Acum se
  desenează deasupra, cu opacitate chiar descrescătoare.
- **Roata: constanta de trecere între faze era greșită** — viteza cădea la
  ~45% fix la mijloc, adică exact smucitura pe care trebuia s-o elimine.
  Cauza: „măsurasem" panta prin diferențe fine pe un `Cubic`, care rezolvă
  prin căutare binară cu toleranță 1e-3 — măsurasem zgomotul de cuantizare.
  Acum se deduce analitic din punctele de control (`p = y2/x2`).
- **Roata: Back în timpul rotirii** lăsa premiul neacordat. `PopScope`.
- **50/50 se consuma în gol.** N-avea fereastră de fază, deci trecea de gardă
  oriunde; corpul lui nu făcea nimic afară din `answering`. Puterea dispărea,
  nu se întâmpla nimic, și se ardea și dreptul la o putere pe runda aia.
- **„Timp în Plus" nu funcționa în NICIUN mod sincron.** Secundele erau o
  valoare locală, dar runda se închide când expiră cronometrul oricărui
  client — adversarul îți tăia runda la secunda normală. Scos din Tanks,
  Obby, Scaunul Electric și Higher & Lower (rămâne la Clasic, unde fiecare
  are propriul termen). **Decizie de-a ta:** dacă îl vrei înapoi, trebuie
  scris în documentul meciului ca să prelungească runda pentru toți — altă
  mecanică.
- **Inventarul de puteri lipsea din faza de țintire** la Tanks, deși șase
  puteri au fereastră fix acolo și tot acolo se și ACORDĂ puterea: primeai
  „ai primit o putere!" exact în ecranul în care n-aveai pe ce apăsa.
- **Pulsația pătrățelelor** cerea cadre la nesfârșit, inclusiv estompate —
  adică fix ce tocmai scosesem din tick-uri. Se oprește când sunt estompate.
- **Mesaj greșit**: „ai folosit deja o putere" spunea „prea târziu".
- **Ecranul de Prieteni** se golea într-un spinner la fiecare cerere primită
  (de două ori la o acceptare), pierzând poziția de derulare.
- **Bolovanii asteroizilor din Obby** rămăseseră pe `Random(seed)`, deci
  arătau altfel în browser față de telefon. Ultimul rest din reparația de
  consistență.
- **Teste**: testul curbei apăra doar o direcție (accelerare), nu și frânarea
  bruscă — adăugat, plus goldene pentru `StableRandom`, care n-avea niciunul.

## Găsite pe viu 2026-09-01 — TOATE REPARATE (se șterge data viitoare)

- **Culorile jucătorilor difereau între telefon și browser.** Cauza reală era
  mai largă decât părea: patru locuri se bazau pe `String.hashCode` sau
  `Random(seed)`, care dau valori DIFERITE în Dart VM față de dart2js. Cel mai
  grav dintre ele nu era cosmetic — **rotația de quest-uri**: același cont
  putea vedea alte quest-uri zilnice pe telefon față de browser. Reparat prin
  `stableHash` / `stableShuffle`, plus un `StableRandom` nou pentru cazul din
  Obby unde nu ajungea o sămânță stabilă. Test golden care reproduce exact
  simptomul raportat (cu `hashCode`, trei jucători primeau 2 culori; cu
  `stableHash`, 3).
- **Power-up-urile „nu se puteau selecta".** Logica era corectă — măsurat:
  pică în 31% din rundele câștigate dacă ești pe primul loc, până la 88% dacă
  ești ultimul. Problema era pastila: 9x4 px de padding, înghesuită între
  „RUNDA N" și cronometru. Acum e țintă de 40px cu pulsație. Prinde toate
  cele 5 moduri.
- **Roata norocului.** Curba își contrazicea comentariul: zicea „viteză mare,
  aproape constantă", folosea `Curves.easeIn` care pleacă de la viteză ZERO.
  Acum fază liniară + decelerare, cu vitezele potrivite la trecere.
- **Redesenări inutile.** Obby reconstruia tot ecranul de 10 ori pe secundă
  (inclusiv scena Flame), Tanks și Scaunul Electric de 4 ori — deși arena din
  Tanks ÎȘI ARE deja propriul `AnimatedBuilder`. Acum: tick adaptiv în Obby,
  o dată pe secundă în celelalte două.

## Rămâne din zona de fluiditate

- **Granularitatea reconstrucției, în general.** 221 `setState` vs 8
  `ValueListenableBuilder` în tot proiectul. Ecranele grele merită mutate
  treptat pe reconstrucție țintită. Nu e urgent după reparațiile de mai sus.
- **Flutter 3.27.4 e din ianuarie 2025** (un an și 7 luni). Un upgrade aduce
  îmbunătățirile de Impeller acumulate de atunci. Operație separată, poate
  rupe pluginuri — nu de făcut pe fugă.

## Blocat pe tine — nu se poate din cod

- **Magazin cu bani reali (IAP).** Azi monedele/gems sunt virtuale;
  `premiumShopRevealed = false` ține blocul de preț ascuns. Anunți tu când se
  dezvăluie.
- **Audit securitate #1** — scoruri multiplayer falsificabile direct din
  Firestore, premii acordate 100% local. **Acum SE POATE ataca** (planul
  Blaze e activ din 2026-08-31): cere o Cloud Function de validare
  server-side a scorului, care să fie singura care scrie premiile. E o
  lucrare reală, nu un fix — vezi memoria `project_guess_it_security_audit_blaze`.

## Firebase Console — acțiuni de-ale tale

- **App Check pe „Enforce"** — codul trimite deja tokenul; aplicația nu e
  înregistrată la App Check și e pe „Unenforced". Capcană: APK-ul sideloaded
  din GitHub Releases ia UNRECOGNIZED_VERSION și rămâne fără multiplayer/
  leaderboard/cloud save. Enforce doar după ce canalul ăla e acceptabil de
  pierdut. Vezi memoria `project_guess_it_app_check`.

## Rezolvat în 2026-08-31 / 09-01 (se șterge din listă data viitoare)

- **Regresia animației de colectare** — badge-ul se mișcă acum la impactul
  jetonului, nu la scrierea în storage. Pauză contorizată pe notificări, cu
  eliberare idempotentă (ultimul impact / ieșire timpurie / cronometru de 6s).
  O recenzie a prins că prima variantă putea îngheța TOATE badge-urile din joc
  până la restart — reparat.
- **`reset_all.py`** encodează id-urile pentru URL; un reset „complet" nu mai
  lasă în urmă rapoartele de întrebări.
- **Comenzile** (8 fișiere `.bat`) mutate în `comenzi/`, cu nume care spun ce
  fac și când se folosesc, plus `CITESTE-MA.txt`.
- **Mod nou Piatră-Hârtie-Foarfecă** — probat live cu 2 jucători (vezi mai sus
  ce a rămas neverificat).
- **Impeller (renderer-ul Vulkan) pornit la loc** — era oprit din cauza unui
  ecran negru după login-ul Google pe GPU-uri Samsung Xclipse. Retestat pe
  SM-S908B cu login complet + ciclu fundal/prim-plan: nu se mai reproduce,
  zero erori în logcat. Tanks se simte vizibil mai bine; roata norocului nu.

- **Timp real** (`13efb6b`, 27 commit-uri): tot ce vine din exterior — grant
  de la admin, redenumire, anunțuri, blocări, mesaje, cereri de prietenie —
  ajunge fără repornire. Balanța anunță dintr-un punct. Ordinea numelor
  într-o funcție pură; oricine își schimbă numele, inclusiv pe cont Google.
  Ban real, reversibil din tab-ul „Banați". Verificat pe viu pe Firebase
  real: grant/redenumire/ban/deblocare live, 0 scrieri în 2 min inactiv.
- **Reguli Firestore deployate** — `banned_players` (nou) + `completed_matches`
  (restanță din 2026-08-29). „Deploy complete!"
- **Planul Blaze activat** + alertă de buget $5 setată.
- **Curățenie de cod**: 8 metode moarte șterse, 141 linii duplicate de
  power-up unificate în `core/powerup_ui.dart`.
- **Release v1.0.2** publicat cu APK-uri; web redeployat; baza de date golită
  complet.
