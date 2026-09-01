import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../core/audio.dart';
import '../core/quest_bump.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';

/// Unghiul (radiani) cu care trebuie rotită roata ca segmentul
/// [resultIndex] (din [segmentCount] segmente egale) să ajungă sub ac.
///
/// Acul e sus (convenția -pi/2), iar segmentul i e DESENAT cu centrul la
/// unghiul local -pi/2 + (i+0.5)*segmentAngle (vezi CustomPainter-ul roții)
/// — deci rotația necesară e doar -(i+0.5)*segmentAngle, FĂRĂ -pi/2
/// suplimentar. Bug fixat aici: formula veche scădea -pi/2 încă o dată,
/// ceea ce ateriza segmentul cerut la stânga acului, nu sub el. Extrasă ca
/// funcție separată (nu inline în _doSpin) exact ca să rămână testabilă.
double wheelTargetAngle(int resultIndex, int segmentCount) {
  final segmentAngle = 2 * pi / segmentCount;
  return -(resultIndex + 0.5) * segmentAngle;
}

/// Un premiu de la Roata norocului — model flexibil (nu un singur
/// tip+cantitate) ca să poată reprezenta și pachete combinate (ex. XP+viață).
/// Toate câmpurile de recompensă sunt opționale (0 = nu se acordă); orice
/// combinație nenulă e posibilă. [weight] controlează șansa relativă de a
/// pica pe acest premiu — segmentele de pe roată rămân vizual egale ca
/// mărime (toate mereu vizibile), raritatea vine din probabilitate, nu din
/// mărimea feliei.
class _WheelPrize {
  final IconData icon;
  final Color color;
  /// Textul scurt desenat pe roată, sub icon (ex. "25", "1", "24h").
  final String wheelLabel;
  final int weight;
  final int coins;
  final int xp;
  final int hints;
  final int gems;
  final int lives;
  /// Premiul-jackpot: vieți nelimitate pentru această durată (altfel null).
  final Duration? unlimitedLives;

  const _WheelPrize({
    required this.icon,
    required this.color,
    required this.wheelLabel,
    required this.weight,
    this.coins = 0,
    this.xp = 0,
    this.hints = 0,
    this.gems = 0,
    this.lives = 0,
    this.unlimitedLives,
  });
}

const _gemColor = Color(0xFF5EC8F2);
const _jackpotColor = Color(0xFFFFD700);

// ─── Tema portocalie a roții ────────────────────────────────────────────────
// Cadranele roții nu mai iau culoarea fiecărui premiu (curcubeu) — sunt
// portocalii, alternând două nuanțe, ca roata să citească vizual "un obiect",
// nu o colecție de resurse; iconițele rămân colorate pe tipul de resursă,
// pentru lizibilitate, dar pe fundal portocaliu.
const _wheelOrange = Color(0xFFFF7A1A);
const _wheelOrangeLight = Color(0xFFFFA94D);
const _wheelOrangeDeep = Color(0xFFC24A00);

