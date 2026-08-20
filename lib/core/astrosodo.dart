/// Regulile modului multiplayer **Astro Sodo** — o cursă de la 2 la 6
/// nave, pe culoare paralele presărate cu bolovani de asteroid. Fiecare
/// navă are exact [astroSodoObstacleCount] bolovani în față — la fel de
/// mulți cât [astroSodoObstacleCount] întrebări de cultură generală are
/// meciul — și un răspuns corect trece nava peste bolovanul din fața ei.
///
/// Runda, în doi pași (ca la Higher & Lower, FĂRĂ fază de țintire):
///   1. **Răspuns** — toți cei care n-au terminat încă văd aceeași
///      întrebare și au [astroSodoRoundSeconds] secunde. Cine răspunde
///      corect trece peste bolovanul curent; cine greșește sau nu apucă
///      rămâne pe loc — spre deosebire de Higher & Lower, nu există nicio
///      eliminare, doar teren pierdut.
///   2. **Reveal** — răspunsul corect și navele care au avansat rămân
///      vizibile [astroSodoRevealSeconds] înainte ca runda următoare să
///      înceapă automat.
///
/// Meciul se termină fie când o navă trece de ultimul bolovan (victorie
/// instantă — nu mai așteaptă restul întrebărilor), fie când s-au epuizat
/// cele [astroSodoObstacleCount] runde fără ca nimeni să fi ajuns la
/// final — caz în care câștigă cine a avansat cel mai mult (clasamentul
/// final se face oricum după [obstaclesCleared]/scor, vezi
/// MultiplayerService.resolveAstroSodoRound).
library;

/// Câți bolovani are fiecare culoar — și, deci, câte întrebări are un
/// meci întreg. Fixat la 10 la cererea explicită a temei modului.
const int astroSodoObstacleCount = 10;

/// Câți jucători încap într-o cameră de Astro Sodo. De la 2 (o cursă tot e
/// o cursă) până la 6 culoare — atâtea încap lizibil unele sub altele pe
/// ecranul de cursă fără să se micșoreze prea mult.
const int astroSodoMaxPlayers = 6;

/// Cât timp are fiecare rundă înainte ca cei ce n-au răspuns încă să fie
/// scorați automat ca greșit — aceeași idee ca la celelalte moduri
/// sincronizate (vezi core/tanks.dart, MultiplayerService).
const int astroSodoRoundSeconds = 12;

/// Cât rămâne vizibil răspunsul corect + navele care au avansat, înainte
/// ca runda următoare să înceapă automat.
const int astroSodoRevealSeconds = 3;

/// Puncte acordate pentru fiecare bolovan trecut — hrănește direct
/// [MatchPlayer.score] (vezi models/multiplayer_models.dart), la fel ca
/// [higherLowerPointsPerWin] din core/tanks.dart, ca sistemul de premii
/// din MultiplayerResultsScreen (deja bazat pe scor) să funcționeze
/// neschimbat și pentru acest mod.
const int astroSodoPointsPerObstacle = 10;
