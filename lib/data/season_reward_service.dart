import '../core/leagues.dart';
import 'player_profile_service.dart';
import 'storage_service.dart';

/// Detectează lazy sfârşitul unui sezon şi pregăteşte recompensa (vezi
/// core/season_rewards.dart). Fără job programat.
class SeasonRewardService {
  SeasonRewardService._();
  static final instance = SeasonRewardService._();

  /// De chemat la pornirea aplicaţiei, ÎNAINTE de orice meci. Dacă sezonul de
  /// pe profilul meu public e din luna trecută şi aveam puncte, îl salvez
  /// local ca „recompensă în aşteptare" — pentru că primul meci din luna nouă
  /// resetează `seasonPoints`/`seasonBestTierIndex` şi informaţia s-ar pierde.
  ///
  /// Best-effort: fără reţea / fără profil = nu face nimic, se reia la
  /// următoarea pornire.
  Future<void> snapshotIfSeasonEnded() async {
    try {
      final profile = await PlayerProfileService.instance.getMyProfile();
      if (profile == null) return;
      final key = profile.seasonKey;
      if (key.isEmpty || key == currentSeasonKey()) return;
      if (profile.seasonPoints <= 0) return;
      if (await StorageService.seasonRewardHandledKey() == key) return;

      await StorageService.setSeasonRewardHandled(key);
      // Nu suprascrie una încă nerevendicată (jucătorul a lipsit 2 luni) —
      // păstrează cea mai veche, care oricum e prima în coadă.
      if (await StorageService.pendingSeasonReward() == null) {
        await StorageService.setPendingSeasonReward(key, profile.seasonBestTierIndex);
      }
    } catch (_) {
      // se reia la următoarea pornire
    }
  }
}
