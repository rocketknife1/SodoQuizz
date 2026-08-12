import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../data/storage_service.dart';
import 'music_tracks.dart';

/// Contextul audio global (Android/iOS), comun pentru [Music] și [Sfx] —
/// setat o singură dată, idempotent, indiferent care din cele două pornește
/// primul. IMPORTANT: usage=media + content=music + focus=gain pun sunetul
/// jocului pe stream-ul Media standard (ca YouTube/Spotify) — cu vechea
/// configurație (assistanceSonification/sonification/none) sunetul ateriza
/// pe alt stream Android, de-aia butoanele fizice de volum nu îl atingeau
/// și trebuia reglat manual din altă categorie de volum din telefon.
Future<void>? _globalAudioContextFuture;
Future<void> _ensureGlobalAudioContext() {
  return _globalAudioContextFuture ??= () async {
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
    } catch (e) {
      debugPrint('Audio: setAudioContext a eșuat: $e');
    }
  }();
}

/// Muzică de fundal — o singură piesă în buclă, complet separată de [Sfx]
/// (player propriu, volum propriu persistat). Pornește automat la lansarea
/// aplicației (vezi main.dart) și respectă preferința "Music Off" +
/// volumul salvat din ecranul de Setări. Fiind un singur player pornit din
/// main, aceeași piesă merge continuu pe toate ecranele.
///
/// Piesa e `.mp3` (era `.wav` până pe 8 august 2026): aceeași durată, dar
/// 0,9 MB în loc de 2,3 MB. MP3-ul poate lăsa o pauză foarte scurtă la
/// reluare, din cauza padding-ului pus de encoder — dacă se aude vreodată
/// deranjant, soluția e un `.ogg`, nu întoarcerea la `.wav`.
class Music {
  static final AudioPlayer _player = AudioPlayer(playerId: 'bg_music');
  static Future<void>? _preloadFuture;
  static bool _enabled = true;
  static double _volume = 0.5;
  static bool _started = false;
  static MusicTrack _track = defaultMusicTrack;

  /// Piesa aleasă acum. Ecranul de muzică o citește ca să bifeze rândul
  /// potrivit; vezi [setTrack] pentru schimbare.
  static MusicTrack get track => _track;

  static Future<void> preload() {
    return _preloadFuture ??= _init();
  }

