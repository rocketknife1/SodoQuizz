import 'dart:math';

import 'package:flutter/material.dart';

import '../core/obby.dart';

/// Ce a pățit un alergător în runda tocmai încheiată — calculat în ecran
/// (MultiplayerObbyScreen._outcomeFor), ca tabla să nu aibă nevoie de regulile
/// din core/obby.dart. [none] = n-a avut dreptul să sară (a greșit întrebarea).
enum ObbyRoundOutcome { none, jumped, fell }

/// După ce fracție din deznodământ cedează pătratul fals. Public: ecranul
/// pornește sunetul de cădere exact atunci (vezi _playRevealSfx).
const double obbyFallDelayFraction = 0.15;

/// Un alergător de pe tablă — extras din `MatchPlayer` de ecran, ca widget-ul
/// să nu importe modelul Firestore.
class ObbyRacerData {
  final String id;
  final String name;
  final Color color;
  final double progress; // 0..1, cât din cursă a trecut DUPĂ runda asta
  final bool isMe;
  final ObbyRoundOutcome outcome;

  const ObbyRacerData({
    required this.id,
    required this.name,
    required this.color,
    required this.progress,
    required this.isMe,
    this.outcome = ObbyRoundOutcome.none,
  });

  int get row => (progress * obbyObstacleCount).round().clamp(0, obbyObstacleCount);
}

/// [choosing] = EU aleg pătratul (vedere personală); [waiting]/[revealed] =
/// tabla comună cu toți alergătorii.
enum ObbyPhase { idle, choosing, waiting, revealed }

/// Obby în 2D, văzut de sus, ca o tablă de șah — decizia de design
/// (2026-09-15), în locul scenei 3D Flame, lentă. Fiecare jucător are coloana
/// lui; un rând = un obstacol, sus e finalul. La alegere vezi cele trei
/// pătrate din fața ta — diagonală stânga ↖, înainte ▲, diagonală dreapta ↗ —
/// unul e fals. Animația deznodământului rulează pe propriul ceas, nu pe
/// rebuild-urile ecranului.
class ObbyBoard extends StatefulWidget {
  final ObbyPhase phase;
  final List<ObbyRacerData> racers;
  final int? myChoice;

  /// De unde pornește animația (0..1) — pentru cine intră în mijlocul ei.
  final double revealT;
  final Duration revealDuration;
  final ValueChanged<int> onPlatformChosen;

  const ObbyBoard({
    super.key,
    required this.phase,
    required this.racers,
    required this.onPlatformChosen,
    required this.revealDuration,
    this.myChoice,
    this.revealT = 0,
  });

  @override
  State<ObbyBoard> createState() => _ObbyBoardState();
}

class _ObbyBoardState extends State<ObbyBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(vsync: this);

  /// Rândul pe care stătea fiecare alergător înainte de deznodământ — de
  /// acolo pornește săritura (poate fi și +2, la rundă dublă).
  final Map<String, int> _lastRow = {};

  @override
  void initState() {
    super.initState();
    if (widget.phase == ObbyPhase.revealed) _startReveal();
  }

  @override
  void didUpdateWidget(ObbyBoard old) {
    super.didUpdateWidget(old);
    if (widget.phase == ObbyPhase.revealed && old.phase != ObbyPhase.revealed) _startReveal();
    if (widget.phase != ObbyPhase.revealed) _reveal.value = 0;
  }

  void _startReveal() {
    _reveal.value = widget.revealT;
    final left = widget.revealDuration * (1 - widget.revealT);
    if (left > Duration.zero) _reveal.animateTo(1, duration: left);
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.phase != ObbyPhase.revealed) {
      for (final r in widget.racers) {
        _lastRow[r.id] = r.row;
      }
    }
    if (widget.phase == ObbyPhase.choosing) return _buildChoice();
    return AnimatedBuilder(
      animation: _reveal,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _BoardPainter(
          racers: widget.racers,
          lastRow: _lastRow,
          t: widget.phase == ObbyPhase.revealed ? _reveal.value : 0,
        ),
      ),
    );
  }

  /// Vederea personală de alegere: pătratul meu jos, cele trei în față.
  Widget _buildChoice() {
    final me = widget.racers.where((r) => r.isMe).firstOrNull;
    final color = me?.color ?? Colors.blue;
    const arrows = ['↖', '▲', '↗'];
    Widget square(Widget child, {Color? fill, Color? border, VoidCallback? onTap}) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill ?? Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border ?? Colors.white24, width: 2),
            ),
            child: child,
          ),
        );
    return Align(
      alignment: const Alignment(0, 0.15),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < obbyPlatformChoiceCount; i++)
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: square(
                    Text(arrows[i], style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    fill: widget.myChoice == i ? const Color(0xFF22C55E).withAlpha(90) : const Color(0xFF14B8A6).withAlpha(40),
                    border: widget.myChoice == i ? const Color(0xFF22C55E) : const Color(0xFF14B8A6),
                    onTap: widget.myChoice == null ? () => widget.onPlatformChosen(i) : null,
                  ),
                ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.all(5), child: square(const SizedBox())),
              Padding(padding: const EdgeInsets.all(5), child: square(_Piece(color: color, isMe: true, size: 46))),
              Padding(padding: const EdgeInsets.all(5), child: square(const SizedBox())),
            ],
          ),
          if (me != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${me.row} / $obbyObstacleCount',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

class _Piece extends StatelessWidget {
  final Color color;
  final bool isMe;
  final double size;
  const _Piece({required this.color, required this.isMe, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: isMe ? Colors.white : Colors.black54, width: isMe ? 3 : 2),
        ),
      );
}

