# Cosmetice pe nivel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rame de avatar + titluri deblocate prin nivel/ligă/realizări, vizibile tuturor în clasament, meci, prieteni și profil.

**Architecture:** Catalog + reguli de deblocare ca funcții pure în `lib/core/cosmetics.dart`. Proprietatea NU se stochează — se recalculează din XP/ligă/realizări la fiecare afișare. Ce se echipează se ține în 2 chei `SharedPreferences` (auto-sincronizate în cloud prin `exportAll`) + 3 câmpuri noi în `player_profiles` (`equippedFrame`, `equippedTitle`, `level`), scrise la heartbeat lângă `avatarStyle`. Rama se randează printr-un parametru opțional pe widget-ul comun `Avatar`; titlul e un widget mic plasat manual în 4 locuri.

**Tech Stack:** Flutter/Dart, `ValueNotifier` globali (tiparul `myAvatarStyle` din `lib/widgets/avatar.dart` și `adminAnswerReveal` din `lib/core/admin_reveal.dart`), `cloud_firestore`, `SharedPreferences` prin `StorageService`.

**Spec:** `docs/superpowers/specs/2026-09-05-cosmetice-pe-nivel-design.md`

## Global Constraints

- **Identificatori în engleză, comentarii în română** — convenția întregului proiect.
- **Enum → string prin `.name`, NU index.** O reordonare a valorilor nu are voie să schimbe cosmeticul echipat al nimănui. `frameFromId`/`titleFromId` fac drumul invers cu `orElse` la default.
- **Nimic nu aruncă la pornire.** `loadCosmetics()` prinde orice eroare și cade pe `Frame.none` / `PlayerTitle.novice`.
- **Cosmeticele sunt PUR vizuale.** Nu ating scorul, economia sau nicio decizie de joc. Validarea cosmeticelor altcuiva e „nice to have", nu securitate (aceeași filozofie ca `onBalanceAudit` — vezi `project_guess_it_balance_audit`).
- **`flutter analyze` curat + suita completă verde** la finalul fiecărei task.
- **Ligile:** `LeagueTier { bronze, silver, gold, platinum, diamond }` — indici 0..4. Tierul se ia cu `leagueTierIndexForPoints(int)` din `lib/core/leagues.dart`.
- **Nivelul:** `levelForXp(int xp)` din `lib/core/progression.dart` — funcție pură.

---

### Task 1: Catalog + reguli de deblocare (`lib/core/cosmetics.dart`)

**Files:**
- Create: `lib/core/cosmetics.dart`
- Modify: `lib/data/storage_service.dart` (adaugă `completedAchievementIds()` lângă `hasClaimableAchievements`, ~linia 1785)
- Test: `test/cosmetics_test.dart`

**Interfaces:**
- Consumes: `leagueTierIndexForPoints(int)` din `lib/core/leagues.dart`; `achievements` (List<Achievement>) și `achievementProgressResolver()` din `lib/core/progression.dart` / `lib/data/storage_service.dart`.
- Produces:
  ```dart
  enum Frame { none, bronze, silver, gold, platinum, diamond, lvl10, lvl25, lvl50 }
  enum PlayerTitle { novice, curios, cunoscator, inAscensiune, expert, veteran, explorator, maestru, legenda, titan }

  Frame frameFromId(String? id);          // orElse: Frame.none
  PlayerTitle titleFromId(String? id);    // orElse: PlayerTitle.novice

  bool ownsFrame(Frame f, {required int level, required int leaguePoints});
  bool ownsTitle(PlayerTitle t, {required int level, required Set<String> achievements});

  class FrameStyle { final List<Color> colors; const FrameStyle(this.colors); }
  FrameStyle frameStyle(Frame f);         // 1 culoare = inel simplu, 2+ = gradient

  (String ro, String en) titleLabel(PlayerTitle t);
  String frameRequirement(Frame f);       // "Liga Gold" / "Nivel 25" — pt. itemele blocate
  String titleRequirement(PlayerTitle t);

  // în StorageService:
  static Future<Set<String>> completedAchievementIds();
  ```

- [ ] **Step 1: Scrie testul care pică — `test/cosmetics_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/cosmetics.dart';

void main() {
  group('ownsFrame', () {
    test('none e mereu detinut', () {
      expect(ownsFrame(Frame.none, level: 0, leaguePoints: 0), isTrue);
    });

    test('ramele de liga cer tierul respectiv', () {
      // 0 puncte = bronze (tier 0). Vezi leagueTierIndexForPoints.
      expect(ownsFrame(Frame.bronze, level: 1, leaguePoints: 0), isTrue);
      expect(ownsFrame(Frame.gold, level: 1, leaguePoints: 0), isFalse);
      // un punctaj de Gold sau mai mare deblocheaza bronze+silver+gold
      const goldPoints = 10000; // suficient de mare; testul verifica monotonia
      expect(ownsFrame(Frame.bronze, level: 1, leaguePoints: goldPoints), isTrue);
      expect(ownsFrame(Frame.silver, level: 1, leaguePoints: goldPoints), isTrue);
    });

    test('ramele de nivel cer nivelul', () {
      expect(ownsFrame(Frame.lvl10, level: 9, leaguePoints: 0), isFalse);
      expect(ownsFrame(Frame.lvl10, level: 10, leaguePoints: 0), isTrue);
      expect(ownsFrame(Frame.lvl50, level: 49, leaguePoints: 999999), isFalse);
      expect(ownsFrame(Frame.lvl50, level: 50, leaguePoints: 0), isTrue);
    });
  });

  group('ownsTitle', () {
    test('novice e mereu detinut', () {
      expect(ownsTitle(PlayerTitle.novice, level: 0, achievements: {}), isTrue);
    });

    test('titlurile pe nivel cer nivelul', () {
      expect(ownsTitle(PlayerTitle.curios, level: 4, achievements: {}), isFalse);
      expect(ownsTitle(PlayerTitle.curios, level: 5, achievements: {}), isTrue);
      expect(ownsTitle(PlayerTitle.legenda, level: 25, achievements: {}), isTrue);
    });

    test('titlurile pe realizare cer id-ul realizarii', () {
      expect(ownsTitle(PlayerTitle.expert, level: 1, achievements: {}), isFalse);
      expect(ownsTitle(PlayerTitle.expert, level: 1, achievements: {'correct_150'}), isTrue);
      expect(ownsTitle(PlayerTitle.veteran, level: 1, achievements: {'level_15'}), isTrue);
    });
  });

  group('frameFromId / titleFromId', () {
    test('id necunoscut cade pe default', () {
      expect(frameFromId('inventat'), Frame.none);
      expect(frameFromId(null), Frame.none);
      expect(titleFromId('inventat'), PlayerTitle.novice);
    });

    test('drum dus-intors', () {
      for (final f in Frame.values) {
        expect(frameFromId(f.name), f);
      }
      for (final t in PlayerTitle.values) {
        expect(titleFromId(t.name), t);
      }
    });
  });

  test('frameStyle returneaza culori pentru fiecare rama', () {
    for (final f in Frame.values) {
      expect(frameStyle(f).colors, isNotEmpty);
    }
  });

  test('titleLabel are RO si EN pentru fiecare titlu', () {
    for (final t in PlayerTitle.values) {
      final (ro, en) = titleLabel(t);
      expect(ro, isNotEmpty);
      expect(en, isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: Rulează testul, verifică că pică**

Run: `flutter test test/cosmetics_test.dart`
Expected: FAIL — `lib/core/cosmetics.dart` nu există.

- [ ] **Step 3: Scrie `lib/core/cosmetics.dart`**

```dart
import 'package:flutter/material.dart';

