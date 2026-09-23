import '../core/weekly_event.dart';
import 'event_service.dart';
import 'storage_service.dart';

/// Detectează lazy încheierea săptămânii tematice și pregătește premiul final
/// (vezi core/weekly_event.dart). Fără job programat pe server: la prima
/// pornire după duminică seara, clientul își citește locul final din
/// clasamentul săptămânii trecute și îl salvează ca „premiu în așteptare",
/// pe care Acasa îl arată într-un dialog fără skip. Același tipar ca
/// SeasonRewardService.
class WeeklyRewardService {
  WeeklyRewardService._();
  static final instance = WeeklyRewardService._();

  /// Best-effort: fără rețea nu marchează nimic, se reia la următoarea
  /// pornire. Săptămâna în care n-am jucat deloc se marchează direct.
  Future<void> snapshotIfWeekEnded({DateTime? now}) async {
    try {
      final today = now ?? DateTime.now();
      final lastWeek = today.subtract(const Duration(days: 7));
      final eventId = weeklyEventId(lastWeek);
      if (await StorageService.weeklyRewardHandled() == eventId) return;
      if (await StorageService.pendingWeeklyReward() != null) return;

      final days = await StorageService.weeklyDaysPlayed(eventId);
      if (days.isEmpty) {
        await StorageService.setWeeklyRewardHandled(eventId);
        return;
      }
      final standing = await EventService.instance.finalStanding(eventId);
      if (standing == null) return; // rețea — încerc la pornirea următoare

      await StorageService.setPendingWeeklyReward(
        eventId: eventId,
        theme: weeklyThemeFor(lastWeek),
        rank: standing.rank,
        participants: standing.participants,
        // zilele de pe telefon sunt sursa sigură (se scriu la final de cursă);
        // cele din clasament pot lipsi dacă o scriere a căzut pe rețea
        days: days.length > standing.days ? days.length : standing.days,
        points: standing.points,
      );
      await StorageService.setWeeklyRewardHandled(eventId);
    } catch (_) {
      // se reia la următoarea pornire
    }
  }
}
