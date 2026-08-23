# SodoQuizz

SodoQuizz este o aplicație Flutter de tip quiz: o imagine se limpezește
treptat pe măsură ce folosești hint-uri, iar tu alegi răspunsul corect
din 4 variante. Patru gamemoduri, aceeași mecanică peste tot.

## Unde găsesc conținutul jocului (întrebări + poze)

Tot ce ține de conținut e într-un singur loc: **`assets/continut/`**,
cu câte un subfolder per gamemod. Aici adaugi/editezi întrebări sau
încarci poze manual:

```
assets/continut/
  cartoon/    intrebari.json + poze/   (desene animate & filme)
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
- `core/` — regulile jocului: `gamemodes.dart` (lista gamemodurilor),
  `game_helpers.dart` (scor, hint-uri, blur), `progression.dart`
  (nivel/XP, quest-uri zilnice, realizări), `audio.dart` (muzică de fundal
  + efecte sonore).
- `data/` — încărcarea întrebărilor din assets, stocarea locală
  (vieți, monede, progres, highscore) prin `shared_preferences`, plus
  autentificare/cloud-save și multiplayer (Firebase).
- `models/` — `Question` și modelele de multiplayer.
- `screens/` — un fișier per ecran; `multiplayer/` grupează cele 6
  ecrane ale fluxului de multiplayer (create/join room, matchmaking,
  meci, rezultate, clasament).
- `widgets/` — componente reutilizate; `mascots/` grupează cele trei
  mascote decorative de pe Home și micul "dispecer" de evenimente comun
  lor (`mascot_sync.dart`).

## Ce urmează

Ce a rămas deschis după ultima sesiune mare + planuri menționate dar
neîncepute încă: [TODO.md](TODO.md).

## Verificare locală

```
flutter analyze
flutter test
flutter run -d chrome   # sau -d windows / device conectat
```
