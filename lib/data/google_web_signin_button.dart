/// Butonul Google randat de SDK-ul lor, necesar DOAR pe web — vezi
/// AuthService._authenticateGoogle pentru de ce (`authenticate()` aruncă
/// `UnimplementedError` pe web, Google cere userului să apese butonul lor
/// randat direct în DOM, nu unul al nostru care declanșează fluxul din cod).
/// Import condiționat ca fișierul cu `dart:ui_web`/`package:web` să nu intre
/// deloc în compilarea pentru Android/iOS (ar pica la compilare acolo).
library;

export 'google_web_signin_button_stub.dart'
    if (dart.library.js_interop) 'google_web_signin_button_web.dart';
