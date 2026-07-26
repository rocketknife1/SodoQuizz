import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'storage_service.dart';

/// Sincronizează progresul local (tot ce ține `StorageService` prin
/// SharedPreferences) cu Firestore, pentru un cont Google logat — Guest
/// rămâne 100% local, neatins. Sincronizare generică (vezi
/// `StorageService.exportAll/importAll`), nu câmp-cu-câmp.
class CloudSyncService {
  CloudSyncService._();
  static final instance = CloudSyncService._();

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) => FirebaseFirestore.instance.collection('users').doc(uid);

  /// Apelat imediat după login. Dacă acest cont are deja progres salvat în
  /// cloud (de pe alt telefon/instalare), CLOUD-UL CÂȘTIGĂ — se suprascrie
  /// local cu el (decizie explicită, comportament standard de cloud save).
  /// Dacă e prima logare pe acest cont, progresul local curent (Guest) se
  /// urcă și devine punctul de plecare.
  Future<void> pullOrSeed() async {
    final user = AuthService.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      final doc = await _userDoc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        await StorageService.importAll(doc.data()!);
      } else {
        await push();
      }
    } catch (e) {
      debugPrint('CloudSyncService.pullOrSeed a esuat: $e');
    }
  }

  /// No-op sigur dacă nu e logat (Guest sau anonim din multiplayer) — se
  /// poate apela oricând fără să verifice apelantul starea de login.
  Future<void> push() async {
    final user = AuthService.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      final data = await StorageService.exportAll();
      await _userDoc(user.uid).set(data);
    } catch (e) {
      debugPrint('CloudSyncService.push a esuat: $e');
    }
  }
}
