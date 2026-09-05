# Cosmetice pe nivel — design

**Data:** 2026-09-05
**De ce:** item 1 din secțiunea RETENȚIE (TODO.md). Feedback real „e plictisitor
la un moment dat". Urci în nivel și primești doar monede — progresia nu se
**vede**. Rame de avatar + titluri deblocate prin nivel/ligă/realizări, vizibile
tuturor (clasament, meci, prieteni, profil).

**Clasificare:** arhitectural. Un singur plan de implementare, nedescompozabil
mai departe.

---

## 1. Catalogul — `lib/core/cosmetics.dart`

### Rame (`enum Frame`)

Cele 5 ligi (`LeagueTier` din `lib/core/leagues.dart`): bronze, silver, gold,
**platinum**, diamond. Tierul se ia cu `leagueTierIndexForPoints(leaguePoints)`.

| valoare | deblocare | aspect |
|---|---|---|
| `none` | mereu (implicit) | fără inel |
| `bronze` | tier >= bronze | inel bronz |
| `silver` | tier >= silver | inel argintiu |
| `gold` | tier >= gold | inel auriu |
| `platinum` | tier >= platinum | inel platină (cyan) |
| `diamond` | tier >= diamond | inel diamant (gradient) |
| `lvl10` | `level >= 10` | inel special (violet) |
| `lvl25` | `level >= 25` | inel special (portocaliu-auriu) |
| `lvl50` | `level >= 50` | inel special (curcubeu) |

`leaguePoints` e cumulativ pe viață (nu sezonier — ăla e `seasonPoints`), deci
practic doar urcă. Ramele de ligă se bazează pe el, NU pe un „high-water mark"
separat — nimic nou de urmărit. Culorile ramelor de ligă = `LeagueInfo.color`
existente, nu inventate.

### Titluri (`enum PlayerTitle`)

Text RO/EN. Praguri pe nivel + legături la realizări existente
(`lib/core/progression.dart`, lista `achievements`):

| valoare | deblocare | text RO |
|---|---|---|
| `novice` | nivel 1 (implicit) | Novice |
| `curios` | nivel 5 | Curios |
| `cunoscator` | realizarea `correct_50` | Cunoscător |
| `inAscensiune` | realizarea `level_5` | În ascensiune |
| `expert` | realizarea `correct_150` | Expert |
| `veteran` | realizarea `level_15` | Veteran |
| `explorator` | realizarea `all_modes` | Exploratorul |
| `maestru` | realizarea `correct_400` | Maestru |
| `nivel25` | nivel 25 | Legendă |
| `nivel50` | nivel 50 | Titan |

(Numărul exact și textele se pot ajusta la implementare — sunt date, nu
structură.)

### Funcții pure

```dart
bool ownsFrame(Frame f, {required int level, required int leaguePoints,
    required Set<String> unlockedAchievements});
bool ownsTitle(PlayerTitle t, {required int level, required int leaguePoints,
    required Set<String> unlockedAchievements});

Color frameColor(Frame f);            // sau Gradient pentru diamond/lvl50
(String, String) titleText(PlayerTitle t);   // (ro, en)
```

Aceleași funcții servesc DOUĂ apeluri: picker-ul (cu statisticile mele) și
validatorul de afișare (cu statisticile din profilul altcuiva).

---

## 2. Stocare și sincronizare

### Local — `SharedPreferences` (prin `StorageService`)

- `equipped_frame` — `String`, numele enum, implicit `'none'`
- `equipped_title` — `String`, implicit `'novice'`

**Proprietatea NU se stochează.** Se calculează la fiecare afișare din
XP/ligă/realizări. Nimic de ratat la deblocare, nicio migrare, niciun set de
sincronizat.

### Globali reactivi — `lib/core/cosmetics.dart`

Pe tiparul `myAvatarStyle` / `setMyAvatarStyle` (și `adminAnswerReveal`):

```dart
final ValueNotifier<Frame> myFrame = ValueNotifier(Frame.none);
final ValueNotifier<PlayerTitle> myTitle = ValueNotifier(PlayerTitle.novice);
Future<void> loadCosmetics();           // în main(), lângă loadAdminAnswerReveal
Future<void> setMyFrame(Frame f);       // scrie prefs + notifier
Future<void> setMyTitle(PlayerTitle t);
```

### `player_profiles` — 3 câmpuri noi

Scrise la heartbeat (`PlayerProfileService.ensureProfileHeartbeat`), lângă
`avatarStyle`:

- `equippedFrame` — `String`
- `equippedTitle` — `String`
- `level` — `int` — **nou în profilul public.** Lipsește azi. Adăugat fiindcă
  (a) validează cosmeticele bazate pe nivel ale altora și (b) e util oricum —
  se afișează lângă nume în clasament.

`AuthService.multiplayerIdentity()` întoarce azi `({name, photoUrl,
avatarStyle})` — se extinde cu `equippedFrame`, `equippedTitle`, `level`.

