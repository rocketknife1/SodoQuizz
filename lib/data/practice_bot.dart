// ═══════════════════════════════════════════════════════════════════════════
//  TEMP BOT — ADVERSAR SIMULAT PENTRU TESTAT MULTIPLAYER-UL DE UNUL SINGUR.
//
//  NU face parte din joc. Există doar ca modul Clasic din multiplayer să
//  poată fi probat fără un al doilea telefon: intră singur în camera privată
//  la câteva secunde după ce o creezi, ca butonul START (care cere minimum 2
//  jucători) să devină apăsabil, apoi "răspunde" pe durata meciului ca să
//  existe un scor real de comparat și un pool de împărțit la final.
//
//  CUM SE ȘTERGE, cap-coadă:
//    1. se șterge fișierul ăsta;
//    2. se scot cele 3 apeluri marcate cu „TEMP BOT" din:
//         - lib/screens/multiplayer/room_lobby_screen.dart   (intrarea în lobby)
//         - lib/screens/multiplayer/multiplayer_match_screen.dart (scorul)
//         - lib/data/multiplayer_service.dart                (curățarea)
//  Nimic altceva din joc nu îl cunoaște.
//
//  De ce e un jucător REAL în Firestore și nu unul desenat local: tot restul
//  fluxului (lobby, rândul de scoruri, decontarea pariurilor, jurnalul de
//  cameră din admin) citește jucătorii din Firestore. Un bot pur local ar fi
//  cerut ramificații în fiecare din locurile alea — exact genul de urme greu
//  de scos la loc. Regulile permit deja scrierea în players/{oricine} (vezi
//  firestore.rules), deci nu e nevoie de nicio schimbare de permisiuni.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/game_helpers.dart';
import '../models/question.dart';

class PracticeBot {
  PracticeBot._();

  /// Comutatorul unic — STINS în orice build normal.
  ///
  /// Se aprinde doar cu `flutter build apk --dart-define=PRACTICE_BOT=true`,
  /// același tipar ca `REAL_ADS` din core/ads_service.dart. Motivul e
  /// economic, nu estetic: pariul botului sunt bani FANTOMĂ — intră în pool
  /// (vezi core/betting.dart) fără să fie scăzuți din portofelul cuiva, deci
  /// un om care câștigă meciul ar primi o parte dintr-un pool umflat cu
  /// monede care n-au existat niciodată. Într-un build de test, pe un singur
  /// telefon, n-are nicio importanță; într-unul public ar fi o fabrică de
  /// monede deschisă oricui.
  static const bool enabled = bool.fromEnvironment('PRACTICE_BOT');

  static const String botPlayerId = 'bot_practice';
  static const String botName = 'BOT (temporar)';

  /// După atâtea secunde de așteptare singur în lobby intră botul. Suficient
  /// cât un prieten adevărat să apuce să intre primul, dacă chiar vine unul.
  static const Duration joinDelay = Duration(seconds: 6);

  static bool isBot(String playerId) => playerId.startsWith('bot_');

  static CollectionReference<Map<String, dynamic>> _players(String matchId) =>
      FirebaseFirestore.instance
          .collection('matches')
          .doc(matchId)
          .collection('players');

