import 'package:flutter/material.dart';

import '../data/storage_service.dart';
import 'leagues.dart';
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

/// Rama de afisat pentru un jucator, verificand ca o DETINE cu adevarat din
/// nivelul/liga lui publice. Titlurile din realizari NU se pot valida (nu-s in
/// profilul public) - se afiseaza pe incredere, sunt pur vizuale.
Frame validatedFrame(String equippedFrame,
    {required int level, required int leaguePoints}) {
  final f = frameFromId(equippedFrame);
  return ownsFrame(f, level: level, leaguePoints: leaguePoints) ? f : Frame.none;
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

// Culorile de ligă sunt copiate din `_leagues` (privat în leagues.dart) —
// bronze/silver/gold/platinum. Le ținem literal aici ca să nu deschidem
// lista de ligi doar pentru cosmetice.
FrameStyle frameStyle(Frame f) => switch (f) {
      Frame.none => const FrameStyle([Colors.transparent]),
      Frame.bronze => const FrameStyle([Color(0xFFCD7F32)]),
      Frame.silver => const FrameStyle([Color(0xFFB0BEC5)]),
      Frame.gold => const FrameStyle([Color(0xFFFFD700)]),
      Frame.platinum => const FrameStyle([Color(0xFF5EC8F2)]),
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

/// Etichetă scurtă pentru pickerul de rame — altfel inelele colorate
/// (aur/argint/diamant/nivel) nu se pot deosebi între ele.
String frameLabel(Frame f) => switch (f) {
      Frame.none => 'Fără',
      Frame.bronze => 'Bronz',
      Frame.silver => 'Argint',
      Frame.gold => 'Aur',
      Frame.platinum => 'Platină',
      Frame.diamond => 'Diamant',
      Frame.lvl10 => 'Nivel 10',
      Frame.lvl25 => 'Nivel 25',
      Frame.lvl50 => 'Nivel 50',
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

// ─── Ce am echipat pe TELEFONUL ăsta ─────────────────────────────────────
//
// Tiparul `myAvatarStyle` din widgets/avatar.dart: ValueNotifier global, citit
// o dată la pornire, ținut aici ca schimbarea să se vadă instant peste tot
// fără restart.

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