/// 11 premii — orice resursă (monede, XP, hints, viață, gems) sau pachet
/// combinat (mai rar) poate ieși la o rotire, plus premiul special ultra-rar:
/// vieți nelimitate 24h. Greutățile sunt relative, nu procente — vezi
/// [_WheelSpinDialogState._pickWeightedIndex].
///
/// Valorile sunt de ~10× mai mari decât în economia veche (unde roata,
/// deși are cel mai lung cooldown din joc — 24h —, era paradoxal cea mai
/// mică sursă de reward: 25-70 monede). Acum e cel mai mare reward dintr-o
/// singură acțiune: media unei rotiri e ~247 monede + ~15 gems + vieți/hints
/// (≈490 echivalent-monede), iar chiar și cel mai slab segment (268 monede)
/// bate orice altceva se poate face cu un singur tap.
const List<_WheelPrize> _prizes = [
  _WheelPrize(icon: Icons.monetization_on_rounded, color: AppColors.coin, wheelLabel: '268', weight: 18, coins: 268),
  _WheelPrize(icon: Icons.star_rounded, color: AppColors.purple, wheelLabel: '431', weight: 14, xp: 431),
  _WheelPrize(icon: Icons.monetization_on_rounded, color: AppColors.coin, wheelLabel: '517', weight: 13, coins: 517),
  _WheelPrize(icon: Icons.tips_and_updates_rounded, color: AppColors.hint, wheelLabel: '7', weight: 11, hints: 7),
  _WheelPrize(icon: Icons.favorite_rounded, color: AppColors.life, wheelLabel: '4', weight: 11, lives: 4),
  _WheelPrize(icon: Icons.diamond_rounded, color: _gemColor, wheelLabel: '39', weight: 10, gems: 39),
  // pachete combinate — mai rare (weight mic) decât o resursă singură.
  _WheelPrize(icon: Icons.card_giftcard_rounded, color: Color(0xFFB388FF), wheelLabel: '692+❤', weight: 9, coins: 692, lives: 3),
  _WheelPrize(icon: Icons.diamond_rounded, color: _gemColor, wheelLabel: '84', weight: 7, gems: 84),
  _WheelPrize(icon: Icons.redeem_rounded, color: Color(0xFFB388FF), wheelLabel: 'MIX', weight: 6, coins: 344, hints: 9, lives: 4),
  _WheelPrize(icon: Icons.workspace_premium_rounded, color: _gemColor, wheelLabel: '1284+💎', weight: 4, coins: 1284, gems: 53),
  // jackpot — ultra-rar (weight 2 din 105 total ≈ 1,9%).
  _WheelPrize(icon: Icons.all_inclusive_rounded, color: _jackpotColor, wheelLabel: '24h', weight: 2, coins: 500, gems: 173, unlimitedLives: Duration(hours: 24)),
];

/// Roata norocului a inelului — un premiu o dată la 24h reale (vezi
/// [StorageService.canSpinRing]). Se deschide ca dialog peste Home;
/// recompensa se aplică imediat la finalul rotației, iar butonul de
/// închidere reîmprospătează header-ul.
class WheelSpinDialog extends StatefulWidget {
  const WheelSpinDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(context: context, barrierDismissible: false, builder: (_) => const WheelSpinDialog());
  }

  @override
  State<WheelSpinDialog> createState() => _WheelSpinDialogState();
}

/// Durata unei rotiri. Folosită și de calculul blur-ului de mișcare, care are
/// nevoie de ea ca să afle câți radiani se parcurg într-un cadru.
const int _spinMs = 4600;

