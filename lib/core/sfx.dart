import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Efecte sonore scurte de UI — un player dedicat per sunet, cu sursa
/// pre-încărcată o singură dată. Repornim cu seek(0)+resume() în loc de
/// stop()+play() de fiecare dată: play() re-decodează AssetSource la
/// fiecare apel, ceea ce pe unele telefoane pierde tap-uri rapide
/// (sunetul nu apucă să se încarce înainte de următorul tap) — seek+resume
/// pe o sursă deja încărcată e instant și de încredere.
///
/// IMPORTANT: modul trebuie să fie [PlayerMode.mediaPlayer], nu
/// [PlayerMode.lowLatency] — pe Android, lowLatency e susținut de
/// SoundPool, care nu are un concept real de seek; apelul seek(0) de mai
/// jos aștepta la nesfârșit evenimentul de finalizare (timeout după 30s),
/// deci sunetul nu se auzea niciodată pe telefon, deși mergea pe web.
class Sfx {
  static final AudioPlayer _next = AudioPlayer(playerId: 'sfx_next');
  static final AudioPlayer _reward = AudioPlayer(playerId: 'sfx_reward');
  static final AudioPlayer _coin = AudioPlayer(playerId: 'sfx_coin');
  static final AudioPlayer _tile = AudioPlayer(playerId: 'sfx_tile');
  static final AudioPlayer _xp = AudioPlayer(playerId: 'sfx_xp');
  static final AudioPlayer _heart = AudioPlayer(playerId: 'sfx_heart');

  static Future<void>? _preloadFuture;

  /// Încarcă toate sursele o singură dată — apelat la pornirea aplicației
  /// (vezi main.dart), ca primul tap din sesiune să sune la fel de sigur
  /// ca oricare altul.
  static Future<void> preload() {
    return _preloadFuture ??= _init();
  }

  /// Pe unele telefoane Android (mai ales cu skin-uri OEM stricte, ex.
  /// Samsung), fără un AudioContext explicit sesiunea audio nu se
  /// inițializează corect pe stream-ul media și playerii rămân muți deși
  /// nu aruncă nicio eroare Dart — de-asta îl setăm explicit, global,
  /// înainte de orice altceva.
  static Future<void> _init() async {
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
    } catch (e) {
      debugPrint('Sfx: setAudioContext a eșuat: $e');
    }
    await Future.wait([
      _prepare(_next, 'next_tap.wav'),
      _prepare(_reward, 'reward_pop.wav'),
      _prepare(_coin, 'coin_hit.wav'),
      _prepare(_tile, 'tile_select.wav'),
      _prepare(_xp, 'xp_hit.wav'),
      _prepare(_heart, 'heart_hit.wav'),
    ]);
  }

  static Future<void> _prepare(AudioPlayer player, String asset) async {
    try {
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(1.0);
      await player.setSourceAsset('sfx/$asset');
    } catch (e) {
      debugPrint('Sfx: nu am putut pregăti $asset: $e');
    }
  }

  static Future<void> _play(AudioPlayer player) async {
    try {
      await preload();
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      debugPrint('Sfx: nu am putut reda sunetul: $e');
    }
  }

  static void next() => _play(_next);
  static void rewardPop() => _play(_reward);
  static void coinHit() => _play(_coin);
  static void tileSelect() => _play(_tile);
  static void xpHit() => _play(_xp);
  static void heartHit() => _play(_heart);
}
