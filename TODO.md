# Ce mai e de făcut

Doar task-uri deschise. Ce s-a rezolvat stă în git + memorii, NU aici.
Notele de lucru pentru Claude sunt în memorii, nu aici.
Ultima curățare: 2026-09-07 (după feedback-ul GPT pe raport).

---

## URMĂTORUL VAL — retenție (feedback GPT, 2026-09-07)

**Diagnosticul GPT:** jocul NU mai duce lipsă de funcții. Fundația e bogată.
Problema e „care dintre funcțiile existente devine motivul principal de
revenire?" — se **consolidează**, nu se mai îngrămădește. Note GPT: Produs
8/10, Varietate 9/10, Fundație 8/10, Retenție potențială 7/10,
**Multiplayer la 0 jucători 4/10**, Securitate competitivă 6/10.

Ordinea de atac (a mea, ajustată față de a lui):

1. ✅ **Analytics de produs — funnel + per-mod** — LIVRAT 2026-09-07 (`0c5e752`).
   Pâlnia: `funnel_prima_partida / funnel_primul_multiplayer /
   funnel_prima_victorie` (o dată pe cont, `hitMilestoneOnce`) + first_open
   și retenția D1/D7 gratis de la Firebase. Multiplayer: `mp_start`,
   `mp_final {mod, castigat}`, `mp_revansa {mod, tip}` — nu era măsurat deloc.
   Abandon = `mp_start − mp_final` pe mod. `categorie_deblocata` wired.
   **De văzut în Firebase Analytics după ce intră trafic real.**

2. ✅ **Async Challenge — „Provoacă un prieten"** — LIVRAT 2026-09-07
   (`b7cb9ce`). Buton ⚔️ pe fiecare rând de prieten → joci 10 întrebări →
   share cod (`guessit://challenge/<id>`). Prietenul intră când poate,
   primește EXACT aceeași rundă → rezultat comparativ + recompense
   (120/60/0 monede + XP, plafon 5/zi). Push la creator când răspunde
   (`onChallengeAnswered`). Titlu nou „Aruncătoru' de Mănuși" la 15 câștigate.
   Reguli + funcție deployate. ✅ VERIFICAT cap-la-cap 2026-09-07 (telefon
   creează → browser intră cu codul → ACELEAȘI 10 întrebări → „YOU WON"
   1840 vs 890 → push la creator 1/1). Bug reparat pe drum (`39566d2`):
   creatorul și adversarul primeau seturi diferite de întrebări.

3. ✅ **Personal Records** — LIVRAT 2026-09-08. Tab-ul „Al tău" are acum
   secțiunea „Recordurile tale": cel mai mare scor, cel mai rapid răspuns
   corect, cea mai bună/slabă categorie (accuracy), „+X întrebări în 7
   zile" (instantaneu săptămânal, o dată/zi, FIFO 8). Tracking nou:
   `recordAnswerSpeed`, `recordCategoryAnswer`, `maybeTakeWeeklySnapshot`.

4. ✅ **Category Mastery** — LIVRAT 2026-09-08. `core/category_mastery.dart`:
   per categorie (întrebări văzute / accuracy / cel mai lung streak),
   „stăpânită" la 60 răspunsuri + 60%+. Ecran nou „Măiestrie pe categorii"
   din Profil. Titlu nou „Colecționar de Diplome" la 3 categorii
   (achievement `category_master_3`).

5. ✅ **Modul zilei în multiplayer** — LIVRAT 2026-09-08.
   `core/daily_mode.dart#modeOfDay` determinist dintr-un pool 1-la-1
   (Clasic / Higher & Lower / Piatra-Hartie). Join Online joacă modul
   zilei (nu mai alege aleator). Banner „🔥 AZI ÎN MECI RAPID" + bonus flat
   20 monede / 8 XP o dată/zi. FĂRĂ clasament separat — sezonul acoperă deja.

6. ✅ **Politică de abandon în multiplayer** — LIVRAT 2026-09-08.
   `core/abandon_policy.dart`: ieșire dintr-un meci ranked încă `playing`,
   fără scor final → meci PIERDUT (rating −12). 3 abandonuri într-o oră →
   Meci Rapid blocat 10 min (camerele cu cod rămân). Adversarul care
   abandonează era deja gestionat (timeout 12s la rezultate).

7. ✅ **Onboarding mai strâns** — LIVRAT 2026-09-08. Prima pornire: 4 pagini
   (ghicești poza / alegi din patru / mai repede = mai multe puncte / acum
   joacă). Versiunea de 12 pagini rămâne la „Revezi tutorialul" din Setări.

