import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/cosmetics.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/storage_service.dart';
import 'avatar_art.dart';

// Oriunde se folosește un Avatar se folosește și stilul lui — reexportate ca
// fiecare ecran să nu aibă nevoie de un al doilea import.
export 'avatar_art.dart';

/// Avatarul ales de jucătorul de pe TELEFONUL ăsta, ținut aici ca să se
/// împrospăteze instant peste tot (header, Profil) în clipa în care îl
/// schimbă, fără restart și fără să reîncarce fiecare ecran din
/// SharedPreferences.
final ValueNotifier<AvatarStyle> myAvatarStyle = ValueNotifier(AvatarStyle.poza);

bool _myAvatarStyleLoaded = false;

Future<void> loadMyAvatarStyle() async {
  myAvatarStyle.value = avatarStyleFromId(await StorageService.getAvatarStyleId());
  _myAvatarStyleLoaded = true;
}

Future<void> setMyAvatarStyle(AvatarStyle style) async {
  myAvatarStyle.value = style;
  _myAvatarStyleLoaded = true;
  await StorageService.setAvatarStyleId(style.id);
}

/// Avatarul jucătorului — poza reală de Google ([photoUrl], dacă userul e
/// logat cu Google, vezi AuthService.multiplayerIdentity), altfel poza
/// locală a userului, altfel un cerc colorat cu inițiala.
///
/// Dacă [label] e dat (ex. inițiala unui alt jucător din multiplayer, care
/// n-are [photoUrl]), arată un cerc colorat cu inițiala în loc de poza
/// locală a userului — comportamentul implicit rămâne neschimbat.
class Avatar extends StatelessWidget {
  final double size;
  final String? label;
  final Color? accentColor;
  final String? photoUrl;

  /// Avatarul desenat, ales de jucătorul ăsta. Când e altul decât
  /// [AvatarStyle.poza], BATE și poza de Google, și inițiala — altfel alegerea
  /// n-ar avea niciun efect vizibil pentru cine e logat cu Google.
  final AvatarStyle style;

  /// Rama cosmetică din jurul avatarului (vezi core/cosmetics.dart).
  /// [Frame.none] = fără inel, comportamentul de dinainte. Inelul CONSUMĂ din
  /// [size] (nu adaugă) — [Avatar] e folosit în rânduri strânse cu dimensiune
  /// fixă (clasament, badge de meci) unde câțiva px în plus ar sparge layout-ul.
  final Frame frame;

  const Avatar({
    super.key,
    this.size = 44,
    this.label,
    this.accentColor,
    this.photoUrl,
    this.style = AvatarStyle.poza,
    this.frame = Frame.none,
  });

  /// Pozele de Google (`...googleusercontent.com/...=s96-c`) vin implicit la
  /// o rezoluție mică (96px) — se vede pixelat aici, unde poza e afișată la
  /// [size] puncte logice, supra-scalată încă 1.18× (vezi overscan) și pe un
  /// ecran cu densitate mare. Cerem explicit o rezoluție proporțională cu ce
  /// chiar afișăm, în loc să lăsăm Flutter să întindă thumbnail-ul mic.
  static String _highResUrl(String url, double logicalSize, double devicePixelRatio) {
    if (!url.contains('googleusercontent.com')) return url;
    final target = (logicalSize * devicePixelRatio * 1.2).round().clamp(96, 512);
    final sizeParam = RegExp(r'=s\d+(-c)?$');
    if (sizeParam.hasMatch(url)) return url.replaceFirst(sizeParam, '=s$target-c');
    return '$url=s$target-c';
  }

  @override
  Widget build(BuildContext context) {
    // Inelul consumă din dimensiunea totală: avatarul interior se desenează la
    // `size - 2*ringWidth`, iar cercul exterior rămâne exact [size].
    final ringWidth =
        frame == Frame.none ? 0.0 : (size * 0.08).clamp(2.0, 5.0);
    final innerSize = size - 2 * ringWidth;
    final color = accentColor ?? AppColors.purple;
    final fallback = Container(
      color: color.withAlpha(60),
      alignment: Alignment.center,
      child: label != null
          ? Text(label!, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: innerSize * 0.4))
          : Icon(Icons.person_rounded, color: Colors.white, size: innerSize * 0.5),
    );
    // pozele (mai ales cele de Google, care nu sunt mereu perfect patrate/
    // centrate) sunt usor "supra-scalate" fata de cerc, ca sa nu ramana
    // colturi vizibile la margini (sus/jos/stanga/dreapta) intre poza si
    // marginea cercului.
    Widget overscan(Widget child) => Transform.scale(scale: 1.18, child: child);
    Widget photo(String url) {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      return overscan(Image.network(_highResUrl(url, innerSize, dpr), fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback));
    }
    Widget localPhoto() => overscan(Image.asset(userAvatarAsset, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback));
    final inner = Container(
      width: innerSize,
      height: innerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: innerSize > 60 ? 3 : 2),
      ),
      clipBehavior: Clip.hardEdge,
      child: style.isArt
          ? AvatarArt(style: style, size: innerSize)
          : (photoUrl != null && photoUrl!.isNotEmpty)
              ? photo(photoUrl!)
              : label != null
                  ? fallback
                  : localPhoto(),
    );
    if (frame == Frame.none) return inner;
    final fs = frameStyle(frame);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: fs.colors.length > 1
            ? SweepGradient(colors: [...fs.colors, fs.colors.first])
            : null,
        color: fs.colors.length == 1 ? fs.colors.first : null,
      ),
      child: inner,
    );
  }
}

/// Avatarul PROPRIU al userului, live — se actualizează automat quando
/// starea de login cu Google se schimbă (poza reală de Google dacă e logat,
/// altfel poza locală default). Folosit în LevelHeader și Profile, ca
/// iconița să reflecte imediat login-ul, fără să fie nevoie de restart.
/// Previzualizarea opțiunii „Poza mea" din selectorul de avatar: arată mereu
/// poza reală (Google sau cea implicită), indiferent ce stil desenat e ales
/// în momentul ăsta — altfel opțiunea de a te întoarce la poză ar arăta
/// exact ca avatarul curent și n-ar mai însemna nimic.
class MyPhotoPreview extends StatelessWidget {
  final double size;
  const MyPhotoPreview({super.key, this.size = 62});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      initialData: AuthService.instance.currentUser,
      builder: (context, snap) => Avatar(size: size, photoUrl: snap.data?.photoURL),
    );
  }
}

class MyAvatar extends StatefulWidget {
  final double size;
  const MyAvatar({super.key, this.size = 44});

  @override
  State<MyAvatar> createState() => _MyAvatarState();
}

class _MyAvatarState extends State<MyAvatar> {
  @override
  void initState() {
    super.initState();
    // prima montare din sesiune hidratează notifier-ul; celelalte îl citesc
    // direct din memorie
    if (!_myAvatarStyleLoaded) loadMyAvatarStyle();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AvatarStyle>(
      valueListenable: myAvatarStyle,
      builder: (context, style, __) => ValueListenableBuilder<Frame>(
        valueListenable: myFrame,
        builder: (context, frame, ___) => StreamBuilder<User?>(
          stream: AuthService.instance.authStateChanges(),
          initialData: AuthService.instance.currentUser,
          builder: (context, snap) => Avatar(
              size: widget.size,
              photoUrl: snap.data?.photoURL,
              style: style,
              frame: frame),
        ),
      ),
    );
  }
}
