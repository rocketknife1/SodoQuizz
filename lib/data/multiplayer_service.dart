import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/betting.dart';
import '../core/electric_chair.dart';
import '../core/rock_paper_scissors.dart';
import '../core/lang.dart';
import '../core/multiplayer_round.dart';
import '../core/obby.dart';
import '../core/powerups.dart';
import '../core/tanks.dart';
import '../models/multiplayer_models.dart';
import 'player_profile_service.dart';

/// Aruncată când Firebase nu e (încă) configurat corect — [firebase_options.dart]
/// are valori placeholder până userul pune un proiect real. UI-ul o prinde și
/// arată un fallback prietenos, nu lasă aplicația să crape.
class MultiplayerUnavailableException implements Exception {
  final String message;
  const MultiplayerUnavailableException([this.message = 'Multiplayer indisponibil momentan.']);
  @override
  String toString() => message;
}

/// Capacitatea maximă a unei camere private (Create Room / Join with Code)
/// pentru [MatchGameMode.classic] și [MatchGameMode.higherLower] — celelalte
/// moduri au propriul plafon (vezi [maxPlayersForMode]).
///
/// Coborât de la 11 la 10 la cererea explicită a userului: toate modurile
/// trebuie să accepte ACELAȘI plafon de 10, ca regula să fie simplă și
/// unică, nu un număr diferit memorat separat pentru fiecare mod. Rândul de
/// avatare de sus rămâne lizibil fiindcă derulează orizontal, iar traficul
/// spre Firestore rămâne sub control cu sincronizarea rară de scor din
/// MultiplayerMatchScreen. Matchmaking-ul public rămâne 1 vs 1 — o coadă
/// care așteaptă 10 străini simultan nu s-ar completa niciodată.
const int matchPlayerCount = 10;

