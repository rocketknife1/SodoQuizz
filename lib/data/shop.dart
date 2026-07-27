/// Câte vieți se adaugă la recompensa zilnică gratuită (peste orice ai deja
/// — vezi StorageService.claimDailyReward) — și, separat, plafonul standard
/// până la care "Completare instantă" (Gems) umple viețile.
const int freeDailyLivesTarget = 5;

/// Preț progresiv (în Coins) pentru a N-a inimă cumpărată ASTĂZI — index 0
/// = prima achiziție a zilei. Lungimea listei e și plafonul zilnic de
/// achiziții (5, cât maximul standard de vieți): nu poți transforma ușor
/// multe monede în multe vieți, prețul crește repede și se resetează doar
/// a doua zi. Vezi reproiectarea economiei.
const List<int> heartCoinPrices = [150, 250, 400, 650, 1000];

/// Preț fix (în Gems) pentru completarea instantă a vieţilor la maximul
/// standard — fără plafon zilnic, fiindcă Gems sunt deja o resursă rară.
const int heartRefillGemsPrice = 40;

class HintPack {
  final int amount;
  final int priceCoins;
  const HintPack({required this.amount, required this.priceCoins});
}

/// Preț plat (nu progresiv ca la vieți) — hint-urile sunt individual mai
/// puțin puternice decât o inimă, plafonul de stoc (20, vezi StorageService)
/// e suficient să le țină valoroase.
const List<HintPack> hintCoinPacks = [
  HintPack(amount: 5, priceCoins: 180),
  HintPack(amount: 15, priceCoins: 450),
];

/// Câte pachete de hints (orice combinație) se pot cumpăra pe zi.
const int hintPackDailyLimit = 3;
