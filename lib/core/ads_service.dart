import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback, debugPrint, kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad unit ID real (Rewarded), din consola AdMob (app "Sodo Quizz").
const _rewardedAdUnitId = 'ca-app-pub-7925849908413802/5562564815';

/// Device-urile de test (telefonul de dezvoltare) primesc reclame marcate
/// clar "Test Ad" în loc de reclame reale, chiar și cu ad unit ID-ul real —
/// altfel vizionările repetate de pe același device în timpul testării
/// riscă să fie catalogate de Google drept trafic invalid și să suspende
/// contul AdMob.
const _testDeviceIds = ['211650EF1A0E1A07C39AF7E073AB33F4'];

/// Wrapper minimal peste reclamele recompensate (Rewarded), conectat la
/// toate punctele din aplicație care oferă recompensă pentru reclamă:
/// butonul "Reclamă" din game_screen.dart (apelează [showRewarded] direct)
/// și quests/achievements/culture_quiz_panel (prin [watchOrSimulate], care
/// acordă recompensa simulat dacă reclama nu s-a încărcat la timp, ca
/// fluxul să nu depindă de fill rate-ul AdMob).
class AdsService {
  AdsService._();
  static final instance = AdsService._();

  bool _initialized = false;
  RewardedAd? _rewardedAd;

  /// Fluxul UMP (User Messaging Platform) cere consimțământul GDPR înainte
  /// de a cere reclame userilor din UE/UK/state americane reglementate —
  /// obligatoriu conform politicii AdMob (nu opțional), altfel contul
  /// riscă suspendare. [ConsentInformation.canRequestAds] rămâne sursa de
  /// adevăr: dacă rămâne false (consimțământ neobținut sau cerere eșuată
  /// fără net la pornire), SDK-ul de reclame nici nu se inițializează —
  /// [_rewardedAd] rămâne null, iar [showRewarded]/[watchOrSimulate] cad
  /// deja pe fallback-ul simulat, deci fluxul de recompensă tot funcționează.
  Future<void> init() async {
    if (_initialized || kIsWeb) return; // google_mobile_ads nu suporta Flutter Web
    _initialized = true;
    try {
      await _requestConsent();
      if (!await ConsentInformation.instance.canRequestAds()) {
        debugPrint('AdsService: consimțământ neobținut — reclame dezactivate pentru sesiunea curentă.');
        return;
      }
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: _testDeviceIds),
      );
      await MobileAds.instance.initialize();
      _loadRewarded();
    } catch (e) {
      debugPrint('AdsService.init a esuat: $e');
    }
  }

  /// [testIdentifiers] activează UI-ul de debug UMP DOAR pe telefonul de
  /// dezvoltare (același ID ca la [_testDeviceIds]) — fără [debugGeography]
  /// setat, geografia rămâne cea reală (România e deja UE, deci formularul
  /// apare oricum normal la testare, fără să simulăm nimic).
  Future<void> _requestConsent() {
    final completer = Completer<void>();
    final params = ConsentRequestParameters(
      consentDebugSettings: ConsentDebugSettings(testIdentifiers: _testDeviceIds),
    );
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () => ConsentForm.loadAndShowConsentFormIfRequired((formError) {
        if (formError != null) {
          debugPrint('AdsService: formularul de consimțământ a eșuat: ${formError.message}');
        }
        if (!completer.isCompleted) completer.complete();
      }),
      (error) {
        debugPrint('AdsService: actualizarea consimțământului a eșuat: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (error) {
          debugPrint('AdsService: reclama recompensata nu s-a incarcat: $error');
          _rewardedAd = null;
        },
      ),
    );
  }

  bool get isRewardedReady => _rewardedAd != null;

  /// Arată reclama recompensată dacă e încărcată — [onReward] se apelează
  /// doar dacă userul a văzut reclama până la capăt. Reîncarcă automat
  /// următoarea reclamă după ce cea curentă se închide. Future-ul returnat
  /// nu se termină la apelul show() (acela revine imediat, înainte ca
  /// userul să fi terminat de văzut reclama) ci abia când reclama chiar
  /// s-a închis, ca apelantul să poată acorda recompensa la momentul corect.
  Future<bool> showRewarded({required VoidCallback onReward}) async {
    final ad = _rewardedAd;
    if (ad == null) return false;
    _rewardedAd = null;
    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewarded();
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => onReward());
    await dismissed.future;
    return true;
  }

  /// La fel ca [showRewarded], dar când reclama nu e încărcată simulează o
  /// scurtă așteptare și acordă recompensa oricum, în loc să blocheze
  /// jucătorul — folosit la locurile unde fluxul NU trebuie să depindă de
  /// fill rate-ul AdMob (ex. Game Over din game_screen.dart, "Revendică x2"
  /// la quests/realizări). Întoarce mereu true (recompensa e mereu acordată).
  Future<bool> watchOrSimulate() async {
    var earned = false;
    final shown = await showRewarded(onReward: () => earned = true);
    if (!shown) {
      await Future.delayed(const Duration(milliseconds: 900));
      earned = true;
    }
    return earned;
  }

  /// True doar pentru useri din UE/UK/state americane reglementate — Google
  /// cere un buton vizibil de "Opțiuni de confidențialitate" în Setări
  /// DOAR pentru aceștia (vezi rândul din settings_screen.dart), nu pentru
  /// restul lumii.
  Future<bool> privacyOptionsRequired() async {
    if (kIsWeb) return false;
    final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  /// Redeschide formularul de opțiuni de confidențialitate UMP (linkul cerut
  /// de Google în Setări). Dacă userul tocmai a acordat consimțământul de
  /// aici (nu la pornire), reclama recompensată nu era încă încărcată —
  /// reîncearcă imediat, ca schimbarea să aibă efect fără un restart.
  Future<void> showPrivacyOptionsForm() async {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((formError) {
      if (formError != null) debugPrint('AdsService: formularul de optiuni a esuat: ${formError.message}');
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    if (_rewardedAd == null && await ConsentInformation.instance.canRequestAds()) {
      await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(testDeviceIds: _testDeviceIds));
      await MobileAds.instance.initialize();
      _loadRewarded();
    }
  }
}
