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

  /// Șterge cloud-save-ul privat (progres local urcat) + un eventual grant
  /// de admin în așteptare — apelat DOAR de [AuthService.deleteAccount] la
  /// ștergere definitivă de cont. Nu atinge progresul local de pe telefon
  /// (StorageService rămâne neschimbat, userul devine un Guest nou).
  Future<void> deleteCloudSave() async {
    final user = AuthService.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    final uid = user.uid;
    try {
      await FirebaseFirestore.instance.collection('admin_grants').doc(uid).delete();
    } catch (_) {
      // ignorat - fara grant in asteptare, e deja no-op.
    }
    try {
      await _userDoc(uid).delete();
    } catch (e) {
      debugPrint('CloudSyncService.deleteCloudSave a esuat: $e');
    }
  }

  /// "Ridică" un eventual grant de resurse lăsat de admin (vezi AdminScreen +
  /// firestore.rules `admin_grants/{uid}`) — no-op sigur dacă nu e logat
  /// (Guest, singurul care nu are niciun canal către admin) sau dacă nu
  /// există niciun grant în așteptare. Apelată alături de
  /// PlayerProfileService.ensureProfileHeartbeat (main.dart), deci rulează
  /// la fiecare pornire/revenire din fundal a aplicației — grant-ul ajunge
  /// la jucător cel târziu la următoarea deschidere, nu instant.
  Future<void> consumePendingGrant() async {
    final user = AuthService.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      final ref = FirebaseFirestore.instance.collection('admin_grants').doc(user.uid);
      final doc = await ref.get();
      if (!doc.exists) return;
      final data = doc.data() ?? const <String, dynamic>{};
      final hearts = data['hearts'] as int? ?? 0;
      final hints = data['hints'] as int? ?? 0;
      final coins = data['coins'] as int? ?? 0;
      final gems = data['gems'] as int? ?? 0;
      final xp = data['xp'] as int? ?? 0;
      // hearts foloseste getLives/setLives (nu exista un StorageService.adjustLives
      // dedicat - setLives deja clampeaza sub 0, la fel ca restul adjust*-urilor).
      if (hearts != 0) await StorageService.setLives(await StorageService.getLives() + hearts);
      if (hints != 0) await StorageService.adjustHints(hints);
      if (coins != 0) await StorageService.adjustCoins(coins);
      if (gems != 0) await StorageService.adjustGems(gems);
      if (xp != 0) await StorageService.adjustXp(xp);
      await ref.delete();
    } catch (e) {
      debugPrint('CloudSyncService.consumePendingGrant a esuat: $e');
    }
  }
}
