import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/question_report.dart';
import 'multiplayer_service.dart';

/// Raportarea unei întrebări (nu a unui jucător — vezi ModerationService
/// pentru aia). Un doc în `question_reports`, care se adună de la toată
/// lumea pentru aceeași întrebare — id-ul include momentul, deliberat, ca
/// mai multe raportări pentru același `questionId` să nu se suprascrie
/// tăcut una pe alta (numărul lor e chiar semnalul că merită verificată).
class QuestionReportService {
  QuestionReportService._();
  static final instance = QuestionReportService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => MultiplayerService.instance.currentPlayerId;

  Future<bool> submitReport({
    required String questionId,
    required String questionText,
    required String category,
    required QuestionReportReason reason,
  }) async {
    final me = _uid;
    if (me.isEmpty || questionId.isEmpty) return false;
    try {
      final id = '${questionId}_${DateTime.now().millisecondsSinceEpoch}';
      await _db.collection('question_reports').doc(id).set({
        'reporterUid': me,
        'questionId': questionId,
        'questionText': questionText,
        'category': category,
        'reason': reason.name,
        'createdAt': FieldValue.serverTimestamp(),
        'handled': false,
      });
      return true;
    } catch (e) {
      debugPrint('QuestionReportService.submitReport a esuat: $e');
      return false;
    }
  }
}