/// Câți jucători încap într-o cameră, după modul ei de joc. Toate modurile
/// folosesc ACELAȘI plafon (10, vezi fiecare constantă proprie mai jos) —
/// funcția rămâne un `switch` pe mod, nu o singură constantă globală, ca
/// fiecare mod să poată avea în continuare motivul lui documentat separat
/// (vezi core/tanks.dart, core/obby.dart, core/electric_chair.dart).
int maxPlayersForMode(MatchGameMode mode) => switch (mode) {
      MatchGameMode.quizzTanks => tanksPlayerCount,
      MatchGameMode.obby => obbyMaxPlayers,
      MatchGameMode.electricChair => electricChairPlayerCount,
      MatchGameMode.classic || MatchGameMode.higherLower || MatchGameMode.rockPaperScissors => matchPlayerCount,
    };

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
/// scorați automat ca greșit — comun tuturor modurilor cu rundă
/// sincronizată, vezi core/multiplayer_round.dart. (Era 15s, diferit de
/// celelalte trei moduri, deja ajunse la 12s prin ajustări separate — userul
/// a cerut explicit ACELAȘI timp peste tot; NU mai e legat de mini-jocul
/// solo, higher_lower_screen.dart, care oricum rulase de mult pe 10s, nu 15.)
const int higherLowerRoundSeconds = sharedRoundAnswerSeconds;

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
      playerIds: [me], // vezi MatchInfo.playerIds — gazda e singura la masa
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
    // Fara asta, `firestore.rules` m-ar refuza la prima scriere de rundă: cine
    // nu e in playerIds nu poate atinge documentul meciului. E singura
    // scriere in care cineva se adauga singur, iar regula o permite EXACT in
    // forma asta (doar propriul uid, doar prin arrayUnion).
    await _paced(() => doc.reference.update({
          'playerIds': FieldValue.arrayUnion([me]),
        }));
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
        // Evenimentul rundei se recalculează AICI, din aceeași funcție pură
        // (core/powerups.dart) pe care o citește și ecranul pentru banner —
        // niciun client nou de scris în Firestore, toți ajung la același
        // rezultat din matchId+roundIndex. Vezi doc-ul din powerups.dart
        // pentru de ce modelul ăsta de încredere e deja cel al proiectului.
        final event = roundEventFor(matchId: matchId, roundIndex: roundIndex, gameModeId: 'higherLower');
        final pointsThisRound = event == RoundEvent.doubleOrNothing ? higherLowerPointsPerWin * 2 : higherLowerPointsPerWin;
        final winnerIds = <String>[];
        var stillActive = 0;
        for (final doc in playerDocs) {
          if (!doc.exists) continue;
          final pData = doc.data()!;
          if (pData['eliminated'] == true) continue; // deja eliminat - spectator, nu joacă runda
          final correct = correctGuess == null || answers[doc.id] == correctGuess;
          if (correct) {
            winnerIds.add(doc.id);
            tx.update(doc.reference, {'score': (pData['score'] as int? ?? 0) + pointsThisRound});
            stillActive++;
          } else {
            // Moarte subită: o greșeală elimină direct, indiferent de câte
            // pâini avea acumulate până acum — „fără a doua șansă runda asta".
            final breads = (pData['breads'] as int? ?? 0) + 1;
            final eliminated = event == RoundEvent.suddenDeath || breads >= higherLowerMaxBreads;
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
          'roundPowerUps': <String, String>{},
          'roundStartedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.advanceSyncRound a esuat: $e');
    }
  }

  // ─── Piatră-Hârtie-Foarfecă ─────────────────────────────────────────────

  /// Rezolvă runda de piatră-hârtie-foarfecă — poate fi apelată de ORICE
  /// client, cu aceeași gardă anti-cursă ca [resolveHigherLowerRound].
  ///
  /// Fără eliminare, fără „pâini": toți joacă fiecare rundă. Fiecare jucător
  /// primește `+1` pentru fiecare adversar pe care îl bate (vezi
  /// core/rock_paper_scissors.dart `rpsRoundScores`). Meciul se termină când
  /// cineva atinge [rpsTargetScore] — restul clasamentului se face după scor
  /// în [MultiplayerResultsScreen], la fel ca la celelalte moduri cu miză.
  ///
  /// Jucătorii care n-au apucat să aleagă (AFK) au alegerea goală: nu bat pe
  /// nimeni și sunt bătuți de toți — la fel ca un răspuns greșit la
  /// Higher & Lower, doar fără eliminare.
  Future<void> resolveRockPaperScissorsRound({
    required String matchId,
    required int roundIndex,
  }) async {
    final matchRef = _db.collection('matches').doc(matchId);
    final playerIds = (await matchRef.collection('players').get()).docs.map((d) => d.id).toList();
    if (playerIds.isEmpty) return;
    try {
      await _db.runTransaction((tx) async {
        final matchDoc = await tx.get(matchRef);
        final data = matchDoc.data();
        if (data == null || data['roundIndex'] != roundIndex || data['roundPhase'] != RoundPhase.answering.name) {
          return; // deja rezolvată de alt client
        }
        final answers = Map<String, dynamic>.from(data['roundAnswers'] as Map? ?? const {});
        final choices = {for (final id in playerIds) id: (answers[id] as String?) ?? ''};
        final gained = rpsRoundScores(choices);

        final playerDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final id in playerIds) {
          playerDocs.add(await tx.get(matchRef.collection('players').doc(id)));
        }
        final newScores = <String, int>{};
        final winnerIds = <String>[];
        for (final doc in playerDocs) {
          if (!doc.exists) continue;
          final pData = doc.data()!;
          final add = gained[doc.id] ?? 0;
          final total = (pData['score'] as int? ?? 0) + add;
          newScores[doc.id] = total;
          if (add > 0) winnerIds.add(doc.id);
          if (add != 0) tx.update(doc.reference, {'score': total});
        }
        // Meciul se termina cand: cineva atinge pragul (rpsTargetScore), SAU
        // a mai ramas cel mult un jucator (ceilalti au plecat) — fara asta
        // ultimul ramas ar fi blocat pe ecran la infinit, cu miza pierduta —
        // SAU s-a atins plafonul de runde (toti aleg mereu la fel = 0 puncte
        // pe runda, deci fara plafon meciul n-ar avea nicio garantie de
        // terminare, spre deosebire de HL unde painile forteaza eliminare).
        final activePlayers = playerDocs.where((d) => d.exists).length;
        final outOfRounds = roundIndex + 1 >= rpsMaxRounds;
        final matchOver = rpsWinnerReached(newScores) || activePlayers <= 1 || outOfRounds;
        tx.update(matchRef, {
          'roundPhase': RoundPhase.revealed.name,
          'roundWinnerIds': winnerIds,
          if (matchOver) 'status': MatchStatus.finished.name,
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.resolveRockPaperScissorsRound a esuat: $e');
    }
  }

  // ─── Obby ───────────────────────────────────────────────────────────────

  /// Închide faza de răspuns și trece în faza de ALEGERE a plăcii — aceeași
  /// structură ca [closeTanksAnswering], inclusiv garda anti-cursă: dintre
  /// clienții care încearcă simultan, exact unul apucă să scrie.
  ///
  /// Un răspuns corect NU înseamnă automat un obstacol trecut: doar te
  /// califică să alegi o placă. Progresul se
  /// acordă abia în [resolveObbyChoices].
  ///
  /// Tot aici se STINGE [MatchPlayer.nextQuestionBonus] pentru toți cei
  /// evaluați: bonusul se consumă la întrebarea la care s-a aplicat,
  /// indiferent dacă a fost nimerită sau nu. Se face în aceeași trecere care
  /// oricum citește fiecare jucător, deci nu costă nicio citire în plus.
  ///
  /// Dacă nimeni n-a răspuns corect, faza de alegere se sare complet — exact
  /// cum [closeTanksAnswering] sare peste țintire când nimeni n-a nimerit
  /// întrebarea.
  Future<void> closeObbyAnswering({
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
        // Firestore cere ca TOATE citirile unei tranzacții să se termine
        // înainte de orice scriere — de-aia colectăm toate documentele
        // aici, într-o singură trecere, și scriem abia mai jos, într-o a
        // doua trecere. Exact tiparul din resolveHigherLowerRound.
        final playerDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final id in playerIds) {
          playerDocs.add(await tx.get(matchRef.collection('players').doc(id)));
        }
        final winnerIds = <String>[];
        final clearedPerPlayer = <int>[];
        for (final doc in playerDocs) {
          if (!doc.exists) continue;
          final pData = doc.data()!;
          final already = pData['obstaclesCleared'] as int? ?? 0;
          clearedPerPlayer.add(already);
          // un personaj deja ajuns la final nu mai joacă runda - stă acolo,
          // spectator, până se încheie meciul pentru toată lumea.
          if (already >= obbyObstacleCount) continue;
          // bonusul rundei tocmai încheiate se stinge acum, câștigată sau nu
          if (pData['nextQuestionBonus'] == true) {
            tx.update(doc.reference, {'nextQuestionBonus': false});
          }
          if (answers[doc.id] == correctAnswer) winnerIds.add(doc.id);
        }

        // Nimeni n-a răspuns corect: n-are cine alege, sărim direct la
        // deznodământ (o rundă în care pur și simplu nu avansează nimeni).
        if (winnerIds.isEmpty) {
          tx.update(matchRef, {
            'roundPhase': RoundPhase.revealed.name,
            'roundWinnerIds': <String>[],
            'roundPlatformChoices': <String, int>{},
            if (obbyMatchIsOver(roundIndex: roundIndex, obstaclesClearedPerPlayer: clearedPerPlayer))
              'status': MatchStatus.finished.name,
          });
          return;
        }

        tx.update(matchRef, {
          'roundPhase': RoundPhase.choosing.name,
          'roundWinnerIds': winnerIds,
          'roundPlatformChoices': <String, int>{},
          // cronometrul de alegere pornește ACUM, nu de la începutul rundei
          'roundStartedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.closeObbyAnswering a esuat: $e');
    }
  }

  /// Placa aleasă de jucătorul curent, din faza de alegere.
  Future<void> submitObbyChoice({required String matchId, required int platformIndex}) {
    final me = currentPlayerId;
    return _paced(() =>
        _db.collection('matches').doc(matchId).update({'roundPlatformChoices.$me': platformIndex}));
  }

  /// Sare efectiv: pentru fiecare jucător calificat se compară placa aleasă cu
  /// cea falsă (calculată determinist, vezi [obbyFakePlatformIndex] — nu se
  /// citește de nicăieri, deci nu costă nicio scriere în plus).
  ///
  /// Cine nimerește o placă bună trece obstacolul, ia punctele și pleacă cu
  /// [MatchPlayer.nextQuestionBonus] aprins pentru runda următoare. Cine
  /// nimerește placa falsă — sau n-a apucat să aleagă deloc — rămâne pe loc,
  /// exact ca cine răspunde greșit: fără eliminare, doar fără progres.
  ///
  /// [roundWinnerIds] e luat ca sursă de adevăr pentru „cine avea drept să
  /// aleagă", scris deja de [closeObbyAnswering] — aceeași graniță de
  /// încredere ca între [closeTanksAnswering] și [resolveTanksRound].
  ///
  /// Aici se aplică și cele două evenimente de rundă din PLAN_DE_VIITOR.md
  /// (punctul 3) — [obbyIsDoubleRound] (cine sare azi trece DOUĂ obstacole)
  /// și [obbyIsComebackRound] (ultimul din clasament, la penultima rundă,
  /// pleacă mereu cu bonus la runda finală, indiferent cum îi iese placa
  /// asta). Ambele determinate client-side, fără niciun câmp nou în
  /// Firestore — la fel ca placa falsă.
  Future<void> resolveObbyChoices({required String matchId, required int roundIndex}) async {
    final matchRef = _db.collection('matches').doc(matchId);
    final playerIds = (await matchRef.collection('players').get()).docs.map((d) => d.id).toList()..sort();
    if (playerIds.isEmpty) return;
    final isDouble = obbyIsDoubleRound(matchId: matchId, roundIndex: roundIndex);
    final isComeback = obbyIsComebackRound(roundIndex: roundIndex);
    final event = roundEventFor(matchId: matchId, roundIndex: roundIndex, gameModeId: 'obby');
    try {
      await _db.runTransaction((tx) async {
        final matchDoc = await tx.get(matchRef);
        final data = matchDoc.data();
        if (data == null || data['roundIndex'] != roundIndex || data['roundPhase'] != RoundPhase.choosing.name) {
          return; // deja rezolvată de alt client - nimic de facut
        }
        final rawChoices = data['roundPlatformChoices'] as Map? ?? const {};
        final winnerIds = List<String>.from(data['roundWinnerIds'] as List? ?? const []);
        final activePowerUps = Map<String, dynamic>.from(data['roundPowerUps'] as Map? ?? const {});
        final sabotaged = Map<String, dynamic>.from(data['roundSabotage'] as Map? ?? const {});
        PowerUp powerUpOf(String id) {
          final raw = activePowerUps[id] as String?;
          if (raw == null) return PowerUp.none;
          return PowerUp.values.firstWhere((p) => p.name == raw, orElse: () => PowerUp.none);
        }

        // Aceeasi regula: toate citirile inainte de orice scriere.
        final playerDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final id in playerIds) {
          playerDocs.add(await tx.get(matchRef.collection('players').doc(id)));
        }

        // Cine e pe ultimul loc ÎNAINTE de runda asta — folosit doar dacă
        // [isComeback], dar calculat oricum (ieftin, câteva perechi în
        // memorie) ca să nu mai fie nevoie de o a treia trecere prin docs.
        final lastPlaceIds = isComeback
            ? obbyLastPlaceIds([
                for (final doc in playerDocs)
                  if (doc.exists) (doc.id, doc.data()!['obstaclesCleared'] as int? ?? 0),
              ]).toSet()
            : const <String>{};

        final clearedPerPlayer = <int>[];
        for (final doc in playerDocs) {
          if (!doc.exists) continue;
          final id = doc.id;
          final pData = doc.data()!;
          final already = pData['obstaclesCleared'] as int? ?? 0;
          final comebackBonus = lastPlaceIds.contains(id);

          if (!winnerIds.contains(id) || already >= obbyObstacleCount) {
            clearedPerPlayer.add(already);
            // N-a avut dreptul să aleagă runda asta (a răspuns greșit sau a
            // terminat deja pista), dar tot era ultimul: primește oricum
            // bonusul pentru runda finală — "a doua șansă" nu depinde de
            // cum a ieșit runda asta, altfel n-ar mai fi o șansă reală.
            if (comebackBonus && already < obbyObstacleCount) {
              tx.update(doc.reference, {'nextQuestionBonus': true});
            }
            continue;
          }

          final chosen = (rawChoices[id] as num?)?.toInt();
          // Jetpack-ul sare peste orice altă regulă a plăcilor — „treci
          // obstacolul automat", indiferent ce a ales sau dacă a fost
          // sabotat. Altfel, siguranța vine din furtuna de asteroizi (DOUĂ
          // plăci false) sau din regula normală (UNA falsă), iar sabotajul
          // unui adversar forțează căderea chiar și pe o placă bună aleasă
          // corect.
          final hasJetpack = powerUpOf(id) == PowerUp.jetpack;
          final safe = hasJetpack ||
              (!sabotaged.containsKey(id) &&
                  (event == RoundEvent.asteroidStorm
                      ? chosen != null &&
                          chosen == obbyStormSafePlatformIndex(matchId: matchId, roundIndex: roundIndex, playerId: id)
                      : obbyChoiceIsSafe(
                          chosenIndex: chosen,
                          fakeIndex: obbyFakePlatformIndex(matchId: matchId, roundIndex: roundIndex, playerId: id),
                        )));
          if (!safe) {
            clearedPerPlayer.add(already);
            if (comebackBonus) tx.update(doc.reference, {'nextQuestionBonus': true});
            continue;
          }

          // Runda dublă (sau gravitație mică — același efect, vezi
          // RoundEvent.lowGravity): obstacolul de azi valorează 2, nu 1 —
          // plafonat la ultimul obstacol, ca să nu treacă "peste" pistă.
          // Punctele urmează exact câte obstacole s-au acordat efectiv, nu
          // un 2x orb, altfel cineva aproape de final ar fi fost plătit
          // dublu pentru un singur obstacol rămas.
          final gained = min((isDouble || event == RoundEvent.lowGravity) ? 2 : 1, obbyObstacleCount - already);
          final cleared = already + gained;
          clearedPerPlayer.add(cleared);
          tx.update(doc.reference, {
            'obstaclesCleared': cleared,
            'score': (pData['score'] as int? ?? 0) + obbyPointsPerObstacle * gained,
            'nextQuestionBonus': true,
          });
        }

        tx.update(matchRef, {
          'roundPhase': RoundPhase.revealed.name,
          if (obbyMatchIsOver(roundIndex: roundIndex, obstaclesClearedPerPlayer: clearedPerPlayer))
            'status': MatchStatus.finished.name,
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.resolveObbyChoices a esuat: $e');
    }
  }

  /// Trece la runda următoare — varianta proprie a lui Obby, fiindcă runda lui
  /// are un câmp în plus de golit ([MatchInfo.roundPlatformChoices]) și n-are
  /// niciun rost să atingă câmpurile de Quizz Tanks.
  ///
  /// Ținut separat de [advanceSyncRound] INTENȚIONAT: acela e apelat de Higher
  /// & Lower și Quizz Tanks, iar Obby nu mai are motive să împartă aceeași
  /// implementare cu ele de când runda lui are trei pași, nu doi.
  Future<void> advanceObbyRound({required String matchId, required int roundIndex}) async {
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
          'roundPlatformChoices': <String, int>{},
          'roundPowerUps': <String, String>{},
          'roundSabotage': <String, bool>{},
          'roundStartedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.advanceObbyRound a esuat: $e');
    }
  }

  /// Activează [PowerUp.jetpack] pentru runda curentă — [resolveObbyChoices]
  /// îl citește de pe `roundPowerUps`, la fel ca mega rachetă/scut la Quizz
  /// Tanks și Scaunul Electric.
  Future<void> submitObbyPowerUp({required String matchId, required PowerUp powerUp}) {
    final me = currentPlayerId;
    return _paced(() => _db.collection('matches').doc(matchId).update({'roundPowerUps.$me': powerUp.name}));
  }

  /// [PowerUp.sabotage]: „îi muți cuiva o placă bună în placă falsă" —
  /// ținta se alege AUTOMAT (cine conduce cursa acum, exclus eu însumi),
  /// nu manual, din același motiv ca [useElectricChairAllyShield]: evită o
  /// fereastră nouă de alegere doar pentru un power-up, iar liderul e oricum
  /// ținta evidentă a unui sabotaj. Efectul se anulează dacă victima are ea
  /// însăși [PowerUp.jetpack] runda asta — vezi [resolveObbyChoices].
  Future<void> useObbySabotage({required String matchId}) async {
    final me = currentPlayerId;
    final matchRef = _db.collection('matches').doc(matchId);
    try {
      await _db.runTransaction((tx) async {
        final playersSnap = await matchRef.collection('players').get();
        String? leaderId;
        var leaderCleared = -1;
        for (final doc in playersSnap.docs) {
          if (doc.id == me) continue;
          final data = doc.data();
          final cleared = data['obstaclesCleared'] as int? ?? 0;
          if (cleared >= obbyObstacleCount) continue; // deja la final - nimic de sabotat
          if (cleared > leaderCleared || (cleared == leaderCleared && doc.id.compareTo(leaderId ?? '') < 0)) {
            leaderCleared = cleared;
            leaderId = doc.id;
          }
        }
        if (leaderId == null) return;
        tx.update(matchRef, {'roundSabotage.$leaderId': true});
      });
    } catch (e) {
      debugPrint('MultiplayerService.useObbySabotage a esuat: $e');
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
        // „Reparații pe teren": toți cei încă în viață primesc puțin HP
        // înapoi ÎNAINTE de foc — vezi core/tanks.dart tanksFieldRepairsHeal.
        final fieldRepairs = roundEventFor(matchId: matchId, roundIndex: roundIndex, gameModeId: 'quizzTanks') == RoundEvent.fieldRepairs;

        // TOATE citirile înaintea oricărei scrieri — cerință Firestore
        // pentru tranzacții (vezi aceeași notă mai jos, la resolveTanksRound).
        final playerDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final id in playerIds) {
          playerDocs.add(await tx.get(matchRef.collection('players').doc(id)));
        }

        final shooters = <String>[];
        var aliveCount = 0;
        for (final doc in playerDocs) {
          if (!doc.exists || doc.data()!['eliminated'] == true) continue;
          aliveCount++;
          if (answers[doc.id] == correctAnswer) shooters.add(doc.id);
          if (fieldRepairs) {
            final hp = doc.data()!['hp'] as int? ?? tanksMaxHp;
            tx.update(doc.reference, {'hp': (hp + tanksFieldRepairsHeal).clamp(0, tanksMaxHp)});
          }
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
  ///
  /// [secondTargetId] se dă doar la [PowerUp.doubleShot]: cele două ținte se
  /// scriu împreună, despărțite prin [tanksTargetSeparator]
  /// (`"tintaA|tintaB"`), ca [resolveTanksRound] să le poată despărți. Poate
  /// fi egal cu [targetId] — atunci ambele proiectile lovesc aceeași țintă,
  /// o singură lovitură cu daune mărite.
  Future<void> submitTanksTarget({
    required String matchId,
    required String targetId,
    String? secondTargetId,
  }) {
    final me = currentPlayerId;
    final value = secondTargetId == null ? targetId : '$targetId$tanksTargetSeparator$secondTargetId';
    return _paced(() => _db.collection('matches').doc(matchId).update({'roundTargets.$me': value}));
  }

  /// Activează un power-up pentru runda curentă — citit de [resolveTanksRound]
  /// la calculul loviturilor (mega rachetă, scut). O singură dată pe rundă,
  /// scris pe câmp separat de `roundTargets`, ca activarea să nu depindă de
  /// ordinea în care ajung cele două scrieri.
  Future<void> submitTanksPowerUp({required String matchId, required PowerUp powerUp}) {
    final me = currentPlayerId;
    return _paced(() => _db.collection('matches').doc(matchId).update({'roundPowerUps.$me': powerUp.name}));
  }

  /// [PowerUp.allyShield] la Quizz Tanks: apără AUTOMAT tancul cel mai
  /// slăbit (cel mai puțin HP), nu unul ales manual — exact convenția de la
  /// [useElectricChairAllyShield] (fără fereastră nouă de alegere doar
  /// pentru un power-up). Ține 2 runde ([powerUpDurationRounds]); citit din
  /// `shields.<id>` de [resolveTanksRound], care blochează toate loviturile
  /// din rundă ca scutul propriu.
  Future<void> useTanksAllyShield({required String matchId, required int roundIndex}) async {
    final me = currentPlayerId;
    final matchRef = _db.collection('matches').doc(matchId);
    try {
      await _db.runTransaction((tx) async {
        final playersSnap = await matchRef.collection('players').get();
        String? weakestId;
        var weakestHp = 1 << 30;
        for (final doc in playersSnap.docs) {
          if (doc.id == me) continue;
          final data = doc.data();
          if (data['eliminated'] == true) continue;
          final hp = data['hp'] as int? ?? tanksMaxHp;
          if (hp < weakestHp || (hp == weakestHp && doc.id.compareTo(weakestId ?? '') < 0)) {
            weakestHp = hp;
            weakestId = doc.id;
          }
        }
        if (weakestId == null) return; // nimeni de apărat
        final rounds = powerUpDurationRounds[PowerUp.allyShield] ?? 2;
        tx.update(matchRef, {'shields.$weakestId': roundIndex + rounds - 1});
      });
    } catch (e) {
      debugPrint('MultiplayerService.useTanksAllyShield a esuat: $e');
    }
  }

  /// [PowerUp.repairKit] pentru Quizz Tanks: recuperare de viață instant, nu
  /// depinde de rezolvarea rundei — se scrie direct pe documentul jucătorului,
  /// la fel ca orice altă acțiune imediată din aplicație.
  Future<void> useTanksRepairKit({required String matchId}) {
    final me = currentPlayerId;
    final ref = _db.collection('matches').doc(matchId).collection('players').doc(me);
    return _paced(() => _db.runTransaction((tx) async {
          final doc = await tx.get(ref);
          if (!doc.exists) return;
          final data = doc.data()!;
          if (data['eliminated'] == true) return;
          final hp = data['hp'] as int? ?? tanksMaxHp;
          tx.update(ref, {'hp': (hp + repairKitHp).clamp(0, tanksMaxHp)});
        }));
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

        // Evenimentul rundei, din aceeași funcție pură pe care o citește și
        // banner-ul din ecran (vezi resolveHigherLowerRound mai sus pentru
        // aceeași idee).
        final event = roundEventFor(matchId: matchId, roundIndex: roundIndex, gameModeId: 'quizzTanks');

        // Scut pe aliat: `shields.<id>` = ultima rundă în care id-ul e
        // protejat (2 runde, vezi [useTanksAllyShield]).
        final allyShields = Map<String, dynamic>.from(data['shields'] as Map? ?? const {});

        // Toată logica de foc (zaruri, power-up-uri, scuturi, reflexie,
        // lovitură dublă) e pură, în core/tanks.dart — testabilă fără
        // Firestore. Aici doar îi dăm datele citite și scriem rezultatul.
        final outcome = resolveTanksVolleys(
          alive: alive,
          shooters: shooters.where(alive.contains).toSet(),
          hpAtStart: hpAtStart,
          rawTargets: {
            for (final e in targets.entries) e.key: (e.value as String?) ?? '',
          },
          rawPowerUps: {
            for (final e in (data['roundPowerUps'] as Map? ?? const {}).entries)
              e.key as String: e.value as String,
          },
          allyShieldedIds: {
            for (final id in alive)
              if ((allyShields[id] as int? ?? -1) >= roundIndex) id,
          },
          event: event,
          rng: Random(),
        );

        // Cine e apărat de scut runda asta (propriu sau de aliat) — scris
        // explicit pe documentul meciului ca ecranul să poată desena domul de
        // scut și „0" în loc de „MISS" la loviturile blocate, fără să mai
        // recalculeze el mulțimea.
        final roundPowerUps = data['roundPowerUps'] as Map? ?? const {};
        final shieldedIds = {
          for (final id in alive)
            if (roundPowerUps[id] == PowerUp.shield.name ||
                (allyShields[id] as int? ?? -1) >= roundIndex)
              id,
        }.toList();

        final shots = [for (final s in outcome.shots) TankShot(byId: s.byId, atId: s.atId, hit: s.hit, damage: s.damage).toMap()];
        final destroyed = outcome.destroyed;
        var stillAlive = 0;
        for (final id in alive) {
          final isDestroyed = destroyed.contains(id);
          if (!isDestroyed) stillAlive++;
          // scorul E totalul daunelor: restul aplicației (clasament final,
          // XP, statistici) citește `score`, iar cerința modului spune că
          // ordinea o dau daunele făcute. Vezi și MatchPlayer.damageDealt.
          final totalDealt = (docs[id]!.data()!['damageDealt'] as int? ?? 0) + (outcome.damageDealt[id] ?? 0);
          tx.update(docs[id]!.reference, {
            'hp': isDestroyed ? 0 : hpAtStart[id]! - (outcome.damageTaken[id] ?? 0),
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
          'roundShieldedIds': shieldedIds,
          if (stillAlive <= 1 || outOfRounds) 'status': MatchStatus.finished.name,
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.resolveTanksRound a esuat: $e');
    }
  }

  // ─── Scaunul Electric ───────────────────────────────────────────────────

  /// Închide faza de răspuns a unei runde de Scaunul Electric: cine a
  /// răspuns corect la propria întrebare capătă dreptul de a alege o
  /// victimă și primește [electricChairPointsPerAnswer].
  ///
  /// NU se acordă niciun punct de "supraviețuire" aici — `score` rămâne un
  /// scor mic, de acțiune pură (răspunsuri + șocuri + apărări reușite),
  /// bun pentru XP; cine a rezistat mai mult se ține separat, în
  /// [MatchPlayer.eliminatedAtRound] (scris de [resolveElectricChairRound]).
  /// Clasamentul final combină cele două, vezi core/electric_chair.dart
  /// `electricChairRankKey` — comentariul de-acolo explică și de ce prima
  /// variantă (puncte de supraviețuire direct în `score`) era greșită.
  ///
  /// Dacă n-a nimerit nimeni, sau a mai rămas un singur jucător, se sare
  /// direct la deznodământ — exact ca [closeTanksAnswering].
  Future<void> closeElectricChairAnswering({
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

        final attackers = <String>[];
        var aliveCount = 0;
        final docs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final id in playerIds) {
          final doc = await tx.get(matchRef.collection('players').doc(id));
          docs[id] = doc;
          if (!doc.exists || doc.data()!['eliminated'] == true) continue;
          aliveCount++;
          if (answers[id] == correctAnswer) attackers.add(id);
        }
        for (final id in attackers) {
          final doc = docs[id]!;
          final base = doc.data()!['score'] as int? ?? 0;
          tx.update(doc.reference, {'score': base + electricChairPointsPerAnswer});
        }

        // Un singur jucător rămas în viață n-are pe cine ținti — ar rămâne
        // blocat pe ecranul de alegere până la plafonul de runde.
        if (attackers.isEmpty || aliveCount < 2) {
          final outOfRounds = roundIndex + 1 >= electricChairMaxRounds;
          tx.update(matchRef, {
            'roundPhase': RoundPhase.revealed.name,
            'roundWinnerIds': attackers,
            'roundChairAssignments': <String, Map<String, dynamic>>{},
            'roundChairOutcomes': <String, bool>{},
            if (aliveCount <= 1 || outOfRounds) 'status': MatchStatus.finished.name,
          });
          return;
        }

        tx.update(matchRef, {
          'roundPhase': RoundPhase.targeting.name,
          'roundWinnerIds': attackers,
          'roundChairChoices': <String, Map<String, dynamic>>{},
          // cronometrul de alegere pornește ACUM, nu de la începutul rundei
          'roundStartedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.closeElectricChairAnswering a esuat: $e');
    }
  }

  /// Victima ȘI întrebarea (0..[electricChairCandidateCount]-1) alese de
  /// atacatorul curent, din ecranul de alegere.
  Future<void> submitElectricChairChoice({
    required String matchId,
    required String targetId,
    required int questionIndex,
  }) {
    final me = currentPlayerId;
    return _paced(() => _db.collection('matches').doc(matchId).update({
          'roundChairChoices.$me': ChairChoice(targetId: targetId, questionIndex: questionIndex).toMap(),
        }));
  }

  /// Combină alegerile tuturor atacatorilor în lista efectivă de victime —
  /// dacă doi (sau mai mulți) au ales aceeași persoană, testul lor se
  /// combină într-unul singur (vezi core/electric_chair.dart pentru de ce).
  /// Cine n-a apucat să aleagă în [electricChairTargetSeconds] secunde NU
  /// pierde alegerea: primește o victimă și o întrebare la întâmplare,
  /// exact cum un țintaș întârziat trage automat în cel mai slăbit la Quizz
  /// Tanks.
  Future<void> resolveElectricChairTargeting({required String matchId, required int roundIndex}) async {
    final matchRef = _db.collection('matches').doc(matchId);
    final playerIds = (await matchRef.collection('players').get()).docs.map((d) => d.id).toList()..sort();
    if (playerIds.isEmpty) return;
    try {
      await _db.runTransaction((tx) async {
        final matchDoc = await tx.get(matchRef);
        final data = matchDoc.data();
        if (data == null || data['roundIndex'] != roundIndex || data['roundPhase'] != RoundPhase.targeting.name) {
          return; // deja închisă de alt client
        }
        final rawChoices = Map<String, dynamic>.from(data['roundChairChoices'] as Map? ?? const {});
        final attackers = List<String>.from(data['roundWinnerIds'] as List? ?? const []);

        final docs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final id in playerIds) {
          docs[id] = await tx.get(matchRef.collection('players').doc(id));
        }
        final alive = [
          for (final id in playerIds)
            if (docs[id]!.exists && docs[id]!.data()!['eliminated'] != true) id,
        ];

        final rnd = Random();
        final picks = <String, ChairChoice>{}; // atacator -> alegerea lui, cu auto-completare
        for (final attacker in attackers) {
          if (!alive.contains(attacker)) continue;
          final raw = rawChoices[attacker];
          final chosen = raw is Map ? ChairChoice.fromMap(Map<String, dynamic>.from(raw)) : null;
          final validTarget = chosen != null && chosen.targetId != attacker && alive.contains(chosen.targetId);
          if (validTarget) {
            picks[attacker] = chosen;
          } else {
            final candidates = alive.where((id) => id != attacker).toList();
            if (candidates.isEmpty) continue; // n-are pe cine alege
            picks[attacker] = ChairChoice(
              targetId: candidates[rnd.nextInt(candidates.length)],
              questionIndex: rnd.nextInt(electricChairCandidateCount),
            );
          }
        }

        // grupează pe victimă, ca alegerile simultane pe aceeași persoană
        // să se combine într-un singur test.
        final byVictim = <String, List<String>>{};
        for (final entry in picks.entries) {
          byVictim.putIfAbsent(entry.value.targetId, () => []).add(entry.key);
        }
        final assignments = <String, Map<String, dynamic>>{};
        for (final entry in byVictim.entries) {
          final attackerIds = entry.value..sort();
          final source = attackerIds.first; // departajaj determinist
          assignments[entry.key] = ChairAssignment(
            attackerIds: attackerIds,
            sourceAttackerId: source,
            questionIndex: picks[source]!.questionIndex,
          ).toMap();
        }

        tx.update(matchRef, {
          'roundPhase': RoundPhase.chair.name,
          'roundChairAssignments': assignments,
          'roundChairAnswers': <String, String>{},
          // cronometrul scaunului pornește ACUM
          'roundStartedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.resolveElectricChairTargeting a esuat: $e');
    }
  }

  /// Răspunsul victimei curente la întrebarea aleasă pentru ea.
  Future<void> submitChairAnswer({required String matchId, required String answer}) {
    final me = currentPlayerId;
    return _paced(() => _db.collection('matches').doc(matchId).update({'roundChairAnswers.$me': answer}));
  }

  /// Rezolvă scaunul: fiecare victimă din [MatchInfo.roundChairAssignments]
  /// e comparată cu răspunsul corect al întrebării ei (transmis de client,
  /// vezi [correctAnswers] — la fel cum [closeTanksAnswering] primește
  /// [correctAnswer] ca parametru, nu-l calculează singur, ca serviciul să
  /// rămână independent de conținutul întrebărilor).
  ///
  /// Cine n-a apucat să răspundă în [electricChairSeconds] secunde e tratat
  /// exact ca cine a greșit: pierde o viață.
  Future<void> resolveElectricChairRound({
    required String matchId,
    required int roundIndex,
    required Map<String, String> correctAnswers,
  }) async {
    final matchRef = _db.collection('matches').doc(matchId);
    final playerIds = (await matchRef.collection('players').get()).docs.map((d) => d.id).toList()..sort();
    if (playerIds.isEmpty) return;
    try {
      await _db.runTransaction((tx) async {
        final matchDoc = await tx.get(matchRef);
        final data = matchDoc.data();
        if (data == null || data['roundIndex'] != roundIndex || data['roundPhase'] != RoundPhase.chair.name) {
          return; // deja rezolvată de alt client
        }
        final assignments = {
          for (final e in (data['roundChairAssignments'] as Map? ?? const {}).entries)
            e.key as String: ChairAssignment.fromMap(Map<String, dynamic>.from(e.value as Map)),
        };
        final answers = Map<String, dynamic>.from(data['roundChairAnswers'] as Map? ?? const {});
        // Power-up-uri de-o rundă (scut propriu, șoc perforant) — vezi
        // [submitElectricChairPowerUp]; scut de aliat separat mai jos,
        // fiindcă ține 2 runde și nu se resetează la fiecare rundă.
        final activePowerUps = Map<String, dynamic>.from(data['roundPowerUps'] as Map? ?? const {});
        PowerUp powerUpOf(String id) {
          final raw = activePowerUps[id] as String?;
          if (raw == null) return PowerUp.none;
          return PowerUp.values.firstWhere((p) => p.name == raw, orElse: () => PowerUp.none);
        }
        final shields = Map<String, dynamic>.from(data['shields'] as Map? ?? const {});
        bool allyShielded(String id) => (shields[id] as int? ?? -1) >= roundIndex;

        // Evenimentul rundei (core/powerups.dart), aceeași funcție pură pe
        // care o citește și banner-ul din ecran.
        final event = roundEventFor(matchId: matchId, roundIndex: roundIndex, gameModeId: 'electricChair');

        final docs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final id in playerIds) {
          docs[id] = await tx.get(matchRef.collection('players').doc(id));
        }

        final outcomes = <String, bool>{};
        final scoreGain = <String, int>{for (final id in playerIds) id: 0};
        final newlyEliminated = <String>{};
        for (final entry in assignments.entries) {
          final victimId = entry.key;
          final assignment = entry.value;
          final victimDoc = docs[victimId];
          if (victimDoc == null || !victimDoc.exists || victimDoc.data()!['eliminated'] == true) continue;
          final correct = correctAnswers[victimId];
          // Decizia (răspuns/scut/perforant/reflexie) e pură, în
          // core/electric_chair.dart `chairVerdict` — testabilă fără Firestore.
          final verdict = chairVerdict(
            answeredCorrectly: correct != null && answers[victimId] == correct,
            hasShield: powerUpOf(victimId) == PowerUp.shield,
            allyShielded: allyShielded(victimId),
            anyAttackerPiercing: assignment.attackerIds.any((a) => powerUpOf(a) == PowerUp.piercingShock),
            hasReflect: powerUpOf(victimId) == PowerUp.reflect,
          );
          final survived = verdict != ChairVerdict.shocked;
          final reflected = verdict == ChairVerdict.reflected;
          outcomes[victimId] = survived;
          if (reflected) {
            for (final attackerId in assignment.attackerIds) {
              final aDoc = docs[attackerId];
              if (aDoc == null || !aDoc.exists || aDoc.data()!['eliminated'] == true) continue;
              final lives = (aDoc.data()!['lives'] as int? ?? electricChairMaxLives) - 1;
              final eliminated = lives <= 0;
              if (eliminated) newlyEliminated.add(attackerId);
              tx.update(aDoc.reference, {
                'lives': lives < 0 ? 0 : lives,
                'eliminated': eliminated,
                if (eliminated) 'eliminatedAtRound': roundIndex,
              });
            }
            continue; // victima nu ia puncte de apărare pentru un scut-noroc
          }
          if (survived) {
            scoreGain[victimId] = (scoreGain[victimId] ?? 0) + electricChairPointsPerDefense;
            // Siguranță: scapi de pe scaun, primești o viață înapoi.
            if (event == RoundEvent.groundedFuse) {
              final lives = (victimDoc.data()!['lives'] as int? ?? electricChairMaxLives) + 1;
              tx.update(victimDoc.reference, {'lives': lives.clamp(0, electricChairMaxLives)});
            }
          } else {
            // Supratensiune: scaunul ia DOUĂ vieți, nu una.
            final livesLost = event == RoundEvent.overcharge ? 2 : 1;
            final lives = (victimDoc.data()!['lives'] as int? ?? electricChairMaxLives) - livesLost;
            final eliminated = lives <= 0;
            if (eliminated) newlyEliminated.add(victimId);
            tx.update(victimDoc.reference, {
              'lives': lives < 0 ? 0 : lives,
              'eliminated': eliminated,
              // câte runde a rezistat — vezi core/electric_chair.dart
              // `electricChairRankKey`, care citește exact câmpul ăsta ca să
              // claseze corect "ultimul rămas în viață" la final.
              if (eliminated) 'eliminatedAtRound': roundIndex,
            });
            for (final attackerId in assignment.attackerIds) {
              scoreGain[attackerId] = (scoreGain[attackerId] ?? 0) + electricChairPointsPerShock;
            }
          }
        }
        for (final id in playerIds) {
          final gained = scoreGain[id] ?? 0;
          if (gained == 0) continue;
          final base = docs[id]!.data()?['score'] as int? ?? 0;
          tx.update(docs[id]!.reference, {'score': base + gained});
        }

        var aliveCount = 0;
        for (final id in playerIds) {
          final wasEliminated = docs[id]!.data()?['eliminated'] == true;
          if (!wasEliminated && !newlyEliminated.contains(id)) aliveCount++;
        }
        final outOfRounds = roundIndex + 1 >= electricChairMaxRounds;
        tx.update(matchRef, {
          'roundPhase': RoundPhase.revealed.name,
          'roundChairOutcomes': outcomes,
          if (aliveCount <= 1 || outOfRounds) 'status': MatchStatus.finished.name,
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.resolveElectricChairRound a esuat: $e');
    }
  }

  /// Trece la runda următoare — varianta proprie a Scaunului Electric,
  /// fiindcă runda lui are câmpuri proprii de golit ([roundChairChoices],
  /// [roundChairAssignments], [roundChairAnswers], [roundChairOutcomes]) și
  /// n-are niciun rost să atingă câmpurile celorlalte moduri. Ținut separat
  /// de [advanceSyncRound] la fel ca [advanceObbyRound] — runda are trei
  /// pași posibili (răspuns → alegere → scaun), nu doi.
  Future<void> advanceElectricChairRound({required String matchId, required int roundIndex}) async {
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
          'roundChairChoices': <String, Map<String, dynamic>>{},
          'roundChairAssignments': <String, Map<String, dynamic>>{},
          'roundChairAnswers': <String, String>{},
          'roundChairOutcomes': <String, bool>{},
          // NU 'shields': scutul de aliat ține 2 runde — vezi
          // [useElectricChairAllyShield] — deci harta aia trebuie să
          // supraviețuiască peste granița asta, spre deosebire de
          // 'roundPowerUps' (scut propriu / șoc perforant, o singură rundă).
          'roundPowerUps': <String, String>{},
          'roundStartedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('MultiplayerService.advanceElectricChairRound a esuat: $e');
    }
  }

  /// Activează [PowerUp.shield] (propriu) sau [PowerUp.piercingShock]
  /// (pe atac) pentru runda curentă — [resolveElectricChairRound] le citește
  /// de acolo, la fel ca [submitTanksPowerUp] pentru Quizz Tanks.
  Future<void> submitElectricChairPowerUp({required String matchId, required PowerUp powerUp}) {
    final me = currentPlayerId;
    return _paced(() => _db.collection('matches').doc(matchId).update({'roundPowerUps.$me': powerUp.name}));
  }

  /// [PowerUp.allyShield]: apără AUTOMAT cel mai slăbit coechipier (mai
  /// puține vieți), nu unul ales manual — evită o fereastră nouă de alegere
  /// doar pentru un power-up, iar „cel mai slăbit" e oricum alegerea
  /// evidentă pentru un scut defensiv. Ține 2 runde (runda curentă +
  /// următoarea), citite din `shields.<id>` = ultima rundă protejată.
  Future<void> useElectricChairAllyShield({required String matchId, required int roundIndex}) async {
    final me = currentPlayerId;
    final matchRef = _db.collection('matches').doc(matchId);
    try {
      await _db.runTransaction((tx) async {
        final playersSnap = await matchRef.collection('players').get();
        String? weakestId;
        var weakestLives = 1 << 30;
        for (final doc in playersSnap.docs) {
          if (doc.id == me) continue;
          final data = doc.data();
          if (data['eliminated'] == true) continue;
          final lives = data['lives'] as int? ?? electricChairMaxLives;
          if (lives < weakestLives || (lives == weakestLives && doc.id.compareTo(weakestId ?? '') < 0)) {
            weakestLives = lives;
            weakestId = doc.id;
          }
        }
        if (weakestId == null) return; // nimeni de apărat
        // vezi core/powerups.dart `powerUpDurationRounds` — 2 runde: cea
        // curentă și următoarea.
        final rounds = powerUpDurationRounds[PowerUp.allyShield] ?? 2;
        tx.update(matchRef, {'shields.$weakestId': roundIndex + rounds - 1});
      });
    } catch (e) {
      debugPrint('MultiplayerService.useElectricChairAllyShield a esuat: $e');
    }
  }

  /// **Invita un prieten in camera curenta**, chiar daca nu e online.
  ///
  /// Scrie un document in `room_invites`; de acolo il preiau Cloud Functions
  /// si trimit notificarea push (vezi functions/index.js `onRoomInvite`), iar
  /// la tap aplicatia lui intra DIRECT in camera. Fara Functions n-ar exista
  /// niciun fel: un client nu poate trimite FCM altui client.
  ///
  /// Nu verificam aici daca prietenul e online — tocmai asta e rostul: cine e
  /// deja in aplicatie vede oricum anuntul de prezenta (vezi
  /// MultiplayerPresenceService), invitatia e pentru cine NU e.
  Future<void> inviteFriendToRoom({
    required String matchId,
    required String toUid,
    String code = '',
  }) async {
    await ensureInitialized();
    final me = currentPlayerId;
    if (me.isEmpty || toUid.isEmpty || toUid == me) return;
    try {
      await _paced(() => _db.collection('room_invites').add({
            'fromUid': me,
            'toUid': toUid,
            'matchId': matchId,
            'code': code,
            'createdAt': FieldValue.serverTimestamp(),
          }));
    } catch (e) {
      debugPrint('MultiplayerService.inviteFriendToRoom a esuat: $e');
    }
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
    // Nu doar "mai există vreun document" — o fantomă (aplicație oprită
    // brusc, fără trecere prin leaveMatch) rămâne la nesfârșit altfel, iar
    // camera nu se mai șterge niciodată. Vezi [_isDeadMatchPlayer].
    final remaining = await matchRef.collection('players').get();
    if (remaining.docs.every((d) => _isDeadMatchPlayer(d.data()))) {
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

  /// Ultimul meci din care jucătorul a IEȘIT — pus de MultiplayerResultsScreen
  /// când ecranul de rezultate se închide, citit de rădăcina aplicației
  /// (main.dart) ca să poată asculta mai departe o cerere de revanșă.
  ///
  /// DE CE EXISTĂ: [watchRematchOffer] era ascultat exclusiv în ecranul de
  /// rezultate, deci cine apuca să iasă în meniu înainte ca gazda să apese
  /// „Cere revanșă" nu mai primea absolut nimic — oferta ajungea într-un ecran
  /// pe care nu-l mai avea nimeni deschis, iar gazda rămânea să aștepte un
  /// accept care n-avea cum să vină.
  ///
  /// Un `ValueNotifier` de sesiune, nu ceva salvat pe disc: o cerere de
  /// revanșă are sens minute, nu între două porniri ale aplicației.
  final ValueNotifier<String?> lastFinishedMatchId = ValueNotifier(null);

  /// Lansează o cerere de revanșă către EXACT jucătorii de la masa tocmai
  /// terminată — [participants] vine din clasamentul deja încărcat de
  /// MultiplayerResultsScreen (masa veche poate fi între timp ștearsă de
  /// [leaveMatch], vezi [RematchOffer]). Doc id-ul e chiar [matchId], singurul
  /// id pe care toți foștii participanți îl cunosc deja. `set` (nu `add`) —
  /// o cerere refuzată/anulată poate fi reîncercată, rescriind același doc.
  /// Poarta de ban, pusa la SURSA (nu in ecranul de rezultate): revansa e
  /// singura cale prin care un cont banat ar continua sa joace la nesfarsit cu
  /// aceiasi oameni fara sa treaca vreodata prin ecranul de Multiplayer, care
  /// are deja poarta lui. Daca maine alt buton cheama aceste metode, e acoperit
  /// din start.
  ///
  /// ATENTIE: `amIBanned` e alimentat de un abonament Firestore, deci e `false`
  /// cat timp primul snapshot n-a sosit (imediat dupa pornire, sau offline).
  /// Verificarea asta NU e o garantie de securitate — e o poarta de interfata.
  /// Securitatea reala pentru multiplayer vine din regulile Firestore si, mai
  /// incolo, din validarea pe server (partea B, cu Cloud Functions).
  ///
  /// Intoarce `false` daca cererea a fost refuzata (cont banat), ca apelantul
  /// sa poata arata mesajul — acelasi tipar ca `acceptFriendRequest`.
  Future<bool> offerRematch({
    required String matchId,
    required MatchGameMode gameMode,
    required int stake,
    required List<RematchParticipant> participants,
  }) async {
    if (PlayerProfileService.instance.amIBanned.value) return false;
    final me = currentPlayerId;
    await _paced(() => _db.collection('rematch_offers').doc(matchId).set(RematchOffer(
          matchId: matchId,
          hostId: me,
          gameMode: gameMode,
          stake: stake,
          participants: participants,
          acceptedIds: [me],
          status: 'pending',
        ).toMap()));
    return true;
  }

  Stream<RematchOffer?> watchRematchOffer(String matchId) => _db
      .collection('rematch_offers')
      .doc(matchId)
      .snapshots()
      .map((d) => d.exists ? RematchOffer.fromDoc(d) : null);

  /// Vezi nota de ban de la [offerRematch] — aceeasi poarta de interfata, la
  /// sursa. Intoarce `false` daca a fost refuzata (cont banat).
  Future<bool> acceptRematchOffer(String matchId) async {
    if (PlayerProfileService.instance.amIBanned.value) return false;
    await _paced(() => _db
        .collection('rematch_offers')
        .doc(matchId)
        .update({'acceptedIds': FieldValue.arrayUnion([currentPlayerId])}));
    return true;
  }

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
      playerIds: [for (final p in offer.participants) p.id],
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
      // vezi [_queueFreshness] — semnul de viață, împrospătat periodic cât
      // timp ecranul de căutare e deschis.
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cât de des își împrospătează semnul de viață clientul care caută.
  static const queueHeartbeatInterval = Duration(seconds: 15);

  /// Peste cât timp fără semn de viață o intrare din coadă e considerată
  /// moartă. Generos față de [queueHeartbeatInterval] (4×), ca o rețea
  /// proastă să nu scoată din coadă pe cineva care chiar caută.
  static const _queueFreshness = Duration(seconds: 60);

  /// „Mai sunt aici" — o singură scriere mică, rară (vezi
  /// [queueHeartbeatInterval]). Fără ea, o aplicație oprită brusc
  /// (force-stop, tab de browser închis, baterie moartă) nu apucă niciodată
  /// să treacă prin [leaveQueue], iar intrarea ei rămâne în coadă la
  /// nesfârșit — vezi [_liveQueueDocs] pentru ce strica asta.
  ///
  /// NU rescrie `joinedAt`: ordinea din coadă e „primul venit, primul
  /// servit", iar un heartbeat care ar reseta-o ar trimite la coada cozii
  /// exact pe cine așteaptă de cel mai mult timp.
  Future<void> queueHeartbeat() async {
    try {
      await _db
          .collection('matchmaking_queue')
          .doc(currentPlayerId)
          .update({'lastSeenAt': FieldValue.serverTimestamp()});
    } catch (e) {
      // documentul poate fi deja șters (am plecat din coadă) — inofensiv
      debugPrint('MultiplayerService.queueHeartbeat: $e');
    }
  }

  /// Intrările CU ADEVĂRAT active din coadă. Scoate două feluri de fantome,
  /// care altfel rămân acolo pentru totdeauna:
  ///
  /// - intrări fără semn de viață recent — cineva a închis aplicația brusc
  ///   și n-a apucat să treacă prin [leaveQueue];
  /// - intrări deja revendicate de o ofertă (au `matchId` scris) — alea nu
  ///   mai caută, așteaptă confirmarea.
  ///
  /// DE CE CONTEAZĂ: [attemptFormMatch] se uită doar la primii din coadă și
  /// se oprește dacă nu ești tu primul. Două fantome mai vechi decât tine
  /// blocau matchmaking-ul PERMANENT — nu mai erai cuplat cu nimeni, oricâți
  /// jucători reali ar fi intrat după tine — iar contorul afișa oameni care
  /// nu existau.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _liveQueueDocs(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs.where((d) => !_isDeadQueueEntry(d.data()) && d.data()['matchId'] == null).toList();
  }

  /// Doar criteriul de TIMP, folosit acolo unde chiar se șterge documentul.
  /// Ținut separat de [_liveQueueDocs] intenționat: o intrare revendicată de
  /// o ofertă (`matchId` scris) nu mai caută, dar NU e de șters — celălalt
  /// client poate să nu-și fi citit încă `matchId`-ul, iar dacă i se șterge
  /// documentul de sub el nu mai află niciodată în ce ofertă a intrat și
  /// rămâne să caute singur, în timp ce adversarul îl așteaptă la confirmare.
  bool _isDeadQueueEntry(Map<String, dynamic> data) {
    // `lastSeenAt` lipsește la intrările scrise de versiuni mai vechi ale
    // jocului — se cade înapoi pe `joinedAt`. Amândouă null înseamnă un
    // document abia scris, căruia serverul nu i-a confirmat încă
    // timestamp-ul: ăla e nou, nu vechi.
    final seen = (data['lastSeenAt'] as Timestamp?) ?? (data['joinedAt'] as Timestamp?);
    if (seen == null) return false;
    return seen.toDate().isBefore(DateTime.now().subtract(_queueFreshness));
  }

  /// Cât de des își împrospătează semnul de viață un jucător aflat într-un
  /// meci activ (lobby sau rundă) — aceeași cadență ca [queueHeartbeatInterval].
  static const matchHeartbeatInterval = Duration(seconds: 15);

  /// Peste cât timp fără semn de viață un jucător dintr-un meci e considerat
  /// fantomă — vezi [_isDeadMatchPlayer].
  static const _matchPlayerFreshness = Duration(seconds: 60);

  /// „Mai sunt aici" pentru un jucător dintr-un meci activ — vezi
  /// [queueHeartbeat], e exact același rol, dar pe `matches/{id}/players`.
  /// Fără el, o aplicație oprită brusc în timpul unui meci/lobby lasă un
  /// jucător-fantomă permanent: [leaveMatch] nu șterge camera decât când
  /// ultimul jucător RĂMAS pleacă explicit, iar o fantomă nu pleacă niciodată
  /// — vezi [_isDeadMatchPlayer], folosit acolo ca să nu mai conteze fantoma.
  Future<void> matchHeartbeat(String matchId) async {
    try {
      await _db
          .collection('matches')
          .doc(matchId)
          .collection('players')
          .doc(currentPlayerId)
          .update({'lastSeenAt': FieldValue.serverTimestamp()});
    } catch (e) {
      // documentul poate fi deja șters (am plecat din meci) — inofensiv
      debugPrint('MultiplayerService.matchHeartbeat: $e');
    }
  }

  bool _isDeadMatchPlayer(Map<String, dynamic> data) {
    final seen = (data['lastSeenAt'] as Timestamp?) ?? (data['joinedAt'] as Timestamp?);
    if (seen == null) return false;
    return seen.toDate().isBefore(DateTime.now().subtract(_matchPlayerFreshness));
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

  /// Câți jucători sunt chiar acum în coada de Join Online — afișat înainte
  /// și în timpul căutării, ca nimeni să nu fie cuplat automat "din senin":
  /// dacă vezi că mai e cineva în coadă, știi dinainte că matchmaking-ul o să
  /// vă cupleze pe voi doi în câteva secunde, în loc să te trezești direct în
  /// meci fără avertisment.
  Stream<int> watchQueueCount() {
    return _db
        .collection('matchmaking_queue')
        .snapshots()
        .map((s) => _liveQueueDocs(s.docs).length);
  }

  /// Cele două moduri pe care matchmaking-ul public le poate alege aleator —
  /// NU [MatchGameMode.quizzTanks]: acela cere exact 4 tancuri într-o arenă
  /// fixă (vezi core/tanks.dart), deci n-are cum să iasă dintr-o pereche 1 la
  /// 1 formată din coada de Meci Rapid.
  static const _quickMatchModes = [MatchGameMode.classic, MatchGameMode.higherLower];

  /// Doar clientul cel mai "vechi" din coadă (primul intrat) încearcă să
  /// formeze o ofertă — reduce coliziunile, deși tranzacția de mai jos e
  /// oricum sigură chiar dacă doi clienți ar încerca simultan. Formează
  /// oferta DOAR când există [matchmakingOpponentCount] jucători reali în
  /// coadă — fără completare cu boți, se așteaptă cât e nevoie de un
  /// adversar real.
  ///
  /// NU pornește meciul direct — scrie doar o [QuickMatchOffer], pe care
  /// AMÂNDOI trebuie s-o confirme explicit (vezi [acceptQuickMatchOffer]) —
  /// altfel cei doi se trezeau cuplați "din senin", fără avertisment.
  Future<String?> attemptFormMatch() async {
    final me = currentPlayerId;
    // Se citește o fereastră mai largă decât perechea căutată, fiindcă
    // fantomele (vezi [_liveQueueDocs]) se pot scoate abia după citire, nu
    // din interogare: Firestore n-are cum să filtreze aici după prospețime
    // fără un index pe care oricum l-ar strica ordonarea după `joinedAt`.
    final queueSnap = await _db.collection('matchmaking_queue').orderBy('joinedAt').limit(20).get();
    final live = _liveQueueDocs(queueSnap.docs);

    // Curățenie oportunistă, DOAR pe cele moarte de timp (vezi
    // [_isDeadQueueEntry]): fantomele rămase blochează coada pentru toată
    // lumea, iar nimeni altcineva nu le mai șterge vreodată.
    for (final d in queueSnap.docs.where((d) => _isDeadQueueEntry(d.data()))) {
      // fire-and-forget: dacă eșuează, reîncercăm la următorul tick
      d.reference.delete().catchError((e) {
        debugPrint('MultiplayerService.attemptFormMatch: nu s-a putut sterge intrarea moarta ${d.id}: $e');
      });
    }

    if (live.isEmpty || live.first.id != me) return null;
    if (live.length < matchmakingOpponentCount) return null;

    final candidates = live.take(matchmakingOpponentCount).toList();
    final offerRef = _db.collection('quickmatch_offers').doc();
    final gameMode = _quickMatchModes[Random().nextInt(_quickMatchModes.length)];

    try {
      await _db.runTransaction((tx) async {
        // re-verifica in tranzactie ca niciun candidat n-a fost deja
        // "furat" de o alta tranzactie concurenta intre timp.
        final fresh = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final c in candidates) {
          final f = await tx.get(c.reference);
          if (!f.exists || f.data()?['matchId'] != null) {
            throw StateError('candidat deja revendicat');
          }
          fresh.add(f);
        }

        final offer = QuickMatchOffer(
          id: offerRef.id,
          gameMode: gameMode,
          stake: publicMatchStake,
          participants: [
            for (final f in fresh)
              RematchParticipant(
                id: f.id,
                name: f.data()?['name'] as String? ?? '?',
                avatarSeed: f.data()?['avatarSeed'] as String? ?? f.id,
                photoUrl: f.data()?['photoUrl'] as String?,
                avatarStyle: f.data()?['avatarStyle'] as String? ?? '',
              ),
          ],
          acceptedIds: const [],
          status: 'pending',
        );
        tx.set(offerRef, offer.toMap());
        for (final c in candidates) {
          tx.update(c.reference, {'matchId': offerRef.id});
        }
      });
      return offerRef.id;
    } catch (e) {
      // De obicei benign: un alt client a format deja oferta intre timp cu
      // acesti candidati, iar ascultatorul propriei intrari din coada va
      // prelua id-ul ei. Se logheaza totusi — fara asta, o eroare reala
      // (ex. reguli Firestore) ramanea complet invizibila, iar ecranul de
      // cautare parea ca nu face nimic la nesfarsit.
      debugPrint('MultiplayerService.attemptFormMatch: nu s-a format oferta: $e');
      return null;
    }
  }

  // ─── Ofertă de Meci Rapid (confirmare explicită înainte de start) ──────

  Stream<QuickMatchOffer?> watchQuickMatchOffer(String offerId) => _db
      .collection('quickmatch_offers')
      .doc(offerId)
      .snapshots()
      .map((d) => d.exists ? QuickMatchOffer.fromDoc(d) : null);

  Future<void> acceptQuickMatchOffer(String offerId) => _paced(() => _db
      .collection('quickmatch_offers')
      .doc(offerId)
      .update({'acceptedIds': FieldValue.arrayUnion([currentPlayerId])}));

  /// Refuzul unui SINGUR jucător anulează oferta pentru amândoi — fiecare
  /// client, la rândul lui, reintră singur în coada de căutare (vezi
  /// MatchmakingScreen), nu rămâne blocat pe un ecran mort.
  Future<void> declineQuickMatchOffer(String offerId) => _paced(() => _db
      .collection('quickmatch_offers')
      .doc(offerId)
      .update({'status': 'cancelled', 'declinedBy': currentPlayerId}));

  /// Apelată DOAR de clientul primului jucător intrat în coadă
  /// ([QuickMatchOffer.participants].first), în clipa în care vede că
  /// AMÂNDOI au acceptat — creează meciul direct în [MatchStatus.playing],
  /// fără lobby (s-a confirmat deja explicit, n-are ce să mai aleagă
  /// nimeni). Vezi [launchRematch], aceeași arhitectură.
  Future<String> launchQuickMatch(QuickMatchOffer offer) async {
    final ref = _db.collection('matches').doc();
    final info = MatchInfo(
      id: ref.id,
      mode: MatchMode.public,
      status: MatchStatus.lobby,
      hostId: offer.participants.first.id,
      gameMode: offer.gameMode,
      stake: offer.stake,
      playerIds: [for (final p in offer.participants) p.id],
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
          isHost: p.id == offer.participants.first.id,
          bet: offer.stake,
          avatarStyle: p.avatarStyle,
        ).toMap(),
      );
    }
    await batch.commit();
    await startMatch(ref.id);
    await _db.collection('quickmatch_offers').doc(offer.id).update({
      'status': 'started',
      'newMatchId': ref.id,
    });
    return ref.id;
  }
}
