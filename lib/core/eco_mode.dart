import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/storage_service.dart';

/// Modul Eco — o singură setare care chiar scade consumul și încălzirea
/// telefonului în timpul jocului, nu doar un comutator decorativ.
///
/// CE FACE, CONCRET, ȘI DE CE AJUTĂ CU ADEVĂRAT:
///
///  1. OPREȘTE BUCLELE DE ANIMAȚIE. Ăsta e câștigul mare, nu luminozitatea.
///     Un `AnimationController..repeat()` cere un cadru nou la fiecare 16 ms,
///     LA NESFÂRȘIT — cât timp există măcar unul viu pe ecran, Flutter nu
///     intră niciodată în repaus, deci GPU-ul și CPU-ul rămân treze chiar și
///     pe un meniu în care nu se întâmplă nimic. Meniul principal are ~8
///     astfel de bucle simultan (mascote, planetă, baloane, pulsuri, unda de
///     energie din bara de XP). Cu ele oprite, aplicația chiar ajunge la 0
///     cadre pe secundă când stă, iar telefonul se răcește — vezi
///     [EcoAnimationController], care e tot ce trebuie schimbat într-un
///     widget ca să respecte modul.
///
///  2. SCADE LUMINOZITATEA ECRANULUI LA NIVEL DE SISTEM, prin fereastra
///     Android (`WindowManager.LayoutParams.screenBrightness`, vezi
///     MainActivity.kt) — adică backlight-ul real, nu un strat negru
///     transparent pus peste imagine. Diferența contează: un strat negru
///     consumă în plus (mai are ceva de compus la fiecare cadru) și nu scade
///     deloc consumul panoului. Setarea e legată de fereastra jocului, deci
///     nu atinge luminozitatea din restul telefonului și dispare de la sine
///     când jocul se închide.
///     Pe platformele fără canalul nativ (web, desktop — vezi
///     [dimOverlayOpacity]) rămâne varianta software, ca setarea să facă
///     totuși ceva vizibil acolo unde se testează.
///
///  3. TAIE TRANZIȚIILE DE ECRAN (vezi [pageTransitionsTheme]) și duratele
///     animațiilor implicite (vezi [duration]) — mai puține cadre compuse la
///     fiecare navigare.
///
/// CE NU OPREȘTE, DELIBERAT: animațiile care sunt singurul semn că aplicația
/// chiar lucrează — spinnerul de încărcare, scanarea din matchmaking. Oprite,
/// ar face jocul să pară blocat, iar câștigul ar fi mic (durează secunde, nu
/// stau pe ecran la nesfârșit).
class EcoMode {
  EcoMode._();

  /// Canalul către MainActivity.kt. Un singur mesaj: `setBrightness`, cu un
  /// double între 0 și 1, sau -1 pentru „înapoi la setarea telefonului".
  static const _channel = MethodChannel('sodoquizz/eco');

  /// Cât de tare se stinge ecranul cât timp modul e pornit. 0.35 e ales ca
  /// să rămână perfect citibil în interior (acolo unde se joacă), dar destul
  /// de jos cât să conteze pe consum — panoul e cel mai mare consumator al
  /// unui telefon în timpul jocului.
  static const _ecoBrightness = 0.35;

  /// Umbra software folosită DOAR unde nu există canalul nativ (web/desktop).
  /// Vezi nota 2 din capul clasei pentru de ce nu e folosită pe Android.
  static double get dimOverlayOpacity => on && !_nativeBrightnessWorks ? 0.28 : 0.0;

  static bool _nativeBrightnessWorks = false;

  /// Sursa de adevăr, ascultată de tot ce trebuie să reacționeze pe loc la
  /// comutarea setării (animațiile pornite deja, MaterialApp, umbra software).
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool get on => enabled.value;

  /// Citește setarea salvată și o aplică — chemat o dată, la pornire, înainte
  /// de `runApp`, ca primul cadru desenat să fie deja cel corect: cerința era
  /// explicit ca la fiecare intrare/reintrare în joc modul să fie deja activ,
  /// nu să se aprindă vizibil după o secundă.
  static Future<void> load() async {
    enabled.value = await StorageService.getEcoMode();
    await _applyBrightness();
  }