### `PlayerProfile` (model) — 3 câmpuri noi

`equippedFrame` (String, default `'none'`), `equippedTitle` (String, default
`'novice'`), `level` (int, default 0). Parsate din snapshot cu fallback-uri
sigure.

### Validare la afișare

Când se randează cosmeticul ALTCUIVA: se recalculează ce deține din
`profile.level` + `profile.leaguePoints`. Realizările altcuiva NU sunt în
profilul public → titlurile din realizări se afișează pe încredere (cosmetic
pur, zero mize — aceeași filozofie ca `onBalanceAudit`). Ramele și titlurile
pe NIVEL/LIGĂ se validează: dacă `equippedFrame` nu e deținut → `Frame.none`.

---

## 3. UI — se extinde alegerea de avatar

`_pickAvatar` din `profile_screen.dart` (azi un `AlertDialog` cu grilă) devine
un **bottom sheet cu 3 file: Avatar · Ramă · Titlu**.

- Fiecare filă: grilă cu ce ai (colorat, apăsabil) și ce n-ai (gri, cu textul
  cerinței — „nivel 25", „Liga Gold", „50 răspunsuri corecte").
- Salvare pe loc la tap, fără buton de confirmare — exact ca alegerea de avatar
  acum. Ecranul din spate se actualizează instant.
- Fila Avatar = codul existent, mutat.

Fără ecran nou în meniu, fără buton nou. Se descoperă unde te-ai duce oricum.

---

## 4. Randare — unde apar

### Rama = inel/gradient în jurul avatarului

Parametru opțional `Frame frame` pe widget-ul comun `Avatar`
(`lib/widgets/avatar.dart`). Randat ca `Container` cu `decoration` (border sau
gradient). Apare automat oriunde e folosit `Avatar` / `AvatarWithLeagueBadge`:

- header profil (`LevelHeader` → `MyAvatar`)
- rând clasament (`_PlayerRow` → `AvatarWithLeagueBadge`)
- badge meci (`PlayerBadge`)
- listă prieteni
- lobby cameră

`AvatarWithLeagueBadge` pune deja o insignă de ligă în colț — rama e stratul
complementar, pe același tipar.

### Titlul = rând `Text` mic sub nume

Adăugat manual în ~4 locuri (nu e un widget comun ca avatarul):

- header profil (sub nume)
- rând clasament (sub nume, lângă „ultima activitate")
- badge meci (sub nume)
- listă prieteni

Culoare discretă (alb 60%), font mic. Titlul `novice` se poate ascunde (e
implicit, n-are ce arăta).

---

## 5. Testare

**Solo, pe un telefon:**

1. `test/cosmetics_test.dart` — unit pe `ownsFrame`/`ownsTitle`: praguri exacte,
   `none`/`novice` mereu deținute, validare (frame neposedat → fallback).
2. Pe telefon: butonul de debug „+99999 monede / nivel" din Admin → verific că
   se deblochează ramele/titlurile în picker, aleg una, verific că apare în
   header-ul de profil și se salvează după repornire.
3. Captură din clasament — mă văd pe mine cu rama + titlul + nivelul.
4. `flutter analyze` curat, suita completă verde.

**Ce NU se poate testa solo:** că un al doilea jucător îmi vede rama în meci.
Se verifică data viitoare când userul intră de pe telefon + PC, sau prin
Playwright pe două contexte.

---

## Fișiere atinse

**Noi:** `lib/core/cosmetics.dart`, `lib/widgets/cosmetic_frame.dart` (dacă
rama iese complexă), `test/cosmetics_test.dart`.

**Modificate:** `lib/data/storage_service.dart` (2 chei + getters/setters),
`lib/main.dart` (`loadCosmetics()`), `lib/data/auth_service.dart`
(`multiplayerIdentity` +3 câmpuri), `lib/data/player_profile_service.dart`
(heartbeat +3 câmpuri), `lib/models/player_profile.dart` (+3 câmpuri),
`lib/widgets/avatar.dart` (param `frame`), `lib/widgets/player_badge.dart`
(titlu), `lib/screens/profile_screen.dart` (picker cu 3 file + titlu în header),
`lib/screens/multiplayer/leaderboard_screen.dart` (titlu + nivel în rând),
`lib/screens/friends_screen.dart` (titlu).

**Reguli:** `firestore.rules` — `player_profiles` acceptă deja scriere de owner
pe câmpuri arbitrare la `update` (cu garda `rankingGrowthOk` doar pe câmpurile
de clasament). `equippedFrame`/`equippedTitle`/`level` sunt câmpuri noi
neacoperite de gardă → trec. De verificat că `rankingGrowthOk` nu le respinge
accidental (nu le citește, deci nu). Un test nou în `firestore_rules_test.mjs`
că owner-ul își poate scrie cosmeticele.
