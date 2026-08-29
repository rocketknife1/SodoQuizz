# Ce urmează

Ce rămâne deschis. Detaliile implementărilor stau în git + memorii, nu aici.
Ultima curățare: 2026-08-29.

## De probat pe telefon (necablat cu jucători reali)

Modificările din commit `7aff8e8` (power-up-uri: gardă de fază, anunț la
primire, Double Shot rescris, cele 5 power-up-uri vizuale acum cu efect) au
trecut `flutter analyze` + `flutter test`, dar `reflect` / `allyShield` /
Double Shot ating tranzacția de rezolvare a rundei și **nu au fost jucate cu
2-3 jucători reali**. De verificat în meci real.

## Blocat pe tine — nu se poate din cod

- **Magazin cu bani reali (IAP).** Azi monedele/gems sunt virtuale;
  `premiumShopRevealed = false` ține blocul de preț ascuns. Nu se dezvăluie
  din proprie inițiativă — anunți tu.
- **Audit securitate #1** (scoruri multiplayer falsificabile direct din
  Firestore, premii acordate 100% local). Repararea cere o Cloud Function de
  validare server-side → cere planul Blaze.
- **Decizia Blaze.** Argumentul principal: Spark nu permite deloc Cloud
  Functions, deci blochează #1. Blaze costă $0 sub aceeași cotă gratuită ca
  Spark. Detalii complete în memoria `project_guess_it_security_audit_blaze`.

## Firebase Console — acțiuni de-ale tale

- **Alerte de buget** (Billing → Budgets & alerts) — gratuit, de făcut oricum.
- **App Check pe „Enforce"** — codul trimite deja tokenul; aplicația nu e
  înregistrată la App Check și e pe „Unenforced". Capcană: APK-ul sideloaded
  din GitHub Releases ia UNRECOGNIZED_VERSION și rămâne fără multiplayer/
  leaderboard/cloud save. Enforce doar după ce canalul ăla e acceptabil de
  pierdut. Vezi memoria `project_guess_it_app_check`.

## Rezolvat în 2026-08-29 (se șterge din listă data viitoare)

Commit `7aff8e8`: toate bug-urile de power-up raportate live + power-up-urile
vizuale + auditul securitate #2 (grant dublu) și #3 (`completed_matches`).
Șters fișierul gol `scriptul`. Regula `completed_matches` din `firestore.rules`
**încă nedeployată** — `firebase deploy --only firestore:rules`.
