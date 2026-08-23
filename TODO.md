# Ce urmează

Document de orientare, actualizat după fiecare sesiune mare — nu e un plan
de implementare (acela a fost `PLAN_DE_VIITOR.md`, șters pe 2026-08-23 după
ce toate cele 5 puncte au fost făcute și verificate). Aici stă doar ce
rămâne deschis și ce s-a menționat vreodată ca direcție viitoare.

## Rămas din sesiunea "Plan de viitor v1" (2026-08-23)

Liga cu sezoane, badge de ligă, evenimente în Obby (rundă dublă + a doua
șansă), recompensă instant în Obby, categoria zilei — toate au fost
construite și verificate. Trei lucruri au rămas deschise:

1. **Bug real, preexistent, găsit în timpul testării** — în
   `lib/screens/multiplayer/multiplayer_results_screen.dart`, la egalitate
   pe locul 1 între doi jucători, doar cel cu `myIndex == 0` primește
   `draw = true`; celălalt (același scor, dar afișat pe locul #2) primește
   `won = false, draw = false` — adică e scris ca **înfrângere**, nu remiză.
   Afectează toate modurile multiplayer, nu doar Obby. Nu a fost atins —
   era în afara scopului sesiunii respective.
2. **Obby cu evenimentele noi — neverificat pe telefon.** Codul a fost
   verificat solid, de două ori, cap-la-cap, cu doi jucători reali în
   browser (Playwright), fără nicio excepție. Pe telefon, testul automat a
   picat din motive de input inconsistent pe device (nu de cod — a dus la
   crearea unei camere cu modul greșit, Astro Sodo, care n-a fost atins
   deloc în sesiune). Merită un test manual, cu adevărat pe telefon, la
   următoarea ocazie.
3. **Ecranul de Profil — neconfirmat separat pe telefon** (identic
   verificat pe web: badge de ligă + "puncte sezonul ăsta · pe viață").

## Planuri menționate în trecut, neîncepute încă

- **Magazin cu bani reali (IAP).** Monedele/gems sunt azi 100% virtuale
  (`pubspec.yaml` n-are `in_app_purchase`). Userul a confirmat intenția în
  timpul înregistrării pe Play Console: shop-ul va deveni cumpărare reală.
  Blocul de preț real din `shop_screen.dart`/`lib/data/shop.dart` e
  deliberat ascuns în spatele unui văl "În curând"
  (`premiumShopRevealed = false`) — **nu se dezvăluie din proprie
  inițiativă**, userul a zis explicit că anunță el când.
- **Link de invitație pentru prieteni.** Spec ales, nimic implementat:
  schemă URI proprie `guessit://addfriend/<cod>` (aleasă în locul unui
  Android App Link complet, ca să nu ceară `assetlinks.json` găzduit). Ar
  intra prin pachetul `app_links`, un intent-filter în
  `AndroidManifest.xml`, plus un buton de "share" lângă cardul de cod din
  `friends_screen.dart`.
- **Ecran negru (Impeller) la revenirea dintr-un Activity extern** (ex.
  login Google) — bug confirmat, reproductibil, cauzat de renderer-ul
  Impeller/Vulkan pe acest GPU (Samsung Xclipse). Soluție candidat, NEAPLICATĂ
  încă: `<meta-data android:name="io.flutter.embedding.android.EnableImpeller"
  android:value="false" />` în `AndroidManifest.xml`, ca să cadă pe Skia.
  Userul a cerut explicit doar să fie notat, nu schimbat, pe 2026-08-02 —
  verifică dacă mai vrea asta înainte s-o aplici.

## Deja făcut, nu mai e de pus aici

Sistemul de siguranță (raportare, blocare, filtru de cuvinte, chat privat
între prieteni) apare deja implementat în cod (`moderation_service.dart`,
`blocked_players_screen.dart`, `chat_filter.dart`, `friend_chat_service.dart`)
— planul vechi din memorie care spunea "necommitat" e depășit.
