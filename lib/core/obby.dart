/// Regulile modului multiplayer **Obby** — o cursă de obstacole tip Roblox,
/// de la 2 la 6 personaje pe aceeași pistă. Aceeași mecanică de progres ca
/// Astro Sodo (vezi core/astrosodo.dart), doar altă haină vizuală: în loc de
/// nave pe culoare paralele, personaje-siluetă care sar peste obstacole pe o
/// singură pistă comună, filmate din spate ca la o cameră 3rd-person.
///
/// Runda, în doi pași (identic cu Astro Sodo, FĂRĂ fază de țintire):
///   1. **Răspuns** — toți cei care n-au terminat încă văd aceeași
///      întrebare de cultură generală și au [obbyRoundSeconds] secunde.
///      Fiecare își vede propriul personaj într-un colț al ecranului,
///      așteptând (idle) — nu vede încă cursa.
///   2. **Reveal** — camera trece la 3rd-person: toate personajele apar pe
///      pistă, iar cine a răspuns corect sare peste obstacolul din față.
///      Rămâne așa [obbyRevealSeconds] înainte ca runda următoare să
///      înceapă automat.
///
/// Meciul se termină fie când un personaj trece de ultimul obstacol
/// (victorie instantă), fie la epuizarea celor [obbyObstacleCount] runde,
/// caz în care clasamentul final se face după [obstaclesCleared]/scor —
/// vezi MultiplayerService.resolveObbyRound.
library;

/// Câte obstacole are pista — și, deci, câte întrebări are un meci întreg.
/// Cerut explicit de tema modului: exact 5 întrebări.
const int obbyObstacleCount = 5;

/// Câți jucători încap într-o cameră de Obby — la fel ca Astro Sodo.
const int obbyMaxPlayers = 6;

/// Cât timp are fiecare rundă înainte ca cei ce n-au răspuns încă să fie
/// scorați automat ca greșit.
const int obbyRoundSeconds = 12;

/// Cât rămâne vizibilă scena de 3rd-person (personajele care au sărit),
/// înainte ca runda următoare să înceapă automat.
const int obbyRevealSeconds = 3;

/// Puncte acordate pentru fiecare obstacol trecut — hrănește direct
/// [MatchPlayer.score] (vezi models/multiplayer_models.dart), la fel ca
/// [astroSodoPointsPerObstacle].
const int obbyPointsPerObstacle = 10;