import 'leagues.dart';
import 'progression.dart';
import 'theme.dart';

// ─── Cosmetice pe nivel ──────────────────────────────────────────────────
//
// Rame de avatar + titluri, deblocate prin NIVEL, LIGĂ sau REALIZĂRI. Vizibile
// tuturor: clasament, meci, prieteni, profil. Motivul: pînă acum urcai în
// nivel și primeai doar monede — progresia nu se VEDEA nicăieri.
//
// Proprietatea NU se stochează. `ownsFrame`/`ownsTitle` se recalculează la
// fiecare afișare din XP/ligă/realizări. Nimic de ratat la deblocare, nicio
// migrare. Ce se ECHIPEAZĂ se ține în SharedPreferences (vezi
// StorageService.getEquippedFrame) și în profilul public (heartbeat).
//
// Pur vizual — nu atinge scorul, economia, nicio decizie de joc. Validarea
// cosmeticului altcuiva (vezi `ownsFrame` chemat cu statisticile lui) e „nice
// to have", nu securitate: un client modificat care-și pune diamant fals...
// arată un inel. Zero mize.

enum Frame { none, bronze, silver, gold, platinum, diamond, lvl10, lvl25, lvl50 }

enum PlayerTitle {
  novice,
  curios,
  cunoscator,
  inAscensiune,
  expert,
  veteran,
  explorator,
  maestru,
  legenda,
  titan,
}

/// Enum → string prin `.name`, drumul invers aici. `orElse` pe default: un id
/// necunoscut (versiune veche, valoare coruptă) nu are voie să arunce.
Frame frameFromId(String? id) =>
    Frame.values.firstWhere((f) => f.name == id, orElse: () => Frame.none);

PlayerTitle titleFromId(String? id) =>
    PlayerTitle.values.firstWhere((t) => t.name == id,
        orElse: () => PlayerTitle.novice);

// ─── Reguli de deblocare (funcții pure) ──────────────────────────────────
//
// Aceleași funcții servesc DOUĂ apeluri: picker-ul (cu statisticile mele) și
// validatorul de afișare (cu statisticile din profilul altcuiva).

bool ownsFrame(Frame f, {required int level, required int leaguePoints}) {
  final tier = leagueTierIndexForPoints(leaguePoints);
  return switch (f) {
    Frame.none => true,
    Frame.bronze => tier >= LeagueTier.bronze.index,
    Frame.silver => tier >= LeagueTier.silver.index,
    Frame.gold => tier >= LeagueTier.gold.index,
    Frame.platinum => tier >= LeagueTier.platinum.index,
    Frame.diamond => tier >= LeagueTier.diamond.index,
    Frame.lvl10 => level >= 10,
    Frame.lvl25 => level >= 25,
    Frame.lvl50 => level >= 50,
  };
}

bool ownsTitle(PlayerTitle t,
    {required int level, required Set<String> achievements}) {
  return switch (t) {
    PlayerTitle.novice => true,
    PlayerTitle.curios => level >= 5,
    PlayerTitle.cunoscator => achievements.contains('correct_50'),
    PlayerTitle.inAscensiune => achievements.contains('level_5'),
    PlayerTitle.expert => achievements.contains('correct_150'),
    PlayerTitle.veteran => achievements.contains('level_15'),
    PlayerTitle.explorator => achievements.contains('all_modes'),
    PlayerTitle.maestru => achievements.contains('correct_400'),
    PlayerTitle.legenda => level >= 25,
    PlayerTitle.titan => level >= 50,
  };
}

// ─── Aspect ─────────────────────────────────────────────────────────────

/// O culoare = inel simplu; două sau mai multe = gradient (diamant, titan).
class FrameStyle {
  final List<Color> colors;
  const FrameStyle(this.colors);
}

FrameStyle frameStyle(Frame f) => switch (f) {
      Frame.none => const FrameStyle([Colors.transparent]),
      Frame.bronze => FrameStyle([leagues[0].color]),
      Frame.silver => FrameStyle([leagues[1].color]),
      Frame.gold => FrameStyle([leagues[2].color]),
      Frame.platinum => FrameStyle([leagues[3].color]),
      Frame.diamond =>
        const FrameStyle([Color(0xFFB388FF), Color(0xFF5EC8F2), Color(0xFFB388FF)]),
      Frame.lvl10 => const FrameStyle([AppColors.purple]),
      Frame.lvl25 => const FrameStyle([Color(0xFFFF7A1A), Color(0xFFFFD700)]),
      Frame.lvl50 => const FrameStyle([
          Color(0xFFFF5252),
          Color(0xFFFFD740),
          Color(0xFF69F0AE),
          Color(0xFF40C4FF),
          Color(0xFFE040FB),
        ]),
    };

(String ro, String en) titleLabel(PlayerTitle t) => switch (t) {
      PlayerTitle.novice => ('Novice', 'Novice'),
      PlayerTitle.curios => ('Curios', 'Curious'),
      PlayerTitle.cunoscator => ('Cunoscător', 'Knower'),
      PlayerTitle.inAscensiune => ('În ascensiune', 'On the rise'),
      PlayerTitle.expert => ('Expert', 'Expert'),
      PlayerTitle.veteran => ('Veteran', 'Veteran'),
      PlayerTitle.explorator => ('Exploratorul', 'The Explorer'),
      PlayerTitle.maestru => ('Maestru', 'Master'),
      PlayerTitle.legenda => ('Legendă', 'Legend'),
      PlayerTitle.titan => ('Titan', 'Titan'),
    };

/// Textul arătat pe un item BLOCAT în picker („de ce nu-l pot pune").
String frameRequirement(Frame f) => switch (f) {
      Frame.none => '',
      Frame.bronze => 'Liga Bronze',
      Frame.silver => 'Liga Silver',
      Frame.gold => 'Liga Gold',
      Frame.platinum => 'Liga Platinum',
      Frame.diamond => 'Liga Diamond',
      Frame.lvl10 => 'Nivel 10',
      Frame.lvl25 => 'Nivel 25',
      Frame.lvl50 => 'Nivel 50',
    };

String titleRequirement(PlayerTitle t) => switch (t) {
      PlayerTitle.novice => '',
      PlayerTitle.curios => 'Nivel 5',
      PlayerTitle.cunoscator => '50 de răspunsuri corecte',
      PlayerTitle.inAscensiune => 'Nivel 5 (realizare)',
      PlayerTitle.expert => '150 de răspunsuri corecte',
      PlayerTitle.veteran => 'Nivel 15 (realizare)',
      PlayerTitle.explorator => 'Toate modurile jucate',
      PlayerTitle.maestru => '400 de răspunsuri corecte',
      PlayerTitle.legenda => 'Nivel 25',
      PlayerTitle.titan => 'Nivel 50',
    };
