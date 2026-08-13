import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/betting.dart';
import '../core/lang.dart';
import '../core/tanks.dart';
import '../models/multiplayer_models.dart';

/// Aruncată când Firebase nu e (încă) configurat corect — [firebase_options.dart]
/// are valori placeholder până userul pune un proiect real. UI-ul o prinde și
/// arată un fallback prietenos, nu lasă aplicația să crape.
class MultiplayerUnavailableException implements Exception {
  final String message;
  const MultiplayerUnavailableException([this.message = 'Multiplayer indisponibil momentan.']);
  @override
  String toString() => message;
}

/// Capacitatea maximă a unei camere private (Create Room / Join with Code).
///
/// Ridicat de la 5 la 11: 5 oameni nu e "un grup". 11 e mărimea la care
/// ladder-ul potului de loc are trepte cu valori distincte (vezi
/// placementShares din core/betting.dart), rândul de avatare de sus rămâne
/// lizibil fiindcă derulează orizontal, iar traficul spre Firestore rămâne sub
/// ~250 de citiri pe meci cu sincronizarea rară de scor din
/// MultiplayerMatchScreen. Matchmaking-ul public rămâne 1 vs 1 — o coadă care
/// așteaptă 11 străini simultan nu s-ar completa niciodată.
const int matchPlayerCount = 11;

/// Câți jucători încap într-o cameră, după modul ei de joc. Quizz Tanks e
/// singurul cu limită proprie ([tanksPlayerCount] = 4): acolo numărul nu e o
/// preferință, ci parte din reguli — „cine răspunde corect trage în ceilalți
/// trei" și arena desenată 2×2 (vezi core/tanks.dart).
int maxPlayersForMode(MatchGameMode mode) =>
    mode == MatchGameMode.quizzTanks ? tanksPlayerCount : matchPlayerCount;

/// Timp minim garantat între un tap al jucătorului (create/join room, dat
/// un răspuns, trimis un mesaj) și finalizarea scrierii în Firestore — nu
/// pentru UX, ci ca frână simplă de trafic: fără el, fiecare tap ajunge
/// direct la Firestore în clipa în care e apăsat, ceea ce la mulți useri
/// simultani înseamnă vârfuri de scriere greu de absorbit. Rulează în
/// paralel cu cererea reală (`Future.wait`), deci nu se adună la latența
/// de rețea — doar impune un plafon minim, nu adaugă timp peste una lentă.
const _writePace = Duration(milliseconds: 350);

Future<T> _paced<T>(Future<T> Function() action) async {
  final results = await Future.wait([action(), Future<void>.delayed(_writePace)]);
  return results[0] as T;
}

/// Câți jucători reali formează un meci prin matchmaking public (Join
/// Online) — 1 vs 1, fără completare cu boți: se așteaptă un adversar real.
const int matchmakingOpponentCount = 2;
const _codeChars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // fara 0/O/1/I - usor de dictat

/// Câte răspunsuri greșite duc la eliminare în [MatchGameMode.higherLower].
const int higherLowerMaxBreads = 5;

/// Cât timp are fiecare rundă înainte ca cei ce n-au votat încă să fie
/// scorați automat ca greșit — aceeași durată ca la mini-jocul solo
/// (higher_lower_screen.dart), pentru consecvență.
const int higherLowerRoundSeconds = 15;

/// Cât timp rămâne vizibil răspunsul corect + câștigătorii rundei înainte
/// ca runda următoare să înceapă automat.
const int higherLowerRevealSeconds = 3;

/// Puncte acordate per rundă câștigată — hrănește direct [MatchPlayer.score],
/// deci recompensele economice din MultiplayerResultsScreen (deja bazate pe
/// scor) funcționează neschimbate și pentru acest mod.
const int higherLowerPointsPerWin = 10;

/// Toată logica de rețea (Firestore + Auth anonim) pentru multiplayer —
/// separată de UI, conform planului. O singură colecție `matches` deservește
/// atât camerele private (cu `code`) cât și meciurile de matchmaking public
/// (fără cod) — vezi [MatchInfo].
class MultiplayerService {
  MultiplayerService._();
  static final instance = MultiplayerService._();

