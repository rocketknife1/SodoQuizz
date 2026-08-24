import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/electric_chair.dart';
import '../core/tanks.dart';
import '../core/theme.dart';

enum MatchMode { private, public }

enum MatchStatus { lobby, playing, finished }

/// Modul de joc ales de host la creare — [classic] e fluxul original (fiecare
/// răspunde în ritmul lui, fără sincronizare), [higherLower] e varianta
/// multiplayer a mini-jocului solo Higher or Lower (higher_lower_data.dart):
/// toți din cameră văd aceeași pereche campion/provocator pe rundă și
/// votează în secret, vezi MultiplayerHigherLowerScreen. [quizzTanks] e
/// lupta cu bare de viață: patru jucători, întrebări de cultură generală,
/// timp fix de răspuns, iar cine răspunde corect își alege ținta —
/// vezi core/tanks.dart și MultiplayerTanksScreen. [obby] e cursa de
/// obstacole tip Roblox: de la 2 la 6 personaje pe aceeași pistă, camera
/// trece la 3rd-person (ca CJ din San Andreas) după fiecare întrebare, iar
/// un răspuns corect face personajul să sară peste obstacolul din față —
/// vezi core/obby.dart și MultiplayerObbyScreen. [electricChair] e cinci
/// jucători cu vieți individuale: cine răspunde corect alege pe cineva ȘI o
/// întrebare din patru pentru el — victima care greșește pierde o viață —
/// vezi core/electric_chair.dart și MultiplayerElectricChairScreen.
enum MatchGameMode { classic, higherLower, quizzTanks, obby, electricChair }

/// Faza rundei curente în modurile cu rundă SINCRONIZATĂ
/// ([MatchGameMode.higherLower], [MatchGameMode.quizzTanks] și
/// [MatchGameMode.obby]) — [answering] cât se
/// așteaptă răspunsurile, [targeting] doar la Quizz Tanks (cei care au
/// răspuns corect își aleg ținta), [choosing] doar la Obby (cei care au
/// răspuns corect își aleg placa pe care sar), [revealed] după ce runda a
/// fost rezolvată (câștigătorii la Higher & Lower, proiectilele trase la
/// Quizz Tanks, săritura reușită sau căderea
/// prin placa falsă la Obby).
///
/// Fiecare fază intermediară aparține UNUI SINGUR mod: Higher & Lower și
/// Higher & Lower sare direct de la [answering] la [revealed]; Quizz Tanks
/// trece doar prin [targeting], niciodată prin [choosing]; Obby doar prin
/// [choosing], niciodată prin [targeting]. Scaunul Electric refolosește
/// [targeting] (cine a răspuns corect își alege victima ȘI întrebarea) și
/// mai trece, în plus, prin [chair] (victima răspunde efectiv). Nicăieri în
/// aplicație nu există un `switch` exhaustiv pe enum-ul ăsta (doar comparații
/// `== RoundPhase.X` și `values.firstWhere(orElse:)`), tocmai ca o fază nouă
/// să nu poată strica modurile care n-o folosesc.
///
/// Numele valorilor e și ce se scrie în Firestore, deci nu se pot redenumi
/// fără să rămână în urmă meciurile aflate în desfășurare.
enum RoundPhase { answering, targeting, choosing, revealed, chair }

/// O tragere dintr-o rundă de Quizz Tanks, așa cum a ieșit din zarurile
/// aruncate O SINGURĂ DATĂ, în tranzacția care rezolvă runda (vezi
/// core/tanks.dart pentru de ce contează asta). Toți clienții citesc exact
/// aceleași trageri și le animează identic.
class TankShot {
  final String byId;
  final String atId;
  final bool hit;
  final int damage;

  const TankShot({required this.byId, required this.atId, required this.hit, required this.damage});

  factory TankShot.fromMap(Map<String, dynamic> map) => TankShot(
        byId: map['by'] as String? ?? '',
        atId: map['at'] as String? ?? '',
        hit: map['hit'] as bool? ?? false,
        damage: map['dmg'] as int? ?? 0,
      );

  // chei scurte: lista asta se rescrie pe documentul meciului la fiecare
  // rundă și e livrată tuturor ascultătorilor, deci contează cât ocupă.
  Map<String, dynamic> toMap() => {'by': byId, 'at': atId, 'hit': hit, 'dmg': damage};
}

