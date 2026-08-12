import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/eco_mode.dart';
import '../core/gamemodes.dart';
import 'planet_entry_dialog.dart';

/// Planetă centrală, cu funcție reală (spre deosebire de vechiul element
/// pur decorativ): se rotește continuu, are o aură pulsantă care sugerează
/// că poți da tap, iar în jurul ei levitează holograme ale categoriilor din
/// modul Play (iconița + culoarea fiecărui [GameMode]). O parte din ele
/// orbitează pe o elipsă înclinată (adâncime 3D: mai mari/opace în față,
/// mai mici/estompate în spatele sferei), iar restul traversează diagonal
/// peste toată zona — inclusiv peste planetă — pe unghiuri aleatorii,
/// apărând și dispărând la capete, ca niște resturi care levitează în spațiu.
/// Tap → [PlanetEntryDialog], poarta către Planeta hologramelor: 17 întrebări
/// (poze + Cultură Generală), 10 inimi ale planetei, 2-3 rulări la 12 ore.
/// Înainte, tap-ul ducea în Quiz Nelimitat, mod care a fost înlocuit de
/// planetă.
class SpinningPlanet extends StatefulWidget {
  final double size;

  /// Chemat după ce jucătorul se întoarce dintr-o rulare, ca ecranul-gazdă
  /// să-și împrospăteze balanțele (la fel ca la celelalte mascote de pe Home).
  final VoidCallback? onRewardsChanged;

  const SpinningPlanet({super.key, this.size = 96, this.onRewardsChanged});

  @override
  State<SpinningPlanet> createState() => _SpinningPlanetState();
}

