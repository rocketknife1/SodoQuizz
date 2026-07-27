import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';

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
  const Avatar({super.key, this.size = 44, this.label, this.accentColor, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.purple;
    final fallback = Container(
      color: color.withAlpha(60),
      alignment: Alignment.center,
      child: label != null
          ? Text(label!, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.4))
          : Icon(Icons.person_rounded, color: Colors.white, size: size * 0.5),
    );
    // pozele (mai ales cele de Google, care nu sunt mereu perfect patrate/
    // centrate) sunt usor "supra-scalate" fata de cerc, ca sa nu ramana
    // colturi vizibile la margini (sus/jos/stanga/dreapta) intre poza si
    // marginea cercului.
    Widget overscan(Widget child) => Transform.scale(scale: 1.18, child: child);
    Widget photo(String url) => overscan(Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback));
    Widget localPhoto() => overscan(Image.asset(userAvatarAsset, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: size > 60 ? 3 : 2),
      ),
      clipBehavior: Clip.hardEdge,
      child: (photoUrl != null && photoUrl!.isNotEmpty)
          ? photo(photoUrl!)
          : label != null
              ? fallback
              : localPhoto(),
    );
  }
}

/// Avatarul PROPRIU al userului, live — se actualizează automat quando
/// starea de login cu Google se schimbă (poza reală de Google dacă e logat,
/// altfel poza locală default). Folosit în LevelHeader și Profile, ca
/// iconița să reflecte imediat login-ul, fără să fie nevoie de restart.
class MyAvatar extends StatelessWidget {
  final double size;
  const MyAvatar({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      initialData: AuthService.instance.currentUser,
      builder: (context, snap) => Avatar(size: size, photoUrl: snap.data?.photoURL),
    );
  }
}
