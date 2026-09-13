import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../core/iap_catalog.dart';
import '../core/remote_flags.dart';
import 'shop.dart';

/// Învelișul subțire peste `in_app_purchase`. NU decide nimic despre economie
/// — doar deschide fluxul de plată al Google și lasă mai departe ce a răspuns.
/// Cine primește ce se hotărăște EXCLUSIV pe server (functions/iap.js).
///
/// Trei lucruri de care depinde corectitudinea, toate aici:
///
/// 1. **[_kAutoConsume] e `false`, mereu.** `buyConsumable` consumă implicit
///    tokenul în momentul în care ajunge pe stream, ÎNAINTE ca serverul nostru
///    să-l fi văzut. Dacă aplicația moare în milisecunda aia, tokenul e
///    consumat, Play nu-l mai livrează niciodată, serverul nu l-a înregistrat
///    — iar jucătorul a plătit degeaba, fără nicio cale de recuperare.
/// 2. **Nimic nu pornește cât timp magazinul e stins.** Cu killswitch-ul pe
///    `false`, pluginul nici măcar nu se conectează la Play.
/// 3. **Doar Android.** Nu există build de iOS aici, iar pe web
///    `InAppPurchase.instance` ar arunca. Toate metodele ies curat.
class IapService {
  IapService._();
  static final instance = IapService._();

  /// Vezi punctul 1 din documentația clasei. Nu schimba asta fără să citești
  /// PurchaseService — consumul se face manual, după validarea pe server.
  static const bool _kAutoConsume = false;

  bool _started = false;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Map<String, ProductDetails> _products = const {};

  /// `true` dacă plățile reale sunt pornite (constanta din cod SAU cheia din
  /// Remote Config, ca să se poată stinge fără build nou).
  bool get storeEnabled =>
      realMoneyStoreEnabled || RemoteFlags.instance.realMoneyStore;

  /// Platforma suportă plăți? (web și desktop: nu).
  bool get platformSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  bool get ready => _started;

  /// Pornește ascultarea fluxului de achiziții. [onPurchases] primește tot ce
  /// vine de la Play: cumpărături noi, cele restaurate, erorile.
  ///
  /// No-op sigur dacă magazinul e stins sau platforma nu suportă — de-aia
  /// poate fi apelată necondiționat de la pornirea aplicației.
  Future<bool> start(
      void Function(List<PurchaseDetails>) onPurchases) async {
    if (_started) return true;
    if (!platformSupported || !storeEnabled) return false;
    try {
      if (!await InAppPurchase.instance.isAvailable()) {
        debugPrint('IapService: Play Billing indisponibil pe dispozitivul asta');
        return false;
      }
      _sub = InAppPurchase.instance.purchaseStream.listen(
        onPurchases,
        onError: (Object e) => debugPrint('IapService: flux de achizitii: $e'),
      );
      _started = true;
      await _loadProducts();
      return true;
    } catch (e) {
      debugPrint('IapService.start a esuat: $e');
      return false;
    }
  }

  Future<void> _loadProducts() async {
    try {
      final r = await InAppPurchase.instance.queryProductDetails(allProductIds);
      _products = {for (final p in r.productDetails) p.id: p};
      if (r.notFoundIDs.isNotEmpty) {
        // Cel mai des: produsele n-au fost create/activate in Play Console, sau
        // build-ul nu e publicat pe nicio pista. Butonul de cumparare n-ar face
        // nimic, deci merita spus raspicat in log.
        debugPrint('IapService: produse negasite in Play: ${r.notFoundIDs}');
      }
    } catch (e) {
      debugPrint('IapService._loadProducts a esuat: $e');
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  /// Deschide fluxul de plată pentru [productId]. `false` dacă nici n-a putut
  /// porni (magazin stins, produs necunoscut de Play, platformă nesuportată).
  ///
  /// [accountId] e amprenta contului nostru (uid hash-uit), trimisă la Google
  /// ca `obfuscatedAccountId` — serverul o poate compara ca să prindă un bon
  /// mutat între conturi.
  Future<bool> buy(String productId, {String? accountId}) async {
    if (!_started || !storeEnabled) return false;
    final details = _products[productId];
    if (details == null) {
      debugPrint('IapService.buy: $productId nu e cunoscut de Play');
      return false;
    }
    final param = PurchaseParam(
      productDetails: details,
      applicationUserName: accountId,
    );
    try {
      // Neconsumabilele (fara reclame, pachetul de start) trec prin
      // buyNonConsumable: asa Play insusi tine minte ca le detii si le poate
      // restaura pe alt telefon.
      if (isNonConsumable(productId)) {
        return await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      }
      return await InAppPurchase.instance.buyConsumable(
        purchaseParam: param,
        autoConsume: _kAutoConsume, // vezi punctul 1 din doc-ul clasei
      );
    } catch (e) {
      debugPrint('IapService.buy($productId) a esuat: $e');
      return false;
    }
  }

  /// Cere lui Play să retrimită tot ce deține contul: neconsumabilele (pentru
  /// restaurare) și consumabilele neconsumate încă (o plată rămasă la
  /// jumătate). Ajung pe același flux, cu `PurchaseStatus.restored`.
  Future<void> restore() async {
    if (!_started || !storeEnabled) return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('IapService.restore a esuat: $e');
    }
  }

  /// Consumă tokenul, adică îl face cumpărabil din nou. Se apelează DOAR după
  /// ce serverul a confirmat că a înregistrat achiziția.
  Future<void> consume(PurchaseDetails purchase) async {
    if (!platformSupported) return;
    try {
      final android = InAppPurchase.instance
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await android.consumePurchase(purchase);
    } catch (e) {
      debugPrint('IapService.consume a esuat: $e');
    }
  }

  /// Închide tranzacția în plugin. Pe Android asta înseamnă `acknowledge` —
  /// dar serverul a confirmat deja (vezi functions/iap.js), deci aici e doar
  /// curățenie: un al doilea acknowledge e inofensiv, iar codul de răspuns nu
  /// ne interesează.
  Future<void> complete(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await InAppPurchase.instance.completePurchase(purchase);
    } catch (e) {
      debugPrint('IapService.complete a esuat (inofensiv): $e');
    }
  }
}
