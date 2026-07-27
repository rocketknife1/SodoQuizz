import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// ID-uri PUBLICE DE TEST ale Google (documentate oficial) — sigure de
/// folosit oricând, nu generează încasări reale și nu au nevoie de cont
/// AdMob propriu. Când există un cont AdMob real (vezi checklist-ul de
/// publicare), înlocuiește-le cu ID-urile reale din consola AdMob, atât aici
/// cât și App ID-ul din android/app/src/main/AndroidManifest.xml.
const _testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

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
    if (_initialized) return;
    _initialized = true;
    try {
      await MobileAds.instance.initialize();
      _loadRewarded();
    } catch (e) {
      debugPrint('AdsService.init a esuat: $e');
    }
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _testRewardedAdUnitId,
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
  /// următoarea reclamă după ce cea curentă se închide.
  Future<bool> showRewarded({required VoidCallback onReward}) async {
    final ad = _rewardedAd;
    if (ad == null) return false;
    _rewardedAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewarded();
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => onReward());
    return true;
  }
}
