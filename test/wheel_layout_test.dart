import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Roata norocului: incap etichetele in felie?
///
/// Plangere reala, de doua ori la rand: "premiile nu se vad, nu incape
/// scrisul complet". Prima incercare a marit doar `size:` din painter, ceea ce
/// n-a facut NIMIC (un `CustomPaint` fara copil isi ia marimea din
/// constrangeri, iar `SizedBox`-ul ramasese 240). Testul asta masoara chiar
/// textul, cu acelasi `TextPainter` pe care il foloseste desenul, si prinde
/// direct simptomul — nu geometria din jurul lui.
void main() {
  // Aceleasi valori ca in widgets/wheel_spin_dialog.dart. Daca se schimba
  // acolo, testul trebuie sa pice, nu sa se adapteze in tacere.
  const dialogInset = 10.0;
  const dialogPadding = 12.0;
  const maxWheel = 420.0;
  const labelRadiusFactor = 0.74;
  const labelFontFactor = 0.062;
  const iconRadiusFactor = 0.40;
  const iconSizeFactor = 0.14;
  const prizeCount = 11;

  /// Eticheta cea mai lata din roata (vezi `_wheelPrizes`).
  const longest = '1284+💎';

  double wheelSizeFor(Size screen) => [
        maxWheel,
        screen.width - dialogInset * 2 - dialogPadding * 2,
        screen.height * 0.46,
      ].reduce(min);

  double textWidth(String s, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  /// Ecrane reale: telefonul userului, un telefon mic, o tableta.
  const screens = <String, Size>{
    'S22 Ultra (portret)': Size(412, 915),
    'telefon mic': Size(360, 640),
    'tableta': Size(800, 1280),
  };

  screens.forEach((nume, screen) {
    group(nume, () {
      final wheel = wheelSizeFor(screen);
      final radius = wheel / 2;

      test('roata incape in fereastra', () {
        expect(wheel, lessThanOrEqualTo(screen.width - dialogInset * 2 - dialogPadding * 2),
            reason: 'roata depaseste latimea ferestrei');
        expect(wheel, greaterThan(0));
      });

      test('eticheta cea mai lunga NU iese din disc', () {
        final font = radius * labelFontFactor;
        final half = textWidth(longest, font) / 2;
        final margine = radius * labelRadiusFactor + half;
        // 0,94 din raza: dincolo de asta intra peste inelul alb de pe margine.
        expect(margine, lessThan(radius * 0.94),
            reason: '"$longest" ajunge la ${margine.toStringAsFixed(1)} din ${radius.toStringAsFixed(1)}');
      });

      test('eticheta NU se atinge de iconita', () {
        final font = radius * labelFontFactor;
        final half = textWidth(longest, font) / 2;
        final textIncepe = radius * labelRadiusFactor - half;
        final iconSeTermina = radius * iconRadiusFactor + radius * iconSizeFactor / 2;
        expect(textIncepe, greaterThan(iconSeTermina),
            reason: 'textul incepe la ${textIncepe.toStringAsFixed(1)}, '
                'iconita se termina la ${iconSeTermina.toStringAsFixed(1)}');
      });

      test('eticheta incape si pe LATIME in felie', () {
        // La raza unde sta textul, felia e o banda de latimea asta. Textul e
        // scris pe raza, deci ce trebuie sa incapa lateral e INALTIMEA lui.
        final segment = 2 * pi / prizeCount;
        final razaInterioara = radius * labelRadiusFactor - textWidth(longest, radius * labelFontFactor) / 2;
        final latimeFelie = 2 * razaInterioara * sin(segment / 2);
        final inaltimeText = radius * labelFontFactor * 1.2;
        expect(inaltimeText, lessThan(latimeFelie),
            reason: 'textul e mai inalt (${inaltimeText.toStringAsFixed(1)}) '
                'decat latimea feliei (${latimeFelie.toStringAsFixed(1)})');
      });
    });
  });

  test('roata chiar e vizibil mai mare decat cei 240 de dinainte', () {
    expect(wheelSizeFor(const Size(412, 915)), greaterThan(300),
        reason: 'daca pica asta, cresterea n-a intrat in efect a treia oara');
  });
}
