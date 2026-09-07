import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Telemetrie per întrebare: de câte ori a fost arătată, câte răspunsuri
/// corecte, suma timpilor de răspuns. Din ea se estimează dificultatea (vezi
/// core/question_difficulty.dart) și, mai târziu, „quality loop"-ul
/// (întrebări cu skip/report mare).
///
/// `question_stats/{questionId}` — un doc plat, incrementat cu
/// `FieldValue.increment` (fără tranzacție, scrieri concurente se adună
/// corect). Regula Firestore e permisivă: e telemetrie, nu economie — cel mai
/// rău caz e o etichetă de dificultate strâmbă, pe care oricum o corectezi
/// manual din Admin.
class QuestionStatsService {
  QuestionStatsService._();
  static final instance = QuestionStatsService._();

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('question_stats');

  /// Se apelează la fiecare răspuns dintr-o partidă single-player.
  /// [ms] = timpul de la afișarea întrebării la răspuns. Best-effort:
  /// un eșec aici nu are voie să încurce jocul.
  void recordAnswer(String questionId,
      {required bool correct, required int ms}) {
    if (questionId.isEmpty) return;
    final safeMs = ms.clamp(0, 60000);
    _col.doc(questionId).set({
      'shown': FieldValue.increment(1),
      'correct': FieldValue.increment(correct ? 1 : 0),
      'msSum': FieldValue.increment(safeMs),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) {
      debugPrint('QuestionStatsService.recordAnswer a esuat: $e');
    });
  }

  /// Toate statisticile, pentru ecranul din Admin. Poate fi mare (până la
  /// numărul de întrebări jucate vreodată) — se citește o dată, la deschidere.
  Future<Map<String, QuestionStat>> fetchAll() async {
    try {
      final snap = await _col.get();
      return {
        for (final d in snap.docs) d.id: QuestionStat.fromMap(d.id, d.data()),
      };
    } catch (e) {
      debugPrint('QuestionStatsService.fetchAll a esuat: $e');
      return {};
    }
  }
}

class QuestionStat {
  final String questionId;
  final int shown;
  final int correct;
  final int msSum;

  const QuestionStat({
    required this.questionId,
    required this.shown,
    required this.correct,
    required this.msSum,
  });

  factory QuestionStat.fromMap(String id, Map<String, dynamic> d) => QuestionStat(
        questionId: id,
        shown: (d['shown'] as num?)?.toInt() ?? 0,
        correct: (d['correct'] as num?)?.toInt() ?? 0,
        msSum: (d['msSum'] as num?)?.toInt() ?? 0,
      );

  double get accuracy => shown == 0 ? 0 : correct / shown;
  double get avgMs => shown == 0 ? 0 : msSum / shown;
}
