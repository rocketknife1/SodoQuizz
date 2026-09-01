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
- **Audit securitate #1** — scorurile de multiplayer sunt falsificabile
  direct din Firestore, premiile se acordă 100% local. **Se poate ataca
  acum.** Planul Blaze e activ din 2026-08-31, deci soluția e disponibilă: o
  Cloud Function de validare server-side a scorului, singura care are voie să
  scrie premiile. Lucrare reală, nu un fix. Vezi memoria
  `project_guess_it_security_audit_blaze`.
- **App Check pe „Enforce"** — codul trimite deja tokenul, dar aplicația nu e
  înregistrată și e pe „Unenforced". Capcana: APK-ul sideloaded din GitHub
  Releases ia `UNRECOGNIZED_VERSION` și rămâne fără multiplayer, clasament și
  cloud save. Enforce doar după ce canalul ăla e acceptabil de pierdut. Vezi
  `project_guess_it_app_check`.

## Datorie tehnică, fără grabă

- **Granularitatea reconstrucției.** 221 `setState` față de 8
  `ValueListenableBuilder` în tot proiectul. Ecranele grele merită mutate
  treptat pe reconstrucție țintită. Nu mai e urgent după reparațiile de
  cronometre din `0e71b19`.
- **Flutter 3.27.4 e din ianuarie 2025.** Un upgrade aduce îmbunătățirile de
  Impeller acumulate de atunci. Operație separată, poate rupe pluginuri — nu
  de făcut pe fugă.
- **`intro_tutorial_dialog.dart` (253 de linii) nu e chemat de nimeni.** E
  dezactivat INTENȚIONAT, cu comentariu în `home_screen.dart:65`. De decis
  cândva: se repune în funcțiune sau se șterge.
