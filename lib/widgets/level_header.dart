import 'dart:math';
import 'package:flutter/material.dart';
import '../core/repeating_animation.dart';
import '../core/progression.dart';
import '../core/theme.dart';
import 'avatar.dart';
import 'cosmetic_title.dart';
import 'notification_bell.dart';

/// Header cu avatar + nivel + bară de progres XP (stânga) și pastilă de
/// monede (dreapta) — folosit în capul fiecărui ecran principal.
///
/// Când [pendingLevelRewards] > 0, BARA ÎNSĂȘI (nu vreo iconiță alăturată)
/// devine punctul de tap — plină, strălucitoare, cu o linie de energie care
/// îi traversează lungimea — un tap colectează, dintr-o singură mișcare,
/// toate recompensele de nivel încă nerevendicate (vezi
/// StorageService.claimAllPendingLevelRewards). Fără [onClaimLevelRewards],
/// bara rămâne doar informativă, ca înainte.
class LevelHeader extends StatefulWidget {
  final int xp;
  final int coins;
  final int? lives;
  final int? hints;
  final int? gems;
  final int pendingLevelRewards;
  /// Premiul rar de la Roata norocului (vezi WheelSpinDialog) — cât timp e
  /// activ, pastila de vieți arată infinit + numărătoare inversă în loc de
  /// cifră (vezi [_livesPill]).
  final bool livesUnlimited;
  final String? livesUnlimitedLabel;
  final VoidCallback? onCoinsTap;
  final VoidCallback? onClaimLevelRewards;

  /// Numele afișat lângă avatar, deasupra "Level N" — opțional, pornit doar
  /// din HomeScreen (ecranul principal). Pe restul ecranelor care refolosesc
  /// acest header (joc etc.), `null` păstrează exact layout-ul de dinainte.
  final String? displayName;

  /// Titlul cosmetic echipat (vezi core/cosmetics.dart) - un rand mic sub
  /// "Level N". `null` sau `'novice'` nu arata nimic.
  final String? titleId;
  /// Dacă e dat, numele devine un shortcut direct spre dialogul de schimbare
  /// a numelui (vezi widgets/edit_name_dialog.dart) — `null` când numele nu
  /// se poate edita de aici (cont Google legat / impus de administrator).
  final VoidCallback? onNameTap;

  /// Arată clopoțelul de notificări deasupra avatarului. Pornit doar în
  /// meniul principal (vezi HomeScreen): acolo e „acasă" pentru jucător și
  /// acolo îl caută, iar pe ecranele de joc ar fi doar o distragere.
  final bool showNotifications;

  /// Chemat după închiderea panoului de notificări — un cadou revendicat
  /// între timp schimbă balanța de sub header.
  final VoidCallback? onNotificationsClosed;
  final Key? coinBadgeKey;
  final Key? xpBadgeKey;
  final Key? livesBadgeKey;
  final Key? hintsBadgeKey;
  final Key? gemsBadgeKey;

  const LevelHeader({
    super.key,
    required this.xp,
    required this.coins,
    this.lives,
    this.hints,
    this.gems,
    this.pendingLevelRewards = 0,
    this.livesUnlimited = false,
    this.livesUnlimitedLabel,
    this.onCoinsTap,
    this.onClaimLevelRewards,
    this.showNotifications = false,
    this.onNotificationsClosed,
    this.coinBadgeKey,
    this.xpBadgeKey,
    this.livesBadgeKey,
    this.hintsBadgeKey,
    this.gemsBadgeKey,
    this.displayName,
    this.onNameTap,
    this.titleId,
  });

  @override
  State<LevelHeader> createState() => _LevelHeaderState();
}

class _LevelHeaderState extends State<LevelHeader> with TickerProviderStateMixin {
  late final RepeatingAnimationController _pulse;
  late final RepeatingAnimationController _wave;

