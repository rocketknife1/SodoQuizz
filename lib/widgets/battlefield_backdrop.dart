import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Fundalul pictat al camerelor cu cadru fix din Quizz Tanks — camera de
/// bombardament (tank_salvo.dart) și camera de apărare (tank_defence.dart).
///
/// Singura imagine din scenele astea: cerul și câmpul. Tot ce se mișcă
/// (tancuri, obuze, explozii, fum) rămâne desenat din cod peste ea. Camera de
/// pe obuz (tank_pov.dart) NU o folosește: acolo solul defilează ca să dea
/// viteză, iar o poză fixă ar opri senzația de zbor.
///
/// Se încarcă o singură dată, la intrarea în meci ([preload]). Până se
/// încarcă — sau dacă încărcarea pică — [paint] întoarce `false` și
/// pictorii își desenează fundalul vechi, din cod.
class BattlefieldBackdrop {
  BattlefieldBackdrop._();

  static const String asset = 'assets/scene/camp_lupta.webp';

  /// Unde e orizontul în poză, ca fracție din înălțimea ei. La desenare poza
  /// se scalează și se mută astfel încât linia asta să cadă exact pe
  /// orizontul scenei — altfel tancurile ar sta în cer sau sub pământ.
  static const double imageHorizonFrac = 0.331;

  /// Culoarea de sus a pozei: umple golul de deasupra când orizontul scenei
  /// e mai jos decât al pozei.
  static const Color topColor = Color(0xFF080618);

  static ui.Image? _image;
  static Future<void>? _loading;

  static Future<void> preload() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      _image = (await codec.getNextFrame()).image;
    } catch (e) {
      debugPrint('BattlefieldBackdrop: fundalul nu s-a încărcat, rămâne cel din cod: $e');
    }
  }

  /// Desenează fundalul cu orizontul la [horizonY]. `false` dacă poza nu e
  /// încă încărcată.
  static bool paint(Canvas canvas, Size size, double horizonY) {
    final img = _image;
    if (img == null) return false;
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    // acoperă lățimea și tot ce e sub orizont; 4% în plus, ca zguduitura
    // cadrului la impact să nu dezvelească marginile
    final scale = max(size.width / iw, (size.height - horizonY) / ((1 - imageHorizonFrac) * ih)) * 1.04;
    final dw = iw * scale;
    final dh = ih * scale;
    final dx = (size.width - dw) / 2;
    final dy = horizonY - imageHorizonFrac * dh;
    if (dy > 0) {
      canvas.drawRect(Rect.fromLTWH(-20, -20, size.width + 40, dy + 21), Paint()..color = topColor);
    }
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH(dx, dy, dw, dh),
      Paint()..filterQuality = FilterQuality.medium,
    );
    return true;
  }
}
