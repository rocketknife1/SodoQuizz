// Valorile Android sunt cele reale, din proiectul Firebase "sodoquizz"
// (extrase din android/app/google-services.json). Web si iOS raman
// placeholder pana se adauga acele platforme in Firebase Console - daca
// e nevoie, repeta pasii din Project settings -> Your apps pentru ele.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('DefaultFirebaseOptions nu are configurare pentru aceasta platforma.');
    }
  }

  static const web = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyDMMbkoqPBzas0siDzH6c-GoBOWYJm-CUs',
    appId: '1:112195368669:android:7a22a626a0d35bbc750d34',
    messagingSenderId: '112195368669',
    projectId: 'sodoquizz',
    storageBucket: 'sodoquizz.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    iosBundleId: 'com.example.guessIt',
  );
}

/// Client ID-ul OAuth "web" din google-services.json - Google Sign-In pe
/// Android are nevoie de el ca serverClientId (vezi auth_service.dart).
const googleSignInServerClientId = '112195368669-p8qe6f5doeraqj3qc61f1l1tmcdu1le2.apps.googleusercontent.com';