  static Future<void> _init() async {
    await _ensureGlobalAudioContext();
    _enabled = await StorageService.getMusicEnabled();
    _volume = await StorageService.getMusicVolume();
    _track = musicTrackById(await StorageService.getMusicTrackId());
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setVolume(_volume);
      await _player.setSourceAsset(_track.assetPath);
    } catch (e) {
      debugPrint('Music: nu am putut pregăti piesa de fundal: $e');
      // Piesa salvată nu mai există (fișier scos din assets între versiuni) —
      // se cade pe cea originală în loc să rămână tăcere pe tot jocul, iar
      // preferința se rescrie ca data viitoare să nu se mai încerce degeaba.
      if (_track.id != defaultMusicTrack.id) {
        _track = defaultMusicTrack;
        await StorageService.setMusicTrackId(_track.id);
        try {
          await _player.setSourceAsset(_track.assetPath);
        } catch (e2) {
          debugPrint('Music: nici piesa implicită nu a putut fi încărcată: $e2');
        }
      }
    }
  }

  /// Schimbă piesa de fundal pe loc, fără repornirea aplicației: oprește ce
  /// se aude, încarcă sursa nouă și, dacă muzica era pornită, reia imediat —
  /// așa alegerea din meniu se AUDE în aceeași secundă, ceea ce e singurul
  /// mod în care cineva poate compara cu adevărat două piese.
  ///
  /// Întoarce false dacă fișierul nu a putut fi încărcat; în acel caz piesa
  /// dinainte rămâne activă și preferința NU se salvează, ca jocul să nu
  /// rămână mut după o alegere eșuată.
  static Future<bool> setTrack(MusicTrack next) async {
    await preload();
    final previous = _track;
    try {
      await _player.stop();
      await _player.setSourceAsset(next.assetPath);
      await _player.setVolume(_volume);
      _track = next;
      await StorageService.setMusicTrackId(next.id);
      if (_enabled && _started) await _player.resume();
      return true;
    } catch (e) {
      debugPrint('Music: nu am putut schimba piesa pe ${next.assetName}: $e');
      _track = previous;
      try {
        await _player.setSourceAsset(previous.assetPath);
        if (_enabled && _started) await _player.resume();
      } catch (e2) {
        debugPrint('Music: revenirea la piesa anterioară a eșuat: $e2');
      }
      return false;
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

  /// Pune muzica pe pauză când aplicația trece în fundal (Home/Recent Apps) —
  /// fără să atingă preferința "Music Off" persistată, doar oprește
  /// redarea efectivă cât timp userul nu se uită la ecran.
  static Future<void> pauseForBackground() async {
    if (!_started) return;
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('Music: nu am putut pune pauză la trecerea în fundal: $e');
    }
  }

  /// Reia muzica la revenirea în prim-plan — doar dacă era activată din
  /// Setări (respectă "Music Off" ca la orice altă pornire).
  static Future<void> resumeFromBackground() async {
    if (!_started || !_enabled) return;
    try {
      await _player.resume();
    } catch (e) {
      debugPrint('Music: nu am putut relua la revenirea în prim-plan: $e');
    }
  }
}

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
  /// înainte de orice altceva (vezi [_ensureGlobalAudioContext]).
  static Future<void> _init() async {
    await _ensureGlobalAudioContext();
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

/// Sunetele modului multiplayer Quizz Tanks — ținute separat de [Sfx]
/// DINADINS, cu preîncărcare proprie: sunt cinci fișiere (dintre care unul
/// de peste o secundă, explozia), folosite de un singur ecran din toată
/// aplicația. Băgate în preîncărcarea generală din main.dart, fiecare
/// pornire de joc ar fi plătit decodarea lor, inclusiv pornirile în care
/// nimeni nu deschide multiplayer-ul.
///
/// [preload] se cheamă din MultiplayerTanksScreen.initState, adică în
/// lobby-ul de dinaintea meciului — sunt câteva secunde bune de așteptare
/// acolo, deci primul foc de tun se aude la fel de sigur ca ultimul.
///
/// Fiecare sunet are player propriu: într-o rundă pleacă până la patru
/// tunuri aproape simultan, iar un singur player le-ar fi tăiat unul pe
/// altul. Vezi [Sfx] pentru de ce se folosește seek(0)+resume() și nu
/// stop()+play().
class TankSfx {
  static final AudioPlayer _fire = AudioPlayer(playerId: 'tank_fire');
  static final AudioPlayer _hit = AudioPlayer(playerId: 'tank_hit');
  static final AudioPlayer _dodge = AudioPlayer(playerId: 'tank_dodge');
  static final AudioPlayer _explode = AudioPlayer(playerId: 'tank_explode');
  static final AudioPlayer _lock = AudioPlayer(playerId: 'tank_lock');
  static final AudioPlayer _alarm = AudioPlayer(playerId: 'tank_alarm');

  static Future<void>? _preloadFuture;

  static Future<void> preload() {
    return _preloadFuture ??= _init();
  }

  static Future<void> _init() async {
    await _ensureGlobalAudioContext();
    await Future.wait([
      _prepare(_fire, 'tank_fire.wav'),
      _prepare(_hit, 'tank_hit.wav'),
      _prepare(_dodge, 'tank_dodge.wav'),
      _prepare(_explode, 'tank_explode.wav'),
      _prepare(_lock, 'tank_lock.wav'),
      _prepare(_alarm, 'tank_alarm.wav'),
    ]);
  }

  static Future<void> _prepare(AudioPlayer player, String asset) async {
    try {
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(1.0);
      await player.setSourceAsset('sfx/$asset');
    } catch (e) {
      debugPrint('TankSfx: nu am putut pregăti $asset: $e');
    }
  }

  static Future<void> _play(AudioPlayer player, double volume) async {
    try {
      await preload();
      await player.setVolume(volume);
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      debugPrint('TankSfx: nu am putut reda sunetul: $e');
    }
  }

  /// Volumele nu sunt toate 1.0: într-o rundă plină se suprapun un tun, două
  /// impacturi și un ricoșeu, iar dacă toate ar veni la maximum rezultatul e
  /// zgomot, nu bătălie. Explozia rămâne cea mai tare — e evenimentul care
  /// chiar contează.
  static void fire() => _play(_fire, 0.75);
  static void hit() => _play(_hit, 0.9);
  static void dodge() => _play(_dodge, 0.55);
  static void explode() => _play(_explode, 1.0);
  static void lock() => _play(_lock, 0.7);
  static void alarm() => _play(_alarm, 0.6);
}