  /// Bagă botul în cameră, dar NUMAI dacă ești încă singur acolo — dacă a
  /// intrat între timp un om adevărat, botul nu mai apare deloc.
  ///
  /// Pariul e copiat din documentul tău de jucător, ca masa să fie
  /// echilibrată și plafonul de masă (mediana × 7,3) să nu retezeze nimic în
  /// timpul testului.
  static Future<void> maybeJoin(String matchId) async {
    if (!enabled) return;
    try {
      final existing = await _players(matchId).get();
      if (existing.docs.length != 1) return;
      final mine = existing.docs.first.data();
      await _players(matchId).doc(botPlayerId).set({
        'name': botName,
        'avatarSeed': botPlayerId,
        'photoUrl': null,
        'score': 0,
        'isHost': false,
        'bet': mine['bet'] as int? ?? 0,
        'betPercent': (mine['betPercent'] as num?)?.toDouble() ?? 0,
        'finished': false,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('PracticeBot.maybeJoin a esuat: $e');
    }
  }

  /// Publică scorul botului. Apelată exact în aceleași două momente ca scorul
  /// jucătorului real (la jumătatea minutului și la final), ca botul să nu
  /// strice bugetul de citiri Firestore pentru care a fost gândită
  /// sincronizarea rară.
  static Future<void> publishScore({
    required String matchId,
    required int score,
    required bool finished,
  }) async {
    if (!enabled) return;
    try {
      await _players(matchId)
          .doc(botPlayerId)
          .update({'score': score, 'finished': finished});
    } catch (e) {
      debugPrint('PracticeBot.publishScore a esuat: $e');
    }
  }

  /// Scoate botul din meci. Fără asta, documentul lui ar rămâne în urmă când
  /// pleci tu, camera n-ar mai fi văzută ca goală și n-ar mai fi ștearsă
  /// niciodată (vezi MultiplayerService.leaveMatch).
  static Future<void> cleanup(String matchId) async {
    if (!enabled) return;
    try {
      final docs = await _players(matchId).get();
      for (final d in docs.docs) {
        if (isBot(d.id)) await d.reference.delete();
      }
    } catch (e) {
      debugPrint('PracticeBot.cleanup a esuat: $e');
    }
  }
}

/// Creierul botului pe durata unui meci Clasic — pur local, fără rețea.
/// Nu are propriul cronometru: e împins de același tick de o secundă care
/// mișcă și cronometrul meciului (vezi MultiplayerMatchScreen).
///
/// Joacă după EXACT aceleași reguli ca un om: aceleași întrebări, în aceeași
/// ordine, aceleași penalizări. Nu trișează — de-aia scorul lui e un reper
/// real, nu un număr inventat.
class PracticeBotBrain {
  final List<Question> questions;
  final Random _rnd;

  /// Cât de des nimerește. 62% e cam un jucător decent: bătabil dacă ești
  /// atent, dar te pedepsește dacă bați la nimereală.
  static const double _accuracy = 0.62;

  /// Cât "se gândește" între răspunsuri, în secunde — de aici iese și câte
  /// întrebări apucă într-un minut (~9-13).
  static const int _minThinkSeconds = 4;
  static const int _thinkSpread = 3;

  int _score = 0;
  int _index = 0;
  int _nextAnswerAt;

  PracticeBotBrain({required this.questions, required int seed})
      : _rnd = Random(seed),
        _nextAnswerAt = 0 {
    _nextAnswerAt = _rollThinkTime();
  }

  int get score => _score;

  int _rollThinkTime() => _minThinkSeconds + _rnd.nextInt(_thinkSpread + 1);

  /// [elapsedSeconds] = de câte secunde durează meciul. Recuperează toate
  /// răspunsurile "datorate" până în acest moment.
  void tick(int elapsedSeconds) {
    while (_nextAnswerAt <= elapsedSeconds && _index < questions.length) {
      _answerOne();
      _nextAnswerAt += _rollThinkTime();
    }
  }

  void _answerOne() {
    final q = questions[_index];
    _index++;
    // Din când în când folosește un hint pe o întrebare grasă, exact ca un om
    // care nu știe: plătește costul în puncte și îi rămân două variante.
    final usesHint = q.maxPoints >= 400 && _rnd.nextDouble() < 0.22;
    var chance = _accuracy;
    if (usesHint) {
      _score -= multiplayerHintPenalty(q.maxPoints);
      // cu două variante rămase, chiar și cine habar n-are are 50%
      chance = _accuracy + (1 - _accuracy) * 0.5;
    }
    if (_rnd.nextDouble() < chance) {
      _score += q.maxPoints;
    } else {
      _score -= multiplayerWrongPenalty(q.maxPoints);
    }
  }
}
