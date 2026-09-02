import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

// ─── App Check: dovada că cererea vine din aplicația adevărată ────────────
// Firestore verifică deja CINE ești (request.auth) și CE ai voie să atingi
// (firestore.rules). Ce nu poate verifica singur e DE UNDE vine cererea: un
// client modificat, cu aceleași chei Firebase (care sunt publice prin
// construcție, vezi firebase_options.dart), trece prin exact aceleași reguli
// ca aplicația reală. App Check închide fix golul ăsta — atașează fiecărei
// cereri un token emis de Google DOAR pentru binarul autentic.
//
// De ce contează aici, concret: câteva reguli din firestore.rules sunt
// deliberat permisive, fiindcă proiectul nu are Cloud Functions —
//   - player_profiles/{uid}: fiecare client își scrie SINGUR scorul, deci un
//     client modificat își poate pune orice în leaderboard-ul global;
//   - matches/{matchId}: orice cont autentificat poate șterge orice meci,
//     inclusiv unul în desfășurare al altora;
//   - completed_matches: scriere liberă, deci statisticile se pot umfla.
// Niciuna nu se poate strânge fără server propriu. App Check nu le strânge
// nici el, dar mută bariera: nu mai e destul să ai un cont, îți trebuie
// binarul autentic, nemodificat, pe un dispozitiv real.
//
// ATENȚIE — activarea de aici NU schimbă nimic pe server, deocamdată.
// Câtă vreme în Firebase Console → App Check aplicația e pe "unenforced"
// (implicit), tokenul e doar trimis și numărat. Se vede în consolă ce
// procent din cereri vin verificate. Beneficiul real de securitate apare
// abia când se apasă "Enforce", iar aia e o decizie separată — vezi mai jos
// de ce nu e gratis.
//
// CAPCANA la Enforce, de citit înainte: APK-ul public din GitHub Releases
// (vezi LINKS.md) e semnat cu cheia de upload locală, pe când Play
// redistribuie binarul semnat cu propria cheie (Play App Signing — de-asta
// sunt 4 amprente SHA-1 în google-services.json). Play Integrity recunoaște
// doar ce distribuie Play, deci APK-ul sideloaded primește
// UNRECOGNIZED_VERSION și NU obține token. Cu Enforce pornit, acei jucători
// rămân fără leaderboard, fără multiplayer și fără salvare în cloud —
// tăcut, fiindcă restul jocului merge local. Enforce doar după ce canalul
// ăla e închis sau declarat acceptabil de pierdut.

/// Forțează providerul de debug și într-un build `--release`, pentru
/// verificările pe telefonul de dezvoltare (unde se testează mereu release,
/// nu debug — vezi CLAUDE.md). Fără el, un APK construit local ar cere
/// Play Integrity și ar primi mereu refuz, fiindcă nu e binarul distribuit
/// de Play.
///
/// Tokenul tipărit în logcat trebuie înregistrat o singură dată în Firebase
/// Console → App Check → Apps → Manage debug tokens.
///
/// NU se pune pe build-ul pentru Play (vezi docs/build.md) — ar face App
/// Check inutil exact acolo unde trebuie să conteze.
const bool _forceDebugProvider = bool.fromEnvironment('APPCHECK_DEBUG');

/// Cheia de site reCAPTCHA pentru varianta din browser, din Firebase
/// Console → App Check. Nu e secretă (ajunge oricum în pagina servită), dar
/// nu e nici în cod: se dă la compilare, ca build-ul web să poată fi făcut
/// și fără ea, în timpul dezvoltării.
///
///   flutter build web --release --dart-define=APPCHECK_RECAPTCHA_KEY=6Lc...
///
/// E o cheie reCAPTCHA **Enterprise** (înregistrată așa în consolă pe
/// 2026-09-02) — providerul e [ReCaptchaEnterpriseProvider], nu v3. reCAPTCHA
/// clasic e blocat de Google pentru înregistrări noi. Cheia a fost creată în
/// proiectul Cloud „SodoQuizz", deci merge prin API-ul Enterprise (plafon
/// gratuit 10.000 verificări/lună — TTL-ul tokenului e 1 zi ca să nu se
/// consume repede).
const String _recaptchaSiteKey = String.fromEnvironment(
  'APPCHECK_RECAPTCHA_KEY',
);

bool get _useDebugProvider => kDebugMode || _forceDebugProvider;

/// Se apelează imediat după [Firebase.initializeApp] și înainte de orice
/// altceva care atinge Firestore/Auth — tokenul trebuie să existe deja când
/// pleacă prima cerere, altfel prima rundă de cereri ar pleca neverificată.
///
/// Nu aruncă niciodată: un eșec aici (fără net, Play Services vechi,
/// aplicație neînregistrată încă în consolă) nu are voie să oprească
/// pornirea. În modul neimpus, o cerere fără token trece oricum.
Future<void> activateAppCheck() async {
  // Pe web fără cheie reCAPTCHA nu are ce activa: SDK-ul ar încerca să
  // încarce reCAPTCHA cu cheie goală și ar arunca. Ieșim curat, ca
  // build-urile web de dezvoltare să meargă neschimbat.
  if (kIsWeb && _recaptchaSiteKey.isEmpty) {
    debugPrint('App Check: sarit pe web (lipseste APPCHECK_RECAPTCHA_KEY).');
    return;
  }
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: _useDebugProvider
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerWeb: kIsWeb ? ReCaptchaEnterpriseProvider(_recaptchaSiteKey) : null,
    );
    debugPrint(
      'App Check activat (${kIsWeb ? "reCAPTCHA Enterprise" : _useDebugProvider ? "debug" : "Play Integrity"}).',
    );
  } catch (e) {
    debugPrint('App Check nu s-a activat: $e');
  }
}
