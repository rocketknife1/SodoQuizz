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

// ─── Deblocare treptată a categoriilor + întrebărilor, cu Gems ─────────────
// La instalare, fiecare user primește 3 categorii random (vezi
// StorageService.getStarterCategories) deja la tier 1 (primele
// [initialUnlockedQuestions] jucabile, gratuit) — toate celelalte pornesc la
// tier 0, adică blocate complet (0 întrebări jucabile, categoria nu se poate
// deschide). Fiecare treaptă de tier (0→1→2→3→4→5, [maxUnlockTier] trepte în
// total) mai deblochează un lot de [questionUnlockBatch] întrebări, cu Gems —
// tier 0→1 e deci și "deblocarea categoriei" pentru cele nealese la
// instalare, nu doar un upgrade obișnuit. Prețurile cresc mult, treaptă cu
// treaptă (nu liniar, ca înainte) — ideea e ca maxarea completă a unei
// categorii (toate 5 trepte) să fie un obiectiv pe termen mai lung, nu ceva
// făcut din câteva sesiuni de joc. Categoriile cu mai puține întrebări decât
// [initialUnlockedQuestions] rămân complet deblocate, fără niciun sistem de
// deblocare (vezi StorageService.getUnlockedQuestionCount).

const int initialUnlockedQuestions = 15;
const int questionUnlockBatch = 15;

/// Câte trepte de upgrade poate face o categorie, în total (tier 0 = pornire,
/// tier [maxUnlockTier] = maxată complet, indiferent de câte întrebări mai
/// sunt teoretic de deblocat dincolo de atât).
const int maxUnlockTier = 5;

/// Preț (Gems) pentru treapta [tier] (1..[maxUnlockTier]) — creștere
/// accentuată de la o treaptă la alta.
const List<int> _questionUnlockTierPrices = [40, 90, 180, 320, 550];
int questionUnlockGemsPrice(int tier) => _questionUnlockTierPrices[tier - 1];

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

// ─── Bani reali (achiziții premium) ─────────────────────────────────────────
// Niciun SDK real de plăți nu e conectat încă (fără pachetul in_app_purchase,
// fără produse configurate în Google Play/App Store) — fluxul de cumpărare
// din shop_screen.dart e SIMULAT (dialog de confirmare + o mică întârziere,
// fără nicio taxare reală), dar prețurile/conținutul de mai jos sunt cele
// reale, gândite ca reper pentru integrarea ulterioară. [productId] e un
// placeholder nefolosit azi, pregătit pentru acel moment.
//
// ATENȚIE: fluxul simulat NU trebuie trimis către un magazin real (Play
// Store/App Store) așa cum e — ambele platforme impun ca plățile reale să
// treacă prin API-ul lor de billing, nu printr-un dialog care doar simulează
// succesul; publicarea în starea asta riscă respingere/sancțiune.

class GemPack {
  final String productId;
  final int gems;
  final String bonusLabel;
  final double priceUsd;
  const GemPack({required this.productId, required this.gems, this.bonusLabel = '', required this.priceUsd});
}

const List<GemPack> gemPacks = [
  GemPack(productId: 'gems_100', gems: 100, priceUsd: 0.99),
  GemPack(productId: 'gems_550', gems: 550, bonusLabel: '+10%', priceUsd: 4.99),
  GemPack(productId: 'gems_1200', gems: 1200, bonusLabel: '+20%', priceUsd: 9.99),
  GemPack(productId: 'gems_2600', gems: 2600, bonusLabel: '+30%', priceUsd: 19.99),
  GemPack(productId: 'gems_7000', gems: 7000, bonusLabel: '+40%', priceUsd: 49.99),
];

class LivesPack {
  final String productId;
  final int lives;
  final double priceUsd;
  const LivesPack({required this.productId, required this.lives, required this.priceUsd});
}

const List<LivesPack> livesPacks = [
  LivesPack(productId: 'lives_5', lives: 5, priceUsd: 0.99),
  LivesPack(productId: 'lives_15', lives: 15, priceUsd: 2.49),
];

const String unlimitedLives24hProductId = 'lives_unlimited_24h';
const double unlimitedLives24hPriceUsd = 1.99;

class HintPackReal {
  final String productId;
  final int hints;
  final double priceUsd;
  const HintPackReal({required this.productId, required this.hints, required this.priceUsd});
}

const List<HintPackReal> hintPacksReal = [
  HintPackReal(productId: 'hints_20', hints: 20, priceUsd: 0.99),
  HintPackReal(productId: 'hints_60', hints: 60, priceUsd: 2.49),
  HintPackReal(productId: 'hints_150', hints: 150, priceUsd: 4.99),
];

/// Ofertă cu mai multe resurse deodată, la un preț mai bun decât cumpărate
/// separat ("ca în jocurile populare") — [permanentNoAds] marchează oferta
/// specială de eliminare a reclamelor pe veci (vezi [noAdsBundle]).
class Bundle {
  final String productId;
  final String title;
  final String subtitle;
  final int gems;
  final int coins;
  final int hearts;
  final int hints;
  final double priceUsd;
  final bool oneTimeOnly;
  final bool permanentNoAds;
  const Bundle({
    required this.productId,
    required this.title,
    required this.subtitle,
    this.gems = 0,
    this.coins = 0,
    this.hearts = 0,
    this.hints = 0,
    required this.priceUsd,
    this.oneTimeOnly = false,
    this.permanentNoAds = false,
  });
}

const List<Bundle> bundles = [
  Bundle(
    productId: 'bundle_starter',
    title: 'Pachet de Start',
    subtitle: 'O singură dată — cea mai bună ofertă din shop',
    gems: 400,
    coins: 3000,
    hearts: 15,
    hints: 40,
    priceUsd: 4.99,
    oneTimeOnly: true,
  ),
  Bundle(
    productId: 'bundle_aventurier',
    title: 'Pachet Aventurier',
    subtitle: 'Un plus solid pentru orice sesiune',
    gems: 150,
    coins: 1200,
    hearts: 5,
    hints: 15,
    priceUsd: 2.99,
  ),
  Bundle(
    productId: 'bundle_campion',
    title: 'Pachet Campion',
    subtitle: 'Pentru cine joacă mult',
    gems: 500,
    coins: 4000,
    hearts: 15,
    hints: 50,
    priceUsd: 9.99,
  ),
  Bundle(
    productId: 'bundle_legendar',
    title: 'Pachet Legendar',
    subtitle: 'Cel mai mare pachet disponibil',
    gems: 1500,
    coins: 12000,
    hearts: 40,
    hints: 150,
    priceUsd: 24.99,
  ),
];

/// Reclamele forțate rămân dezactivate definitiv (nu există încă vreuna în
/// joc — doar butonul opțional de reclamă recompensată de la Game Over,
/// care rămâne activ și după această achiziție, fiindcă e o recompensă
/// aleasă de jucător, nu o reclamă impusă) + un bonus imediat, mai mic decât
/// suma pachetelor de mai sus la preț individual — perkul permanent e ce
/// justifică prețul, nu conținutul bonus.
const Bundle noAdsBundle = Bundle(
  productId: 'no_ads_forever',
  title: 'Fără reclame pe veci',
  subtitle: 'Reclamele forțate rămân dezactivate definitiv, plus un bonus imediat',
  gems: 200,
  coins: 2000,
  hearts: 15,
  hints: 40,
  priceUsd: 9.99,
  permanentNoAds: true,
);
