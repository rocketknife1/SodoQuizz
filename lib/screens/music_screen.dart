import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/lang.dart';
import '../core/music_tracks.dart';
import '../core/theme.dart';

/// Alegerea piesei de fundal, plus comutatorul și volumul muzicii — tot ce
/// ține de muzică, într-un singur loc.
///
/// Alegerea unei piese o și PORNEȘTE, pe loc (vezi [Music.setTrack]): altfel
/// n-ai avea cum să compari două piese fără să ieși din meniu de fiecare
/// dată. De-aia butonul muzicii se aprinde singur dacă era stins — cineva
/// care intră aici și apasă pe o piesă vrea s-o audă, nu să bifeze o casetă.
///
/// Se listează doar piesele al căror fișier chiar există în build (vezi
/// [availableMusicTracks]).
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  late Future<List<MusicTrack>> _tracksFuture;
  bool _musicEnabled = Music.isEnabled;
  double _volume = Music.volume;
  String _currentId = Music.track.id;
  String? _switchingId;

  @override
  void initState() {
    super.initState();
    _tracksFuture = availableMusicTracks();
  }

  Future<void> _select(MusicTrack track) async {
    if (_switchingId != null) return;
    setState(() => _switchingId = track.id);
    // Dacă muzica era oprită, o pornim — vezi nota din capul clasei.
    if (!_musicEnabled) {
      await Music.setEnabled(true);
      if (mounted) setState(() => _musicEnabled = true);
    }
    final ok = await Music.setTrack(track);
    if (!mounted) return;
    setState(() {
      _currentId = Music.track.id;
      _switchingId = null;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Nu am putut porni „${track.name}".', 'Could not start "${track.name}".'))),
      );
    }
  }

  Future<void> _toggleMusic(bool value) async {
    setState(() => _musicEnabled = value);
    await Music.setEnabled(value);
  }

  Future<void> _changeVolume(double value) async {
    setState(() => _volume = value);
    await Music.setVolume(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  Text(tr('Muzică', 'Music'),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _buildMusicSwitchCard(context),
                  const SizedBox(height: 18),
                  Text(
                    tr('ALEGE PIESA', 'PICK A TRACK'),
                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('Se aude imediat ce o alegi.', 'It starts playing the moment you pick it.'),
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<MusicTrack>>(
                    future: _tracksFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator(color: AppColors.purple)),
                        );
                      }
                      final tracks = snapshot.data ?? const <MusicTrack>[];
                      return Column(
                        children: [
                          for (final track in tracks) ...[
                            _TrackRow(
                              track: track,
                              selected: track.id == _currentId,
                              busy: track.id == _switchingId,
                              onTap: () => _select(track),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicSwitchCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.play.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _musicEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
                  color: AppColors.play,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Muzică de fundal', 'Background music'),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(tr('Separată de sunetele de buton', 'Separate from button sounds'),
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoSwitch(
                value: _musicEnabled,
                activeTrackColor: AppColors.play,
                onChanged: _toggleMusic,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, color: Colors.white38, size: 18),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.play,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: AppColors.play,
                    overlayColor: AppColors.play.withAlpha(40),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _volume,
                    onChanged: _musicEnabled ? _changeVolume : null,
                  ),
                ),
              ),
              const Icon(Icons.volume_up_rounded, color: Colors.white38, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final MusicTrack track;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  const _TrackRow({required this.track, required this.selected, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.play : Colors.white10, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(track.emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(track.description,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.play))
            else if (selected)
              Icon(Icons.graphic_eq_rounded, color: AppColors.play, size: 22)
            else
              const Icon(Icons.play_circle_outline_rounded, color: Colors.white24, size: 22),
          ],
        ),
      ),
    );
  }
}
