# Ce urmează

Ce rămâne deschis. Detaliile implementărilor stau în git + memorii, nu aici.
Ultima curățare: 2026-09-01.

## De probat pe viu (cu 2-3 jucători reali)

Toate au trecut `flutter analyze` + `flutter test` și, o parte, recenzie
independentă — dar niciunul n-a fost jucat cu jucători reali:

- **Piatră-Hârtie-Foarfecă, finalul de meci.** Verificat live cu 2 jucători:
  apare în selector, miza și tabelul de premii merg, camera se creează și se
  intră cu cod, runda se rezolvă corect (piatra bate foarfeca → +1, listă
  resortată), egalitatea dă 0 puncte. NEVERIFICAT: finalul la 10 puncte,
  plafonul de 30 de runde și plata premiilor (ar fi cerut 10 runde jucate).
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