class _SpinningPlanetState extends State<SpinningPlanet> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _orbit;
  late final AnimationController _aura;

  // parametri aleatorii per-hologramă, generați o singură dată (stabili cât
  // trăiește widget-ul), ca traiectoriile de "levitație" să nu fie identice
  // una cu alta — fiecare categorie plutește pe propriul tipar.
  late final List<bool> _isDrift;
  late final List<double> _driftAngle;
  late final List<double> _driftPhase;
  late final List<double> _driftSpeed;
  late final List<double> _orbitPhase;

  @override
  void initState() {
    super.initState();
    // EcoAnimationController: planeta, orbitele si aura sunt trei bucle
    // infinite pornite chiar in meniul principal — se opresc singure in
    // Modul Eco, iar planeta ramane desenata, doar nemiscata.
    _spin = EcoAnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
    _orbit = EcoAnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _aura = EcoAnimationController(vsync: this, duration: const Duration(seconds: 2), restValue: 0.5)..repeat(reverse: true);

    final rnd = Random();
    final n = gameModes.length;
    _isDrift = List.generate(n, (i) => i % 3 == 0);
    _driftAngle = List.generate(n, (_) => rnd.nextDouble() * 2 * pi);
    _driftPhase = List.generate(n, (_) => rnd.nextDouble());
    _driftSpeed = List.generate(n, (_) => 0.55 + rnd.nextDouble() * 0.9);
    _orbitPhase = List.generate(n, (_) => rnd.nextDouble());
  }

  @override
  void dispose() {
    _spin.dispose();
    _orbit.dispose();
    _aura.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    Sfx.tileSelect();
    await PlanetEntryDialog.show(context, onRewardsChanged: widget.onRewardsChanged);
  }

  @override
  Widget build(BuildContext context) {
    final orbitRadiusX = widget.size * 1.15;
    final orbitRadiusY = orbitRadiusX * 0.5;
    final boxSize = orbitRadiusX * 2 + 60;
    final center = boxSize / 2;
    final modes = gameModes;

    return GestureDetector(
      onTap: _onTap,
      child: SizedBox(
        width: boxSize,
        height: boxSize,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _orbit, _aura]),
          builder: (context, _) {
            final angle = _spin.value * 2 * pi;
            final orbitT = _orbit.value;
            final auraT = _aura.value;

            final backHolograms = <Widget>[];
            final frontHolograms = <Widget>[];
            final driftHolograms = <Widget>[];
            for (var i = 0; i < modes.length; i++) {
              if (_isDrift[i]) {
                driftHolograms.add(_buildDriftHologram(i, modes[i], boxSize, center, orbitT));
              } else {
                final built = _buildOrbitHologram(i, modes[i], orbitRadiusX, orbitRadiusY, center, orbitT);
                (built.isBack ? backHolograms : frontHolograms).add(built.widget);
              }
            }

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // aură pulsantă — semnalează vizual că planeta e "activă",
                // apăsabilă (nu doar decor), la fel ca indicatorul de pe inel.
                // Alfa amestecată direct în culoare (nu Opacity() peste
                // Container) — animația asta rulează continuu cât ecranul e
                // deschis, deci orice strat offscreen suplimentar per-frame
                // se simte constant, nu doar tranzitoriu.
                Container(
                  width: widget.size * 1.15 + auraT * 26,
                  height: widget.size * 1.15 + auraT * 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFC542).withAlpha(((0.18 + auraT * 0.22) * 255).round()),
                  ),
                ),
                // holograme "din spate" (adâncime negativă pe elipsă) —
                // desenate SUB inel/sferă, ca să pară că trec pe după planetă.
                ...backHolograms,
                // inelul (tip Saturn), înclinat, se rotește mai încet și în
                // sens invers față de sferă — dă senzația de mișcare 3D.
                Transform.rotate(
                  angle: -angle * 0.4,
                  child: CustomPaint(
                    size: Size(widget.size * 1.7, widget.size * 1.7),
                    painter: _RingPainter(),
                  ),
                ),
                // sfera — benzile (sweep gradient) rotindu-se fac spinul
                // vizibil clar, nu doar un cerc static colorat.
                Transform.rotate(
                  angle: angle,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Color(0xFFFF7A1A),
                          Color(0xFFFFC542),
                          Color(0xFFE24B4A),
                          Color(0xFF534AB7),
                          Color(0xFF1D9E75),
                          Color(0xFFFF7A1A),
                        ],
                      ),
                      boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 10)],
                    ),
                  ),
                ),
                // highlight fix (nu se rotește), ca sfera să pară rotundă/3D
                // nu un cerc plat.
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Colors.white.withAlpha(80), Colors.white.withAlpha(0)],
                      center: const Alignment(-0.4, -0.4),
                      radius: 0.55,
                    ),
                  ),
                ),
                // holograme "din față" — peste sferă.
                ...frontHolograms,
                // holograme care traversează diagonal toată zona, inclusiv
                // peste planetă, pe unghiuri aleatorii — mereu deasupra.
                ...driftHolograms,
              ],
            );
          },
        ),
      ),
    );
  }

  /// Orbită eliptică înclinată (simulează un plan 3D): adâncimea (sin(angle))
  /// controlează scala, opacitatea și dacă hologramă e desenată în spatele
  /// sau în fața sferei.
  ({Widget widget, bool isBack}) _buildOrbitHologram(
    int i,
    GameMode mode,
    double radiusX,
    double radiusY,
    double center,
    double orbitT,
  ) {
    final dir = i.isEven ? 1 : -1;
    final angle = (orbitT * dir + _orbitPhase[i]) * 2 * pi;
    final depth = sin(angle); // -1 (spate) .. 1 (față)
    final pos = Offset(cos(angle) * radiusX, depth * radiusY);
    final scale = 0.55 + (depth + 1) / 2 * 0.55;
    final flicker = (sin(orbitT * 2 * pi * 1.6 + i * 1.9) + 1) / 2;
    final opacity = ((0.35 + flicker * 0.65) * (0.55 + (depth + 1) / 2 * 0.45)).clamp(0.0, 1.0);

    final widget = Positioned(
      left: center + pos.dx - 13 * scale,
      top: center + pos.dy - 13 * scale,
      child: Transform.scale(scale: scale, child: _HologramDot(mode: mode, opacity: opacity)),
    );
    return (widget: widget, isBack: depth < 0);
  }

  /// Trecere diagonală liniară prin toată zona (inclusiv peste planetă), pe
  /// un unghi aleatoriu fix per hologramă — apare la un capăt, traversează
  /// prin centru, dispare la celălalt capăt, apoi reia (buclă).
  Widget _buildDriftHologram(int i, GameMode mode, double boxSize, double center, double orbitT) {
    final t = (orbitT * _driftSpeed[i] + _driftPhase[i]) % 1.0;
    final dir = Offset(cos(_driftAngle[i]), sin(_driftAngle[i]));
    final perp = Offset(-dir.dy, dir.dx);
    final sweep = boxSize * 0.62;
    final travel = (t - 0.5) * 2 * sweep;
    final edgeFade = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
    final jitter = sin(t * pi * 5 + i) * 10 * edgeFade;
    final pos = dir * travel + perp * jitter;
    final opacity = sin(t * pi).clamp(0.0, 1.0);
    final scale = 0.45 + sin(t * pi) * 0.75;

    return Positioned(
      left: center + pos.dx - 13 * scale,
      top: center + pos.dy - 13 * scale,
      child: Transform.scale(scale: scale, child: _HologramDot(mode: mode, opacity: opacity)),
    );
  }
}

/// Punctul-hologramă al unei categorii — degrade radial (nu culoare plată),
/// ca să pară o mică sferă/proiecție, nu un disc 2D.
class _HologramDot extends StatelessWidget {
  final GameMode mode;
  /// Amestecată direct în alfa fiecărei culori din desen — nu un Opacity()
  /// extern — pentru că holograma e recreată la fiecare cadru al buclei
  /// continue de orbitare/derivă (vezi [_SpinningPlanetState]).
  final double opacity;
  const _HologramDot({required this.mode, this.opacity = 1});

  int _a(int base) => (base * opacity).round();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [mode.accentColor.withAlpha(_a(210)), mode.accentColor.withAlpha(_a(50))],
          center: const Alignment(-0.3, -0.3),
        ),
        border: Border.all(color: mode.accentColor.withAlpha(_a(200))),
        boxShadow: [BoxShadow(color: mode.accentColor.withAlpha(_a(140)), blurRadius: 10)],
      ),
      child: Icon(mode.icon, color: Colors.white.withAlpha(_a(255)), size: 14),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFC9C9E8).withAlpha(170);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, 0.38); // elipsă înclinată, ca un inel văzut din lateral
    canvas.drawCircle(Offset.zero, size.width / 2 - 2, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
