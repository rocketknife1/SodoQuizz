import 'dart:math';

import 'package:flutter/material.dart';

import '../core/bot_brain.dart';
import '../core/daily_mode.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/bot_match.dart';
import '../models/multiplayer_models.dart';
import '../widgets/solid_menu_button.dart';
import '../widgets/space_background.dart';
import 'higher_lower_screen.dart';
import 'multiplayer/multiplayer_electric_chair_screen.dart';
import 'multiplayer/multiplayer_match_screen.dart';
import 'multiplayer/multiplayer_obby_screen.dart';
import 'multiplayer/multiplayer_rock_paper_scissors_screen.dart';
import 'multiplayer/multiplayer_tanks_screen.dart';
import 'unknown_game_screen.dart';

/// Modurile arătate pe ecranul de start — [botMatchModes] (cele cu boți
/// reali) plus Higher or Lower, care e deja solo prin natura lui (nu are
/// adversar de bătut, doar un cronometru), deci apasă direct pe modul lui
/// existent, fără [BotMatch].
const List<MatchGameMode> _setupModes = [...botMatchModes, MatchGameMode.higherLower];

/// Pornește un meci cu boți și deschide ecranul modului. [replace] = din
/// ecranul de rezultate („Joacă din nou"), ca butonul înapoi să nu ducă la
/// clasamentul vechi.
Future<void> launchBotMatch(BuildContext context, BotMatchSettings settings, {bool replace = false}) async {
  final navigator = Navigator.of(context);
  final identity = await AuthService.instance.multiplayerIdentity();
  final match = await BotMatch.start(
    settings,
    displayName: identity.name,
    photoUrl: identity.photoUrl,
    avatarStyle: identity.avatarStyle,
  );
  final route = MaterialPageRoute<void>(
    builder: (_) => switch (settings.mode) {
      MatchGameMode.quizzTanks => MultiplayerTanksScreen(matchId: match.matchId, bot: match),
      MatchGameMode.obby => MultiplayerObbyScreen(matchId: match.matchId, bot: match),
      MatchGameMode.electricChair => MultiplayerElectricChairScreen(matchId: match.matchId, bot: match),
      MatchGameMode.rockPaperScissors => MultiplayerRockPaperScissorsScreen(matchId: match.matchId, bot: match),
      MatchGameMode.classic || MatchGameMode.higherLower => MultiplayerMatchScreen(matchId: match.matchId, bot: match),
    },
  );
  // Boții se opresc singuri: la ecranul de rezultate, sau când jucătorul iese
  // din meci (BotMatch vede că fișa lui a dispărut). NU după `push` — ecranul
  // meciului e ÎNLOCUIT de rezultate, iar la Clasic boții își scriu scorul
  // final abia după ce jucătorul a ajuns deja acolo.
  if (replace) {
    await navigator.pushReplacement(route);
  } else {
    await navigator.push(route);
  }
}

class BotMatchSetupScreen extends StatefulWidget {
  const BotMatchSetupScreen({super.key});

  @override
  State<BotMatchSetupScreen> createState() => _BotMatchSetupScreenState();
}

class _BotMatchSetupScreenState extends State<BotMatchSetupScreen> {
  MatchGameMode _mode = MatchGameMode.classic;

  /// „Unknown" nu e un mod de meci multiplayer (nu are `MatchGameMode`):
  /// rulează local, cu boții în același proces — vezi unknown_game_screen.dart.
  bool _unknown = true;
  int _bots = 3;
  int _difficulty = 2;
  bool _starting = false;

  static IconData _iconFor(MatchGameMode m) => switch (m) {
        MatchGameMode.classic => Icons.quiz_rounded,
        MatchGameMode.rockPaperScissors => Icons.back_hand_rounded,
        MatchGameMode.quizzTanks => Icons.military_tech_rounded,
        MatchGameMode.electricChair => Icons.electric_bolt_rounded,
        MatchGameMode.obby => Icons.directions_run_rounded,
        MatchGameMode.higherLower => Icons.compare_arrows_rounded,
      };

