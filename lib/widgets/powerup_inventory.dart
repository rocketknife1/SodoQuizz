import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/powerups.dart';
import '../core/theme.dart';

/// Iconițele puterilor. Stau AICI, nu în `core/powerups.dart`: acela e fișier
/// de logică pură, fără nicio dependență de interfață — la fel ca restul
/// `core/`-ului. Emoji-urile din [powerUpTitles] rămân pentru bannere și
/// mesaje; astea sunt pentru pătrățelele din inventar.
const Map<PowerUp, IconData> powerUpIcons = {
  PowerUp.megaRocket: Icons.rocket_launch_rounded,
  PowerUp.doubleShot: Icons.filter_2_rounded,
  PowerUp.piercingShock: Icons.bolt_rounded,
  PowerUp.sabotage: Icons.dangerous_rounded,
  PowerUp.shield: Icons.shield_rounded,
  PowerUp.allyShield: Icons.health_and_safety_rounded,
  PowerUp.reflect: Icons.flip_camera_android_rounded,
  PowerUp.fiftyFifty: Icons.content_cut_rounded,
  PowerUp.extraTime: Icons.more_time_rounded,
  PowerUp.peek: Icons.visibility_rounded,
  PowerUp.jetpack: Icons.rocket_rounded,
  PowerUp.repairKit: Icons.build_rounded,
};

/// Numele scurt al puterii, FĂRĂ emoji-ul din [powerUpTitles] — pătrățelul
/// are deja iconița lui, iar un emoji în plus lângă ea ar arăta încărcat.
String powerUpShortName(PowerUp p) {
  final t = powerUpTitles[p];
  if (t == null) return '';
  final full = tr(t.$1, t.$2);
  // titlurile sunt de forma "🚀 Mega Rachetă" — tăiem tot până la primul spațiu
  final i = full.indexOf(' ');
  return i > 0 ? full.substring(i + 1) : full;
}

/// Inventarul de puteri — pătrățele cu iconiță și nume, sub tancuri.
///
/// ÎNAINTE era o singură putere, ținută într-un chip minuscul în bara de sus:
/// dacă primeai una nouă cât o aveai pe cea veche nefolosită, cea veche se
/// PIERDEA în tăcere. Acum se adună, iar tu alegi pe care o folosești.
///
/// Regula care rămâne: **o singură putere pe rundă**. După ce ai folosit una,
/// restul se estompează până la runda următoare — nu dispar, ca să vezi în
/// continuare ce ai strâns.
class PowerUpInventory extends StatelessWidget {
  final List<PowerUp> powerUps;

  /// `true` dacă s-a folosit deja una în runda asta.
  final bool usedThisRound;
  final void Function(PowerUp) onUse;

  const PowerUpInventory({
    super.key,
    required this.powerUps,
    required this.usedThisRound,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    if (powerUps.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: powerUps.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _PowerUpTile(
          powerUp: powerUps[i],
          dimmed: usedThisRound,
          onTap: () => onUse(powerUps[i]),
        ),
      ),
    );
  }
}

class _PowerUpTile extends StatefulWidget {
  final PowerUp powerUp;
  final bool dimmed;
  final VoidCallback onTap;
  const _PowerUpTile({required this.powerUp, required this.dimmed, required this.onTap});

  @override
  State<_PowerUpTile> createState() => _PowerUpTileState();
}

class _PowerUpTileState extends State<_PowerUpTile> with SingleTickerProviderStateMixin {
  // NU `late`: `dispose()` ar declanșa altfel inițializatorul pe un State
  // deja demontat dacă build-ul n-a rulat niciodată.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _PowerUpTile old) {
    super.didUpdateWidget(old);
    if (old.dimmed != widget.dimmed) _syncPulse();
  }

  /// Pulsația se OPREȘTE cât puterea e estompată. Fără asta, fiecare pătrățel
  /// din inventar ținea `SchedulerBinding` să ceară cadre la nesfârșit — și
  /// cu 4-8 puteri strânse ecranul de Tanks nu mai intra niciodată în repaus,
  /// exact ce tocmai eliminaserăm din tick-uri (recenzie 2026-09-01). Când e
  /// estompată, scala e oricum 1.0, deci nu se pierde nimic vizual.
  void _syncPulse() {
    if (widget.dimmed) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = powerUpIcons[widget.powerUp] ?? Icons.star_rounded;
    final name = powerUpShortName(widget.powerUp);
    return GestureDetector(
      onTap: widget.dimmed ? null : widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          // Pulsează doar cât e folosibilă — o putere estompată nu are de ce
          // să ceară atenție.
          final t = widget.dimmed ? 0.0 : Curves.easeInOut.transform(_pulse.value);
          return Transform.scale(scale: 1 + t * 0.04, child: child);
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.dimmed ? 0.35 : 1,
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.purple.withAlpha(70),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.purple, width: 2),
              boxShadow: widget.dimmed
                  ? null
                  : [BoxShadow(color: AppColors.purple.withAlpha(90), blurRadius: 10)],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, height: 1.1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
