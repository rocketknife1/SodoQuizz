import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/game_helpers.dart';

/// Afișează imaginea întrebării cu blur real, care scade pe măsură ce
/// jucătorul folosește hints (vezi [resolveBlurSigma]). Folosit de toate
/// gamemodurile — aceeași mecanică de reveal peste tot.
class BlurImage extends StatelessWidget {
  final Color color;
  final String answer;
  final bool revealed;
  final int hintsUsed;
  final String? imageAssetPath;
  final bool noBlur;

  const BlurImage({
    super.key,
    required this.color,
    required this.answer,
    required this.revealed,
    required this.hintsUsed,
    this.imageAssetPath,
    this.noBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final target = noBlur ? 0.0 : resolveBlurSigma(hintsUsed, revealed: revealed);
    // Limpezirea (hint sau răspuns) curge în ~300 ms, nu sare. Cheia pe poză e
    // obligatorie: fără ea, la întrebarea următoare animația ar porni de la
    // poza clară spre blur și ar arăta o clipă noua poză clară — adică
    // răspunsul. Cu cheie nouă, TweenAnimationBuilder pornește direct de la
    // valoarea finală, fără animație.
    return TweenAnimationBuilder<double>(
      key: ValueKey(imageAssetPath ?? answer),
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, sigma, _) => _build(sigma),
    );
  }

  Widget _build(double sigma) {
    // Imaginea NU trebuie să fie vreodată neagră — blur-ul singur o ascunde.
    // Overlay-ul e doar un dim ușor (max ~55), proporțional cu blur-ul, ca
    // pozele foarte deschise să nu pară "spălate"; scade spre 0 cu hint-uri.
    final darkenAlpha = revealed ? 0 : (55 * (sigma / 34.0)).round().clamp(0, 55);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
              color: Colors.black,
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageAssetPath != null)
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
                    child: Image.asset(
                      imageAssetPath!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallback(),
                    ),
                  )
                else
                  _fallback(),

                if (darkenAlpha > 0) Container(color: Colors.black.withAlpha(darkenAlpha)),

                if (revealed)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, o, child) => Opacity(opacity: o, child: child),
                    child: Container(
                    color: Colors.black.withAlpha(160),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Text(
                      answer,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Arătat când imaginea lipsește (categorii noi, unde nu toate întrebările
  /// au încă o poză reală atașată) — un placeholder clar, nu doar o iconiță
  /// generică fără context.
  Widget _fallback() {
    return Container(
      color: color.withAlpha(80),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_rounded, color: color, size: 56),
          const SizedBox(height: 8),
          Text(
            'Va urma',
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