```

- [ ] **Step 4: Adaugă `completedAchievementIds()` în `StorageService`**

În `lib/data/storage_service.dart`, imediat după `hasClaimableAchievements()` (~linia 1790):

```dart
  /// Id-urile realizărilor cu ținta atinsă (revendicate SAU nu). Folosit de
  /// cosmetice pentru titlurile legate de realizări — vezi
  /// `ownsTitle` din core/cosmetics.dart.
  static Future<Set<String>> completedAchievementIds() async {
    final progressFor = await achievementProgressResolver();
    return {
      for (final a in achievements)
        if (progressFor(a) >= a.target) a.id,
    };
  }
```

- [ ] **Step 5: Rulează testul, verifică că trece**

Run: `flutter test test/cosmetics_test.dart`
Expected: PASS (toate grupurile).

Dacă testul de ligă pică pe `goldPoints = 10000` fiindcă pragul real e mai mare: deschide `lib/core/leagues.dart`, citește pragurile din `leagueForPoints`, pune o valoare peste pragul de gold în test. Nu schimba codul.

- [ ] **Step 6: `flutter analyze` + commit**

Run: `flutter analyze`
Expected: No issues found.

```bash
git add lib/core/cosmetics.dart lib/data/storage_service.dart test/cosmetics_test.dart
git commit -m "$(cat <<'EOF'
Cosmetice: catalog + reguli de deblocare (functii pure)

Rame (8) si titluri (10), deblocate prin nivel/liga/realizari. Proprietatea nu
se stocheaza — se recalculeaza. ownsFrame/ownsTitle servesc si picker-ul, si
validarea cosmeticelor altcuiva.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Chei de stocare + globali reactivi

**Files:**
- Modify: `lib/data/storage_service.dart` (chei + getters/setters lângă `_adminAnswerRevealKey` ~linia 33 și `getAdminAnswerReveal` ~linia 1300)
- Modify: `lib/core/cosmetics.dart` (adaugă globalii la sfârșit)
- Modify: `lib/main.dart` (`loadCosmetics()` lângă `loadAdminAnswerReveal()` ~linia 70)
- Test: `test/cosmetics_test.dart` (adaugă un grup)

**Interfaces:**
- Consumes: `frameFromId`, `titleFromId` din Task 1.
- Produces:
  ```dart
  // StorageService
  static Future<String> getEquippedFrame();   // default 'none'
  static Future<void> setEquippedFrame(String id);
  static Future<String> getEquippedTitle();   // default 'novice'
  static Future<void> setEquippedTitle(String id);

  // cosmetics.dart
  final ValueNotifier<Frame> myFrame;
  final ValueNotifier<PlayerTitle> myTitle;
  Future<void> loadCosmetics();
  Future<void> setMyFrame(Frame f);
  Future<void> setMyTitle(PlayerTitle t);
  ```

- [ ] **Step 1: Scrie testul care pică — adaugă în `test/cosmetics_test.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:guess_it/data/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ... în void main(), grup nou:

  group('echipare — persistenta si globali', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('valorile implicite fara nimic salvat', () async {
      expect(await StorageService.getEquippedFrame(), 'none');
      expect(await StorageService.getEquippedTitle(), 'novice');
    });

    test('setMyFrame scrie prefs SI notifier', () async {
      SharedPreferences.setMockInitialValues({});
      await loadCosmetics();
      expect(myFrame.value, Frame.none);
      await setMyFrame(Frame.gold);
      expect(myFrame.value, Frame.gold);
      expect(await StorageService.getEquippedFrame(), 'gold');
    });

    test('loadCosmetics citeste ce s-a salvat', () async {
      SharedPreferences.setMockInitialValues({
        'equipped_frame': 'diamond',
        'equipped_title': 'veteran',
      });
      await loadCosmetics();
      expect(myFrame.value, Frame.diamond);
      expect(myTitle.value, PlayerTitle.veteran);
    });

    test('loadCosmetics cade pe default la valoare corupta', () async {
      SharedPreferences.setMockInitialValues({'equipped_frame': 'zzz'});
      await loadCosmetics();
      expect(myFrame.value, Frame.none);
    });
  });
```

- [ ] **Step 2: Rulează, verifică că pică**

Run: `flutter test test/cosmetics_test.dart -n "echipare"`
Expected: FAIL — `getEquippedFrame`, `loadCosmetics` etc. nu există.

- [ ] **Step 3: Chei + getters în `StorageService`**

Lângă `_adminAnswerRevealKey` (~linia 33):
```dart
  static const _equippedFrameKey = 'equipped_frame';
  static const _equippedTitleKey = 'equipped_title';
```

Lângă `getAdminAnswerReveal` / `setAdminAnswerReveal` (~linia 1300):
```dart
  static Future<String> getEquippedFrame() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_equippedFrameKey) ?? 'none';
  }

  static Future<void> setEquippedFrame(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedFrameKey, id);
  }

  static Future<String> getEquippedTitle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_equippedTitleKey) ?? 'novice';
  }

  static Future<void> setEquippedTitle(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedTitleKey, id);
  }
```

**NU** adăuga cheile în `_localOnlyKeys` — vrem să se sincronizeze în cloud (cosmeticul echipat supraviețuiește reinstalării). **NU** le adăuga în `_resetPreservedKeys` — un reset le duce înapoi la default, iar proprietatea oricum se recalculează din XP=0.

- [ ] **Step 4: Globali în `lib/core/cosmetics.dart`** (la sfârșitul fișierului)

```dart
// ─── Ce am echipat pe TELEFONUL ăsta ─────────────────────────────────────
//
// Tiparul `myAvatarStyle` din widgets/avatar.dart: ValueNotifier global, citit
// o dată la pornire, ținut aici ca schimbarea să se vadă instant peste tot
// fără restart.

import 'package:flutter/foundation.dart';
import '../data/storage_service.dart';

final ValueNotifier<Frame> myFrame = ValueNotifier<Frame>(Frame.none);
final ValueNotifier<PlayerTitle> myTitle =
    ValueNotifier<PlayerTitle>(PlayerTitle.novice);

/// Chemată din `main()`. Nu aruncă niciodată.
Future<void> loadCosmetics() async {
  try {
    myFrame.value = frameFromId(await StorageService.getEquippedFrame());
    myTitle.value = titleFromId(await StorageService.getEquippedTitle());
  } catch (_) {
    myFrame.value = Frame.none;
    myTitle.value = PlayerTitle.novice;
  }
}

Future<void> setMyFrame(Frame f) async {
  myFrame.value = f;
  await StorageService.setEquippedFrame(f.name);
}

Future<void> setMyTitle(PlayerTitle t) async {
  myTitle.value = t;
  await StorageService.setEquippedTitle(t.name);
}
```

**Notă:** mută importurile `package:flutter/foundation.dart` și
`../data/storage_service.dart` sus, lângă celelalte importuri, dacă analizorul
se plânge de import în mijlocul fișierului.

- [ ] **Step 5: Wire în `main.dart`**

În `lib/main.dart`, lângă `unawaited(loadAdminAnswerReveal());` (~linia 70):
```dart
  // Cosmeticele echipate (rama + titlul) — vezi core/cosmetics.dart.
  unawaited(loadCosmetics());
```
Adaugă importul `import 'core/cosmetics.dart';` lângă `import 'core/admin_reveal.dart';`.

- [ ] **Step 6: Rulează testele + analyze**

Run: `flutter test test/cosmetics_test.dart && flutter analyze`
Expected: PASS + No issues found.

- [ ] **Step 7: Commit**

