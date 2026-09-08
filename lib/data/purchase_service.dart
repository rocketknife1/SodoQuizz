import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/iap_catalog.dart';
import 'iap_service.dart';
import 'multiplayer_service.dart';
import 'purchase_validation_service.dart';
import 'storage_service.dart';

/// Ce s-a aplicat efectiv în sold dintr-o achiziție — folosit de magazin ca
/// să pornească animația de recompensă cu sumele reale.
class AppliedPurchase {
  final String grantId;
  final String productId;
  final int gems;
  final int hearts;
  final int hints;
  const AppliedPurchase({
    required this.grantId,
    required this.productId,
    this.gems = 0,
    this.hearts = 0,
    this.hints = 0,
  });

  bool get isEmpty => gems == 0 && hearts == 0 && hints == 0;
}

/// Dirijorul achizițiilor cu bani reali. Leagă cele trei straturi care se
/// acoperă unul pe altul, ca o plată să nu se piardă și să nu se dubleze:
///
/// 1. **Play** — ține tokenul „deținut și neconsumat" până îl eliberăm noi
///    explicit. Orice cade înainte ca serverul să confirme se recuperează prin
///    `restorePurchases()` la următoarea pornire.
/// 2. **Firestore** — `purchase_tokens` revendicat cu `tx.create` în aceeași
///    tranzacție care scrie cumpărătura în cutia poștală. Exact o dată,
///    rezistent la apeluri simultane.
/// 3. **Jurnalul local** — [StorageService.beginPurchaseJournal] și frații lui.
///    Aici se inversează prejudecata de la `admin_grants`: se aplică ÎNTÂI, se
///    șterge din cloud DUPĂ.
///
/// Drepturile permanente (fără reclame, pachetul de start) se OGLINDESC din
/// `entitlements/{uid}` în SharedPreferences, monoton: doar se aprind, nu se
/// sting niciodată. Un listener care n-a apucat să răspundă sau o citire
/// offline n-au voie să ia înapoi un perk plătit.
class PurchaseService {
  PurchaseService._();
  static final instance = PurchaseService._();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _entSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _grantsSub;
  bool _applying = false;

  final _applied = StreamController<AppliedPurchase>.broadcast();

  /// Ce tocmai a intrat în sold. Magazinul ascultă cât e deschis, ca să
  /// pornească animația; când nu ascultă nimeni, [StorageService.balanceRevision]
  /// se ocupă oricum de reîmprospătarea ecranelor.
  Stream<AppliedPurchase> get onApplied => _applied.stream;

  String get _uid => MultiplayerService.instance.currentPlayerId;

  /// Amprenta contului trimisă la Google ca `obfuscatedAccountId`.
  String? get accountId {
    final uid = _uid;
    if (uid.isEmpty) return null;
    return sha256.convert(utf8.encode(uid)).toString().substring(0, 32);
  }

  // ─── Ciclu de viață (chemat din LiveSync) ─────────────────────────────────

  void startLive() {
    final uid = _uid;
    if (uid.isEmpty) return;
    stopLive();
    final db = FirebaseFirestore.instance;
    try {
      _entSub = db.collection('entitlements').doc(uid).snapshots().listen(
            _mirrorEntitlements,
            onError: (Object e) => debugPrint('PurchaseService: drepturi: $e'),
          );
      _grantsSub = db
          .collection('purchase_grants')
          .doc(uid)
          .collection('pending')
          .snapshots()
          .listen(
            (snap) => _applyPending(snap.docs),
            onError: (Object e) => debugPrint('PurchaseService: cutia postala: $e'),
          );
    } catch (e) {
      debugPrint('PurchaseService.startLive a esuat: $e');
    }
    // Achizițiile rămase la jumătate de la sesiunea trecută (aplicația a murit
    // în timpul aplicării) — listenerul de mai sus le re-livrează oricum, dar
    // asta le prinde și când documentul a apucat să fie șters.
    unawaited(_finishUnfinishedJournals());
    // Pluginul de plăți pornește DE AICI, nu din main: cu magazinul stins
    // (killswitch) `start` iese imediat, deci nici nu se conectează la Play.
    // Odată pornit, cere lui Play ce a rămas neconsumat de la o sesiune
    // întreruptă — asta e calea prin care se recuperează o plată pierdută.
    unawaited(() async {
      if (await IapService.instance.start(handlePurchases)) {
        await IapService.instance.restore();
      }
    }());
  }

  void stopLive() {
    _entSub?.cancel();
    _entSub = null;
    _grantsSub?.cancel();
    _grantsSub = null;
  }

  // ─── Oglinda drepturilor permanente ───────────────────────────────────────

  Future<void> _mirrorEntitlements(DocumentSnapshot<Map<String, dynamic>> snap) async {
    final d = snap.data();
    if (d == null) return; // lipsa documentului NU revocă nimic
    try {
      if (d['noAdsForever'] == true) await StorageService.setNoAdsForever();
      if (d['starterPackBought'] == true) await StorageService.setStarterPackBought();
      final until = d['unlimitedLivesUntil'];
      if (until is Timestamp) {
        final left = until.toDate().difference(DateTime.now());
        // MONOTON, ca tot restul oglinzii: `activateUnlimitedLives` SUPRASCRIE
        // termenul, deci fără comparația asta un server rămas în urmă ar putea
        // SCURTA un interval plătit. Se scrie doar dacă serverul întinde mai
        // departe decât ce avem local.
        final local = await StorageService.unlimitedLivesRemaining();
        if (left > local) await StorageService.activateUnlimitedLives(left);
      }
    } catch (e) {
      debugPrint('PurchaseService._mirrorEntitlements a esuat: $e');
    }
  }

