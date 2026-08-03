/// Câte vieți se adaugă la recompensa zilnică gratuită (peste orice ai deja
/// — vezi StorageService.claimDailyReward) — și, separat, plafonul standard
/// până la care "Completare instantă" (Gems) umple viețile.
const int freeDailyLivesTarget = 6;

/// Preț progresiv (în Coins) pentru a N-a inimă cumpărată ASTĂZI — index 0
/// = prima achiziție a zilei. Lungimea listei e și plafonul zilnic de
/// achiziții.
///
/// Suma completă (2.189 monede) e calibrată pe venitul brut al unui jucător
/// activ (~2.900 monede/zi): cine are bani de 3 vieți dimineața trebuie să
/// mai joace și să mai farmeze, cu pauze, ca să prindă și a 4-a și a 5-a —
/// dar nu e imposibil într-o zi. Prima e ieftină intenționat (89), ca un
/// jucător nou blocat pe 0 vieți să aibă o ieșire accesibilă.
const List<int> heartCoinPrices = [89, 167, 312, 578, 1043];

/// Preț fix (în Gems) pentru completarea instantă a vieţilor la maximul
/// standard — fără plafon zilnic, fiindcă Gems sunt deja o resursă rară.
const int heartRefillGemsPrice = 31;

// ─── Deblocare treptată a categoriilor + întrebărilor, cu Gems ─────────────
// La instalare, fiecare user primește 3 categorii random (vezi
// StorageService.getStarterCategories) deja la tier 1, PLUS
// [starterGemGrant] gems "din partea casei" — exact cât să deblocheze el
// însuși o a 4-a categorie, la alegere, în loc să depindă de zar.
//
// Fiecare treaptă de tier (0→1→2→3→4→5) mai deblochează un lot de
// [questionUnlockBatch] întrebări; tier 0→1 e deci și "deblocarea
// categoriei". Maxarea completă a unei categorii costă 1.099 gems — un
// obiectiv de câteva săptămâni, nu de câteva sesiuni.

const int initialUnlockedQuestions = 15;
const int questionUnlockBatch = 15;

/// Gems primiți gratuit la instalare — [_questionUnlockTierPrices]`[0]` (34)
/// plus un rest care contează pentru următoarea deblocare.
const int starterGemGrant = 47;

/// Câte trepte de upgrade poate face o categorie, în total (tier 0 = pornire,
/// tier [maxUnlockTier] = maxată complet, indiferent de câte întrebări mai
/// sunt teoretic de deblocat dincolo de atât).
const int maxUnlockTier = 5;

/// Preț (Gems) pentru treapta [tier] (1..[maxUnlockTier]) — creștere
/// accentuată de la o treaptă la alta.
const List<int> _questionUnlockTierPrices = [34, 79, 167, 298, 521];
int questionUnlockGemsPrice(int tier) => _questionUnlockTierPrices[tier - 1];

class HintPack {
  final int amount;
  final int priceCoins;
  const HintPack({required this.amount, required this.priceCoins});
}

/// Prețul de BAZĂ al pachetelor — cel efectiv plătit crește cu fiecare pachet
/// cumpărat azi, vezi [hintPackPriceMultipliers].
const List<HintPack> hintCoinPacks = [
  HintPack(amount: 4, priceCoins: 137),
  HintPack(amount: 13, priceCoins: 389),
];

/// Câte pachete de hints (orice combinație) se pot cumpăra pe zi.
const int hintPackDailyLimit = 3;

/// Multiplicator de preț pentru al N-lea pachet cumpărat azi (index 0 =
/// primul). La fel ca la vieți, e un sink progresiv: 3 pachete mici costă
/// 567 de monede în total, 3 mari costă 1.610 — deci a doua ofertă repetabilă
/// a zilei nu se poate epuiza "în 10 minute".
const List<double> hintPackPriceMultipliers = [1.0, 1.35, 1.79];

int hintPackPriceToday(HintPack pack, int boughtToday) {
  final i = boughtToday.clamp(0, hintPackPriceMultipliers.length - 1);
  return (pack.priceCoins * hintPackPriceMultipliers[i]).round();
}

// ─── Bani reali (achiziții premium) ─────────────────────────────────────────
// Prețurile sunt în RON (lei), la pragurile reale folosite de Google Play
// România (~4,7 lei/USD), nu în dolari ca înainte.
//
// ATENȚIE, blocant de publicare: niciun SDK real de plăți nu e conectat încă
// (fără pachetul in_app_purchase, fără produse configurate în Play Console) —
// fluxul de cumpărare din shop_screen.dart e SIMULAT. Secțiunea cu bani reali
// NU trebuie să ajungă activă într-un build trimis la Google Play; vezi
// [realMoneyStoreEnabled], care o comută pe "În curând".

