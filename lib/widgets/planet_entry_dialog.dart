import 'dart:async';
import 'package:flutter/material.dart';
import '../core/ads_service.dart';
import '../core/progression.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../screens/planet_hologram_screen.dart';

/// Poarta către [PlanetHologramScreen] — deschisă de tap pe planeta de pe
/// Home. Există ca ecran separat de rulare fiindcă planeta e un mod LIMITAT:
/// jucătorul trebuie să vadă câte rulări mai are și cât mai durează
/// cooldown-ul ÎNAINTE să intre, nu după.
class PlanetEntryDialog extends StatefulWidget {
  /// Chemat după ce jucătorul se întoarce din rulare, ca Home să-și
  /// împrospăteze balanțele.
  final VoidCallback? onRewardsChanged;

  const PlanetEntryDialog({super.key, this.onRewardsChanged});

  static Future<void> show(BuildContext context,
      {VoidCallback? onRewardsChanged}) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(190),
      builder: (_) => PlanetEntryDialog(onRewardsChanged: onRewardsChanged),
    );
  }

  @override
  State<PlanetEntryDialog> createState() => _PlanetEntryDialogState();
}

class _PlanetEntryDialogState extends State<PlanetEntryDialog> {
  int _runsLeft = 0;
  Duration _cooldown = Duration.zero;
  bool _canWatchAd = false;
  bool _loading = true;
  bool _busy = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _refresh();
    // numărătoarea inversă trebuie să scadă vizibil, nu doar la redeschidere.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_cooldown > Duration.zero) _refresh();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final cooldown = await StorageService.planetCooldownRemaining();
    final runsLeft = await StorageService.planetRunsLeft();
    final canWatchAd = await StorageService.canWatchAdForPlanetRun();
    if (!mounted) return;
    setState(() {
      _cooldown = cooldown;
      _runsLeft = runsLeft;
      _canWatchAd = canWatchAd;
      _loading = false;
    });
  }

  Future<void> _enter() async {
    if (_busy || _runsLeft <= 0) return;
    setState(() => _busy = true);
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlanetHologramScreen()),
    );
    widget.onRewardsChanged?.call();
  }

  /// Reclama ridică plafonul ciclului curent de la 2 la 3 rulări și șterge
  /// cooldown-ul tocmai pornit — vezi StorageService.unlockPlanetAdRun.
  Future<void> _watchAd() async {
    if (_busy) return;
    setState(() => _busy = true);
    final earned = await AdsService.instance.watchOrSimulate();
    if (!mounted) return;
    if (earned) await StorageService.unlockPlanetAdRun();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  static String _format(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.gem.withAlpha(120), width: 1.5),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B1140), Color(0xFF0B1229)],
          ),
          boxShadow: [
            BoxShadow(color: AppColors.gem.withAlpha(60), blurRadius: 30)
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.blur_on_rounded, color: AppColors.gem, size: 44),
              const SizedBox(height: 8),
              const Text(
                'Planeta hologramelor',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _buildRules(),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: AppColors.gem),
                )
              else ...[
                _buildStatus(),
                const SizedBox(height: 12),
                _buildActions(),
              ],
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Mai târziu',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRules() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _rule(Icons.help_outline_rounded,
              '$planetQuestionCount de holograme: poze și Cultură Generală, amestecate altfel de fiecare dată.'),
          _rule(Icons.favorite_rounded,
              '$planetHearts inimi ALE PLANETEI. Greșelile se scad din ele, niciodată din viețile tale.'),
          _rule(Icons.visibility_rounded,
              'Fără hint și fără blur — pozele se văd clar de la început.'),
          _rule(Icons.auto_awesome_rounded,
              'De la $planetGoodRunCorrect corecte ai șansă la recompensa mare; la $planetQuestionCount din $planetQuestionCount e garantată.'),
        ],
      ),
    );
  }

  Widget _rule(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.gem, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    if (_runsLeft > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.play.withAlpha(35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.play.withAlpha(140)),
        ),
        child: Text(
          _runsLeft == 1
              ? 'Mai ai o rulare în ciclul ăsta.'
              : 'Mai ai $_runsLeft rulări în ciclul ăsta.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.play, fontSize: 13, fontWeight: FontWeight.w800),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          const Text('Planeta se reîncarcă',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_format(_cooldown),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _buildActions() {
    if (_runsLeft > 0) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _enter,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gem,
            disabledBackgroundColor: Colors.white24,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Intră pe planetă',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.black)),
        ),
      );
    }
    if (!_canWatchAd) {
      return Text(
        'Ai folosit toate cele $planetRunsPerCycleWithAd rulări ale ciclului. Revino după numărătoare.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : _watchAd,
        icon: const Icon(Icons.smart_display_rounded, size: 18),
        label: const Text('Vezi o reclamă pentru o rulare în plus',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.coin,
          disabledBackgroundColor: Colors.white24,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