```bash
git add lib/data/storage_service.dart lib/core/cosmetics.dart lib/main.dart test/cosmetics_test.dart
git commit -m "$(cat <<'EOF'
Cosmetice: chei de stocare + globali reactivi (myFrame/myTitle)

Tiparul myAvatarStyle. 2 chei SharedPreferences, auto-sincronizate in cloud.
loadCosmetics() in main(), nu arunca niciodata.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Câmpuri în `PlayerProfile` + sincronizare la heartbeat

**Files:**
- Modify: `lib/models/player_profile.dart` (câmpuri + `fromDoc`, ~linia 10 și ~linia 117)
- Modify: `lib/data/auth_service.dart` (`multiplayerIdentity`, ~linia 84)
- Modify: `lib/data/player_profile_service.dart` (`ensureProfileHeartbeat`, `ref.set({...})` ~linia 204)
- Test: `test/player_profile_test.dart` (creează dacă nu există)

**Interfaces:**
- Consumes: `StorageService.getEquippedFrame/getEquippedTitle` (Task 2), `levelForXp`, `StorageService.getXp`.
- Produces:
  ```dart
  // PlayerProfile
  final String equippedFrame;   // 'none'
  final String equippedTitle;   // 'novice'
  final int level;              // 0

  // AuthService.multiplayerIdentity() întoarce acum și:
  //   String equippedFrame, String equippedTitle, int level
  ```

- [ ] **Step 1: Testul care pică — `test/player_profile_test.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/models/player_profile.dart';

void main() {
  test('fromDoc citeste cosmeticele cu fallback-uri', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('player_profiles').doc('u1').set({
      'name': 'Test',
      'equippedFrame': 'gold',
      'equippedTitle': 'veteran',
      'level': 12,
    });
    final snap = await db.collection('player_profiles').doc('u1').get();
    final p = PlayerProfile.fromDoc(snap);
    expect(p.equippedFrame, 'gold');
    expect(p.equippedTitle, 'veteran');
    expect(p.level, 12);
  });

  test('fromDoc pe un profil vechi fara cosmetice → default-uri', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('player_profiles').doc('u2').set({'name': 'Vechi'});
    final snap = await db.collection('player_profiles').doc('u2').get();
    final p = PlayerProfile.fromDoc(snap);
    expect(p.equippedFrame, 'none');
    expect(p.equippedTitle, 'novice');
    expect(p.level, 0);
  });
}
```

**Dacă `fake_cloud_firestore` nu e în `dev_dependencies`:** verifică cu
`grep fake_cloud_firestore pubspec.yaml`. Dacă lipsește, scrie testul cu un
`DocumentSnapshot` mock minimal SAU testează doar un constructor `PlayerProfile`
direct (fără `fromDoc`) și verifică `fromDoc` manual pe telefon în Task 8.
Preferă să adaugi pachetul: `flutter pub add -d fake_cloud_firestore`.

- [ ] **Step 2: Rulează, verifică că pică**

Run: `flutter test test/player_profile_test.dart`
Expected: FAIL — `equippedFrame` nu e câmp pe `PlayerProfile`.

- [ ] **Step 3: Câmpuri pe `PlayerProfile`**

`lib/models/player_profile.dart`, lângă `final String avatarStyle;` (~linia 18):
```dart
  /// Cosmeticele echipate — vezi core/cosmetics.dart. Doar id-uri (numele
  /// enum); randarea recalculează ce e chiar deblocat din `level`/`leaguePoints`.
  final String equippedFrame;
  final String equippedTitle;

  /// Nivelul (levelForXp) — nou în profilul public. Se afișează lângă nume în
  /// clasament și validează ramele/titlurile pe nivel ale acestui jucător.
  final int level;
```

Adaugă în constructor cu default-uri:
```dart
    this.equippedFrame = 'none',
    this.equippedTitle = 'novice',
    this.level = 0,
```

În `fromDoc` (~linia 124, lângă `avatarStyle:`):
```dart
      equippedFrame: data['equippedFrame'] as String? ?? 'none',
      equippedTitle: data['equippedTitle'] as String? ?? 'novice',
      level: data['level'] as int? ?? 0,
```

- [ ] **Step 4: Extinde `multiplayerIdentity()`**

`lib/data/auth_service.dart` ~linia 84. Semnătura devine:
```dart
  Future<({String name, String? photoUrl, String avatarStyle,
      String equippedFrame, String equippedTitle, int level})>
      multiplayerIdentity() async {
    final avatarStyle = await StorageService.getAvatarStyleId();
    // ... (codul existent pentru `name`) ...
    return (
      name: name,
      photoUrl: u?.photoURL,
      avatarStyle: avatarStyle,
      equippedFrame: await StorageService.getEquippedFrame(),
      equippedTitle: await StorageService.getEquippedTitle(),
      level: levelForXp(await StorageService.getXp()),
    );
  }
```
Adaugă importul `import '../core/progression.dart';` dacă `levelForXp` nu e vizibil.

- [ ] **Step 5: Scrie cosmeticele la heartbeat**

`lib/data/player_profile_service.dart`, în `ref.set({...})` din `ensureProfileHeartbeat` (~linia 204), lângă `'avatarStyle': identity.avatarStyle,`:
```dart
        'equippedFrame': identity.equippedFrame,
        'equippedTitle': identity.equippedTitle,
        'level': identity.level,
```

- [ ] **Step 6: Rulează testele + analyze**

Run: `flutter test test/player_profile_test.dart && flutter analyze`
Expected: PASS + No issues.

Verifică că nu s-a rupt nimic care consumă `multiplayerIdentity()`:
Run: `grep -rn "multiplayerIdentity()" lib/ --include=*.dart`
Fiecare consumator care destructurează rezultatul (`final (name: ..., ...)`) trebuie să meargă mai departe — câmpurile noi sunt adăugate, nu redenumite. Dacă vreun consumator folosește pattern-matching pozițional strict, adaugă câmpurile lipsă acolo.

- [ ] **Step 7: Commit**

```bash
git add lib/models/player_profile.dart lib/data/auth_service.dart lib/data/player_profile_service.dart test/player_profile_test.dart pubspec.yaml pubspec.lock
git commit -m "$(cat <<'EOF'
Cosmetice: 3 campuri noi in player_profiles (equippedFrame/Title/level)

Scrise la heartbeat, langa avatarStyle. `level` lipsea din profilul public —
adaugat, valideaza cosmeticele pe nivel si se afiseaza in clasament.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Randarea ramei pe widget-ul `Avatar`

**Files:**
- Modify: `lib/widgets/avatar.dart` (param `frame` pe `Avatar`, ~linia 38; `MyAvatar` ~linia 132)
- Modify: `lib/widgets/league_badge.dart` (`AvatarWithLeagueBadge` pasează `frame` mai departe, ~linia 56)
- Modify: `lib/widgets/player_badge.dart` (pasează `frame`, ~linia 11)
- Test: `test/cosmetic_frame_widget_test.dart`

**Interfaces:**
- Consumes: `Frame`, `frameStyle` din Task 1; `myFrame` din Task 2.
- Produces: `Avatar(..., frame: Frame.gold)` desenează un inel; `AvatarWithLeagueBadge` și `PlayerBadge` acceptă `Frame frame`.

