import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

// ─── Comutatoare de la distanță ───────────────────────────────────────────
//
// DE CE EXISTĂ, în cuvintele scopului: „lansez, mai dau un update mic și nu
// mă mai ating de aplicație". Ca aia să fie posibil, trebuie să poți schimba
// comportamentul FĂRĂ să publici un build — altfel orice fleac (un preț
// greșit, o funcție care trebuie oprită, un anunț) devine o versiune nouă
// care mai și așteaptă review-ul Google, apoi propagarea la jucători.
//
// PUȚINE chei, dinadins. Fiecare cheie e un lucru în plus de ținut minte și
// o cale în plus prin care aplicația se poate comporta altfel decât codul pe
// care îl citești. Aici sunt doar cele care chiar nu se pot face altfel.
//
// VALORILE IMPLICITE SUNT ADEVĂRUL cât timp nu s-a adus nimic: prima pornire,
// fără net, sau Remote Config nedisponibil. Aplicația nu așteaptă niciodată
// după rețea ca să pornească.

class RemoteFlags {
  RemoteFlags._();
  static final RemoteFlags instance = RemoteFlags._();

  /// Versiunea minimă acceptată, ca „1.0.2". Sub ea, jucătorul primește un
  /// ecran care îi cere să actualizeze.
  ///
  /// ASTA E CHEIA CARE SALVEAZĂ SITUAȚIA dacă scapă un bug urât în magazin:
  /// fără ea, clienții vechi rămân pe versiunea stricată pentru totdeauna,
  /// fiindcă nimeni nu e obligat să actualizeze. Gol = nicio constrângere.
  static const _kMinVersion = 'versiune_minima';

  /// Dacă nu e gol, se arată ca anunț peste joc („Revenim în 10 minute").
  /// Calea prin care spui ceva tuturor fără să publici nimic.
  static const _kMaintenance = 'mesaj_intretinere';

  /// Cele două comutatoare ale magazinului cu bani reali — azi constante în
  /// `data/shop.dart`, ceea ce înseamnă că deschiderea magazinului cere un
  /// build nou. De aici se pot aprinde în ziua în care produsele sunt gata.
  static const _kRealMoney = 'magazin_bani_reali';
  static const _kPremiumVisible = 'magazin_premium_vizibil';

  static const Map<String, dynamic> _defaults = {
    _kMinVersion: '',
    _kMaintenance: '',
    _kRealMoney: false,
    _kPremiumVisible: false,
  };

  FirebaseRemoteConfig? _rc;

  /// Se schimbă când sosesc valori noi — ecranele care depind de ele se
  /// reconstruiesc singure, fără repornire.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String get minVersion => _rc?.getString(_kMinVersion) ?? '';
  String get maintenanceMessage => _rc?.getString(_kMaintenance) ?? '';
  bool get realMoneyStore => _rc?.getBool(_kRealMoney) ?? false;
  bool get premiumVisible => _rc?.getBool(_kPremiumVisible) ?? false;

  /// Se apelează după `Firebase.initializeApp`. NU se așteaptă după ea la
  /// pornire: valorile implicite sunt bune, iar cele aduse se aplică atunci
  /// când sosesc.
  Future<void> init() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setDefaults(_defaults);
      _rc = rc;
      // Un minut între aduceri: destul cât o schimbare făcută în consolă să
      // ajungă repede la jucători, dar nu atât de des încât să coste cotă.
      // La prima pornire valorile vin oricum din `_defaults`.
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval: const Duration(minutes: 60),
      ));
      await rc.fetchAndActivate();
      revision.value++;
    } catch (e) {
      // Fără net, sau proiect fără Remote Config activat: rămân valorile
      // implicite. Nu are voie să rupă pornirea.
      debugPrint('RemoteFlags.init a esuat (raman valorile implicite): $e');
    }
  }

  /// `true` dacă [current] e mai mic decât versiunea minimă cerută.
  ///
  /// Compară numeric, parte cu parte („1.10.0" e mai mare decât „1.9.9",
  /// ceea ce o comparație de text ar greși). Orice lucru neînțeles înseamnă
  /// „nu bloca": mai bine lași pe cineva să joace o versiune veche decât să
  /// blochezi pe toată lumea dintr-o greșeală de tastare în consolă.
  static bool isTooOld({required String current, required String minimum}) {
    if (minimum.trim().isEmpty || current.trim().isEmpty) return false;
    final a = _parse(current);
    final b = _parse(minimum);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return false;
  }

  static List<int>? _parse(String v) {
    // Se acceptă și „1.0.2+6" — partea de după `+` e numărul de build, care
    // nu intră în comparație.
    final core = v.split('+').first.trim();
    final parts = core.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final out = <int>[0, 0, 0];
    for (var i = 0; i < parts.length; i++) {
      final n = int.tryParse(parts[i]);
      if (n == null) return null;
      out[i] = n;
    }
    return out;
  }
}