class _WheelSpinDialogState extends State<WheelSpinDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  double _finalAngle = 0;
  bool _spinning = false;
  bool _done = false;
  _WheelPrize? _result;
  int? _lastHapticSegment;

  @override
  void initState() {
    super.initState();
    // durată mai lungă + curbă cu suspans (vezi _SuspenseWheelCurve) — roata
    // se învârte "plin" mult timp, fără să dea niciun indiciu, apoi
    // încetinește vizibil doar spre final.
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: _spinMs));
    _spin.addListener(_onSpinTick);
  }

  @override
  void dispose() {
    _spin.removeListener(_onSpinTick);
    _spin.dispose();
    super.dispose();
  }

  /// Vibrație scurtă la fiecare cadran trecut pe sub ac — întărește senzația
  /// de suspans (ca un clichet fizic de roată), fără riscul unui sunet
  /// suprapus la redeclanșare rapidă (vezi Sfx._play).
  void _onSpinTick() {
    if (!_spinning) return;
    final angle = const _SuspenseWheelCurve().transform(_spin.value) * _finalAngle;
    final segmentAngle = 2 * pi / _prizes.length;
    final segment = (-angle / segmentAngle).floor();
    if (segment != _lastHapticSegment) {
      _lastHapticSegment = segment;
      HapticFeedback.selectionClick();
    }
  }

  /// Tragere ponderată (nu uniformă) — indexul ales alimentează aceeași
  /// logică de unghi-țintă de mai jos, deci nu schimbă nimic din animația
  /// roții, doar CE index e ales.
  int _pickWeightedIndex() {
    final total = _prizes.fold<int>(0, (sum, p) => sum + p.weight);
    var roll = Random().nextDouble() * total;
    for (var i = 0; i < _prizes.length; i++) {
      roll -= _prizes[i].weight;
      if (roll <= 0) return i;
    }
    return _prizes.length - 1;
  }

  Future<void> _doSpin() async {
    if (_spinning || _done) return;
    final resultIndex = _pickWeightedIndex();
    final targetAngle = wheelTargetAngle(resultIndex, _prizes.length);
    // mai multe ture decât înainte (7-9, nu 5-7) — combinat cu durata mai
    // mare, roata se învârte vizibil mai mult timp "plin", fără niciun
    // indiciu, înainte să înceapă să încetinească spre final.
    final extraSpins = 7 + Random().nextInt(3);
    setState(() {
      _spinning = true;
      _finalAngle = extraSpins * 2 * pi + targetAngle;
      _lastHapticSegment = null;
    });
    Sfx.tileSelect();
    await _spin.forward(from: 0);

    final prize = _prizes[resultIndex];
    if (prize.coins > 0) await StorageService.addCoins(prize.coins);
    if (prize.xp > 0) await StorageService.addXp(prize.xp);
    if (prize.hints > 0) await StorageService.addHints(prize.hints);
    if (prize.gems > 0) await StorageService.addGems(prize.gems);
    if (prize.lives > 0) await StorageService.addLivesUncapped(prize.lives);
    if (prize.unlimitedLives != null) {
      await StorageService.activateUnlimitedLives(prize.unlimitedLives!);
    }
    await StorageService.recordRingSpin();
    if (mounted) await bumpQuestMetric(context, 'wheel_spin', 1);
    Sfx.rewardPop();
    if (!mounted) return;
    setState(() {
      _spinning = false;
      _done = true;
      _result = prize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _wheelOrange.withAlpha(140)),
          boxShadow: [BoxShadow(color: _wheelOrange.withAlpha(50), blurRadius: 28, spreadRadius: -6)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Roata norocului', 'Lucky wheel'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(tr('Un premiu o dată la 24 de ore', 'One prize every 24 hours'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 20),
            SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Glow pulsatoriu în spatele roții — mai intens cât timp se
                  // învârte, ca senzație de "energie/suspans" în plus față de
                  // rotația în sine.
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) {
                      final pulse = _spinning ? 0.55 + 0.25 * sin(_spin.value * pi * 10) : 0.35;
                      return Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: _wheelOrange.withAlpha((120 * pulse).round()), blurRadius: 40, spreadRadius: 4)],
                        ),
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) {
                      const curve = _SuspenseWheelCurve();
                      final t = _spin.value;
                      final angle = curve.transform(t) * _finalAngle;

                      // BLUR DE MIȘCARE. La viteză mare, o roată desenată în
                      // poziții discrete la 60-120 Hz produce efectul de
                      // „roată de căruță": paletele par că sar înapoi sau că
                      // stau pe loc, și totul arată ieftin. Un obiect real ar
                      // fi estompat pe direcția mișcării.
                      //
                      // Aproximăm cu câteva copii decalate cu unghiul parcurs
                      // într-un cadru, cu opacitate descrescătoare. Apar DOAR
                      // cât viteza chiar e mare — la final, când roata
                      // ezită, dispar singure și marginile redevin clare.
                      const dt = 0.004;
                      final speed = ((curve.transform((t + dt).clamp(0.0, 1.0)) -
                                  curve.transform((t - dt).clamp(0.0, 1.0))) /
                              (2 * dt)) *
                          _finalAngle;
                      // radiani parcurși într-un cadru (durata totală a
                      // animației e `_spinDuration`)
                      final perFrame = speed * (1 / 60) / (_spinMs / 1000);
                      final ghosts = perFrame.abs() < 0.012 ? 0 : 4;

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          for (var g = ghosts; g >= 1; g--)
                            Opacity(
                              opacity: 0.16,
                              child: Transform.rotate(
                                angle: angle - perFrame * (g / ghosts),
                                child: const CustomPaint(
                                  size: Size(290, 290),
                                  painter: _WheelPainter(wedgesOnly: true),
                                ),
                              ),
                            ),
                          Transform.rotate(
                            angle: angle,
                            child: const CustomPaint(
                              size: Size(290, 290),
                              painter: _WheelPainter(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  IgnorePointer(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        shape: BoxShape.circle,
                        border: Border.all(color: _wheelOrangeLight, width: 3),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -8,
                    child: Icon(Icons.arrow_drop_down_rounded, color: _wheelOrangeLight, size: 44, shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (_done && _result != null) ...[
              Text(
                _result!.unlimitedLives != null ? 'JACKPOT! 🎉' : tr('Ai câștigat!', 'You won!'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _buildResultRows(_result!),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.play, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
                child: const Text('Super!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ] else
              ElevatedButton(
                onPressed: _spinning ? null : _doSpin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _wheelOrange,
                  disabledBackgroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: _spinning ? 0 : 6,
                  shadowColor: _wheelOrange,
                ),
                child: Text(
                  _spinning ? tr('Se învârte...', 'Spinning...') : tr('ÎNVÂRTE', 'SPIN'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Listează TOATE resursele câștigate — nu doar una — ca pachetele
  /// combinate (ex. XP+viață) să arate ambele rânduri, nu doar primul.
  Widget _buildResultRows(_WheelPrize prize) {
    final rows = <Widget>[];
    if (prize.unlimitedLives != null) {
      rows.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.all_inclusive_rounded, color: _jackpotColor, size: 30),
          const SizedBox(width: 10),
          Text(tr('Vieți nelimitate\n24 de ore!', 'Unlimited lives\nfor 24 hours!'), textAlign: TextAlign.center, style: const TextStyle(color: _jackpotColor, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ));
    }
    void addRow(IconData icon, Color color, String text) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ));
    }

    if (prize.coins > 0) addRow(Icons.monetization_on_rounded, AppColors.coin, '+${prize.coins}');
    if (prize.xp > 0) addRow(Icons.star_rounded, AppColors.purple, '+${prize.xp}');
    if (prize.hints > 0) addRow(Icons.tips_and_updates_rounded, AppColors.hint, '+${prize.hints}');
    if (prize.gems > 0) addRow(Icons.diamond_rounded, _gemColor, '+${prize.gems}');
    if (prize.lives > 0) addRow(Icons.favorite_rounded, AppColors.life, '+${prize.lives}');
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _WheelPainter extends CustomPainter {
  /// Fantomele de blur desenează DOAR cadranele colorate, fără iconițe și
  /// fără etichete: la viteza la care apar, textul e oricum ilizibil, iar
  /// desenarea lui de câteva ori pe cadru ar fi singurul lucru scump de aici.
  final bool wedgesOnly;
  const _WheelPainter({this.wedgesOnly = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final segmentAngle = 2 * pi / _prizes.length;

    for (var i = 0; i < _prizes.length; i++) {
      final prize = _prizes[i];
      final startAngle = -pi / 2 + i * segmentAngle;
      // cadranul roții e portocaliu (alternând două nuanțe) — jackpot-ul
      // (24h) iese în evidență cu o nuanță mai închisă/distinctă, restul
      // cadranelor doar alternează, culoarea premiului rămâne doar pe icon.
      final wedgeColor = prize.unlimitedLives != null ? _wheelOrangeDeep : (i.isEven ? _wheelOrange : _wheelOrangeLight);
      final fill = Paint()..color = wedgeColor;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, segmentAngle, true, fill);

      final line = Paint()
        ..color = Colors.white.withAlpha(70)
        ..strokeWidth = 2;
      canvas.drawLine(center, center + Offset(cos(startAngle), sin(startAngle)) * radius, line);

      if (wedgesOnly) continue;

      final midAngle = startAngle + segmentAngle / 2;
      final iconPos = center + Offset(cos(midAngle), sin(midAngle)) * radius * 0.60;
      _paintText(canvas, String.fromCharCode(prize.icon.codePoint), prize.icon.fontFamily, prize.icon.fontPackage, iconPos, 22, Colors.white);

      // Eticheta se scrie PE RAZĂ, rotită să urmeze felia — ca la roțile
      // adevărate. Orizontal, un premiu lung („1284+💎") depășea lățimea
      // feliei la marginea cercului și se lovea de vecini; pe rază are toată
      // lungimea razei la dispoziție, deci încape orice sumă.
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(midAngle);
      // După rotație, axa X pozitivă merge spre marginea feliei. Pe jumătatea
      // STÂNGĂ a roții direcția aia arată spre stânga ecranului, deci textul
      // ar apărea cu capul în jos — îl întoarcem, exact ca la roțile
      // adevărate, unde eticheta e mereu citibilă indiferent unde se oprește.
      if (cos(midAngle) < 0) {
        canvas.rotate(pi);
        _paintText(canvas, prize.wheelLabel, null, null, Offset(-radius * 0.87, 0), 13, Colors.white, bold: true);
      } else {
        _paintText(canvas, prize.wheelLabel, null, null, Offset(radius * 0.87, 0), 13, Colors.white, bold: true);
      }
      canvas.restore();
    }

    canvas.drawCircle(center, radius, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = _wheelOrangeLight);
  }

  void _paintText(Canvas canvas, String text, String? fontFamily, String? fontPackage, Offset pos, double size, Color color, {bool bold = false}) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        fontFamily: fontFamily,
        package: fontPackage,
        color: color,
        fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
      ),
    );
    tp.layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Curbă în două faze, pentru senzația de suspans a unei roți fizice: viteză
/// mare și CONSTANTĂ pe primii [_split] din timp (nu se poate ghici nimic
/// încă — trece prin majoritatea cadranelor), urmată de o decelerare
/// accentuată ([Curves.easeOutQuint]) pe restul timpului, unde roata
/// încetinește vizibil și "ezită" tot mai aproape de rezultat.
///
/// PRIMA FAZĂ E LINIARĂ, nu `easeIn`. Varianta veche folosea `Curves.easeIn`,
/// care pornește de la viteză ZERO și accelerează — adică exact opusul a ce
/// spunea propriul ei comentariu. Pe o animație de 4,6 secunde, roata abia se
/// târa în prima secundă și se simțea moale; o roată reală e pocnită cu
/// degetul, deci pleacă din prima cu viteză maximă.
///
/// [_splitValue] NU e ales din ochi: e valoarea la care viteza fazei liniare
/// (`_splitValue / _split`) e EXACT egală cu viteza cu care începe curba de
/// decelerare. Fără potrivirea asta, roata ar avea o smucitură la trecerea
/// între faze — ori ar accelera brusc, ori ar frâna sec.
///
/// Formula, cu `p` = panta inițială a curbei de coadă:
///
///     _splitValue = p * _split / ((1 - _split) + p * _split)
///
/// ATENȚIE: `p` se MĂSOARĂ, nu se deduce. Curbele `Curves.easeOutX` din
/// Flutter sunt aproximări Bézier, nu funcțiile matematice după care sunt
/// numite — `easeOutQuint` are panta inițială ~14,6, nu 5. Prima încercare de
/// reparație a folosit valoarea teoretică și testul de smucitură a picat.
///
/// De ce [Curves.easeOut] și nu ceva mai agresiv: măsurat pe durata reală de
/// 4,6 secunde, ultimele 5% din rotație durează ~1s cu `easeOut`, dar 2,5s cu
/// `easeOutQuint` — adică roata se târăște vizibil la final în loc să
/// „ezite". O secundă de ezitare e tensiune; două și jumătate e plictiseală.
/// Expusa pentru `test/wheel_curve_test.dart`, care apara forma curbei
/// (pleaca cu viteza maxima, e monotona, nu smuceste la trecerea intre faze).
@visibleForTesting
const Curve suspenseWheelCurveForTest = _SuspenseWheelCurve();

class _SuspenseWheelCurve extends Curve {
  const _SuspenseWheelCurve();

  static const double _split = 0.35;
  static const double _splitValue = 0.6611736558; // masurat pentru Curves.easeOut

  @override
  double transform(double t) {
    if (t <= _split) {
      // liniar: viteză constantă, roata pleacă din prima cu viteză maximă
      return _splitValue * (t / _split).clamp(0.0, 1.0);
    }
    final local = ((t - _split) / (1 - _split)).clamp(0.0, 1.0);
    final tail = Curves.easeOut.transform(local);
    return _splitValue + (1 - _splitValue) * tail;
  }
}
