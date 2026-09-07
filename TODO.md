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

1. **Analytics de produs — funnel + per-mod.** Firebase Analytics e deja
   legat. De adăugat ~15 evenimente la punctele care contează:
   `first_open → first_game → first_multiplayer → first_win →
   second_session → day2/7/30`, plus per-mod `start/finish/quit/rematch`.
   **De ce primul:** fără el ghicești ce e „plictisitor". Ieftin, rezolvă
   deciziile de mai jos cu date, nu cu păreri.

2. **Async Challenge — „Provoacă un prieten".** Primești 10 întrebări, le
   faci, jocul generează un cod/link (`share_plus` + `app_links` sunt deja
   în pubspec). Prietenul intră când poate și primește EXACT aceeași rundă.
   La final: scorul tău vs al lui. Fără boți, fără meci fals, fără
   simultaneitate. **De ce e cel mai important:** singura formă de
   multiplayer care merge la 0 jucători online — exact gaura de 4/10.
   Tehnic: mecanica Provocării Zilei + un seed partajabil + un doc de
   scoruri pe id de provocare. Efort mediu.

3. **Personal Records.** Cel mai mare scor, cel mai rapid răspuns, cel mai
   lung streak, cea mai bună/proastă categorie, „+X% față de acum 7 zile".
   **De ce:** progres chiar și când nu e nimeni online. Ieftin — jumătate
   din statistici deja există (streak, winrate), e mai mult stocare + ecran.

4. **Category Mastery.** Nivel per categorie: întrebări întâlnite, accuracy,
   best streak, titlu la mastery 10 („Maestru Auto"). **De ce:** conținutul
   devine progres, nu combustibil consumabil — „mai joc ca să termin
   categoria", nu „mai joc pentru monede". Efort mediu (contoare per
   categorie + ecran). Se leagă de titlurile care există deja.

5. **Modul zilei în multiplayer.** „🔥 AZI: TANKS" — ales determinist pe
   dată, cu bonus XP + clasament separat. „Join Online" te bagă în modul
   ăla. **De ce:** o coadă recomandată în loc de 6 goale; jucătorul nou nu
   învață 6 moduri deodată. Ieftin — același tipar ca „categoria zilei".

6. **Politică de abandon în multiplayer.** Deconectare temporară →
   reconectare permisă (există deja). Abandon definitiv (heartbeat mort peste
   prag) → meci PIERDUT. Abandonuri repetate → cooldown la ranked. **De ce:**
   altfel „își dă seama că pierde → închide jocul", iar adversarul rămâne
   agățat. Se leagă de filozofia anti-reluare de acum
   (`guess-it-anti-replay`). Efort mediu.

7. **Onboarding mai strâns.** Tutorialul de 3 pași există. GPT vrea 4 pași
   și-atât: „ghicește poza / răspunde rapid / mai rapid = mai multe puncte /
   acum joacă primul meci". Fără monede/gems/quest-uri în tutorial. Efort
   mic — rafinare, nu construcție.

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
- **Titlul „Boboc" nu se afișează pe cont nou** — INTENȚIONAT azi
  (`cosmetic_title.dart` întoarce `SizedBox.shrink()` pentru `novice`).
  Consecință: un jucător nou nu vede că există sistem de titluri. DECIZIE:
  îl arătăm și pe „Boboc" (titlu amuzant, gen „Fresh Meat" din LoL) sau
  rămâne ascuns?

---

## Decizii care te așteaptă pe TINE

- **IAP / magazin cu bani reali** — GPT: NU rușa. Întâi dovada că oamenii
  joacă (install → first game → second game → return), abia apoi plăți.
  IAP în closed testing = doar pentru validare tehnică, nu ca să transformi
  jocul într-o economie agresivă. Pasul ZERO = validarea bonului pe server.
  Detalii: memoria `guess-it-iap-prerequisites`.

- **Miza pe monede în multiplayer = gambling-adjacent** (observație GPT
  nouă). Azi e ok (monede virtuale), dar dacă monedele devin cumpărabile,
  „pui miză, câștigătorul ia potul" seamănă cu pariuri. GPT: monetizează
  cosmetice/bundle-uri/convenience, ține rezultatul competitiv INDEPENDENT
  de miză. De cântărit înainte de IAP.

- **Dificultate Easy/Medium/Hard** — GPT confirmă: NU manual la început.
  După trafic: estimată din date (95% corect → Easy, 70% → Medium,
  40% → Hard, 15% → Extreme), ajustată cu timpul mediu, apoi corectat
  manual cazurile bizare.

- **`users/{uid}` / rating / league points scriabile de client** — GPT:
  🟡 acceptabil pentru closed testing, 🔴 obligatoriu de reparat la lansare
  serioasă. Regula de aur GPT (mai bună decât „rescrie economia"):
  XP tolerant · cosmetice client-cache ok · **ranking competitiv → server** ·
  **monedă premium → server** · **cumpărături → server** ·
  **revendicări de recompense → server**. Doar partea competitivă +
  bani-adiacentă, nu tot stratul de economie.

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