/// Alegerea unui atacator din faza [RoundPhase.targeting] a Scaunului
/// Electric: victima ȘI care din cele [electricChairCandidateCount]
/// întrebări oferite i-a ales-o. Textul întrebării nu se scrie aici — se
/// derivă determinist din matchId + rundă + uid-ul atacatorului (vezi
/// MultiplayerElectricChairScreen), la fel cum Quizz Tanks nu scrie
/// întrebarea rundei, doar indexul ei.
class ChairChoice {
  final String targetId;
  final int questionIndex;

  const ChairChoice({required this.targetId, required this.questionIndex});

  factory ChairChoice.fromMap(Map<String, dynamic> map) => ChairChoice(
        targetId: map['t'] as String? ?? '',
        questionIndex: (map['q'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {'t': targetId, 'q': questionIndex};
}

/// Cine ajunge efectiv pe scaun într-o rundă de Scaunul Electric, așa cum a
/// ieșit din combinarea alegerilor tuturor atacatorilor (vezi
/// MultiplayerService.resolveElectricChairTargeting) — scrisă O SINGURĂ
/// DATĂ, de tranzacția care închide faza de alegere.
///
/// [attackerIds] = TOȚI cei care au ales-o victimă (poate fi mai mult de
/// unul); [sourceAttackerId] + [questionIndex] = a CUI întrebare se
/// folosește efectiv, când sunt mai mulți — vezi core/electric_chair.dart
/// pentru de ce se combină într-un singur test, nu unul per atacator.
class ChairAssignment {
  final List<String> attackerIds;
  final String sourceAttackerId;
  final int questionIndex;

  const ChairAssignment({
    required this.attackerIds,
    required this.sourceAttackerId,
    required this.questionIndex,
  });

  factory ChairAssignment.fromMap(Map<String, dynamic> map) => ChairAssignment(
        attackerIds: List<String>.from(map['a'] as List? ?? const []),
        sourceAttackerId: map['s'] as String? ?? '',
        questionIndex: (map['q'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {'a': attackerIds, 's': sourceAttackerId, 'q': questionIndex};
}

/// Un meci multiplayer (cameră privată SAU matchmaking public) — un singur
/// model deservește ambele fluxuri, vezi planul de arhitectură: o cameră
/// privată e doar un meci creat cu un [code] vizibil, unul public e creat
/// de matchmaking, fără cod.
class MatchInfo {
  final String id;
  final MatchMode mode;
  final String? code;
  final MatchStatus status;
  final String hostId;
  final String? hostName;
  final String? hostPhotoUrl;
  final String hostAvatarStyle;
  final Timestamp? createdAt;

  /// Miza camerei — aleasă o singură dată, de cel care a creat-o (vezi
  /// core/betting.dart). Toți jucătorii plătesc exact atât; cine intră nu mai
  /// alege nimic. 0 doar la camerele rămase de la versiuni mai vechi.
  final int stake;

  /// Dacă documentul chiar mai EXISTĂ în Firestore. Contează pentru că ștergerea
  /// camerei e felul în care gazda îi anunță pe ceilalți că a plecat: fără
  /// steagul ăsta, un `fromDoc` pe un document șters întorcea un MatchInfo gol,
  /// care arăta exact ca o cameră normală goală — iar cei rămași înăuntru
  /// stăteau blocați într-un lobby fantomă. Vezi RoomLobbyScreen.
  final bool exists;

  /// Momentul (de server) în care hostul a apăsat START — ancora
  /// cronometrului de 60 de secunde din modul Clasic. `null` cât timp meciul
  /// e încă în lobby.
  final Timestamp? startedAt;
  final MatchGameMode gameMode;

  /// Câmpuri de sincronizare a rundei — folosite doar în modurile cu rundă
  /// comună ([MatchGameMode.higherLower], [MatchGameMode.quizzTanks]), dar
  /// scrise (cu valori implicite, neutre) și pentru [MatchGameMode.classic],
  /// ca [toMap] să nu aibă nevoie de ramificații pe mod.
  ///
  /// [roundAnswers] ține uid → răspunsul lui: 'higher'/'lower' la Higher &
  /// Lower, textul variantei alese la Quizz Tanks.
  final int roundIndex;
  final RoundPhase roundPhase;
  final Map<String, String> roundAnswers;
  final List<String> roundWinnerIds;
  final Timestamp? roundStartedAt;

  /// Doar [MatchGameMode.quizzTanks]: proiectilele trase în runda tocmai
  /// rezolvată și tancurile care au fost distruse de ele. Scrise o singură
  /// dată, de clientul care câștigă tranzacția de rezolvare — restul doar
  /// le animează, vezi [TankShot].
  final List<TankShot> roundShots;
  final List<String> roundDestroyedIds;

  /// Doar [MatchGameMode.quizzTanks], în faza [RoundPhase.targeting]:
  /// uid-ul țintașului → uid-ul celui pe care l-a ales. Cine a răspuns
  /// corect apare în [roundWinnerIds] (lista țintașilor) încă de la
  /// începutul fazei; cine a și apucat să aleagă apare și aici.
  ///
  /// Ținta ALEASĂ nu e secretă între țintași — dar ecranul n-o arată
  /// nimănui până la foc, ca alegerea să nu devină o negociere de trei
  /// secunde.
  final Map<String, String> roundTargets;

  /// Doar [MatchGameMode.obby], în faza [RoundPhase.choosing]: uid → indexul
  /// plăcii pe care a ales să sară (0..[obbyPlatformChoiceCount]-1). Exact ca
  /// [roundTargets] la Quizz Tanks: cine a răspuns corect apare în
  /// [roundWinnerIds] de la începutul fazei, iar cine a și apucat să aleagă
  /// apare și aici.
  ///
  /// CARE placă e falsă NU se ține aici — se calculează identic pe fiecare
  /// client din `obbyFakePlatformIndex` (core/obby.dart), determinist din
  /// matchId + rundă + jucător. Vezi acolo pentru de ce nu e nevoie de o
  /// scriere în plus.
  final Map<String, int> roundPlatformChoices;

  /// Doar [MatchGameMode.electricChair], în faza [RoundPhase.targeting]:
  /// uid-ul atacatorului → victima și întrebarea aleasă de el (vezi
  /// [ChairChoice]). Exact ca [roundTargets] la Quizz Tanks: cine a răspuns
  /// corect apare în [roundWinnerIds] de la începutul fazei, cine a și
  /// apucat să aleagă apare și aici.
  final Map<String, ChairChoice> roundChairChoices;

  /// Doar [MatchGameMode.electricChair], din faza [RoundPhase.chair] înainte:
  /// uid-ul victimei → cine a pus-o pe scaun și cu ce întrebare, combinate
  /// într-un singur test (vezi [ChairAssignment]). Scrise o singură dată, de
  /// tranzacția care închide faza de alegere.
  final Map<String, ChairAssignment> roundChairAssignments;

  /// Doar [MatchGameMode.electricChair], în faza [RoundPhase.chair]: uid-ul
  /// victimei → răspunsul ei la întrebarea de pe scaun.
  final Map<String, String> roundChairAnswers;

  /// Doar [MatchGameMode.electricChair], după ce faza [RoundPhase.chair] s-a
  /// rezolvat: uid-ul victimei → a scăpat (true) sau a picat la scaun
  /// (false). Scris o singură dată, de tranzacția care rezolvă runda —
  /// ecranul doar animează, la fel ca [roundShots] la Quizz Tanks.
  final Map<String, bool> roundChairOutcomes;

  const MatchInfo({
    required this.id,
    required this.mode,
    required this.status,
    required this.hostId,
    this.code,
    this.hostName,
    this.hostPhotoUrl,
    this.hostAvatarStyle = '',
    this.createdAt,
    this.stake = 0,
    this.exists = true,
    this.startedAt,
    this.gameMode = MatchGameMode.classic,
    this.roundIndex = 0,
    this.roundPhase = RoundPhase.answering,
    this.roundAnswers = const {},
    this.roundWinnerIds = const [],
    this.roundStartedAt,
    this.roundShots = const [],
    this.roundDestroyedIds = const [],
    this.roundTargets = const {},
    this.roundPlatformChoices = const {},
    this.roundChairChoices = const {},
    this.roundChairAssignments = const {},
    this.roundChairAnswers = const {},
    this.roundChairOutcomes = const {},
  });

  factory MatchInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MatchInfo(
      id: doc.id,
      mode: (data['mode'] as String?) == 'private' ? MatchMode.private : MatchMode.public,
      code: data['code'] as String?,
      status: MatchStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => MatchStatus.lobby,
      ),
      hostId: data['hostId'] as String? ?? '',
      hostName: data['hostName'] as String?,
      hostPhotoUrl: data['hostPhotoUrl'] as String?,
      hostAvatarStyle: data['hostAvatarStyle'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
      stake: data['stake'] as int? ?? 0,
      exists: doc.exists,
      startedAt: data['startedAt'] as Timestamp?,
      gameMode: MatchGameMode.values.firstWhere(
        (m) => m.name == data['gameMode'],
        orElse: () => MatchGameMode.classic,
      ),
      roundIndex: data['roundIndex'] as int? ?? 0,
      roundPhase: RoundPhase.values.firstWhere(
        (p) => p.name == data['roundPhase'],
        orElse: () => RoundPhase.answering,
      ),
      roundAnswers: Map<String, String>.from(data['roundAnswers'] as Map? ?? const {}),
      roundWinnerIds: List<String>.from(data['roundWinnerIds'] as List? ?? const []),
      roundStartedAt: data['roundStartedAt'] as Timestamp?,
      roundShots: [
        for (final s in (data['roundShots'] as List? ?? const []))
          TankShot.fromMap(Map<String, dynamic>.from(s as Map)),
      ],
      roundDestroyedIds: List<String>.from(data['roundDestroyedIds'] as List? ?? const []),
      roundTargets: Map<String, String>.from(data['roundTargets'] as Map? ?? const {}),
      // (x as num).toInt() nu `as int`: Firestore poate întoarce un întreg
      // scris de pe web ca `double`, iar un cast direct ar arunca.
      roundPlatformChoices: {
        for (final e in (data['roundPlatformChoices'] as Map? ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      },
      roundChairChoices: {
        for (final e in (data['roundChairChoices'] as Map? ?? const {}).entries)
          e.key as String: ChairChoice.fromMap(Map<String, dynamic>.from(e.value as Map)),
      },
      roundChairAssignments: {
        for (final e in (data['roundChairAssignments'] as Map? ?? const {}).entries)
          e.key as String: ChairAssignment.fromMap(Map<String, dynamic>.from(e.value as Map)),
      },
      roundChairAnswers: Map<String, String>.from(data['roundChairAnswers'] as Map? ?? const {}),
      roundChairOutcomes: {
        for (final e in (data['roundChairOutcomes'] as Map? ?? const {}).entries)
          e.key as String: e.value as bool,
      },
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': mode.name,
        'code': code,
        'status': status.name,
        'hostId': hostId,
        'hostName': hostName,
        'hostPhotoUrl': hostPhotoUrl,
        'hostAvatarStyle': hostAvatarStyle,
        'stake': stake,
        'createdAt': FieldValue.serverTimestamp(),
        'gameMode': gameMode.name,
        'roundIndex': 0,
        'roundPhase': RoundPhase.answering.name,
        'roundAnswers': <String, String>{},
        'roundWinnerIds': <String>[],
        'roundShots': <Map<String, dynamic>>[],
        'roundDestroyedIds': <String>[],
        'roundTargets': <String, String>{},
        'roundPlatformChoices': <String, int>{},
        'roundChairChoices': <String, Map<String, dynamic>>{},
        'roundChairAssignments': <String, Map<String, dynamic>>{},
        'roundChairAnswers': <String, String>{},
        'roundChairOutcomes': <String, bool>{},
      };
}

/// Un jucător dintr-un meci — întotdeauna real, identificat prin auth
/// Firebase (Google sau anonim/Guest). [photoUrl] vine din contul Google
/// (vezi AuthService.multiplayerIdentity) — null pentru Guest, caz în care
/// se arată cercul colorat cu inițiala (vezi [pickAvatarColor]).
class MatchPlayer {
  final String id;
  final String name;
  final String avatarSeed;
  final String? photoUrl;
  final int score;
  final bool isHost;

  /// [breads] e folosit doar în [MatchGameMode.higherLower] — număr de
  /// răspunsuri greșite ("pâini", vezi widget-ul dedicat).
  ///
  /// [eliminated] e comun: la Higher & Lower înseamnă „a strâns prea multe
  /// pâini", la Quizz Tanks „tancul a fost distrus". În ambele cazuri
  /// jucătorul rămâne la masă ca spectator, nu e dat afară.
  final int breads;
  final bool eliminated;

  /// Doar [MatchGameMode.quizzTanks]: viața rămasă (din [tanksMaxHp]) și
  /// totalul daunelor făcute de la începutul meciului.
  ///
  /// [damageDealt] e ținut separat de [score] deși, azi, scorul unui meci de
  /// Quizz Tanks E chiar totalul daunelor (vezi
  /// MultiplayerService.resolveTanksRound): [score] e câmpul pe care îl
  /// citește tot restul aplicației (clasament, XP, statistici de profil),
  /// iar [damageDealt] e cifra proprie modului, folosită la împărțirea
  /// prăzii. Dacă vreodată scorul capătă și alte componente, prada rămâne
  /// legată de daunele reale, care sunt criteriul cerut.
  final int hp;
  final int damageDealt;

  /// Doar [MatchGameMode.obby]: câte obstacole a trecut jucătorul de la
  /// începutul meciului — sărituri peste obstacole, din cele
  /// [obbyObstacleCount] ale pistei lui. Vezi core/obby.dart. Ținut separat
  /// de [score] deși [score] urcă exact în pas cu el (vezi
  /// MultiplayerService.resolveObbyRound): [score] e câmpul citit de restul
  /// aplicației (clasament, premii), [obstaclesCleared] e cifra proprie
  /// modului, folosită să deseneze poziția pe pistă.
  final int obstaclesCleared;

  /// Doar [MatchGameMode.electricChair]: vieți rămase (din
  /// [electricChairMaxLives]). Scade cu una de fiecare dată când jucătorul
  /// pică la scaun; la zero, [eliminated] devine adevărat, la fel ca la
  /// celelalte moduri.
  final int lives;

  /// Doar [MatchGameMode.electricChair]: runda în care jucătorul a fost
  /// eliminat, sau `-1` dacă încă e în viață. NU e folosit pentru
  /// clasamentul propriu-zis (care citește `score`, la fel ca toate
  /// modurile) — e materia primă din care MultiplayerResultsScreen
  /// calculează [electricChairRankKey], ca "ultimul rămas în viață" să iasă
  /// GARANTAT pe primul loc, indiferent cât de activ a fost oricine în
  /// timpul meciului (vezi core/electric_chair.dart).
  final int eliminatedAtRound;

  /// Miza plătită la intrare — aceeași pentru toți, e miza camerei (vezi
  /// [MatchInfo.stake]). Scrisă o singură dată, la intrare, și citită de TOȚI
  /// clienții la final, ca fiecare să calculeze exact aceeași împărțire.
  ///
  /// Se ține și aici, nu doar pe documentul camerei, ca ecranul de rezultate
  /// să nu mai aibă nevoie de o citire în plus și ca un meci să se poată
  /// deconta corect chiar dacă documentul camerei a fost între timp curățat.
  final int bet;

  /// Id-ul avatarului desenat ales de jucător (vezi widgets/avatar_art.dart).
  /// Gol = poza obișnuită. Călătorește cu jucătorul ca ceilalți de la masă
  /// să-l vadă exact cum și-a ales, nu ca inițială.
  final String avatarStyle;

  /// Marcat o singură dată, când jucătorului i s-a scurs minutul și și-a
  /// scris scorul FINAL. Ecranul de rezultate așteaptă ca toată lumea de la
  /// masă să-l aibă înainte să calculeze plățile — altfel, cine termină cu o
  /// secundă mai devreme ar împărți pool-ul după scoruri încă nescrise ale
  /// celorlalți și ar ajunge la alte cifre decât ei.
  final bool finished;

  /// Doar [MatchGameMode.obby]: a nimerit placa bună în runda trecută, deci la
  /// întrebarea URMĂTOARE vede doar 2 variante din 4. Se aprinde în
  /// `resolveObbyChoices` și se stinge în `closeObbyAnswering` — bonusul se
  /// consumă la întrebarea la care s-a aplicat, indiferent dacă a nimerit-o
  /// sau nu (altfel un jucător norocos l-ar păstra la nesfârșit).
  final bool nextQuestionBonus;

  const MatchPlayer({
    required this.id,
    required this.name,
    required this.avatarSeed,
    required this.score,
    this.photoUrl,
    this.isHost = false,
    this.breads = 0,
    this.eliminated = false,
    this.bet = 0,
    this.finished = false,
    this.avatarStyle = '',
    this.hp = tanksMaxHp,
    this.damageDealt = 0,
    this.obstaclesCleared = 0,
    this.nextQuestionBonus = false,
    this.lives = electricChairMaxLives,
    this.eliminatedAtRound = -1,
  });

  factory MatchPlayer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MatchPlayer(
      id: doc.id,
      name: data['name'] as String? ?? '?',
      avatarSeed: data['avatarSeed'] as String? ?? doc.id,
      photoUrl: data['photoUrl'] as String?,
      score: data['score'] as int? ?? 0,
      isHost: data['isHost'] as bool? ?? false,
      breads: data['breads'] as int? ?? 0,
      eliminated: data['eliminated'] as bool? ?? false,
      bet: data['bet'] as int? ?? 0,
      finished: data['finished'] as bool? ?? false,
      avatarStyle: data['avatarStyle'] as String? ?? '',
      hp: data['hp'] as int? ?? tanksMaxHp,
      damageDealt: data['damageDealt'] as int? ?? 0,
      obstaclesCleared: data['obstaclesCleared'] as int? ?? 0,
      nextQuestionBonus: data['nextQuestionBonus'] as bool? ?? false,
      lives: data['lives'] as int? ?? electricChairMaxLives,
      eliminatedAtRound: data['eliminatedAtRound'] as int? ?? -1,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'avatarSeed': avatarSeed,
        'photoUrl': photoUrl,
        'score': score,
        'isHost': isHost,
        'bet': bet,
        'finished': finished,
        'avatarStyle': avatarStyle,
        // scrise pentru toate modurile, ca fișa de jucător să aibă aceeași
        // formă peste tot; în afara Quizz Tanks nu le citește nimeni.
        'hp': hp,
        'damageDealt': damageDealt,
        'obstaclesCleared': obstaclesCleared,
        'nextQuestionBonus': nextQuestionBonus,
        'lives': lives,
        'eliminatedAtRound': eliminatedAtRound,
        'joinedAt': FieldValue.serverTimestamp(),
        // semnul de viață, împrospătat periodic cât timp ecranul e deschis —
        // vezi MultiplayerService.matchHeartbeat.
        'lastSeenAt': FieldValue.serverTimestamp(),
      };
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '?',
      text: data['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      };
}

/// Un fost participant la un meci terminat, așa cum trebuie reținut ca să
/// poată fi reașezat la o masă nouă fără să mai treacă prin `joinRoomByCode`
/// — vezi [RematchOffer]. Doar câmpurile necesare ca să scrii direct fișa lui
/// de jucător în camera de revanșă (nume, avatar), nu tot [MatchPlayer].
class RematchParticipant {
  final String id;
  final String name;
  final String avatarSeed;
  final String? photoUrl;
  final String avatarStyle;

  const RematchParticipant({
    required this.id,
    required this.name,
    required this.avatarSeed,
    this.photoUrl,
    this.avatarStyle = '',
  });

  factory RematchParticipant.fromMap(Map<String, dynamic> map) => RematchParticipant(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '?',
        avatarSeed: map['avatarSeed'] as String? ?? '',
        photoUrl: map['photoUrl'] as String?,
        avatarStyle: map['avatarStyle'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'avatarSeed': avatarSeed,
        'photoUrl': photoUrl,
        'avatarStyle': avatarStyle,
      };
}

/// Cererea de revanșă lansată de gazda unui meci ABIA TERMINAT, către exact
/// aceiași jucători care au stat la masa veche — vezi
/// MultiplayerResultsScreen și MultiplayerService.offerRematch.
///
/// Documentul are ID-UL EGAL cu matchId-ul meciului terminat: e singurul id
/// pe care toți foștii participanți îl cunosc deja (fiecare ecran de
/// rezultate e deschis cu el), fără să fie nevoie de niciun canal de
/// invitație separat. Camera VECHE (`matches/{matchId}`) poate dispărea
/// între timp — vezi MultiplayerService.leaveMatch — dar oferta de revanșă
/// trăiește independent, într-o colecție proprie.
class RematchOffer {
  final String matchId;
  final String hostId;
  final MatchGameMode gameMode;
  final int stake;
  final List<RematchParticipant> participants;
  final List<String> acceptedIds;
  final String status; // 'pending' | 'started' | 'cancelled'
  final String? newMatchId;
  final String? declinedBy;

  const RematchOffer({
    required this.matchId,
    required this.hostId,
    required this.gameMode,
    required this.stake,
    required this.participants,
    required this.acceptedIds,
    required this.status,
    this.newMatchId,
    this.declinedBy,
  });

  factory RematchOffer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return RematchOffer(
      matchId: doc.id,
      hostId: data['hostId'] as String? ?? '',
      gameMode: MatchGameMode.values.firstWhere(
        (m) => m.name == data['gameMode'],
        orElse: () => MatchGameMode.classic,
      ),
      stake: data['stake'] as int? ?? 0,
      participants: [
        for (final p in (data['participants'] as List? ?? const []))
          RematchParticipant.fromMap(Map<String, dynamic>.from(p as Map)),
      ],
      acceptedIds: List<String>.from(data['acceptedIds'] as List? ?? const []),
      status: data['status'] as String? ?? 'pending',
      newMatchId: data['newMatchId'] as String?,
      declinedBy: data['declinedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'gameMode': gameMode.name,
        'stake': stake,
        'participants': [for (final p in participants) p.toMap()],
        'acceptedIds': acceptedIds,
        'status': status,
        'newMatchId': newMatchId,
        'declinedBy': declinedBy,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// Oferta de meci formată de sistem când matchmaking-ul (Meci Rapid) găsește
/// doi jucători reali — NU se pornește direct: fiecare trebuie să confirme
/// explicit (vezi MultiplayerService.acceptQuickMatchOffer), altfel cei doi
/// se trezeau cuplați "din senin", fără avertisment. Aceeași arhitectură ca
/// [RematchOffer] (participanți + acceptedIds + status), doar că aici nu
/// există un "host" care cere — cei doi sunt egali, iar clientul care a
/// intrat primul în coadă ([participants.first]) e cel care lansează
/// camera odată ce amândoi au acceptat (vezi [MultiplayerService.launchQuickMatch]).
///
/// [gameMode] e ales aleator o SINGURĂ DATĂ, la formarea ofertei — doar
/// dintre modurile compatibile cu exact 2 jucători ([MatchGameMode.classic]
/// și [MatchGameMode.higherLower]). [MatchGameMode.quizzTanks] cere exact 4
/// tancuri într-o arenă fixă (vezi core/tanks.dart), deci nu poate ieși
/// dintr-o pereche 1 la 1 din matchmaking public.
class QuickMatchOffer {
  final String id;
  final MatchGameMode gameMode;
  final int stake;
  final List<RematchParticipant> participants;
  final List<String> acceptedIds;
  final String status; // 'pending' | 'started' | 'cancelled'
  final String? newMatchId;
  final String? declinedBy;

  const QuickMatchOffer({
    required this.id,
    required this.gameMode,
    required this.stake,
    required this.participants,
    required this.acceptedIds,
    required this.status,
    this.newMatchId,
    this.declinedBy,
  });

  factory QuickMatchOffer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return QuickMatchOffer(
      id: doc.id,
      gameMode: MatchGameMode.values.firstWhere(
        (m) => m.name == data['gameMode'],
        orElse: () => MatchGameMode.classic,
      ),
      stake: data['stake'] as int? ?? 0,
      participants: [
        for (final p in (data['participants'] as List? ?? const []))
          RematchParticipant.fromMap(Map<String, dynamic>.from(p as Map)),
      ],
      acceptedIds: List<String>.from(data['acceptedIds'] as List? ?? const []),
      status: data['status'] as String? ?? 'pending',
      newMatchId: data['newMatchId'] as String?,
      declinedBy: data['declinedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'gameMode': gameMode.name,
        'stake': stake,
        'participants': [for (final p in participants) p.toMap()],
        'acceptedIds': acceptedIds,
        'status': status,
        'newMatchId': newMatchId,
        'declinedBy': declinedBy,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// Culoare deterministă (din paleta existentă a aplicației, nu inventată)
/// pentru avatarul unui jucător fără poză reală — același [seed] dă mereu
/// aceeași culoare, ca un jucător să se poată recunoaște vizual pe durata
/// unui meci.
Color pickAvatarColor(String seed) {
  const palette = [
    AppColors.purple,
    AppColors.blue,
    AppColors.orange,
    AppColors.teal,
    AppColors.danger,
    AppColors.coin,
  ];
  return palette[seed.hashCode.abs() % palette.length];
}
