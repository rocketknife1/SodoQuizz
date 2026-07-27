// Valorile Android si Web sunt cele reale, din proiectul Firebase
// "sodoquizz" (Android extras din android/app/google-services.json, Web
// din Project settings -> Your apps -> SodoQuizz Web). iOS ramane
// placeholder pana se adauga acea platforma in Firebase Console.
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
    apiKey: 'AIzaSyAG1yZlVrHq1bFFT-HTJbvSjJC0sGUPnfU',
    appId: '1:112195368669:web:42c506db4ab76f92750d34',
    messagingSenderId: '112195368669',
    projectId: 'sodoquizz',
    authDomain: 'sodoquizz.firebaseapp.com',
    storageBucket: 'sodoquizz.firebasestorage.app',
    measurementId: 'G-2PW25LL1VG',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyDMMbkoqPBzas0siDzH6c-GoBOWYJm-CUs',
    appId: '1:112195368669:android:6961c0c5b1946b12750d34',
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
