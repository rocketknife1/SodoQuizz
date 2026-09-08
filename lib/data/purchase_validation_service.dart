import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Ce a răspuns serverul la validarea unui bon (vezi functions/iap.js).
class ValidationResult {
  /// Serverul a înregistrat achiziția (fie acum, fie mai devreme).
  final bool ok;

  /// `granted` / `already_granted` / `transferred`.
  final String status;

  /// Id-ul cumpărăturii din cutia poștală, dacă are resurse de livrat.
  final String? grantId;

  /// Are voie clientul să consume tokenul la Play? (doar la consumabile, și
  /// doar după ce serverul a zis da).
  final bool consume;

  /// De ce a picat, când [ok] e `false` — vezi tabelul din functions/iap.js.
  final String? reason;

  /// `true` = mai încearcă la o pornire viitoare, NU atinge tokenul de la Play.
  /// `false` = e definitiv, tokenul poate fi eliberat.
  final bool retryable;

  final bool noAdsForever;
  final bool starterPackBought;
  final int? unlimitedLivesUntilMs;

  const ValidationResult({
    required this.ok,
    this.status = '',
    this.grantId,
    this.consume = false,
    this.reason,
    this.retryable = true,
    this.noAdsForever = false,
    this.starterPackBought = false,
    this.unlimitedLivesUntilMs,
  });
}

/// Singurul loc din aplicație care cheamă o Cloud Function.
///
/// ATENȚIE la regiune: funcțiile proiectului rulează în `europe-west1`
/// (`setGlobalOptions` din functions/index.js). Fără `instanceFor(region:)`
/// SDK-ul cheamă `us-central1` și apelul pică tăcut cu NOT_FOUND — o oră
/// pierdută garantat dacă se uită.
class PurchaseValidationService {
  PurchaseValidationService._();
  static final instance = PurchaseValidationService._();

  static const String region = 'europe-west1';

  FirebaseFunctions get _fns => FirebaseFunctions.instanceFor(region: region);

  Future<ValidationResult> validate({
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      final res = await _fns.httpsCallable('validatePurchase').call<Map<String, dynamic>>({
        'platform': 'android',
        'productId': productId,
        'purchaseToken': purchaseToken,
      });
      final d = Map<String, dynamic>.from(res.data);
      final ent = Map<String, dynamic>.from(d['entitlements'] as Map? ?? const {});
      return ValidationResult(
        ok: d['ok'] == true,
        status: d['status'] as String? ?? '',
        grantId: d['grantId'] as String?,
        consume: d['consume'] == true,
        noAdsForever: ent['noAdsForever'] == true,
        starterPackBought: ent['starterPackBought'] == true,
        unlimitedLivesUntilMs: (ent['unlimitedLivesUntil'] as num?)?.toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : const {};
      final reason = details['reason'] as String? ?? e.code;
      // Prejudecata implicită e „mai încearcă": a NU elibera tokenul înseamnă
      // cel mult o reîncercare la următoarea pornire, în timp ce a-l elibera
      // greșit înseamnă o plată pierdută definitiv.
      final retryable = details['retryable'] as bool? ?? true;
      debugPrint('validatePurchase a picat: $reason (retryable: $retryable)');
      return ValidationResult(ok: false, reason: reason, retryable: retryable);
    } catch (e) {
      debugPrint('validatePurchase a picat neasteptat: $e');
      return const ValidationResult(ok: false, reason: 'unexpected', retryable: true);
    }
  }
}