class _BoardPainter extends CustomPainter {
  final List<ObbyRacerData> racers;
  final Map<String, int> lastRow;
  final double t;
  _BoardPainter({required this.racers, required this.lastRow, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final cols = max(racers.length, 3);
    const rows = obbyObstacleCount + 1; // rândul 0 = start, ultimul = final
    // Loc sus pentru legenda de fază, jos pentru rezumatul rundei. Pătratele
    // au un plafon: pe ecran mare tabla stă compactă, nu umple tot.
    final area = Rect.fromLTRB(12, 56, size.width - 12, size.height - 64);
    final cell = min(min(area.width / cols, area.height / rows), 56.0);
    if (cell < 6) return; // spațiu prea mic (tastatură/ecran mic) — nimic de desenat
    final origin = Offset(area.center.dx - cell * cols / 2, area.center.dy - cell * rows / 2);
    Rect cellRect(int c, double r) =>
        Rect.fromLTWH(origin.dx + c * cell, origin.dy + (rows - 1 - r) * cell, cell, cell);

    final light = Paint()..color = const Color(0xFF2A2F55);
    final dark = Paint()..color = const Color(0xFF1A1E3C);
    final finish = Paint()..color = const Color(0xFFFFC53D).withAlpha(70);
    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        final rect = cellRect(c, r.toDouble()).deflate(1);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), (c + r).isEven ? light : dark);
        if (r == rows - 1) canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), finish);
      }
    }

    for (var i = 0; i < racers.length; i++) {
      final rc = racers[i];
      final to = rc.row;
      var y = to.toDouble();
      var scale = 1.0;
      var alpha = 1.0;
      switch (rc.outcome) {
        case ObbyRoundOutcome.jumped:
          final from = lastRow[rc.id] ?? max(0, to - 1);
          final jt = Curves.easeOut.transform((t / 0.35).clamp(0.0, 1.0));
          y = from + (to - from) * jt;
          scale = 1 + 0.35 * sin(pi * jt);
        case ObbyRoundOutcome.fell:
          final from = (lastRow[rc.id] ?? to).toDouble();
          // sare spre pătratul din față, pătratul cedează, reapare la loc
          final crack = cellRect(i, from + 1).deflate(cell * 0.18);
          if (t > obbyFallDelayFraction && from + 1 < rows) {
            canvas.drawRRect(RRect.fromRectAndRadius(crack, const Radius.circular(4)),
                Paint()..color = const Color(0xFFEF4444).withAlpha((160 * (1 - (t - 0.7).clamp(0.0, 0.3) / 0.3)).round()));
          }
          if (t < obbyFallDelayFraction) {
            y = from + 0.8 * (t / obbyFallDelayFraction);
          } else if (t < 0.7) {
            y = from + 0.8;
            final ft = (t - obbyFallDelayFraction) / (0.7 - obbyFallDelayFraction);
            scale = 1 - ft;
            alpha = 1 - ft;
          } else {
            y = from;
            alpha = (t - 0.7) / 0.3;
          }
        case ObbyRoundOutcome.none:
          break;
      }
      final center = cellRect(i, y).center;
      final radius = cell * 0.34 * scale;
      if (radius <= 0.5) continue;
      canvas.drawCircle(center, radius, Paint()..color = rc.color.withAlpha((255 * alpha).round()));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rc.isMe ? 3 : 1.5
          ..color = (rc.isMe ? Colors.white : Colors.black54).withAlpha((255 * alpha).round()),
      );
      final label = TextPainter(
        text: TextSpan(
          text: rc.name.isEmpty ? '?' : rc.name.characters.first.toUpperCase(),
          style: TextStyle(color: Colors.white.withAlpha((255 * alpha).round()), fontSize: radius * 0.9, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
