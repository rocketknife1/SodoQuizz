import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'lang.dart';

/// O piesă din catalogul de muzică de fundal.
///
/// [assetName] e numele fișierului din `assets/music/`. Nu e nevoie de nicio
/// modificare în pubspec.yaml când se adaugă una nouă: acolo e înscris
/// directorul întreg (`- assets/music/`), deci orice fișier pus acolo intră
/// automat în build.
class MusicTrack {
  final String id;
  final String assetName;

  /// Numele arătat jucătorului. Nu se traduce — e nume propriu de piesă, la
  /// fel în orice limbă.
  final String name;

  /// Pentru cine e, în română și engleză — rândul mic de sub nume.
  final String descriptionRo;
  final String descriptionEn;

  /// Emoji-ul din pastila piesei, ca stilurile să se distingă dintr-o privire.
  final String emoji;

  const MusicTrack({
    required this.id,
    required this.assetName,
    required this.name,
    required this.descriptionRo,
    required this.descriptionEn,
    required this.emoji,
  });

  String get assetPath => 'music/$assetName';
  String get description => tr(descriptionRo, descriptionEn);
}

/// Catalogul de muzică de fundal — piesa originală plus patru stiluri
/// deliberat diferite între ele, ca fiecare jucător (și fiecare vârstă) să
/// găsească ceva ascultabil ore în șir: nu are rost ca toate cinci să fie
/// variațiuni pe aceeași temă.
///
/// PRIMA e cea care se aude azi și rămâne implicită — un jucător care nu
/// intră niciodată în meniul de muzică nu observă absolut nicio schimbare.
///
/// PIESELE CARE LIPSESC DIN `assets/music/` NU APAR ÎN MENIU. Vezi
/// [availableMusicTracks]: catalogul e o listă de intenții, nu o promisiune
/// că fișierele există. Alegerea asta e deliberată — altfel un fișier
/// neadăugat încă ar fi produs un rând care, apăsat, oprea muzica în tăcere
/// și părea o defecțiune a jocului.
const List<MusicTrack> musicTracks = [
  MusicTrack(
    id: 'theme',
    assetName: 'theme_loop.mp3',
    name: 'Neon Drive',
    descriptionRo: 'Dark techno — piesa originală a jocului',
    descriptionEn: 'Dark techno — the original game theme',
    emoji: '🌃',
  ),
  MusicTrack(
    id: 'arcade',
    assetName: 'arcade_loop.mp3',
    name: 'Retro Arcade',
    descriptionRo: 'Chiptune 8-bit, vioi — pentru cei mici și nostalgici',
    descriptionEn: 'Upbeat 8-bit chiptune — for kids and the nostalgic',
    emoji: '👾',
  ),
  MusicTrack(
    id: 'lofi',
    assetName: 'lofi_loop.mp3',
    name: 'Lofi Chill',
    descriptionRo: 'Lo-fi relaxat — pentru sesiuni lungi, fără oboseală',
    descriptionEn: 'Relaxed lo-fi — for long sessions without fatigue',
    emoji: '🎧',
  ),
  MusicTrack(
    id: 'epic',
    assetName: 'epic_loop.mp3',
    name: 'Epic Quest',
    descriptionRo: 'Orchestral cinematic — pentru atmosferă de mare aventură',
    descriptionEn: 'Cinematic orchestral — for a big-adventure feel',
    emoji: '⚔️',
  ),
  MusicTrack(
    id: 'funk',
    assetName: 'funk_loop.mp3',
    name: 'Funky Groove',
    descriptionRo: 'Funk vesel, cu ritm — bun la orice vârstă',
    descriptionEn: 'Cheerful, groovy funk — good at any age',
    emoji: '🕺',
  ),
];

final MusicTrack defaultMusicTrack = musicTracks.first;

MusicTrack musicTrackById(String id) =>
    musicTracks.firstWhere((t) => t.id == id, orElse: () => defaultMusicTrack);

List<MusicTrack>? _availableCache;

/// Piesele al căror fișier CHIAR există în build. Verificate o singură dată
/// pe sesiune, încercând să le încarce din bundle — nu există o cale de a
/// întreba „ce fișiere sunt în assets" fără să le deschizi.
///
/// Costul e o citire de fișier per piesă, o dată, la deschiderea meniului de
/// muzică; nimic din asta nu se întâmplă la pornirea jocului.
Future<List<MusicTrack>> availableMusicTracks() async {
  if (_availableCache != null) return _availableCache!;
  final available = <MusicTrack>[];
  for (final track in musicTracks) {
    if (await musicAssetExists(track)) available.add(track);
  }
  // Dacă nu s-a găsit absolut nimic (build stricat, assets lipsă), meniul
  // arată totuși piesa implicită în loc să rămână gol și de neînțeles.
  _availableCache = available.isEmpty ? [defaultMusicTrack] : available;
  return _availableCache!;
}

Future<bool> musicAssetExists(MusicTrack track) async {
  try {
    await rootBundle.load('assets/${track.assetPath}');
    return true;
  } catch (_) {
    debugPrint('MusicTracks: ${track.assetName} lipseste din assets/music/');
    return false;
  }
}
