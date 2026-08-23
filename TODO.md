# Ce urmează

Document de orientare, actualizat după fiecare sesiune mare — nu e un plan
de implementare (acela a fost `PLAN_DE_VIITOR.md`, șters pe 2026-08-23 după
ce toate cele 5 puncte au fost făcute și verificate). Aici stă doar ce
rămâne deschis și ce s-a menționat vreodată ca direcție viitoare.

## Rămas din sesiunea "Plan de viitor v1" (2026-08-23)

Liga cu sezoane, badge de ligă, evenimente în Obby (rundă dublă + a doua
șansă), recompensă instant în Obby, categoria zilei — toate au fost
construite și verificate. Trei lucruri au rămas deschise:

1. ~~Bug de remiză~~ — **REPARAT 2026-08-23**: `matchOutcomeForScore` în
   `core/betting.dart`, folosit acum din `multiplayer_results_screen.dart`,
   testat (5 teste noi în `game_logic_test.dart`). Necommitat.
2. **Obby cu evenimentele noi — tot neverificat pe telefon.** Cod solid
   (verificat de două ori cap-la-cap cu doi jucători în browser). Pe acest
   telefon anume, meniul Multiplayer nu răspunde fiabil la tap-uri
   automate — zona vizuală „Cod cameră" declanșează sistematic „Meci
   rapid" în loc (verificat: nu e bug de layout în cod, cele trei butoane
   sunt separate corect). Renunțat la automatizare; rămâne de testat manual.
3. ~~Ecranul de Profil~~ — **CONFIRMAT pe telefon 2026-08-23** (badge de
   ligă + „0 puncte sezonul ăsta · 44 pe viață", identic cu web).

## Planuri menționate în trecut, neîncepute încă

- **Magazin cu bani reali (IAP).** Monedele/gems sunt azi 100% virtuale
  (`pubspec.yaml` n-are `in_app_purchase`). Userul a confirmat intenția în
  timpul înregistrării pe Play Console: shop-ul va deveni cumpărare reală.
  Blocul de preț real din `shop_screen.dart`/`lib/data/shop.dart` e
  deliberat ascuns în spatele unui văl "În curând"
  (`premiumShopRevealed = false`) — **nu se dezvăluie din proprie
  inițiativă**, userul a zis explicit că anunță el când.
- ~~Link de invitație pentru prieteni~~ — **CONSTRUIT ȘI VERIFICAT
  2026-08-23**: `guessit://addfriend/<cod>` prin `app_links`, intent-filter
  în `AndroidManifest.xml`, buton „share" cu `share_plus` în
  `friends_screen.dart`. Testat end-to-end pe telefon (cerere reală trimisă
  și primită între două conturi). Necommitat.
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
