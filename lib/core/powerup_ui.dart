import 'package:flutter/material.dart';

import '../models/multiplayer_models.dart';
import '../widgets/in_app_notification.dart';
import 'lang.dart';
import 'powerups.dart';
import 'theme.dart';

/// Bucățile de interfață pentru power-up-uri, comune tuturor modurilor
/// multiplayer. Erau copiate identic în Scaunul Electric, Obby și Tanks —
/// o schimbare la una însemna trei locuri de ținut minte, iar al treilea se
/// uita.
///
/// Se transmit ca parametri exact lucrurile care difereau între copii: id-ul
/// jucătorului curent și harta de nume. Restul era identic caracter cu
/// caracter.

/// „Spionajul": arată răspunsurile celorlalți jucători din runda curentă.
void showPeekResults(
  BuildContext context,
  MatchInfo info, {
  required String myId,
  required Map<String, String> playerNames,
}) {
  if (!context.mounted) return;
  final others = info.roundAnswers.entries.where((e) => e.key != myId).toList();
  final line = others.isEmpty
      ? tr('Nimeni n-a răspuns încă.', 'Nobody has answered yet.')
      : others.map((e) => '${playerNames[e.key] ?? '?'}: ${e.value}').join('  ·  ');
  InAppNotification.showInfo(
    context,
    title: tr('👁️ Spionaj', '👁️ Peek'),
    message: line,
    icon: Icons.visibility_rounded,
    color: AppColors.purple,
    duration: const Duration(seconds: 4),
  );
}

/// Power-up folosit prea târziu în rundă (nu mai e utilizabil în faza curentă).
void notifyPowerUpTooLate(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(tr(
        'Prea târziu pentru puterea asta — folosește-o la începutul rundei.',
        'Too late for that power-up — use it at the start of the round.',
      )),
    ));
}

/// Anunță jucătorul că tocmai a primit un power-up.
void announcePowerUp(BuildContext context, PowerUp p) {
  if (!context.mounted) return;
  final t = powerUpTitles[p];
  if (t == null) return;
  InAppNotification.showInfo(
    context,
    title: tr('Ai primit o putere!', 'Power-up received!'),
    message: '${tr(t.$1, t.$2)} — ${tr('apasă pastila din bară ca s-o folosești', 'tap the chip up top to use it')}',
    icon: Icons.bolt_rounded,
    color: AppColors.purple,
  );
}