class GemPack {
  final String productId;
  final int gems;
  final String bonusLabel;
  final double priceRon;
  const GemPack({required this.productId, required this.gems, this.bonusLabel = '', required this.priceRon});
}

/// Comutatorul unic pentru toată secțiunea Premium (bani reali). Cât timp e
/// `false`, shop-ul arată ofertele ca "În curând" și nu lasă nicio achiziție
/// simulată să se întâmple — singura stare în care build-ul poate fi urcat în
/// Play Console fără să încalce regulile de billing. Se pune pe `true` odată
/// cu integrarea reală Google Play Billing.
const bool realMoneyStoreEnabled = false;

/// Al doilea comutator, pur VIZUAL: cât timp e `false`, toată zona premium
/// (de la "Fără reclame pe veci" în jos — pachete, gems, vieți & hints cu
/// bani reali) e afișată blurată și complet inertă, cu un strat "În curând"
/// peste ea. Motivul e comercial, nu tehnic: până la lansarea magazinului nu
/// vrem ca prețurile și conținutul ofertelor să fie vizibile în capturile de
/// ecran din Google Play. Secțiunile care se plătesc în monede (Vieți, Hints)
/// rămân neatinse — ele fac parte din joc, nu din magazinul cu bani reali.
///
/// Reveal-ul e o singură linie: `true` aici. [realMoneyStoreEnabled] rămâne
/// separat — ăla deblochează plățile efective, ăsta doar vizibilitatea.
const bool premiumShopRevealed = false;

/// Formatare unitară a prețului, cu virgulă zecimală (convenția din România).
String formatRon(double price) => '${price.toStringAsFixed(2).replaceAll('.', ',')} lei';

const List<GemPack> gemPacks = [
  GemPack(productId: 'gems_118', gems: 118, priceRon: 4.79),
  GemPack(productId: 'gems_634', gems: 634, bonusLabel: '+10%', priceRon: 23.49),
  GemPack(productId: 'gems_1372', gems: 1372, bonusLabel: '+20%', priceRon: 46.99),
  GemPack(productId: 'gems_2918', gems: 2918, bonusLabel: '+30%', priceRon: 93.99),
  GemPack(productId: 'gems_7640', gems: 7640, bonusLabel: '+40%', priceRon: 233.99),
];

class LivesPack {
  final String productId;
  final int lives;
  final double priceRon;
  const LivesPack({required this.productId, required this.lives, required this.priceRon});
}

const List<LivesPack> livesPacks = [
  LivesPack(productId: 'lives_7', lives: 7, priceRon: 4.79),
  LivesPack(productId: 'lives_19', lives: 19, priceRon: 11.79),
];

const String unlimitedLives24hProductId = 'lives_unlimited_24h';
const double unlimitedLives24hPriceRon = 9.29;

class HintPackReal {
  final String productId;
  final int hints;
  final double priceRon;
  const HintPackReal({required this.productId, required this.hints, required this.priceRon});
}

const List<HintPackReal> hintPacksReal = [
  HintPackReal(productId: 'hints_23', hints: 23, priceRon: 4.79),
  HintPackReal(productId: 'hints_68', hints: 68, priceRon: 11.79),
  HintPackReal(productId: 'hints_172', hints: 172, priceRon: 23.49),
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
  final double priceRon;
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
    required this.priceRon,
    this.oneTimeOnly = false,
    this.permanentNoAds = false,
  });
}

const List<Bundle> bundles = [
  Bundle(
    productId: 'bundle_starter',
    title: 'Pachet de Start',
    subtitle: 'O singură dată — cea mai bună ofertă din shop',
    gems: 434,
    coins: 3170,
    hearts: 17,
    hints: 43,
    priceRon: 23.49,
    oneTimeOnly: true,
  ),
  Bundle(
    productId: 'bundle_aventurier',
    title: 'Pachet Aventurier',
    subtitle: 'Un plus solid pentru orice sesiune',
    gems: 167,
    coins: 1283,
    hearts: 6,
    hints: 17,
    priceRon: 13.99,
  ),
  Bundle(
    productId: 'bundle_campion',
    title: 'Pachet Campion',
    subtitle: 'Pentru cine joacă mult',
    gems: 534,
    coins: 4270,
    hearts: 17,
    hints: 53,
    priceRon: 46.99,
  ),
  Bundle(
    productId: 'bundle_legendar',
    title: 'Pachet Legendar',
    subtitle: 'Cel mai mare pachet disponibil',
    gems: 1634,
    coins: 12840,
    hearts: 43,
    hints: 158,
    priceRon: 117.99,
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
  gems: 214,
  coins: 2130,
  hearts: 17,
  hints: 43,
  priceRon: 46.99,
  permanentNoAds: true,
);