- [ ] **Step 1: Testul care pică — `test/cosmetic_frame_widget_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/cosmetics.dart';
import 'package:guess_it/widgets/avatar.dart';

void main() {
  testWidgets('Avatar cu frame.none nu adauga niciun strat vizibil', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Avatar(size: 44, label: 'A', frame: Frame.none)),
    ));
    expect(tester_noThrow(t), isTrue);
  });

  testWidgets('Avatar cu frame.gold se construieste fara eroare', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Avatar(size: 44, label: 'A', frame: Frame.gold)),
    ));
    expect(t.takeException(), isNull);
    // inelul e un Container cu decoration circulara in plus fata de none
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('frame.lvl50 (gradient) nu arunca', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Avatar(size: 44, label: 'A', frame: Frame.lvl50)),
    ));
    expect(t.takeException(), isNull);
  });
}

bool tester_noThrow(WidgetTester t) => t.takeException() == null;
```

- [ ] **Step 2: Rulează, verifică că pică**

Run: `flutter test test/cosmetic_frame_widget_test.dart`
Expected: FAIL — `Avatar` nu are parametrul `frame`.

- [ ] **Step 3: Param `frame` pe `Avatar`**

`lib/widgets/avatar.dart`. Adaugă importul `import '../core/cosmetics.dart';` sus.

În clasa `Avatar`:
```dart
  /// Rama cosmetică din jurul avatarului (vezi core/cosmetics.dart).
  /// `Frame.none` = fără inel, comportamentul de dinainte.
  final Frame frame;
```
În constructor: `this.frame = Frame.none,`

În `build`, înfășoară avatarul existent (poza/inițiala) într-un inel când
`frame != Frame.none`. Găsește widget-ul rădăcină returnat de `build` și
înlocuiește-l cu:
```dart
    final inner = /* widget-ul avatar existent */;
    if (frame == Frame.none) return inner;
    final style = frameStyle(frame);
    final ringWidth = (size * 0.08).clamp(2.0, 5.0);
    return Container(
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: style.colors.length > 1
            ? SweepGradient(colors: [...style.colors, style.colors.first])
            : null,
        color: style.colors.length == 1 ? style.colors.first : null,
      ),
      child: inner,
    );
```
**Atenție la dimensiune:** inelul adaugă `2*ringWidth` la lățimea totală. Dacă
asta strică layout-uri strânse (clasament, badge meci), fă inelul să
CONSUME din `size` în loc să adauge: desenează inner la `size - 2*ringWidth`.
Verifică pe telefon în Task 8; dacă e strâmt, comută pe varianta „consumă".

- [ ] **Step 4: `MyAvatar` folosește `myFrame`**

`lib/widgets/avatar.dart`, în `MyAvatar` (~linia 132). E deja un `StatefulWidget`
care ascultă `myAvatarStyle`. Adaugă un `ValueListenableBuilder<Frame>` pe
`myFrame` (sau ascultă-l în `initState` cu `addListener` + `setState`, la fel ca
`myAvatarStyle`) și pasează `frame: myFrame.value` la `Avatar`.

Adaugă și `if (!_cosmeticsLoaded) loadCosmetics();` pe modelul liniei existente
`if (!_myAvatarStyleLoaded) loadMyAvatarStyle();` (~linia 146) — un flag
`bool _cosmeticsLoaded` la fel ca `_myAvatarStyleLoaded`, setat de
`loadCosmetics`/`setMyFrame`.

**Alternativă mai simplă:** dacă `loadCosmetics()` e deja chemat din `main()`
(Task 2 Step 5), `myFrame`/`myTitle` au valoarea corectă la orice build ulterior
pornirii. Testele de widget montează fără `main()`, deci acolo rămân pe default
— acceptabil. Sari peste flag-ul lazy dacă `main()` acoperă cazul real.

- [ ] **Step 5: `AvatarWithLeagueBadge` + `PlayerBadge` pasează `frame`**

`lib/widgets/league_badge.dart`, `AvatarWithLeagueBadge` (~linia 56): adaugă
`final Frame frame;` (default `Frame.none`), pasează la `Avatar` intern.
Import `../core/cosmetics.dart`.

`lib/widgets/player_badge.dart` (~linia 11): la fel — `final Frame frame;`
default `Frame.none`, pasat la `Avatar`/`AvatarWithLeagueBadge` intern.

- [ ] **Step 6: Rulează testele + analyze**

Run: `flutter test test/cosmetic_frame_widget_test.dart && flutter analyze`
Expected: PASS + No issues. (Consumatorii existenți ai `Avatar`/`PlayerBadge`
merg neschimbați — `frame` are default.)

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/avatar.dart lib/widgets/league_badge.dart lib/widgets/player_badge.dart test/cosmetic_frame_widget_test.dart
git commit -m "$(cat <<'EOF'
Cosmetice: rama se randeaza pe widget-ul comun Avatar

Param `frame` optional (default none). Inel simplu sau gradient (SweepGradient).
Trece prin AvatarWithLeagueBadge si PlayerBadge. MyAvatar foloseste myFrame.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Randarea titlului

**Files:**
- Create: `lib/widgets/cosmetic_title.dart`
- Modify: `lib/widgets/level_header.dart` (titlu sub nume, ~linia 200 unde e `'Level $level'`)
- Modify: `lib/screens/multiplayer/leaderboard_screen.dart` (`_PlayerRow` ~linia 389 și `_SeasonHeader` ~linia 269)
- Modify: `lib/widgets/player_badge.dart` (titlu sub nume)
- Modify: `lib/screens/friends_screen.dart` (rândul de prieten — găsește unde se afișează `friend.name`)
- Test: `test/cosmetic_title_widget_test.dart`

**Interfaces:**
- Consumes: `PlayerTitle`, `titleFromId`, `titleLabel` din Task 1; `myTitle` din Task 2; `PlayerProfile.equippedTitle` din Task 3.
- Produces: `CosmeticTitle(titleId: 'veteran')` — un `Text` mic; gol pentru `novice`.

- [ ] **Step 1: Testul care pică — `test/cosmetic_title_widget_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/cosmetic_title.dart';

void main() {
  testWidgets('titlul novice nu afiseaza nimic', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'novice')),
    ));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('un titlu real se afiseaza', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'veteran')),
    ));
    expect(find.text('Veteran'), findsOneWidget);
  });

  testWidgets('id necunoscut → nimic (cade pe novice)', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'inventat')),
    ));
    expect(find.byType(Text), findsNothing);
  });
}
```

- [ ] **Step 2: Rulează, verifică că pică**

Run: `flutter test test/cosmetic_title_widget_test.dart`
Expected: FAIL — `lib/widgets/cosmetic_title.dart` nu există.

- [ ] **Step 3: `lib/widgets/cosmetic_title.dart`**

```dart
import 'package:flutter/material.dart';

import '../core/cosmetics.dart';
import '../core/lang.dart';

/// Titlul cosmetic al unui jucător — un rând mic sub nume, oriunde apare
/// numele (profil, clasament, meci, prieteni). Gol pentru `novice` (titlul
/// implicit n-are ce arăta).
class CosmeticTitle extends StatelessWidget {
  final String titleId;
  final double fontSize;
  final TextAlign align;

  const CosmeticTitle({
    super.key,
    required this.titleId,
    this.fontSize = 11,
    this.align = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final t = titleFromId(titleId);
    if (t == PlayerTitle.novice) return const SizedBox.shrink();
    final (ro, en) = titleLabel(t);
    return Text(
      tr(ro, en),
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withAlpha(150),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}
```

