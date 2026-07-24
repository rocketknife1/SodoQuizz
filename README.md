# Guess It

Guess It este o aplicație Flutter de tip quiz: o imagine se limpezește
treptat pe măsură ce folosești hint-uri, iar tu alegi răspunsul corect
din 4 variante. Patru gamemoduri, aceeași mecanică peste tot.

## Unde găsesc conținutul jocului (întrebări + poze)

Tot ce ține de conținut e într-un singur loc: **`assets/continut/`**,
cu câte un subfolder per gamemod. Aici adaugi/editezi întrebări sau
încarci poze manual:

```
assets/continut/
  pixelat/    intrebari.json + poze/   (desene animate & filme)
  logouri/    intrebari.json + poze/   (branduri cunoscute)
  jocuri/     intrebari.json + poze/   (Gamers Cave — trivia Steam)
  medical/    intrebari.json + poze/   (obiecte medicale)
```

- **`intrebari.json`** — toate întrebările unui gamemod: răspuns, 3 hint-uri,
  4 variante de răspuns, punctaj maxim.
- **`poze/`** — o poză per întrebare, numită după `id`-ul întrebării
  (ex: `daf_001.png`). Dacă lipsește o poză, jocul arată un fallback
  simplu (iconiță colorată) — nu crapă.
- Ca să adaugi un gamemod nou: un folder nou aici + o intrare în lista
  `gameModes` din [lib/core/gamemodes.dart](lib/core/gamemodes.dart)
  (titlu, culoare, iconiță). Restul aplicației (home screen, ecranul de
  joc) le preia automat, fără alte modificări.
- Script-uri de ajutor pentru conținut (generare întrebări, descărcare
  poze potrivite cu răspunsul, eliminare duplicate) sunt în
  [tools/](tools/) — vezi comentariul din capul fiecărui fișier `.py`.

## Structura codului (`lib/`)

- `main.dart` — punctul de intrare.
- `core/` — regulile jocului: `gamemodes.dart` (lista celor 4 moduri, o
  singură sursă de adevăr) și `game_helpers.dart` (scor, hint-uri, blur).
- `data/` — încărcarea întrebărilor din assets și stocarea locală
  (vieți, monede, progres, highscore) prin `shared_preferences`.
- `models/` — modelul `Question`.
- `screens/` — `home`, `loading`, `game`, `shop` (shop e dezactivat
  momentan din meniu, cod gata pentru mai târziu).
- `widgets/` — componente reutilizate în ecranul de joc (imagine cu
  blur, banner de rezultat, butonul de mai departe).

## Verificare locală

```
flutter analyze
flutter test
flutter run -d chrome   # sau -d windows / device conectat
```