  static Color _colorFor(MatchGameMode m) => switch (m) {
        MatchGameMode.classic => AppColors.blue,
        MatchGameMode.rockPaperScissors => AppColors.teal,
        MatchGameMode.quizzTanks => AppColors.orange,
        MatchGameMode.electricChair => AppColors.purple,
        MatchGameMode.obby => AppColors.play,
        MatchGameMode.higherLower => AppColors.gray,
      };

  static String _difficultyLabel(int d) => switch (d) {
        1 => tr('Începător', 'Beginner'),
        2 => tr('Ușor', 'Easy'),
        3 => tr('Normal', 'Normal'),
        4 => tr('Greu', 'Hard'),
        _ => tr('Maestru', 'Master'),
      };

  Future<void> _start() async {
    if (_starting) return;
    if (_unknown) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UnknownGameScreen(botCount: min(_bots, _unknownMaxBots), difficulty: _difficulty)),
      );
      return;
    }
    if (_mode == MatchGameMode.higherLower) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HigherLowerScreen()));
      return;
    }
    setState(() => _starting = true);
    try {
      await launchBotMatch(context, BotMatchSettings(mode: _mode, botCount: _bots, difficulty: _difficulty));
    } catch (e) {
      debugPrint('BotMatchSetupScreen._start: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Meciul cu boți n-a pornit. Încearcă din nou.', 'The bot match did not start. Try again.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    Text(tr('JOACĂ CU BOȚI', 'PLAY WITH BOTS'),
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    Text(
                      tr('Fără internet, fără miză. Nu contează la clasament.',
                          'No internet, no stake. Does not count for the leaderboard.'),
                      style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle(tr('MODUL', 'MODE')),
                    _unknownTile(),
                    for (final m in _setupModes) _modeTile(m),
                    // Higher or Lower e deja solo — nu are boți de ales.
                    if (_unknown || _mode != MatchGameMode.higherLower) ...[
                      const SizedBox(height: 14),
                      _sectionTitle(tr('BOȚI', 'BOTS')),
                      _chipRow(
                        count: (_unknown ? _unknownMaxBots : botMaxCount) - botMinCount + 1,
                        selected: min(_bots, _unknown ? _unknownMaxBots : botMaxCount) - botMinCount,
                        label: (i) => '${i + botMinCount}',
                        onTap: (i) => setState(() => _bots = i + botMinCount),
                      ),
                      const SizedBox(height: 18),
                      _sectionTitle(tr('DIFICULTATE • ${_difficultyLabel(_difficulty)}',
                          'DIFFICULTY • ${_difficultyLabel(_difficulty)}')),
                      _chipRow(
                        count: botMaxDifficulty - botMinDifficulty + 1,
                        selected: _difficulty - botMinDifficulty,
                        label: (i) => '★' * (i + 1),
                        onTap: (i) => setState(() => _difficulty = i + botMinDifficulty),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _starting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(color: AppColors.play),
                      )
                    : SolidMenuButton(
                        icon: Icons.smart_toy_rounded,
                        label: tr('START', 'START'),
                        color: AppColors.play,
                        big: true,
                        onTap: _start,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
      );

  /// Tabla are 6 culori de pioni: tu + cel mult 5 boți.
  static const _unknownMaxBots = 5;

  Widget _unknownTile() {
    final selected = _unknown;
    const color = AppColors.coin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _unknown = true),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? color.withAlpha(50) : Colors.white.withAlpha(12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? color : Colors.white24, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.star_rounded, color: Color(0xFF0B1229), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Unknown', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(tr('Insula stelelor: zaruri, cufere, dueluri', 'Star island: dice, chests, duels'),
                        style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)),
                child: Text(tr('NOU', 'NEW'),
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle_rounded, color: color, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeTile(MatchGameMode m) {
    final selected = !_unknown && m == _mode;
    final color = _colorFor(m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() {
          _mode = m;
          _unknown = false;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? color.withAlpha(60) : Colors.white.withAlpha(12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? color : Colors.white24, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Icon(_iconFor(m), color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(matchGameModeLabel(m),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipRow({
    required int count,
    required int selected,
    required String Function(int) label,
    required void Function(int) onTap,
  }) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == count - 1 ? 0 : 6),
              child: GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.coin : Colors.white.withAlpha(14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: i == selected ? AppColors.coin : Colors.white24),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(label(i),
                          style: TextStyle(
                            color: i == selected ? const Color(0xFF0B1229) : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          )),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