- [ ] **Step 4: Plasează titlul — profil (`LevelHeader`)**

`lib/widgets/level_header.dart`, ~linia 200. `LevelHeader` primește deja `xp` și
opțional `name`. Adaugă un param `String? titleId` și, sub numele/`'Level N'`,
pune `if (titleId != null) CosmeticTitle(titleId: titleId!, align: TextAlign.center)`.

În `lib/screens/profile_screen.dart`, unde se construiește `LevelHeader` (caută
`LevelHeader(`), pasează `titleId: ...` dintr-un `ValueListenableBuilder<PlayerTitle>`
pe `myTitle` (sau `myTitle.value.name` dacă e deja încărcat din `main()`).

- [ ] **Step 5: Plasează titlul — clasament**

`lib/screens/multiplayer/leaderboard_screen.dart`:
- `_PlayerRow` (~linia 389): sub `Text(profile.name, ...)`, adaugă
  `CosmeticTitle(titleId: profile.equippedTitle)`. Lângă nume adaugă și nivelul:
  `Text('Nivel ${profile.level}', style: ...)` dacă `profile.level > 0`.
- `_SeasonHeader` (~linia 269): la fel, sub `Text(p.name, ...)`.
- Pasează `frame: validatedFrame(profile)` la `AvatarWithLeagueBadge` — vezi
  Step 7 pentru `validatedFrame`.

Import `../../widgets/cosmetic_title.dart` și `../../core/cosmetics.dart`.

- [ ] **Step 6: Plasează titlul — badge meci + prieteni**

`lib/widgets/player_badge.dart`: adaugă `final String titleId;` (default `'novice'`),
sub `Text(name, ...)` pune `CosmeticTitle(titleId: titleId, fontSize: 9, align: TextAlign.center)`.
Consumatorii (`multiplayer_match_screen`, `room_lobby_screen`, `electric_chair`)
pasează `titleId: player.equippedTitle` dacă `MatchPlayer` are câmpul — dacă NU,
lasă default `'novice'` acum și notează în Task 8 că badge-ul de meci nu arată
titlul până când `MatchPlayer` nu carează `equippedTitle` (extindere viitoare,
în afara acestui plan).

`lib/screens/friends_screen.dart`: găsește unde se afișează `friend.name`
(caută `\.name`), adaugă `CosmeticTitle(titleId: friend.equippedTitle)` sub el
dacă obiectul de prieten e un `PlayerProfile`. Dacă e alt model fără câmp,
lasă-l pe seama Task 8 / extindere viitoare.

- [ ] **Step 7: `validatedFrame` — helper de validare**

În `lib/core/cosmetics.dart`, adaugă:
```dart
/// Rama de afișat pentru un jucător, verificând că o DEȚINE cu adevărat din
/// nivelul/liga lui publice. Titlurile din realizări NU se pot valida (nu-s în
/// profilul public) — se afișează pe încredere, sunt pur vizuale.
Frame validatedFrame(String equippedFrame,
    {required int level, required int leaguePoints}) {
  final f = frameFromId(equippedFrame);
  return ownsFrame(f, level: level, leaguePoints: leaguePoints) ? f : Frame.none;
}
```
Test rapid în `test/cosmetics_test.dart`:
```dart
  test('validatedFrame cade pe none daca nu e detinuta', () {
    expect(validatedFrame('diamond', level: 1, leaguePoints: 0), Frame.none);
    expect(validatedFrame('lvl10', level: 15, leaguePoints: 0), Frame.lvl10);
  });
```
În clasament: `frame: validatedFrame(profile.equippedFrame, level: profile.level, leaguePoints: profile.leaguePoints)`.

- [ ] **Step 8: Rulează toate testele + analyze**

Run: `flutter test && flutter analyze`
Expected: PASS (toate) + No issues.

- [ ] **Step 9: Commit**

```bash
git add lib/widgets/cosmetic_title.dart lib/widgets/level_header.dart lib/widgets/player_badge.dart lib/screens/multiplayer/leaderboard_screen.dart lib/screens/friends_screen.dart lib/core/cosmetics.dart lib/screens/profile_screen.dart test/cosmetic_title_widget_test.dart test/cosmetics_test.dart
git commit -m "$(cat <<'EOF'
Cosmetice: titlul se afiseaza sub nume (profil, clasament, meci, prieteni)

Widget CosmeticTitle, gol pentru `novice`. Nivelul apare in randul de
clasament. validatedFrame() verifica proprietatea din profilul public.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Alegerea aspectului — bottom sheet cu 3 file

**Files:**
- Modify: `lib/screens/profile_screen.dart` (`_pickAvatar` ~linia 147 → `_pickAppearance`)
- Create: `lib/widgets/appearance_sheet.dart` (conținutul sheet-ului, ca `profile_screen.dart` să nu crească)
- Test: `test/appearance_sheet_test.dart`

**Interfaces:**
- Consumes: tot din Task 1 + `myFrame`/`myTitle`/`setMyFrame`/`setMyTitle` din Task 2; `myAvatarStyle`/`setMyAvatarStyle`/`AvatarStyle` existente.
- Produces: `showAppearanceSheet(BuildContext, {required int level, required int leaguePoints, required Set<String> achievements})`.

- [ ] **Step 1: Testul care pică — `test/appearance_sheet_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guess_it/core/cosmetics.dart';
import 'package:guess_it/widgets/appearance_sheet.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sheet-ul are 3 file: Avatar, Rama, Titlu', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => showAppearanceSheet(ctx,
              level: 30, leaguePoints: 0, achievements: {}),
          child: const Text('deschide'),
        )),
      ),
    ));
    await t.tap(find.text('deschide'));
    await t.pumpAndSettle();
    expect(find.text('Avatar'), findsOneWidget);
    expect(find.text('Ramă'), findsOneWidget);
    expect(find.text('Titlu'), findsOneWidget);
  });

  testWidgets('un item blocat arata cerinta si nu se echipeaza la tap', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => showAppearanceSheet(ctx,
              level: 1, leaguePoints: 0, achievements: {}),
          child: const Text('deschide'),
        )),
      ),
    ));
    await t.tap(find.text('deschide'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ramă'));
    await t.pumpAndSettle();
    // rama lvl50 e blocata la nivel 1 → cerinta vizibila
    expect(find.text('Nivel 50'), findsOneWidget);
    // tap pe ea nu schimba myFrame
    await loadCosmetics();
    final before = myFrame.value;
    await t.tap(find.text('Nivel 50'));
    await t.pumpAndSettle();
    expect(myFrame.value, before);
  });
}
```

- [ ] **Step 2: Rulează, verifică că pică**

Run: `flutter test test/appearance_sheet_test.dart`
Expected: FAIL — `lib/widgets/appearance_sheet.dart` nu există.

- [ ] **Step 3: `lib/widgets/appearance_sheet.dart`**

```dart
import 'package:flutter/material.dart';

import '../core/cosmetics.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import 'avatar.dart';

