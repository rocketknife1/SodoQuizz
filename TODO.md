# Ce urmează

Ce rămâne deschis. Detaliile implementărilor stau în git + memorii, nu aici.
Ultima curățare: 2026-09-01.

## De probat pe viu (cu 2-3 jucători reali)

Toate au trecut `flutter analyze` + `flutter test` și, o parte, recenzie
independentă — dar niciunul n-a fost jucat cu jucători reali:

- **Mod nou Piatră-Hârtie-Foarfecă** (`5f2bb26`). Logica pură = 15 teste.
  Fluxul complet (rundă → dezvăluire → final la 10 sau plafon 30 runde →
  premii cu miză) neverificat. Recenzia a prins 2 bug-uri (meci blocat la ≤1
  jucător, meci infinit) — reparate în `2206fe0`.
- **Mesaje + cereri de prietenie live** între 2 jucători (Sarcina 9 din
  timp-real, 4 runde de reparare + recenzie finală). Tiparul de abonament e
  identic cu grant/redenumire/ban, care AU fost verificate pe viu.
- **Power-up-uri în Tanks / Obby / Scaunul Electric** (`7aff8e8` + refactorul
  `118fab7` care a mutat interfața de power-up într-un fișier comun).
  `reflect` / `allyShield` / Double Shot ating tranzacția de rezolvare a
  rundei.

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

## Bug de unealtă — de reparat într-o sesiune viitoare

- **`tools/reset_all.py` nu poate șterge documente cu ghilimele sau `?` în
  id.** `question_reports` folosește textul întrebării ca id de document (ex.
  `Ce animal e "regele junglei"?_1787...`). REST-ul Firestore cere ca
  segmentul de path să fie URL-encodat; scriptul îl trimite brut și primește
  400. Consecință: un reset „complet" lasă în urmă rapoartele de întrebări.
  Găsit 2026-09-01, șters manual cu encoding. Fix: `urllib.parse.quote(id,
  safe='')` pe id înainte de `DELETE`, în `reset_all.py` (și oriunde altundeva
  scriptul construiește un path de document dintr-un id venit din date).
  Aceeași grijă pentru `question_reports` la scanarea subcolecțiilor.

## REGRESIE de reparat — animația de colectare vs. balanceRevision

Găsită pe viu 2026-09-01, introdusă de Sarcina 2 din timp-real (ecranele
ascultă `StorageService.balanceRevision`).

Simptome la revendicarea unui quest:
  - bara de XP crește ÎNAINTE ca jetoanele de XP să atingă badge-ul
  - balanța de inimi se actualizează ÎNAINTE ca jetoanele să ajungă în căsuță
  - balanța de MONEDE nu crește deloc

Cauză: `balanceRevision` se incrementează în `_writeBalance` (la scrierea în
SharedPreferences), care se face din start. Ascultătorii de pe Home fac
`setState` imediat și recitesc balanța, deci badge-ul sare la valoarea nouă
înainte ca `reward_collector` să "livreze" vizual jetoanele. Monedele probabil
merg pe o cale de aplicare amânată (după animație) care acum nu mai
declanșează un refresh corect, sau scrie într-un moment în care Home a
recitit deja.

Direcție de fix: `reward_collector` / ecranul de quest trebuie fie să aplice
TOATE resursele la finalul animației (nu unele înainte), fie badge-urile de
pe Home să ignore `balanceRevision` cât timp o animație de colectare e în
curs și să se sincronizeze la final. Prima variantă e mai curată. Verifică
`lib/core/reward_collector.dart` + `lib/screens/quests_screen.dart` +
handlerele de balanță din `home_screen.dart`.

## Rezolvat în 2026-08-31 / 09-01 (se șterge din listă data viitoare)

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
