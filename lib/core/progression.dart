/// Formula de nivel/XP: 1000 XP pe nivel, simplu și previzibil.
/// XP-ul câștigat la o întrebare corectă = punctele obținute la acea
/// întrebare (vezi calculateAwardedPoints din game_helpers.dart).
const int xpPerLevel = 1000;

int levelForXp(int xp) => (xp ~/ xpPerLevel) + 1;

int xpIntoCurrentLevel(int xp) => xp % xpPerLevel;

double levelProgress(int xp) => xpIntoCurrentLevel(xp) / xpPerLevel;