**Val 2 (după ce sunt date din analytics):**
- Server-authoritative pe partea competitivă (vezi secțiunea de decizii)
- Quality loop pe întrebări (accuracy / skip rate / report count per întrebare)
- Replay de meci + „share replay" (conținut social fără jucători online)
- UX de matchmaking („Caut adversar..." cu mesaje care escaladează la 3s/8s)
- Strategie de notificări (Prime Time, „Alex e online și a început un meci")

---

## Home — un singur „aur" vizual (feedback GPT)

Home are acum PLAY sus, dar și Roata / Clippy / Planeta / mascote care
aglomerează. GPT: un singur accent — **JOACĂ** — apoi dedesubt Daily
Challenge / Continue-Rematch / Friends Online, restul secundar.
Constrângere dură: `home_no_scroll` — tot trebuie să încapă fără scroll,
deci simplificarea e aliniată. Polish, nu blocant.

---

## Înainte de a trimite un build în Play

1. **AAB nou** — `flutter build appbundle --release` (FĂRĂ `REAL_ADS`).
   Cel vechi e din `b805052`, dinainte de tot ce s-a livrat după.
2. **Formularul Data safety** — o singură trecere, toată lista deodată:
   deja declarat (email, nume, progres) + Crashlytics („Crash logs" +
   „Diagnostics") + Analytics („App interactions" + „Other actions") +
   rapoarte bug („Diagnostics", NU „User messages") + Remote Config (doar
   citește). Play Console → App content → Data safety.
3. **Scoate `matchLegacyPlayerDoc()` din `firestore.rules`** — regulă
   tranzitorie pentru clienți vechi fără `playerIds`. De scos după ce
   build-ul cu `playerIds` ajunge la toți pe Play. Apoi rulează testele de
   reguli + scoate cazul „meci vechi fără playerIds".
4. **Sprint „documentation & release consistency"** (GPT) — README vechi,
   ecrane vechi, text Play Store, changelog, versiune. (`pubspec` +
   comentariul din `gamemodes.dart` — REPARATE 2026-09-07.)

---

## Polish (nu blochează lansarea)

- **Categoria Matematică** — poze cu matematicieni de ghicit (cere linia
  `assets/continut/matematica/poze/` în `pubspec.yaml`) + mai multe
  întrebări. Toate răspunsurile unice global (`test/question_loader_test.dart`).
- **Curățare colecții care se adună** — `daily_challenges/{dată}/scores` +
  `events/{id}/scores` cresc cu ~1 doc/jucător/zi. Purge lunar sau TTL
  Firestore când contează.
- ✅ **Titlul „Boboc"** — REZOLVAT 2026-09-08: se arată și „Boboc" /
  „Fresh Meat" pe cont nou, ca progresia de titluri să fie vizibilă.

---

## Decizii care te așteaptă pe TINE

Astea trei NU sunt fix-uri rapide — fiecare cere fie Blaze activ, fie o
decizie de timing la lansare, fie trafic real de date. Nu se ating solo,
fără o sesiune dedicată. Stare, 2026-09-08:

- **IAP / magazin cu bani reali** — BLOCAT pe: (1) dovada că oamenii joacă
  (install → first game → second game → return) din analytics; (2) validarea
  bonului pe server = pasul ZERO, cere Cloud Functions + Blaze. GPT: IAP în
  closed testing doar pt validare tehnică, nu economie agresivă. Detalii:
  memoria `guess-it-iap-prerequisites`. Când te apuci: sesiune separată.

- **Miza pe monede în multiplayer = gambling-adjacent** — de cântărit ÎNAINTE
  de IAP: dacă monedele devin cumpărabile, „pui miză, câștigătorul ia potul"
  seamănă cu pariuri. GPT: monetizează cosmetice/convenience, ține rezultatul
  competitiv INDEPENDENT de miză. Decizie de design, nu de cod, acum.

- **Dificultate Easy/Medium/Hard** — NIMIC de construit acum: GPT + planul
  spun explicit „NU manual la început". Se estimează din date DUPĂ trafic
  (95% corect → Easy … 15% → Extreme), apoi corectat manual cazurile bizare.
  Blocat pe trafic, nu pe muncă.

- **`users/{uid}` / rating / league points scriabile de client** — 🟡 ok
  pentru closed testing, 🔴 obligatoriu la lansare serioasă. Regula de aur
  GPT: XP tolerant · cosmetice client-cache ok · **ranking competitiv →
  server** · **monedă premium → server** · **cumpărături → server** ·
  **revendicări de recompense → server**. Șantier separat, cere Blaze;
  NU e „rescrie economia", doar partea competitivă + bani-adiacentă.

---

## Blocat pe bază de jucători (RETENȚIE 9-12)

Moduri în echipă (2v2/3v3), turnee/bracket, clanuri, spectating live. GPT e
de acord: nu se construiesc acum. (Replay de meci — DA, e în Valul 2 mai sus,
e altceva decât spectating live.)

---

## Datorie tehnică (fără grabă, NU odată cu o lansare)

- **Lanțul de build Android** — Gradle 8.14 → ≥9.1, AGP 8.11.1 → ≥9.0.1,
  Kotlin 2.2.20 → ≥2.3.20. De la AGP 9 se citește doar DSL-ul nou, deci
  `android/app/build.gradle` trebuie rescris. Șantier separat.
- **Granularitatea reconstrucției** — 221 `setState` vs 8
  `ValueListenableBuilder`. Ecranele grele merită reconstrucție țintită.
- **Flutter 3.47.2** — ok acum. Upgrade-urile aduc Impeller dar pot rupe
  pluginuri. Nu pe fugă.
