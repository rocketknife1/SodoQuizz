import 'package:flutter/foundation.dart';

/// Comutator local: îngheață cronometrele de tip „întrebare cu timp" cât e
/// deschis dialogul de notă al owner-ului (OwnerNoteOverlay) — DOAR în
/// singleplayer. Meciurile multiplayer reale nu ating niciodată acest steag.
class GamePause {
  GamePause._();
  static final GamePause instance = GamePause._();

  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  bool get isPaused => paused.value;

  void pause() => paused.value = true;
  void resume() => paused.value = false;
}