  bool _initialized = false;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Asigură o identitate (Google, dacă userul e logat prin Cont în Profil,
  /// altfel anonimă) — LAZY, doar când multiplayer-ul chiar e folosit.
  /// Firebase core e deja inițializat la pornirea aplicației (vezi
  /// main.dart); aici doar ne asigurăm că există un user curent. Aruncă
  /// [MultiplayerUnavailableException] dacă eșuează (ex. Firebase
  /// neconfigurat corect încă, sau fără rețea).
  /// Trei încercări, cu pauză crescătoare între ele, și 15 secunde de
  /// răbdare fiecare (era o singură încercare cu 8 secunde). Pe date mobile,
  /// prima cerere după ce ecranul se aprinde poate depăși lejer 8 secunde cât
  /// se trezește radioul — iar atunci userul vedea "Multiplayer indisponibil"
  /// deși nu era nimic stricat, doar rețeaua lentă. Un Guest lovea asta mai
  /// des decât un cont Google: el chiar trebuie să facă login anonim în acel
  /// moment, pe când contul Google e deja autentificat de la pornire.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await Future(() async {
          if (FirebaseAuth.instance.currentUser == null) {
            await FirebaseAuth.instance.signInAnonymously();
          }
        }).timeout(const Duration(seconds: 15));
        _initialized = true;
        return;
      } catch (e) {
        lastError = e;
        debugPrint('MultiplayerService.ensureInitialized, incercarea $attempt/3 a esuat: $e');
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
        }
      }
    }
    // Mesajul spune ce poate face userul, nu doar că "nu merge" — cel mai
    // frecvent motiv real e conexiunea, nu serverul.
    throw MultiplayerUnavailableException(
      _looksOffline(lastError)
          ? tr('Nu am reușit să mă conectez. Verifică internetul și încearcă din nou.',
              'Could not connect. Check your internet and try again.')
          : tr('Multiplayer indisponibil momentan. Încearcă din nou în câteva secunde.',
              'Multiplayer is unavailable right now. Try again in a few seconds.'),
    );
  }

  /// Erorile de rețea ale Firebase Auth vin cu coduri diferite pe Android și
  /// pe web; le prindem pe cele uzuale, plus timeout-ul nostru.
  static bool _looksOffline(Object? error) {
    final text = error.toString().toLowerCase();
    return text.contains('network') ||
        text.contains('timeout') ||
        text.contains('timeoutexception') ||
        text.contains('unavailable') ||
        text.contains('unreachable');
  }

  String get currentPlayerId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _randomCode() {
    final rnd = Random();
    return List.generate(5, (_) => _codeChars[rnd.nextInt(_codeChars.length)]).join();
  }

  // ─── Camera privată ─────────────────────────────────────────────────────

  /// [stake] e miza camerei, aleasă de cel care o creează — singurul moment
  /// din tot fluxul în care cineva alege o sumă. Se scrie pe documentul
  /// camerei, ca oricine intră după aceea să plătească exact atât, fără să mai
  /// aibă ceva de decis.
  Future<MatchInfo> createRoom({
    required String displayName,
    String? photoUrl,
    String avatarStyle = '',
    MatchGameMode gameMode = MatchGameMode.classic,
    int stake = 0,
  }) async {
    await ensureInitialized();
    final me = currentPlayerId;
    final code = _randomCode();
    final ref = _db.collection('matches').doc();
    final info = MatchInfo(
      id: ref.id,
      mode: MatchMode.private,
      code: code,
      status: MatchStatus.lobby,
      hostId: me,
      hostName: displayName,
      hostPhotoUrl: photoUrl,
      hostAvatarStyle: avatarStyle,
      gameMode: gameMode,
      stake: stake,
    );
    await _paced(() async {
      await ref.set(info.toMap());
      await ref.collection('players').doc(me).set(
            MatchPlayer(
              id: me,
              name: displayName,
              avatarSeed: me,
              photoUrl: photoUrl,
              score: 0,
              isHost: true,
              bet: stake,
              avatarStyle: avatarStyle,
            ).toMap(),
          );
    });
    return info;
  }

  /// Caută o cameră după cod FĂRĂ să intri în ea — folosit ca să-i putem
  /// arăta jucătorului miza camerei înainte să plătească ceva. Aruncă dacă
  /// nu există sau dacă meciul a pornit deja.
  Future<MatchInfo> lookupRoomByCode(String code) async {
    await ensureInitialized();
    final doc = await _findLobbyByCode(code);
    return MatchInfo.fromDoc(doc);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _findLobbyByCode(String code) async {
    final query = await _db
        .collection('matches')
        .where('code', isEqualTo: code.toUpperCase())
        .where('status', isEqualTo: MatchStatus.lobby.name)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw const MultiplayerUnavailableException('Cod invalid sau camera a pornit deja.');
    }
    return query.docs.first;
  }

  /// Caută o cameră după cod și te alătură ca jucător — aruncă dacă nu
  /// există, dacă meciul a pornit deja, sau dacă e plină.
  Future<MatchInfo> joinRoomByCode({
    required String code,
    required String displayName,
    String? photoUrl,
    String avatarStyle = '',
  }) async {
    await ensureInitialized();
    return _joinRoomDoc(await _findLobbyByCode(code),
        displayName: displayName, photoUrl: photoUrl, avatarStyle: avatarStyle);
  }

  /// La fel ca [joinRoomByCode], dar pentru o cameră aleasă direct din
  /// lista de camere deschise (vezi [watchOpenRooms]) — fără cod, doar id.
  Future<MatchInfo> joinRoomById({
    required String matchId,
    required String displayName,
    String? photoUrl,
    String avatarStyle = '',
  }) async {
    await ensureInitialized();
    final doc = await _db.collection('matches').doc(matchId).get();
    if (!doc.exists || doc.data()?['status'] != MatchStatus.lobby.name) {
      throw MultiplayerUnavailableException(
          tr('Camera nu mai e disponibilă.', 'That room is no longer available.'));
    }
    return _joinRoomDoc(doc,
        displayName: displayName, photoUrl: photoUrl, avatarStyle: avatarStyle);
  }

  /// Miza NU e un parametru: se citește de pe documentul camerei. Cine intră
  /// plătește exact cât a stabilit cel care a creat camera, și n-are cum să
  /// ajungă la masă cu altă sumă decât ceilalți — nici din grabă, nici dintr-un
  /// client modificat.
  Future<MatchInfo> _joinRoomDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String displayName,
    String? photoUrl,
    String avatarStyle = '',
  }) async {
    final info = MatchInfo.fromDoc(doc);
    final players = await doc.reference.collection('players').get();
    // Plafonul e al MODULUI, nu al camerei: Quizz Tanks nu primește al
    // cincilea jucător, oricât de goală ar părea camera din listă.
    if (players.docs.length >= maxPlayersForMode(info.gameMode)) {
      throw MultiplayerUnavailableException(tr('Camera e plină.', 'That room is full.'));
    }
    final me = currentPlayerId;
    await _paced(() => doc.reference.collection('players').doc(me).set(
          MatchPlayer(
            id: me,
            name: displayName,
            avatarSeed: me,
            photoUrl: photoUrl,
            score: 0,
            bet: info.stake,
            avatarStyle: avatarStyle,
          ).toMap(),
        ));
    return info;
  }

  /// O cameră abandonată (host ieșit brusc din tab, fără să treacă prin
  /// [leaveMatch] — ex. închidere directă de fereastră, fără Cloud
  /// Functions/TTL care s-o curețe din Firestore) tot rămâne "lobby" la
  /// nesfârșit. Fără curățare server-side, o ascundem din listă după acest
  /// prag ca vechile camere de test să nu rămână vizibile permanent.
  static const _openRoomFreshness = Duration(minutes: 15);

  /// Camerele private aflate încă în lobby, deschise oricui vrea să intre
  /// direct din ecranul Join Online (fără cod) — vezi discuția din
  /// RoomLobbyScreen/MultiplayerScreen: o cameră creată cu Create Room
  /// trebuie să fie găsibilă și așa, nu doar prin cod. Exclude propria
  /// cameră (n-are sens să te alături propriei camere din listă), camerele
  /// fără hostName (create înainte ca acest câmp să existe) și cele mai
  /// vechi de [_openRoomFreshness] — probabil abandonate. Sortată
  /// client-side (nu server-side) ca să nu fie nevoie de un index compus în
  /// Firestore doar pentru o listă mică, decorativă.
  Stream<List<MatchInfo>> watchOpenRooms() {
    final me = currentPlayerId;
    return _db
        .collection('matches')
        .where('mode', isEqualTo: MatchMode.private.name)
        .where('status', isEqualTo: MatchStatus.lobby.name)
        .snapshots()
        .map((s) {
      final cutoff = DateTime.now().subtract(_openRoomFreshness);
      final rooms = s.docs.map(MatchInfo.fromDoc).where((m) {
        if (m.hostId == me) return false;
        if (m.hostName == null || m.hostName!.isEmpty) return false;
        final createdAt = m.createdAt?.toDate();
        if (createdAt == null || createdAt.isBefore(cutoff)) return false;
        return true;
      }).toList();
      rooms.sort((a, b) => (b.createdAt ?? Timestamp(0, 0)).compareTo(a.createdAt ?? Timestamp(0, 0)));
      return rooms;
    });
  }

  /// Pornește meciul — resetează și câmpurile de rundă (necesar în
  /// [MatchGameMode.higherLower]: cronometrul rundei trebuie să înceapă
  /// chiar acum, nu la crearea camerei, care poate fi cu mult timp în urmă
  /// dacă hostul a așteptat în lobby). Resetul e inofensiv pentru
  /// [MatchGameMode.classic], care nu citește aceste câmpuri.
  /// [startedAt] e ancora comună a cronometrului de 60 de secunde din modul
  /// Clasic — scrisă de server, nu de telefonul hostului, ca să nu depindă de
  /// ceasul (posibil greșit) al vreunui dispozitiv.
  Future<void> startMatch(String matchId) => _db.collection('matches').doc(matchId).update({
        'status': MatchStatus.playing.name,
        'startedAt': FieldValue.serverTimestamp(),
        'roundIndex': 0,
        'roundPhase': RoundPhase.answering.name,
        'roundAnswers': <String, String>{},
        'roundWinnerIds': <String>[],
        'roundShots': <Map<String, dynamic>>[],
        'roundDestroyedIds': <String>[],
        'roundStartedAt': FieldValue.serverTimestamp(),
      });

  // ─── Runda sincronizată (Higher & Lower + Quizz Tanks) ─────────────────

  /// Răspunsul propriu la runda curentă — 'higher'/'lower' la Higher &
  /// Lower, textul variantei alese la Quizz Tanks. Ceilalți văd că ai
  /// răspuns (cheia există în `roundAnswers`), nu și CE ai răspuns: nimeni
  /// nu se uită la harta răspunsurilor înainte de rezolvarea rundei.
  Future<void> submitRoundAnswer({required String matchId, required String answer}) {
    final me = currentPlayerId;
    return _paced(() => _db.collection('matches').doc(matchId).update({'roundAnswers.$me': answer}));
  }

  /// Calculează rezultatul rundei curente — poate fi apelată de ORICE
  /// client (nu doar host): tranzacția verifică dacă runda a fost deja
  /// rezolvată de altcineva între timp și, dacă da, nu face nimic. Același
  /// principiu ca [attemptFormMatch] mai jos — evită un singur punct de
  /// eșec (dacă hostul ar fi singurul care rezolvă runde și ar pleca din
  /// meci, jocul ar rămâne blocat). Jucătorii care n-au apucat să voteze
  /// (AFK/deconectați) sunt scorați automat ca greșit, ceea ce dublează și
  /// drept limită de timp a rundei — vezi [higherLowerRoundSeconds].
  ///
  /// [correctGuess] e `null` la EGALITATE de popularitate — dataset-ul
  /// (higher_lower_data.dart) reutilizează intenționat aceleași valori între
  /// categorii, deci nu e un caz rar. La fel ca la modul solo
  /// (higher_lower_screen.dart._choose), egalitatea nu penalizează pe
  /// nimeni, indiferent ce a votat fiecare.
  Future<void> resolveHigherLowerRound({
    required String matchId,
    required int roundIndex,
    required String? correctGuess,
  }) async {
    final matchRef = _db.collection('matches').doc(matchId);
    final playerIds = (await matchRef.collection('players').get()).docs.map((d) => d.id).toList();
    if (playerIds.isEmpty) return;
    try {
      await _db.runTransaction((tx) async {
        final matchDoc = await tx.get(matchRef);
        final data = matchDoc.data();
        if (data == null || data['roundIndex'] != roundIndex || data['roundPhase'] != RoundPhase.answering.name) {
          return; // deja rezolvată de alt client - nimic de facut
        }
        final answers = Map<String, dynamic>.from(data['roundAnswers'] as Map? ?? const {});
        final playerDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final id in playerIds) {
          playerDocs.add(await tx.get(matchRef.collection('players').doc(id)));
        }
        final winnerIds = <String>[];
        var stillActive = 0;
        for (final doc in playerDocs) {
          if (!doc.exists) continue;
          final pData = doc.data()!;
          if (pData['eliminated'] == true) continue; // deja eliminat - spectator, nu joacă runda
          final correct = correctGuess == null || answers[doc.id] == correctGuess;
          if (correct) {
            winnerIds.add(doc.id);
            tx.update(doc.reference, {'score': (pData['score'] as int? ?? 0) + higherLowerPointsPerWin});
            stillActive++;
          } else {
            final breads = (pData['breads'] as int? ?? 0) + 1;
            final eliminated = breads >= higherLowerMaxBreads;
            tx.update(doc.reference, {'breads': breads, 'eliminated': eliminated});
            if (!eliminated) stillActive++;
          }
        }
        tx.update(matchRef, {
          'roundPhase': RoundPhase.revealed.name,
          'roundWinnerIds': winnerIds,
          if (stillActive <= 1) 'status': MatchStatus.finished.name,
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.resolveHigherLowerRound a esuat: $e');
    }
  }

  /// Trece la runda următoare — apelabilă de orice client la fel ca
  /// [resolveHigherLowerRound], cu aceeași gardă anti-cursă. Comună ambelor
  /// moduri cu rundă sincronizată: golește TOT ce ține de runda încheiată,
  /// inclusiv câmpurile pe care le folosește doar Quizz Tanks (a le șterge
  /// și în Higher & Lower nu strică nimic, dar a le uita ar face ca
  /// proiectilele rundei trecute să fie animate din nou în cea nouă).
  Future<void> advanceSyncRound({required String matchId, required int roundIndex}) async {
    final matchRef = _db.collection('matches').doc(matchId);
    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(matchRef);
        final data = doc.data();
        if (data == null || data['roundIndex'] != roundIndex || data['roundPhase'] != RoundPhase.revealed.name) {
          return;
        }
        tx.update(matchRef, {
          'roundIndex': roundIndex + 1,
          'roundPhase': RoundPhase.answering.name,
          'roundAnswers': <String, String>{},
          'roundWinnerIds': <String>[],
          'roundShots': <Map<String, dynamic>>[],
          'roundDestroyedIds': <String>[],
          'roundStartedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.advanceSyncRound a esuat: $e');
    }
  }

  // ─── Quizz Tanks ────────────────────────────────────────────────────────

  /// Închide faza de răspuns a unei runde de Quizz Tanks și decide ce
  /// urmează: dacă a nimerit măcar unul, se trece la ȚINTIRE (cei care au
  /// răspuns corect își aleg victima); dacă n-a nimerit nimeni, se sare
  /// direct la faza de foc, cu runda goală — n-are cine trage.
  ///
  /// Apelabilă de ORICE client, ca la Higher & Lower — meciul nu are voie să
  /// se blocheze dacă pleacă tocmai hostul. Garda din capul tranzacției face
  /// ca, dintre cei (până la patru) clienți care încearcă simultan, exact
  /// unul să apuce să scrie: ceilalți văd faza deja schimbată și ies fără să
  /// facă nimic.
  ///
  /// Cine n-a apucat să răspundă în cele [tanksRoundSeconds] secunde e tratat
  /// exact ca cine a răspuns greșit: nu trage, și evită mult mai greu.
  Future<void> closeTanksAnswering({
    required String matchId,
    required int roundIndex,
    required String correctAnswer,
  }) async {
    final matchRef = _db.collection('matches').doc(matchId);
    final playerIds = (await matchRef.collection('players').get()).docs.map((d) => d.id).toList()..sort();
    if (playerIds.isEmpty) return;
    try {
      await _db.runTransaction((tx) async {
        final matchDoc = await tx.get(matchRef);
        final data = matchDoc.data();
        if (data == null || data['roundIndex'] != roundIndex || data['roundPhase'] != RoundPhase.answering.name) {
          return; // deja închisă de alt client
        }
        final answers = Map<String, dynamic>.from(data['roundAnswers'] as Map? ?? const {});

        final shooters = <String>[];
        var aliveCount = 0;
        for (final id in playerIds) {
          final doc = await tx.get(matchRef.collection('players').doc(id));
          if (!doc.exists || doc.data()!['eliminated'] == true) continue;
          aliveCount++;
          if (answers[id] == correctAnswer) shooters.add(id);
        }

        // Un singur jucător rămas în viață nu are pe cine ținti — ar rămâne
        // blocat pe ecranul de țintire până la plafonul de runde.
        if (shooters.isEmpty || aliveCount < 2) {
          final outOfRounds = roundIndex + 1 >= tanksMaxRounds;
          tx.update(matchRef, {
            'roundPhase': RoundPhase.revealed.name,
            'roundWinnerIds': shooters,
            'roundShots': <Map<String, dynamic>>[],
            'roundDestroyedIds': <String>[],
            if (aliveCount <= 1 || outOfRounds) 'status': MatchStatus.finished.name,
          });
          return;
        }

        tx.update(matchRef, {
          'roundPhase': RoundPhase.targeting.name,
          'roundWinnerIds': shooters,
          'roundTargets': <String, String>{},
          // cronometrul de țintire pornește ACUM, nu de la începutul rundei
          'roundStartedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.closeTanksAnswering a esuat: $e');
    }
  }

  /// Ținta aleasă de jucătorul curent, din ecranul de țintire.
  Future<void> submitTanksTarget({required String matchId, required String targetId}) {
    final me = currentPlayerId;
    return _paced(() => _db.collection('matches').doc(matchId).update({'roundTargets.$me': targetId}));
  }

  /// Trage efectiv: fiecare țintaș trimite UN proiectil spre ținta lui, se
  /// aruncă zarurile (vezi [rollTankShot]), se scad vieți, se marchează
  /// tancurile distruse.
  ///
  /// DE CE SE APLICĂ TOT SIMULTAN: daunele se calculează pe viața de la
  /// ÎNCEPUTUL rundei, nu pe măsură ce se scad. Așa doi jucători care se
  /// termină reciproc chiar mor amândoi, în loc ca cel care s-a nimerit
  /// primul în listă să scape. Consecința acceptată: daunele „în plus" peste
  /// viața rămasă a țintei se contorizează întregi la cel care a tras —
  /// contorul se numește daune FĂCUTE, iar el chiar atât a tras.
  ///
  /// Cine n-a apucat să aleagă în cele [tanksTargetSeconds] secunde NU pierde
  /// tragerea: țintește automat adversarul cu cea mai puțină viață. E și cea
  /// mai bună alegere evidentă, deci penalizarea pentru ezitare rămâne mică —
  /// dar tot pierzi dreptul de a decide, ceea ce contează când vrei să lovești
  /// pe cine face daune, nu pe cine e aproape mort.
  Future<void> resolveTanksRound({required String matchId, required int roundIndex}) async {
    final matchRef = _db.collection('matches').doc(matchId);
    // ordonate, ca lista de proiectile să iasă în aceeași ordine indiferent
    // ce client rezolvă runda — animația e mai ușor de urmărit așa.
    final playerIds = (await matchRef.collection('players').get()).docs.map((d) => d.id).toList()..sort();
    if (playerIds.isEmpty) return;
    try {
      await _db.runTransaction((tx) async {
        final matchDoc = await tx.get(matchRef);
        final data = matchDoc.data();
        if (data == null || data['roundIndex'] != roundIndex || data['roundPhase'] != RoundPhase.targeting.name) {
          return; // deja rezolvată de alt client - nimic de facut
        }
        final targets = Map<String, dynamic>.from(data['roundTargets'] as Map? ?? const {});
        // Lista țintașilor E lista celor care au răspuns corect, scrisă de
        // [closeTanksAnswering] — deci tot din ea se citește și cine e „în
        // gardă" la apărare, fără să mai comparăm răspunsurile a doua oară.
        final shooters = List<String>.from(data['roundWinnerIds'] as List? ?? const []);

        // TOATE citirile înaintea oricărei scrieri — cerință Firestore
        // pentru tranzacții, nu o preferință de stil.
        final docs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final id in playerIds) {
          docs[id] = await tx.get(matchRef.collection('players').doc(id));
        }

        final alive = <String>[];
        final hpAtStart = <String, int>{};
        for (final id in playerIds) {
          final doc = docs[id]!;
          if (!doc.exists) continue;
          final pData = doc.data()!;
          if (pData['eliminated'] == true) continue; // tanc deja distrus - spectator
          alive.add(id);
          hpAtStart[id] = pData['hp'] as int? ?? tanksMaxHp;
        }

        final rnd = Random();
        final shots = <Map<String, dynamic>>[];
        final incoming = {for (final id in alive) id: 0};
        final dealt = {for (final id in alive) id: 0};
        for (final shooter in alive) {
          if (!shooters.contains(shooter)) continue;
          final chosen = targets[shooter] as String?;
          final target = (chosen != null && chosen != shooter && alive.contains(chosen))
              ? chosen
              : _weakestEnemy(alive, hpAtStart, shooter);
          if (target == null) continue; // nu mai are pe cine trage
          // „În gardă" = a răspuns și el corect, adică e tot în lista
          // țintașilor — de-aia evită mult mai des.
          final roll = rollTankShot(targetAnsweredCorrectly: shooters.contains(target), rnd: rnd);
          shots.add(TankShot(byId: shooter, atId: target, hit: roll.hit, damage: roll.damage).toMap());
          if (roll.hit) {
            incoming[target] = incoming[target]! + roll.damage;
            dealt[shooter] = dealt[shooter]! + roll.damage;
          }
        }

        final destroyed = <String>[];
        var stillAlive = 0;
        for (final id in alive) {
          final newHp = hpAtStart[id]! - incoming[id]!;
          final isDestroyed = newHp <= 0;
          if (isDestroyed) {
            destroyed.add(id);
          } else {
            stillAlive++;
          }
          // scorul E totalul daunelor: restul aplicației (clasament final,
          // XP, statistici) citește `score`, iar cerința modului spune că
          // ordinea o dau daunele făcute. Vezi și MatchPlayer.damageDealt.
          final totalDealt = (docs[id]!.data()!['damageDealt'] as int? ?? 0) + dealt[id]!;
          tx.update(docs[id]!.reference, {
            'hp': isDestroyed ? 0 : newHp,
            'eliminated': isDestroyed,
            'damageDealt': totalDealt,
            'score': totalDealt,
          });
        }

        // Meciul se termină când rămâne cel mult un tanc în picioare (zero e
        // posibil: două tancuri se pot distruge reciproc în aceeași rundă) —
        // sau la plafonul de runde, ca o masă în care nimeni nu mai nimerește
        // nimic să nu curgă la nesfârșit.
        final outOfRounds = roundIndex + 1 >= tanksMaxRounds;
        tx.update(matchRef, {
          'roundPhase': RoundPhase.revealed.name,
          'roundShots': shots,
          'roundDestroyedIds': destroyed,
          if (stillAlive <= 1 || outOfRounds) 'status': MatchStatus.finished.name,
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.resolveTanksRound a esuat: $e');
    }
  }

  /// Ținta implicită a unui țintaș care n-a apucat să aleagă: adversarul cu
  /// cea mai puțină viață. La egalitate decide uid-ul, ca alegerea să fie
  /// aceeași oricare client ar rezolva runda.
  static String? _weakestEnemy(List<String> alive, Map<String, int> hp, String shooter) {
    String? best;
    for (final id in alive) {
      if (id == shooter) continue;
      if (best == null || hp[id]! < hp[best]! || (hp[id]! == hp[best]! && id.compareTo(best) < 0)) {
        best = id;
      }
    }
    return best;
  }

  Future<void> sendChatMessage({required String matchId, required String senderName, required String text}) async {
    final me = currentPlayerId;
    await _paced(() => _db.collection('matches').doc(matchId).collection('chat').add(
          ChatMessage(id: '', senderId: me, senderName: senderName, text: text).toMap(),
        ));
  }

  Stream<List<ChatMessage>> watchChat(String matchId) {
    return _db
        .collection('matches')
        .doc(matchId)
        .collection('chat')
        .orderBy('sentAt')
        .limitToLast(100)
        .snapshots()
        .map((s) => s.docs.map(ChatMessage.fromDoc).toList());
  }

  /// Părăsește meciul — dacă GAZDA pleacă în timp ce meciul e încă în lobby,
  /// ștergem camera întreagă (players + chat). Ștergerea e și semnalul prin
  /// care ceilalți află: documentul dispare, iar lobby-ul lor îi scoate afară
  /// cu mesajul „gazda a plecat" (vezi RoomLobbyScreen — fără asta rămâneau
  /// blocați într-o cameră care nu mai exista, fără Start și invizibilă pentru
  /// oricine altcineva); altfel propriul jucător e scos, iar
  /// dacă era ultimul rămas, ștergem și noi camera întreagă (players + chat
  /// + documentul meciului) — altfel meciurile terminate s-ar acumula la
  /// nesfârșit în Firestore, fără niciun cleanup automat (nu avem Cloud
  /// Functions/TTL configurate).
  Future<void> leaveMatch(String matchId) async {
    final me = currentPlayerId;
    final matchRef = _db.collection('matches').doc(matchId);
    final matchDoc = await matchRef.get();
    if (!matchDoc.exists) return;
    final info = MatchInfo.fromDoc(matchDoc);
    if (info.hostId == me && info.status == MatchStatus.lobby) {
      await _deleteMatch(matchRef);
      return;
    }
    await matchRef.collection('players').doc(me).delete();
    final remaining = await matchRef.collection('players').limit(1).get();
    if (remaining.docs.isEmpty) {
      await _deleteMatch(matchRef);
    }
  }

  Future<void> _deleteMatch(DocumentReference<Map<String, dynamic>> matchRef) async {
    final players = await matchRef.collection('players').get();
    final chat = await matchRef.collection('chat').get();
    final batch = _db.batch();
    for (final d in players.docs) {
      batch.delete(d.reference);
    }
    for (final d in chat.docs) {
      batch.delete(d.reference);
    }
    batch.delete(matchRef);
    await batch.commit();
  }

  // ─── Revanșă ─────────────────────────────────────────────────────────────

  /// Lansează o cerere de revanșă către EXACT jucătorii de la masa tocmai
  /// terminată — [participants] vine din clasamentul deja încărcat de
  /// MultiplayerResultsScreen (masa veche poate fi între timp ștearsă de
  /// [leaveMatch], vezi [RematchOffer]). Doc id-ul e chiar [matchId], singurul
  /// id pe care toți foștii participanți îl cunosc deja. `set` (nu `add`) —
  /// o cerere refuzată/anulată poate fi reîncercată, rescriind același doc.
  Future<void> offerRematch({
    required String matchId,
    required MatchGameMode gameMode,
    required int stake,
    required List<RematchParticipant> participants,
  }) {
    final me = currentPlayerId;
    return _paced(() => _db.collection('rematch_offers').doc(matchId).set(RematchOffer(
          matchId: matchId,
          hostId: me,
          gameMode: gameMode,
          stake: stake,
          participants: participants,
          acceptedIds: [me],
          status: 'pending',
        ).toMap()));
  }

  Stream<RematchOffer?> watchRematchOffer(String matchId) => _db
      .collection('rematch_offers')
      .doc(matchId)
      .snapshots()
      .map((d) => d.exists ? RematchOffer.fromDoc(d) : null);

  Future<void> acceptRematchOffer(String matchId) => _paced(() => _db
      .collection('rematch_offers')
      .doc(matchId)
      .update({'acceptedIds': FieldValue.arrayUnion([currentPlayerId])}));

  /// Refuzul unui SINGUR jucător anulează cererea pentru toată lumea — gazda
  /// vede cine a refuzat și poate încerca din nou (vezi [offerRematch]).
  Future<void> declineRematchOffer(String matchId) => _paced(() => _db
      .collection('rematch_offers')
      .doc(matchId)
      .update({'status': 'cancelled', 'declinedBy': currentPlayerId}));

  Future<void> cancelRematchOffer(String matchId) =>
      _db.collection('rematch_offers').doc(matchId).delete();

  /// Apelată DOAR de clientul gazdei, în clipa în care vede că toți
  /// participanții au acceptat — creează camera nouă cu toți jucătorii deja
  /// așezați (scrise direct, fără să mai treacă unul câte unul prin
  /// [_joinRoomDoc]) și o pornește imediat, fără să mai aștepte în lobby:
  /// gazda a cerut deja revanșa, iar toți ceilalți au acceptat-o explicit —
  /// n-are ce să mai decidă nimeni în plus apăsând START.
  Future<String> launchRematch(RematchOffer offer) async {
    final ref = _db.collection('matches').doc();
    final host = offer.participants.firstWhere(
      (p) => p.id == offer.hostId,
      orElse: () => RematchParticipant(id: offer.hostId, name: '?', avatarSeed: offer.hostId),
    );
    final info = MatchInfo(
      id: ref.id,
      mode: MatchMode.private,
      code: _randomCode(),
      status: MatchStatus.lobby,
      hostId: offer.hostId,
      hostName: host.name,
      hostPhotoUrl: host.photoUrl,
      hostAvatarStyle: host.avatarStyle,
      gameMode: offer.gameMode,
      stake: offer.stake,
    );
    final batch = _db.batch();
    batch.set(ref, info.toMap());
    for (final p in offer.participants) {
      batch.set(
        ref.collection('players').doc(p.id),
        MatchPlayer(
          id: p.id,
          name: p.name,
          avatarSeed: p.avatarSeed,
          photoUrl: p.photoUrl,
          score: 0,
          isHost: p.id == offer.hostId,
          bet: offer.stake,
          avatarStyle: p.avatarStyle,
        ).toMap(),
      );
    }
    await batch.commit();
    await startMatch(ref.id);
    await _db.collection('rematch_offers').doc(offer.matchId).update({
      'status': 'started',
      'newMatchId': ref.id,
    });
    return ref.id;
  }

  // ─── Meci (comun ambelor fluxuri) ───────────────────────────────────────

  Stream<MatchInfo> watchMatch(String matchId) => _db.collection('matches').doc(matchId).snapshots().map(MatchInfo.fromDoc);

  Stream<List<MatchPlayer>> watchPlayers(String matchId) {
    return _db.collection('matches').doc(matchId).collection('players').snapshots().map(
          (s) => s.docs.map(MatchPlayer.fromDoc).toList(),
        );
  }

  /// Publică scorul curent. ATENȚIE la cât de des se apelează: fiecare
  /// scriere e livrată TUTUROR celor care ascultă masa, deci costul în citiri
  /// Firestore crește cu PĂTRATUL numărului de jucători. Scris la fiecare
  /// răspuns, un meci de 20 de oameni consuma ~4.000 de citiri — adică ~12
  /// meciuri pe zi din cota gratuită, împărțită cu tot restul aplicației.
  /// De-aia modul Clasic îl cheamă exact de două ori pe meci (la jumătatea
  /// minutului și la final), nu la fiecare răspuns.
  Future<void> updateScore({required String matchId, required int score}) {
    return _paced(() => _db.collection('matches').doc(matchId).collection('players').doc(currentPlayerId).update({'score': score}));
  }

  /// Scorul FINAL, plus semnalul că jucătorul și-a încheiat minutul — vezi
  /// [MatchPlayer.finished] pentru de ce contează la decontare.
  Future<void> finishWithScore({required String matchId, required int score}) {
    return _paced(() => _db
        .collection('matches')
        .doc(matchId)
        .collection('players')
        .doc(currentPlayerId)
        .update({'score': score, 'finished': true}));
  }

  // ─── Matchmaking public ─────────────────────────────────────────────────

  /// La Join Online nu există cineva care să creeze camera, deci nu are cine
  /// alege miza: toată lumea intră cu [publicMatchStake], scrisă aici odată cu
  /// jucătorul și copiată apoi în documentul de meci de cel care formează
  /// perechea (vezi [attemptFormMatch]).
  Future<void> joinMatchmakingQueue({
    required String displayName,
    String? photoUrl,
    String avatarStyle = '',
  }) async {
    await ensureInitialized();
    final me = currentPlayerId;
    await _db.collection('matchmaking_queue').doc(me).set({
      'name': displayName,
      'avatarSeed': me,
      'photoUrl': photoUrl,
      'avatarStyle': avatarStyle,
      'matchId': null,
      'bet': publicMatchStake,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Streamul propriei intrări din coadă — când un alt client (liderul)
  /// formează meciul, îi scrie `matchId` aici; UI-ul ascultă asta ca să
  /// navigheze automat, fără sa aiba nevoie de Cloud Functions.
  Stream<String?> watchOwnQueueEntry() {
    final me = currentPlayerId;
    return _db.collection('matchmaking_queue').doc(me).snapshots().map((d) => d.data()?['matchId'] as String?);
  }

  Future<void> leaveQueue() async {
    await _db.collection('matchmaking_queue').doc(currentPlayerId).delete();
  }

  /// Doar clientul cel mai "vechi" din coadă (primul intrat) încearcă să
  /// formeze un meci — reduce coliziunile, deși tranzacția de mai jos e
  /// oricum sigură chiar dacă doi clienți ar încerca simultan. Formează
  /// meciul DOAR când există [matchmakingOpponentCount] jucători reali în
  /// coadă — fără completare cu boți, se așteaptă cât e nevoie de un
  /// adversar real.
  Future<String?> attemptFormMatch() async {
    final me = currentPlayerId;
    final queueSnap = await _db.collection('matchmaking_queue').orderBy('joinedAt').limit(matchmakingOpponentCount).get();
    if (queueSnap.docs.isEmpty || queueSnap.docs.first.id != me) return null;
    if (queueSnap.docs.length < matchmakingOpponentCount) return null;

    final candidates = queueSnap.docs;
    final matchRef = _db.collection('matches').doc();

    try {
      await _db.runTransaction((tx) async {
        // re-verifica in tranzactie ca niciun candidat n-a fost deja
        // "furat" de o alta tranzactie concurenta intre timp.
        for (final c in candidates) {
          final fresh = await tx.get(c.reference);
          if (!fresh.exists || fresh.data()?['matchId'] != null) {
            throw StateError('candidat deja revendicat');
          }
        }

        final info = MatchInfo(
          id: matchRef.id,
          mode: MatchMode.public,
          status: MatchStatus.playing,
          hostId: me,
          stake: publicMatchStake,
        );
        tx.set(matchRef, info.toMap());

        for (final c in candidates) {
          final data = c.data();
          tx.set(
            matchRef.collection('players').doc(c.id),
            MatchPlayer(
              id: c.id,
              name: data['name'] as String? ?? '?',
              avatarSeed: data['avatarSeed'] as String? ?? c.id,
              photoUrl: data['photoUrl'] as String?,
              avatarStyle: data['avatarStyle'] as String? ?? '',
              score: 0,
              isHost: c.id == me,
              bet: data['bet'] as int? ?? publicMatchStake,
            ).toMap(),
          );
          tx.update(c.reference, {'matchId': matchRef.id});
        }
      });
      return matchRef.id;
    } catch (_) {
      // un alt client a format deja meciul intre timp cu acesti candidati -
      // e ok, ascultatorul propriei intrari din coada va prelua matchId-ul.
      return null;
    }
  }
}
