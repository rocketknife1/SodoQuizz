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

/// Ai folosit deja o putere în runda asta — regula e una pe rundă.
/// Mesaj separat de [notifyPowerUpTooLate]: până la recenzia din 2026-09-01
/// ambele situații spuneau „prea târziu", ceea ce n-avea nicio legătură cu
/// motivul real al refuzului.
void notifyPowerUpAlreadyUsed(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(tr(
        'Ai folosit deja o putere runda asta — mai ai voie una la runda următoare.',
        'You already used a power-up this round — you get another one next round.',
      )),
    ));
}

/// Puterea nu mai are ce face acum (ex. 50/50 după ce ai răspuns deja).
/// NU se consumă: jucătorul o păstrează pentru runda următoare.
void notifyPowerUpNoEffect(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(tr(
        'N-are ce face acum — ai răspuns deja. O păstrezi.',
        'Nothing to do right now — you already answered. You keep it.',
      )),
    ));
}

/// Puterea are nevoie de mai mulți jucători în viață (azi doar
/// [PowerUp.allyShield], care la 1v1 ar apăra chiar adversarul — vezi
/// `powerUpMinLivePlayers`). NU se consumă: rămâne în inventar.
void notifyPowerUpNeedsMorePlayers(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(tr(
        'N-ai pe cine apăra — la doi jucători ar apăra adversarul. O păstrezi.',
        'Nobody to protect — with two players it would shield your opponent. You keep it.',
      )),
    ));
}

/// Un adversar/coechipier a plecat din meci CÂT ÎNCĂ SE JOACĂ — dispărut din
/// `watchPlayers` (leaveMatch îi șterge documentul, vezi
/// MultiplayerService.leaveMatch) fără să fi terminat runda. Fără mesajul
/// ăsta, jucătorul rămas dispărea din listă/clasament în tăcere — la 1v1
/// mai ales, arăta ca un bug, nu ca „a ieșit celălalt". Bug raportat live
/// de pe telefon (2026-09-09).
void notifyPlayerLeft(BuildContext context, String name) {
  if (!context.mounted) return;
  InAppNotification.showInfo(
    context,
    title: tr('A ieșit din meci', 'Left the match'),
    message: tr('$name a părăsit meciul.', '$name left the match.'),
    icon: Icons.logout_rounded,
    color: AppColors.danger,
    duration: const Duration(seconds: 4),
  );
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
