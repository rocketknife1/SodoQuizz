import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/models/player_profile.dart';

void main() {
  test('isRecentlyActive: sub 5 min = activ, peste = inactiv, null = inactiv', () {
    final now = DateTime.now();
    PlayerProfile withActive(DateTime? t) => PlayerProfile(
        uid: 'x',
        name: 'X',
        avatarSeed: 'x',
        lastActive: t == null ? null : Timestamp.fromDate(t));
    expect(withActive(now.subtract(const Duration(minutes: 2))).isRecentlyActive, isTrue);
    expect(withActive(now.subtract(const Duration(minutes: 9))).isRecentlyActive, isFalse);
    expect(withActive(null).isRecentlyActive, isFalse);
  });

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

  test('fromDoc pe un profil vechi fara cosmetice -> default-uri', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('player_profiles').doc('u2').set({'name': 'Vechi'});
    final snap = await db.collection('player_profiles').doc('u2').get();
    final p = PlayerProfile.fromDoc(snap);
    expect(p.equippedFrame, 'none');
    expect(p.equippedTitle, 'novice');
    expect(p.level, 0);
  });
}