  @override
  void initState() {
    super.initState();
    _pulse = RepeatingAnimationController(vsync: this, duration: const Duration(milliseconds: 1100), restValue: 0.5)
      ..repeat(reverse: true);
    _wave = RepeatingAnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = levelForXp(widget.xp);
    final claimable = widget.pendingLevelRewards > 0 && widget.onClaimLevelRewards != null;
    // Cât timp mai e ceva necolectat, bara arată plină (nivelul e deja
    // "terminat", doar aștepți să-l revendici) — progresul real spre
    // nivelul următor se vede din nou abia după ce colectezi tot.
    final progress = claimable ? 1.0 : levelProgress(widget.xp);
    final barHeight = claimable ? 10.0 : 6.0;

    // Bara nu sare direct la noua valoare — alunecă progresiv spre ea
    // (TweenAnimationBuilder animează implicit de la valoarea curentă la
    // noul `end` ori de câte ori [progress] se schimbă). Reîncărcarea
    // balanței pornește chiar la impactul primei stelute XP (vezi
    // CoinRewardOverlay.onImpact), deci alunecarea începe exact atunci —
    // dacă nu mai vine nicio recompensă, bara pur și simplu se oprește la
    // valoarea deja atinsă.
    Widget barCore = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: progress, end: progress),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, animatedProgress, _) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: animatedProgress,
          minHeight: barHeight,
          backgroundColor: Colors.white12,
          valueColor: AlwaysStoppedAnimation(claimable ? AppColors.coin : AppColors.purple),
        ),
      ),
    );

    Widget bar = SizedBox(height: barHeight, child: barCore);

    if (claimable) {
      // toată bara strălucește/pulsează, traversată de o linie de energie —
      // bara ÎNSĂȘI e indiciul, fără iconițe alăturate.
      bar = AnimatedBuilder(
        animation: Listenable.merge([_pulse, _wave]),
        builder: (context, child) {
          final glow = 0.4 + _pulse.value * 0.6;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(color: AppColors.coin.withAlpha((190 * glow).round()), blurRadius: 8 + 10 * glow, spreadRadius: 1 + 2 * glow),
              ],
            ),
            child: SizedBox(
              height: barHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    barCore,
                    Positioned.fill(child: CustomPaint(painter: _EnergyWavePainter(phase: _wave.value, pulse: _pulse.value))),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    Widget xpColumn = Padding(
      // hitbox mult mai mare decât conținutul vizual — ușor de apăsat.
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        key: widget.xpBadgeKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.displayName != null) ...[
            GestureDetector(
              onTap: widget.onNameTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.displayName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (widget.onNameTap != null) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.edit_rounded, color: Colors.white54, size: 13),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            'Level $level',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: widget.displayName != null
                ? const TextStyle(color: Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w700)
                : const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (widget.titleId != null) CosmeticTitle(titleId: widget.titleId!, fontSize: 10),
          const SizedBox(height: 5),
          bar,
          if (!claimable) ...[
            const SizedBox(height: 3),
            Text(
              '${xpIntoCurrentLevel(widget.xp)} / ${xpForLevel(level)} XP',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: const TextStyle(color: Colors.white38, fontSize: 9.5, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );

    if (claimable) {
      xpColumn = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClaimLevelRewards,
        child: xpColumn,
      );
    }

    // Rândul de pastile (vieți/hints/gems/coins) e SUB rândul de nivel, nu
    // pe același rând — vieți/hints nu mai au plafon, deci pot ajunge la 2-3
    // cifre; pe un singur rând, asta storcea lățimea barei de XP până la
    // trunchiere ("L..."). Pe rânduri separate, bara are mereu toată
    // lățimea ecranului, indiferent cât de mari devin cifrele pastilelor.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const MyAvatar(size: 44),
            const SizedBox(width: 10),
            Expanded(child: xpColumn),
          ],
        ),
        const SizedBox(height: 8),
        // scroll orizontal, nu Row simplu — cu vieți/hints fără plafon,
        // valorile pot ajunge la 4-5 cifre, iar 4 pastile pe un rând nu mai
        // încap pe ecran (overflow); scroll-ul le păstrează pe toate
        // vizibile/citibile în loc să le trunchieze.
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (widget.lives != null) ...[
                      _livesPill(),
                      const SizedBox(width: 10),
                    ],
                    if (widget.hints != null) ...[
                      _pill(key: widget.hintsBadgeKey, icon: Icons.lightbulb_rounded, color: AppColors.hint, value: widget.hints!),
                      const SizedBox(width: 10),
                    ],
                    if (widget.gems != null) ...[
                      _pill(key: widget.gemsBadgeKey, icon: Icons.diamond_rounded, color: const Color(0xFF5EC8F2), value: widget.gems!),
                      const SizedBox(width: 10),
                    ],
                    _pill(
                      key: widget.coinBadgeKey,
                      icon: Icons.monetization_on_rounded,
                      color: AppColors.coin,
                      value: widget.coins,
                      onTap: widget.onCoinsTap,
                      trailingIcon: widget.onCoinsTap != null ? Icons.add_circle_rounded : null,
                    ),
                  ],
                ),
              ),
            ),
            // Clopoțelul de notificări stă AICI, la dreapta pastilelor, lângă
            // balanța de monede — cerut explicit, fiindcă deasupra avatarului
            // se pierdea peste poză. E în afara zonei care derulează: cu
            // vieți/hints fără plafon, pastilele pot depăși lățimea ecranului,
            // iar un clopoțel prins de capătul lor ar fi ieșit din cadru exact
            // când ai mai multe resurse.
            if (widget.showNotifications) ...[
              const SizedBox(width: 8),
              NotificationBell(onClosed: widget.onNotificationsClosed),
            ],
          ],
        ),
      ],
    );
  }

  Widget _livesPill() {
    if (!widget.livesUnlimited) {
      return _pill(key: widget.livesBadgeKey, icon: Icons.favorite_rounded, color: AppColors.life, value: widget.lives!);
    }
    return Container(
      key: widget.livesBadgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.all_inclusive_rounded, color: AppColors.life, size: 16),
          if (widget.livesUnlimitedLabel != null) ...[
            const SizedBox(width: 6),
            Text(widget.livesUnlimitedLabel!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  Widget _pill({
    Key? key,
    required IconData icon,
    required Color color,
    required int value,
    VoidCallback? onTap,
    IconData? trailingIcon,
  }) {
    final pill = Container(
      key: onTap == null ? key : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text('$value', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, color: AppColors.play, size: 16),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(key: key, onTap: onTap, child: pill);
  }
}

/// Linie de "energie" (traiectorie sinusoidală, fază animată continuu) care
/// traversează bara plină cât timp e claimable — un glow alb dedesubt, un
/// fir auriu deasupra (ca un curent electric care circulă prin bară), și
/// peste tot asta, 2 "vene" albastre, cu fază/lungime de undă diferite (ca
/// să se încrucișeze cu firul auriu, nu să-l dubleze), a căror opacitate
/// pulsează în ritm cu [pulse] (aceeași "respirație" ca glow-ul din jurul
/// barei) — un contrast electric-albastru peste galben, nu doar o linie în
/// plus.
class _EnergyWavePainter extends CustomPainter {
  final double phase;
  final double pulse;
  const _EnergyWavePainter({required this.phase, required this.pulse});

  Path _wavePath(Size size, double waveLength, double amp, double phaseOffset) {
    final midY = size.height / 2;
    final path = Path();
    for (double x = 0; x <= size.width; x += 3) {
      final y = midY + sin((x / waveLength) * 2 * pi + (phase + phaseOffset) * 2 * pi) * amp;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final amp = size.height * 0.34;
    final waveLength = size.height * 9;

    final path = _wavePath(size, waveLength, amp, 0);

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.coin.withAlpha(235)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // vene albastre pulsatile — respiră între 0.35 și 1.0 alpha, în ritm cu
    // [pulse] (0..1), cu o mică defazare între ele ca pulsul să pară
    // "curgător", nu sincron perfect.
    final veinGlow1 = 0.35 + ((sin(pulse * pi)).abs()) * 0.65;
    final veinGlow2 = 0.35 + ((sin(pulse * pi + 0.9)).abs()) * 0.65;
    const veinBlue = Color(0xFF2F8CFF);

    final vein1 = _wavePath(size, waveLength * 1.15, amp * 1.05, 0.33);
    canvas.drawPath(
      vein1,
      Paint()
        ..color = veinBlue.withAlpha((90 * veinGlow1).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawPath(
      vein1,
      Paint()
        ..color = veinBlue.withAlpha((235 * veinGlow1).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    final vein2 = _wavePath(size, waveLength * 0.6, amp * 0.8, 0.68);
    canvas.drawPath(
      vein2,
      Paint()
        ..color = veinBlue.withAlpha((80 * veinGlow2).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
    );
    canvas.drawPath(
      vein2,
      Paint()
        ..color = veinBlue.withAlpha((200 * veinGlow2).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );
  }

  @override
  bool shouldRepaint(covariant _EnergyWavePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.pulse != pulse;
}