/// Alegerea aspectului: avatar, ramă, titlu. Deschis prin apăsare pe avatar în
/// Profil. Salvare pe loc la tap, fără buton de confirmare — la fel ca vechea
/// alegere de avatar. Itemele blocate apar gri, cu textul cerinței.
Future<void> showAppearanceSheet(
  BuildContext context, {
  required int level,
  required int leaguePoints,
  required Set<String> achievements,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1a1a2e),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AppearanceSheet(
      level: level,
      leaguePoints: leaguePoints,
      achievements: achievements,
    ),
  );
}

class _AppearanceSheet extends StatefulWidget {
  final int level;
  final int leaguePoints;
  final Set<String> achievements;
  const _AppearanceSheet({
    required this.level,
    required this.leaguePoints,
    required this.achievements,
  });

  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabs,
              indicatorColor: AppColors.play,
              tabs: [
                Tab(text: tr('Avatar', 'Avatar')),
                Tab(text: tr('Ramă', 'Frame')),
                Tab(text: tr('Titlu', 'Title')),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _AvatarGrid(),
                  _FrameGrid(
                      level: widget.level, leaguePoints: widget.leaguePoints),
                  _TitleGrid(
                      level: widget.level, achievements: widget.achievements),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AvatarStyle>(
      valueListenable: myAvatarStyle,
      builder: (_, current, __) => SingleChildScrollView(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final style in AvatarStyle.values)
              GestureDetector(
                onTap: () => setMyAvatarStyle(style),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: style == current
                              ? AppColors.play
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: style == AvatarStyle.poza
                          ? const MyPhotoPreview(size: 58)
                          : AvatarArt(style: style, size: 58),
                    ),
                    const SizedBox(height: 4),
                    Text(style.label,
                        style: TextStyle(
                            color: style == current
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FrameGrid extends StatelessWidget {
  final int level;
  final int leaguePoints;
  const _FrameGrid({required this.level, required this.leaguePoints});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Frame>(
      valueListenable: myFrame,
      builder: (_, current, __) => SingleChildScrollView(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 16,
          children: [
            for (final f in Frame.values)
              _CosmeticCell(
                selected: f == current,
                owned: ownsFrame(f, level: level, leaguePoints: leaguePoints),
                requirement: frameRequirement(f),
                onTap: () => setMyFrame(f),
                preview: Avatar(size: 58, label: '★', frame: f),
                label: f == Frame.none ? tr('Fără', 'None') : '',
              ),
          ],
        ),
      ),
    );
  }
}

class _TitleGrid extends StatelessWidget {
  final int level;
  final Set<String> achievements;
  const _TitleGrid({required this.level, required this.achievements});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerTitle>(
      valueListenable: myTitle,
      builder: (_, current, __) => SingleChildScrollView(
        child: Column(
          children: [
            for (final t in PlayerTitle.values)
              _CosmeticCell(
                selected: t == current,
                owned: ownsTitle(t, level: level, achievements: achievements),
                requirement: titleRequirement(t),
                onTap: () => setMyTitle(t),
                preview: const SizedBox.shrink(),
                label: titleLabel(t).$1, // RO; wrap in tr() dacă vrei EN
              ),
          ],
        ),
      ),
    );
  }
}

/// Un item din grilă: preview + etichetă. Blocat = gri + textul cerinței,
/// tap-ul nu face nimic.
class _CosmeticCell extends StatelessWidget {
  final bool selected;
  final bool owned;
  final String requirement;
  final VoidCallback onTap;
  final Widget preview;
  final String label;

  const _CosmeticCell({
    required this.selected,
    required this.owned,
    required this.requirement,
    required this.onTap,
    required this.preview,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: owned ? onTap : null,
      child: Opacity(
        opacity: owned ? 1 : 0.35,
        child: Container(
          width: 96,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.play : Colors.white12,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              preview,
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              if (!owned && requirement.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(requirement,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 9)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Notă:** dacă `_TitleGrid` are nevoie de `tr()` pe etichetă, folosește
`CosmeticTitle`-ul din Task 5 sau `tr(titleLabel(t).$1, titleLabel(t).$2)`.

- [ ] **Step 4: Cablează în `profile_screen.dart`**

Redenumește `_pickAvatar` → `_pickAppearance`. Corpul devine:
```dart
  Future<void> _pickAppearance() async {
    final data = await _dataFuture; // sau reia XP/leaguePoints din starea existentă
    await showAppearanceSheet(
      context,
      level: levelForXp(data.xp),
      leaguePoints: data.multiplayerProfile.leaguePoints, // verifică numele real al câmpului
      achievements: await StorageService.completedAchievementIds(),
    );
    if (mounted) setState(() {}); // reîmprospătează header-ul
  }
```
Actualizează `onTap: _pickAvatar` → `onTap: _pickAppearance` (~linia 231).
Actualizează textul „Apasă pe poză ca să-ți schimbi avatarul" →
`tr('Apasă pe avatar ca să-ți schimbi aspectul', 'Tap the avatar to change your look')` (~linia 249).

- [ ] **Step 5: Rulează testele + analyze**

Run: `flutter test && flutter analyze`
Expected: PASS + No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/appearance_sheet.dart lib/screens/profile_screen.dart test/appearance_sheet_test.dart
git commit -m "$(cat <<'EOF'
Cosmetice: alegerea aspectului — bottom sheet cu 3 file (Avatar/Rama/Titlu)

Inlocuieste vechiul dialog de avatar. Itemele blocate apar gri cu textul
cerintei, tap-ul nu face nimic. Salvare pe loc, fara buton de confirmare.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Test pe regulile Firestore

**Files:**
- Modify: `test/firestore_rules_test.mjs` (grup nou, lângă cazurile `player_profiles`)

**Interfaces:**
- Consumes: nimic din task-urile anterioare — verifică doar `firestore.rules`.
- Produces: încredere că owner-ul își poate scrie `equippedFrame`/`equippedTitle`/`level` și că `rankingGrowthOk` nu le respinge.

- [ ] **Step 1: Adaugă cazurile în `test/firestore_rules_test.mjs`**

Lângă grupul care testează scrierea în `player_profiles` (caută `rankingGrowthOk` sau `un meci castigat`):
```javascript
await reset();
await check('owner-ul isi poate scrie cosmeticele + nivelul', () => assertSucceeds(
  write({ equippedFrame: 'gold', equippedTitle: 'veteran', level: 12 })));

await reset();
await check('cosmeticele NU pacalesc garda anti-cheat de clasament', () => assertSucceeds(
  write({ equippedFrame: 'diamond', equippedTitle: 'titan', level: 50,
          leaguePoints: 110 }))); // +10, sub winPoints=20, deci OK

await reset();
await check('cosmeticele nu deblocheaza un salt ilegal de leaguePoints', () => assertFails(
  write({ equippedFrame: 'gold', leaguePoints: 999999 })));
```

- [ ] **Step 2: Rulează testele de reguli pe emulator**

```bash
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-25.0.3.9-hotspot"
export PATH="$JAVA_HOME/bin:$PATH" && hash -r
cd test && cp ../firestore.rules . && firebase.cmd emulators:exec --only firestore --project sodoquizz-test "node firestore_rules_test.mjs" 2>&1 | grep -E "PICA|trec, "
cd .. && rm -f test/firestore.rules
```
Expected: toate trec (numărul crește cu 3).

**Dacă „owner-ul isi poate scrie cosmeticele" pică:** `firestore.rules`,
regula `allow update` pe `player_profiles/{uid}` — verifică dacă are o listă
albă de câmpuri (`request.resource.data.keys().hasOnly([...])`). Dacă da,
adaugă `'equippedFrame', 'equippedTitle', 'level'` în listă. Dacă folosește
doar `rankingGrowthOk()` fără listă albă, câmpurile noi trec liber și testul
ar fi trebuit să pice pe altceva — recitește eroarea.

- [ ] **Step 3: Actualizează `test/README-reguli.md`**

Schimbă „N/N" cu noul total, adaugă o linie despre `equippedFrame`/`equippedTitle`/`level`.

- [ ] **Step 4: Commit**

```bash
git add test/firestore_rules_test.mjs test/README-reguli.md
git commit -m "$(cat <<'EOF'
Cosmetice: teste de reguli — owner-ul isi scrie cosmeticele, anti-cheat intact

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Verificare pe telefon + buton de debug

**Files:**
- Modify: `lib/screens/admin/debug_tab.dart` (buton nou „SARI LA NIVEL 50 + LIGĂ")
- Modify: `lib/data/storage_service.dart` (dacă e nevoie de un helper `bumpLeaguePointsForTest`)
- Modify: `TODO.md` (bifează item 1 din secțiunea RETENȚIE, notează ce n-a fost verificat)

**Interfaces:**
- Consumes: `StorageService.addXp`, `myFrame`, `myTitle`, tot restul.
- Produces: cale de a testa cosmeticele pe nivel/ligă fără să joci ore.

- [ ] **Step 1: Buton de debug**

`lib/screens/admin/debug_tab.dart`, lângă `_buildDevToolButton` pentru „VEZI TUTORIALUL":
```dart
          _buildDevToolButton(
            icon: Icons.workspace_premium_rounded,
            label: 'DEBLOCHEAZĂ COSMETICELE (nivel 50 + ligă)',
            color: AppColors.coin,
            onTap: () async {
              // Suficient XP pentru nivel 50 + puncte de ligă pentru diamant.
              await StorageService.addXp(500000);
              await PlayerProfileService.instance
                  .debugGrantLeaguePoints(2000); // vezi Step 2
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Cosmeticele sunt deblocate. Deschide Profil → avatar.'),
                  backgroundColor: AppColors.teal,
                ));
              }
            },
          ),
          const SizedBox(height: 10),
```

- [ ] **Step 2: Helper `debugGrantLeaguePoints`**

`lib/data/player_profile_service.dart`:
```dart
  /// DOAR pentru testarea cosmeticelor pe telefon — vezi butonul din tabul
  /// Debug. Nu are cale de acces din joc.
  Future<void> debugGrantLeaguePoints(int amount) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    await _col.doc(uid).set(
        {'leaguePoints': FieldValue.increment(amount)}, SetOptions(merge: true));
  }
```

- [ ] **Step 3: `flutter analyze` + build + instalare**

```bash
flutter analyze && flutter test
flutter build apk --release --dart-define=APPCHECK_DEBUG=true
```
Instalează pe telefon (vezi `CLAUDE.md` pentru comanda `adb install -d`).

- [ ] **Step 4: Checklist pe telefon (capturi la fiecare pas)**

1. Admin → Debug → „DEBLOCHEAZĂ COSMETICELE". Snackbar apare.
2. Profil → apasă pe avatar → sheet cu 3 file. Fila **Ramă**: toate deblocate (colorate). Alege `lvl50` (gradient curcubeu).
3. Fila **Titlu**: alege „Titan". Închide sheet-ul.
4. Header-ul de profil: avatarul are inel curcubeu, sub nume scrie „Titan".
5. Repornește aplicația (force-stop + redeschide). Rama + titlul persistă.
6. Clasament (din Profil): te vezi pe tine cu rama, titlul „Titan", și „Nivel 50" lângă nume.
7. Reset progres (Setări → Reset) NU e obligatoriu de testat, dar dacă îl faci: cosmeticele cad la default (nivel 0 → nu deții nimic).

- [ ] **Step 5: Curăță datele de test din producție**

Contul de test (`Șodo`) are acum leaguePoints umflate. Fie le lași (e contul
tău de dev), fie:
```bash
python3 -c "
import sys; sys.path.insert(0,'tools')
from purge_accounts import FIRESTORE, _session
s=_session()
s.patch(f'{FIRESTORE}/player_profiles/JWmT7q0QycRFtVfyYd2Xlnus1Ng1', json={'fields':{'leaguePoints':{'integerValue':'0'}}})
"
```

- [ ] **Step 6: Bifează în TODO.md**

Secțiunea RETENȚIE: mută item 1 la „✅ Cosmetice pe nivel — livrat, verificat
pe telefon". Notează: **NEVERIFICAT** — că un al doilea jucător îmi vede rama
în meci (badge-ul de meci nu carează încă `equippedTitle` din `MatchPlayer` —
extindere viitoare).

- [ ] **Step 7: Commit final**

```bash
git add lib/screens/admin/debug_tab.dart lib/data/player_profile_service.dart TODO.md
git commit -m "$(cat <<'EOF'
Cosmetice: buton de debug pentru testare + verificat pe telefon

Rama + titlul apar in profil si clasament, persista dupa repornire. Nivelul
apare langa nume. NEVERIFICAT: un al doilea jucator imi vede rama in meci.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- Catalog (rame + titluri + funcții pure) → Task 1 ✓
- Stocare locală + globali → Task 2 ✓
- `player_profiles` +3 câmpuri + heartbeat + `multiplayerIdentity` + model → Task 3 ✓
- Validare la afișare → Task 5 Step 7 (`validatedFrame`) ✓
- UI picker cu 3 file → Task 6 ✓
- Randare ramă (5 locuri) → Task 4 (widget comun acoperă profil/clasament/badge/prieteni/lobby) ✓
- Randare titlu (4 locuri) → Task 5 ✓
- Testare (unit + telefon) → Task 1/2/4/5/6 unit, Task 8 telefon ✓
- Reguli Firestore → Task 7 ✓

**Placeholder scan:** Task 5 Step 6 și Task 4 Step 4 conțin ramuri „dacă modelul
n-are câmpul, lasă pe seama Task 8" — nu sunt placeholdere, sunt decizii
condiționate de ce găsește executantul în `MatchPlayer`/modelul de prieten,
cu instrucțiune clară de fallback. Acceptabil.

**Type consistency:** `Frame`/`PlayerTitle` enums stabile din Task 1.
`frameFromId`/`titleFromId`/`frameStyle`/`titleLabel`/`ownsFrame`/`ownsTitle`/
`validatedFrame` — semnături identice peste tot. `myFrame`/`myTitle` +
`setMyFrame`/`setMyTitle`/`loadCosmetics` din Task 2, folosite consistent în
4, 5, 6. `equippedFrame`/`equippedTitle`/`level` pe `PlayerProfile` din Task 3,
citite în Task 5. `completedAchievementIds()` din Task 1, folosit în Task 6.

**Risc cunoscut:** numele exact al câmpului `leaguePoints` pe obiectul returnat
în `profile_screen.dart` (`data.multiplayerProfile.leaguePoints` e o ghicire) —
executantul verifică la Task 6 Step 4. `MatchPlayer` s-ar putea să nu carreze
`equippedTitle`/`equippedFrame` → badge-ul de meci nu arată cosmeticele altora
în v1, notat explicit în Task 5 Step 6 și Task 8 Step 6 ca extindere viitoare.