  static Future<void> setEnabled(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    await StorageService.setEcoMode(value);
    await _applyBrightness();
  }

  /// Reaplică luminozitatea la revenirea din fundal. Android resetează
  /// atributele ferestrei când Activity-ul e recreat (rotire, revenire după
  /// ce sistemul a eliberat memorie), deci fără apelul ăsta modul rămânea
  /// „pornit" în setări, dar ecranul revenea la luminozitatea de sistem.
  static Future<void> reapply() => _applyBrightness();

  static Future<void> _applyBrightness() async {
    try {
      await _channel.invokeMethod<void>('setBrightness', on ? _ecoBrightness : -1.0);
      _nativeBrightnessWorks = true;
    } on MissingPluginException {
      // web/desktop — nu există partea nativă, se cade pe umbra software.
      _nativeBrightnessWorks = false;
    } catch (e) {
      debugPrint('EcoMode._applyBrightness a esuat: $e');
      _nativeBrightnessWorks = false;
    }
  }

  /// Durata unei animații implicite (AnimatedContainer, AnimatedOpacity,
  /// TweenAnimationBuilder...) — zero cât timp modul e pornit, adică saltul
  /// direct la starea finală, fără cadre intermediare.
  static Duration duration(Duration normal) => on ? Duration.zero : normal;

  /// Fără animație de tranziție între ecrane cât timp modul e pornit.
  static PageTransitionsTheme? pageTransitionsTheme() {
    if (!on) return null;
    return const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoTransitionBuilder(),
        TargetPlatform.iOS: _NoTransitionBuilder(),
        TargetPlatform.windows: _NoTransitionBuilder(),
        TargetPlatform.linux: _NoTransitionBuilder(),
        TargetPlatform.macOS: _NoTransitionBuilder(),
        TargetPlatform.fuchsia: _NoTransitionBuilder(),
      },
    );
  }
}

class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// `AnimationController` care își oprește singur bucla cât timp Modul Eco e
/// pornit. Singura schimbare necesară într-un widget cu animație decorativă e
/// numele constructorului — restul codului (`_pulse.value`, AnimatedBuilder,
/// dispose) rămâne neatins, tocmai ca modul să nu poată fi „uitat" pe la
/// jumătate prin widget-uri.
///
/// Cât timp e oprit, controller-ul nu îngheață oriunde s-ar nimeri, ci sare
/// la [restValue] — o poziție aleasă de widget ca să arate normal static.
/// Contează: un puls oprit la 0 face iconița să pară stinsă, nu liniștită.
///
/// La stingerea modului, bucla repornește singură, fără ca ecranul să fie
/// reconstruit — de-aia ascultă direct [EcoMode.enabled].
class EcoAnimationController extends AnimationController {
  EcoAnimationController({
    required super.vsync,
    required super.duration,
    this.restValue = 0.0,
  });

  /// Unde stă animația cât timp e oprită (0..1, în unități de `value`).
  final double restValue;

  bool _looping = false;
  bool _reverse = false;
  bool _listening = false;

  @override
  TickerFuture repeat({double? min, double? max, bool reverse = false, Duration? period, int? count}) {
    _looping = true;
    _reverse = reverse;
    if (!_listening) {
      _listening = true;
      EcoMode.enabled.addListener(_applyEco);
    }
    if (EcoMode.on) {
      value = restValue;
      return TickerFuture.complete();
    }
    return super.repeat(min: min, max: max, reverse: reverse, period: period, count: count);
  }

  void _applyEco() {
    if (!_looping) return;
    if (EcoMode.on) {
      stop();
      value = restValue;
    } else if (!isAnimating) {
      super.repeat(reverse: _reverse);
    }
  }

  @override
  void dispose() {
    if (_listening) EcoMode.enabled.removeListener(_applyEco);
    super.dispose();
  }
}
