import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../data/storage_service.dart';

/// Muzică de fundal — o singură piesă în buclă, complet separată de [Sfx]
/// (player propriu, volum propriu persistat). Pornește automat la lansarea
/// aplicației (vezi main.dart) și respectă preferința "Music Off" +
/// volumul salvat din ecranul de Setări.
class Music {
  static final AudioPlayer _player = AudioPlayer(playerId: 'bg_music');
  static Future<void>? _preloadFuture;
  static bool _enabled = true;
  static double _volume = 0.5;
  static bool _started = false;

  static Future<void> preload() {
    return _preloadFuture ??= _init();
  }

  static Future<void> _init() async {
    _enabled = await StorageService.getMusicEnabled();
    _volume = await StorageService.getMusicVolume();
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setVolume(_volume);
      await _player.setSourceAsset('music/theme_loop.wav');
    } catch (e) {
      debugPrint('Music: nu am putut pregăti piesa de fundal: $e');
    }
  }

  /// Pornește muzica dacă e activată — apelat o dată, la lansarea aplicației.
  static Future<void> start() async {
    await preload();
    _started = true;
    if (!_enabled) return;
    try {
      await _player.resume();
    } catch (e) {
      debugPrint('Music: nu am putut porni piesa de fundal: $e');
    }
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    await StorageService.setMusicEnabled(value);
    try {
      if (value && _started) {
        await _player.resume();
      } else {
        await _player.pause();
      }
    } catch (e) {
      debugPrint('Music: nu am putut comuta starea: $e');
    }
  }

  static Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    await StorageService.setMusicVolume(_volume);
    try {
      await _player.setVolume(_volume);
    } catch (e) {
      debugPrint('Music: nu am putut seta volumul: $e');
    }
  }

  static bool get isEnabled => _enabled;
  static double get volume => _volume;
}
