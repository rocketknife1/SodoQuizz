import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/firestore_batch.dart';
import 'package:guess_it/data/local_firestore.dart';

void main() {
  test('deleteInChunks șterge și peste limita de 500 a unui batch', () async {
    final db = LocalFirestore();
    final col = db.collection('friend_chats').doc('a_b').collection('messages');
    for (var i = 0; i < 1001; i++) {
      await col.doc('m$i').set({'i': i});
    }
    await deleteInChunks(db, [for (final d in (await col.get()).docs) d.reference]);
    expect((await col.get()).docs, isEmpty);
  });
}
