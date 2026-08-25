# Ce urmează

Document de orientare, actualizat după fiecare sesiune mare — nu e un plan
de implementare. Aici stă doar ce rămâne deschis.

## Power-up-uri — bug-uri raportate live pe telefon (2026-08-25)

Userul a jucat cu puterile din bara de sus și a găsit probleme reale:

1. **Se pot folosi oricând, inclusiv în momente greșite** (în timpul
   tragerii, după deznodământ etc.) — apăsarea "funcționează" (se scrie în
   Firestore pe `roundPowerUps`), dar dacă runda aia s-a rezolvat deja,
   scrierea ajunge prea târziu și puterea se pierde fără niciun semn vizibil
   pentru jucător. Lipsește o gardă de fază (ex. doar în `answering`/
   `targeting`, înainte de rezolvare) pe fiecare mod care are puteri de
   "luptă" (mega rachetă/scut/lovitură dublă la Quizz Tanks, scut/șoc
   perforant/scut de aliat la Scaunul Electric, jetpack/sabotaj la Obby).
2. **Lipsește o notificare la primirea unei puteri.** Acum doar apare
   pastila (`PowerUpChip`) în bara de sus — ușor de ratat. Userul vrea un
   anunț explicit (gen bannerul deja existent din `InAppNotification`/
   `_NotificationBanner`, folosit pentru quest-uri și prezența din
   multiplayer) care să spună clar "ai primit puterea X, apasă aici s-o
   folosești".
3. **Lovitură Dublă (double shot) la Quizz Tanks nu dă senzația de "mai
   mult daune"** — de design lovește DOI adversari cu daune normale
   fiecare, nu unul singur cu daune duble. Userul se aștepta la daune mai
   mari. De reclarificat cu el ce vrea de fapt (fie o descriere mai clară
   în joc, fie o schimbare de efect) înainte de a umbla la echilibrul
   modului.

De gândit per power-up, nu doar per mod: FIECARE putere are nevoie de o
fereastră clară de "acum se poate folosi", nu doar "e în inventar".

## Power-up-uri rămase doar vizuale, fără efect real

- Quizz Tanks: `PowerUp.allyShield`, `PowerUp.reflect`, `PowerUp.peek`.
- Scaunul Electric: `PowerUp.reflect`, `PowerUp.peek`.

Chip-ul apare și se poate "consuma" (dispare din bară), dar nu schimbă
nimic mecanic. Ar cere fiecare o interfață de alegere a țintei (aliat/
inamic) care încă nu există.

## Planuri menționate în trecut, neîncepute încă

- **Magazin cu bani reali (IAP).** Monedele/gems sunt azi 100% virtuale
  (`pubspec.yaml` n-are `in_app_purchase`). Blocul de preț real din
  `shop_screen.dart`/`lib/data/shop.dart` e deliberat ascuns în spatele
  unui văl "În curând" (`premiumShopRevealed = false`) — **nu se dezvăluie
  din proprie inițiativă**, userul a zis explicit că anunță el când.

## Fișierul `scriptul` din rădăcina proiectului

E gol (0 octeți) — nu face nimic. Probabil un fișier creat din greșeală
(ex. o redirecționare de shell către un nume greșit). Lăsat neatins,
nu e al acestei sesiuni.
