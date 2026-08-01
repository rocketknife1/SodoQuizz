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

/// Wrapper minimal peste reclamele recompensate (Rewarded) — pregătit, dar
/// NEconectat încă la butonul "Reclamă" din game_screen.dart (acela rămâne
/// simulat deocamdată, la cerere explicită). Când se decide activarea
/// reclamelor reale, [GameScreen] poate apela [AdsService.instance.showRewarded]
/// în loc să acorde recompensa direct.
class AdsService {
  AdsService._();
  static final instance = AdsService._();

  bool _initialized = false;
  RewardedAd? _rewardedAd;

  Future<void> init() async {
    if (_initialized || kIsWeb) return; // google_mobile_ads nu suporta Flutter Web
    _initialized = true;
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: _testDeviceIds),
      );
      await MobileAds.instance.initialize();
      _loadRewarded();
    } catch (e) {
      debugPrint('AdsService.init a esuat: $e');
    }
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
}