  // ─── Aplicarea cumpărăturilor din cutia poștală ───────────────────────────

  Future<void> _applyPending(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_applying) return;
    _applying = true;
    try {
      for (final doc in docs) {
        await _applyGrant(doc.id, doc.data(), doc.reference);
      }
    } finally {
      _applying = false;
    }
  }

  /// Aplică o cumpărătură în sold, pas cu pas, cu jurnal. Ordinea contează:
  /// scrie în sold, marchează pasul, iar la final șterge documentul din cloud.
  /// O întrerupere oriunde lasă exact urma din care se reia.
  Future<void> _applyGrant(
    String grantId,
    Map<String, dynamic> data,
    DocumentReference<Map<String, dynamic>>? ref,
  ) async {
    final gems = (data['gems'] as num?)?.toInt() ?? 0;
    final hearts = (data['hearts'] as num?)?.toInt() ?? 0;
    final hints = (data['hints'] as num?)?.toInt() ?? 0;
    final unlimitedHours = (data['unlimitedLivesHours'] as num?)?.toInt() ?? 0;
    final productId = data['productId'] as String? ?? '';

    if (!await StorageService.isPurchaseApplied(grantId)) {
      await StorageService.beginPurchaseJournal(grantId);
      final facuti = await StorageService.journalSteps(grantId);

      if (gems != 0 && !facuti.contains('gems')) {
        await StorageService.adjustGems(gems);
        await StorageService.markJournalStep(grantId, 'gems');
      }
      if (hearts != 0 && !facuti.contains('hearts')) {
        await StorageService.setLives(await StorageService.getLives() + hearts);
        await StorageService.markJournalStep(grantId, 'hearts');
      }
      if (hints != 0 && !facuti.contains('hints')) {
        await StorageService.adjustHints(hints);
        await StorageService.markJournalStep(grantId, 'hints');
      }
      if (unlimitedHours != 0 && !facuti.contains('unlimited')) {
        await StorageService.activateUnlimitedLives(Duration(hours: unlimitedHours));
        await StorageService.markJournalStep(grantId, 'unlimited');
      }

      await StorageService.endPurchaseJournal(grantId);

      final applied = AppliedPurchase(
        grantId: grantId,
        productId: productId,
        gems: gems,
        hearts: hearts,
        hints: hints,
      );
      if (!applied.isEmpty) _applied.add(applied);
    }

    // Abia acum se șterge din cloud. Dacă ștergerea pică, documentul revine la
    // următoarea pornire, verificarea de mai sus scurtcircuitează și se
    // reîncearcă doar ștergerea.
    try {
      await ref?.delete();
    } catch (e) {
      debugPrint('PurchaseService: nu am putut sterge grantul $grantId: $e');
    }
  }

  /// Reia jurnalele rămase deschise. Documentul din cloud poate lipsi deja
  /// (ștergerea a reușit, aplicarea nu apucase să se închidă), caz în care nu
  /// mai avem ce aplica — doar închidem jurnalul ca să nu rămână orfan.
  Future<void> _finishUnfinishedJournals() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      for (final grantId in await StorageService.unfinishedPurchaseJournals()) {
        final ref = FirebaseFirestore.instance
            .collection('purchase_grants')
            .doc(uid)
            .collection('pending')
            .doc(grantId);
        final snap = await ref.get();
        if (snap.exists) {
          await _applyGrant(grantId, snap.data()!, ref);
        } else {
          await StorageService.endPurchaseJournal(grantId);
        }
      }
    } catch (e) {
      debugPrint('PurchaseService._finishUnfinishedJournals a esuat: $e');
    }
  }

  // ─── Fluxul de la Play ────────────────────────────────────────────────────

  /// Se dă lui [IapService.start] ca ascultător. Fiecare cumpărătură trece pe
  /// aici: se validează pe server, ABIA APOI se eliberează tokenul.
  Future<void> handlePurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      try {
        await _handleOne(p);
      } catch (e) {
        debugPrint('PurchaseService: achizitia ${p.productID} a esuat: $e');
      }
    }
  }

  Future<void> _handleOne(PurchaseDetails p) async {
    switch (p.status) {
      case PurchaseStatus.pending:
        // Plată în așteptare (transfer bancar, aprobare părinte). NU se
        // completează — pluginul aruncă dacă o faci acum.
        return;

      case PurchaseStatus.error:
      case PurchaseStatus.canceled:
        debugPrint('PurchaseService: ${p.productID} ${p.status.name}: ${p.error?.message}');
        await IapService.instance.complete(p);
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        final res = await PurchaseValidationService.instance.validate(
          productId: p.productID,
          purchaseToken: p.verificationData.serverVerificationData,
        );

        if (!res.ok) {
          if (res.retryable) {
            // NU atingem tokenul: Play îl va re-livra la următoarea pornire.
            debugPrint('PurchaseService: validare amanata (${res.reason})');
            return;
          }
          // Definitiv (bon anulat/rambursat, produs necunoscut) — eliberăm
          // tokenul ca să nu rămână blocat în coadă pentru totdeauna.
          debugPrint('PurchaseService: validare refuzata definitiv (${res.reason})');
          if (!isNonConsumable(p.productID)) await IapService.instance.consume(p);
          await IapService.instance.complete(p);
          return;
        }

        // Serverul a înregistrat achiziția. Resursele vin prin listenerul
        // cutiei poștale (sau prin cel de drepturi) — aici doar eliberăm
        // tokenul, ca Play să nu-l mai re-livreze.
        if (res.consume) await IapService.instance.consume(p);
        await IapService.instance.complete(p);
        return;
    }
  }

}
