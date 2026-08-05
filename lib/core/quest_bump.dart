import 'package:flutter/material.dart';
import 'audio.dart';
import 'progression.dart';
import '../data/storage_service.dart';
import '../screens/achievements_screen.dart';
import '../screens/quests_screen.dart';
import '../widgets/in_app_notification.dart';

/// Adaugă progres la un quest zilnic, identificat prin [metricKey] (nu prin
/// id — mai multe variante de dificultate ale aceleiași acțiuni, ex.
/// correct_5/10/15, împart același contor de progres, vezi
/// [Quest.metricKey]). Dacă vreunul dintre quest-urile active AZI (vezi
/// [todaysQuests] — grupa zilei din rotația săptămânală) care folosesc acest metric tocmai și-a
/// atins ținta, arată o notificare in-app. Un singur bump poate completa
/// mai multe quest-uri deodată (ex: un salt mare de monede poate trece
/// simultan pragul unui quest ușor și al unuia mediu din aceeași familie).
Future<void> bumpQuestMetric(BuildContext context, String metricKey, int amount) async {
  if (amount == 0) return;
  // Totalul pe viață se scrie MEREU, chiar dacă metricul nu e în rotația de
  // azi — realizările permanente sunt construite pe el (vezi
  // StorageService.addLifetimeMetric). Dacă ar sta sub filtrul de mai jos, o
  // realizare pe "răspunsuri fără hint" ar avansa doar în ziua în care pică
  // un quest de no_hint_correct, adică o dată pe săptămână.
  await StorageService.addLifetimeMetric(metricKey, amount);
  final active = todaysQuests().where((q) => q.metricKey == metricKey).toList();
  if (active.isEmpty) return;
  final updated = await StorageService.addQuestProgress(metricKey, amount);
  final previous = updated - amount;
  for (final quest in active) {
    final justCompleted = updated >= quest.target && previous < quest.target;
    if (!justCompleted) continue;
    if (await StorageService.isQuestClaimed(quest.id)) continue;
    if (!context.mounted) return;
    Sfx.tileSelect();
    InAppNotification.show(
      context,
      title: 'Quest completat! 🎯',
      message: quest.title,
      icon: quest.icon,
      color: const Color(0xFF534AB7),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestsScreen())),
    );
  }
}

/// Verifică toate realizările permanente și anunță, pe rând, orice tocmai
/// a fost deblocată — folosit de ecranele unde progresul unei realizări se
/// poate schimba în afara GameScreen (care are propria variantă locală),
/// ex. ShopScreen după o achiziție care poate debloca "Susținător".
Future<void> checkAchievements(BuildContext context) async {
  final newlyDone = await StorageService.checkNewlyCompletedAchievements();
  if (!context.mounted || newlyDone.isEmpty) return;
  for (var i = 0; i < newlyDone.length; i++) {
    if (!context.mounted) return;
    final a = newlyDone[i];
    Sfx.tileSelect();
    InAppNotification.show(
      context,
      title: 'Realizare deblocată! 🏆',
      message: a.title,
      icon: a.icon,
      color: const Color(0xFFFF7A1A),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen())),
    );
    if (i < newlyDone.length - 1) await Future.delayed(const Duration(milliseconds: 400));
  }
}
