# Ce mai e de făcut

Doar task-uri deschise. Ce s-a rezolvat stă în git + memorii, NU aici.
Notele de lucru pentru Claude sunt în memorii, nu aici.
Ultima curățare: 2026-09-07.

---

## Cod de scris ACUM

Nimic. Toată secțiunea RETENȚIE (1-8) e livrată și testată cu 2/4 jucători.

---

## Înainte de a trimite un build în Play

1. **AAB nou** — `flutter build appbundle --release` (FĂRĂ `REAL_ADS`).
   Cel vechi e din `b805052`, dinainte de tot ce s-a livrat după.
   `REAL_ADS=true` se pune abia la lansarea în PRODUCȚIE, nu la testeri
   (reclame reale la un grup mic = risc de suspendare AdMob).

2. **Formularul Data safety** — o singură trecere, toată lista deodată:
   - deja declarat: email (Firebase Auth), nume afișat, progres de joc
   - Crashlytics → „Crash logs" + „Diagnostics"
   - Analytics → „App interactions" + „Other actions"
   - rapoarte „Trimite raportul" → „Diagnostics" (NU „User messages" —
     nimic scris de jucător)
   - Remote Config → doar citește, probabil nicio bifă (verifică la final)
   - Play Console → App content → Data safety

3. **Scoate `matchLegacyPlayerDoc()` din `firestore.rules`** — regulă
   tranzitorie care lasă clienții vechi (fără `playerIds`) să scrie în
   `matches`. De scos după ce build-ul cu `playerIds` ajunge la toți pe
   Play (web e deja acolo). După ștergere: rulează testele de reguli și
   scoate și cazul „meci vechi fără playerIds".

---

## Polish (nu blochează lansarea)

- **Categoria Matematică** — poze cu matematicieni de ghicit (cere linia
  `assets/continut/matematica/poze/` în `pubspec.yaml`) + mai multe
  întrebări. Toate răspunsurile unice global (`test/question_loader_test.dart`).
- **Curățare colecții care se adună** — `daily_challenges/{dată}/scores` +
  `events/{id}/scores` cresc cu ~1 doc/jucător/zi. Purge lunar sau TTL
  Firestore când contează. (`room_invites` nu se mai acumulează din 2026-09-06.)

---

## Decizii care te așteaptă pe TINE (nu e task de cod până nu decizi)

- **IAP / magazin cu bani reali** — se face ÎN testarea închisă, ÎNAINTE de
  a cere accesul la producție (testerii licențiați cumpără fără să fie
  taxați). Pasul ZERO = validarea bonului pe server (Cloud Function), NU
  rescrierea economiei. Detalii complete + ordinea pașilor + capcana
  ferestrei de 3 zile: memoria `guess-it-iap-prerequisites`.

- **Dificultate Easy/Medium/Hard pe întrebare** — decizie de CONȚINUT, nu de
  cod. Nu există niciun semnal din care s-o deduc azi. Fie etichetezi manual
  ~1.494 de întrebări (în xlsx), fie se măsoară din rata reală de răspuns
  corect (colecție nouă + bază de jucători). Nu inventez o valoare fără date.

- **`users/{uid}` scriabil de client** — azi doar DETECTAT
  (`onBalanceAudit` → `security_flags`, vizibil în panoul Admin), nu blocat.
  Blocarea reală cere balanța scrisă doar de Cloud Functions = rescriere
  economie. Merită abia la bani reali.

---

## Blocat pe bază de jucători (RETENȚIE 9-12)

Moduri în echipă (2v2/3v3), turnee/bracket, clanuri, spectating. Toate cer
mulți jucători simultan ca să aibă sens. Nu se ating până jocul nu prinde.

---

## Datorie tehnică (fără grabă, NU odată cu o lansare)

- **Lanțul de build Android** — Gradle 8.14 → ≥9.1, AGP 8.11.1 → ≥9.0.1,
  Kotlin 2.2.20 → ≥2.3.20. De la AGP 9 se citește doar DSL-ul nou, deci
  `android/app/build.gradle` trebuie rescris. Șantier separat.
- **Granularitatea reconstrucției** — 221 `setState` vs 8
  `ValueListenableBuilder`. Ecranele grele merită mutate treptat pe
  reconstrucție țintită.
- **Flutter 3.47.2** — ok acum. Upgrade-urile aduc îmbunătățiri Impeller
  dar pot rupe pluginuri. Nu pe fugă.
