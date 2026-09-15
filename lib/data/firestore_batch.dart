import 'package:cloud_firestore/cloud_firestore.dart';

/// Șterge [refs] în loturi, în ordinea dată. Un batch Firestore ține maximum
/// 500 de operații: un fir de chat sau un meci cu mai multe documente pica
/// întreg (eroarea era prinsă în tăcere) și rămânea în bază.
Future<void> deleteInChunks(FirebaseFirestore db, List<DocumentReference> refs) async {
  for (var i = 0; i < refs.length; i += 450) {
    final batch = db.batch();
    for (final ref in refs.skip(i).take(450)) {
      batch.delete(ref);
    }
    await batch.commit();
  }
}
