import '../core/lang.dart';

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
/// plus un rest care contează pentru următoarea deblocare. NU trece prin
/// [gemGiftGems]: ăștia sunt deja în sold de la prima pornire (vezi
/// StorageService.getGems), cadoul de mai jos vine peste ei.
const int starterGemGrant = 47;

// ─── Cadoul de gems „din partea casei", repetabil ─────────────────────────
// Era un mesaj pasiv pe ecranul de categorii, care se stingea singur când
// soldul scădea sub prețul primei trepte. Acum e un buton de revendicat care
// revine periodic — jucătorul vede ce primește și când.
//
// DE CE 34 la 48 de ore, și nu altceva:
//
//  • 34 e exact `questionUnlockGemsPrice(1)`, prețul unei trepte de
//    categorie. Cadoul are deci un înțeles în joc („îți plătesc o treaptă"),
//    nu e o cifră aleasă la întâmplare.
//  • Venitul de gems al unui jucător activ e azi ~13/zi din quest-uri (1 per
//    quest, 12-14 quest-uri pe zi) plus ~15/zi din roată, dacă o învârte
//    zilnic — deci ~28/zi. Cadoul adaugă 17/zi, adică +60%: se simte, dar nu
//    face gems-ul o resursă comună. Maxarea completă a unei categorii rămâne
//    1.099 gems, obiectiv de săptămâni.
//  • 48h, nu 24h: la o zi ar fi devenit „încă o recompensă zilnică" lângă
//    cele existente. La 72h se pierde ca motiv de revenire. Două zile ține
//    cadoul un eveniment, dar prinde și jucătorul care intră din două în
//    două zile.
//  • Cel mai ieftin pachet cu bani reali dă 130 gems, adică ~7,6 cadouri.
//    Trickle-ul gratuit nu-l anulează — doar îl face opțional.
const int gemGiftCooldownHours = 48;

/// Cât dă un cadou. Aceeași sumă de fiecare dată, inclusiv prima — un prim
/// cadou mai mare ar fi dublat [starterGemGrant], care e deja în sold de la
/// instalare.
int get gemGiftGems => questionUnlockGemsPrice(1);

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
///
/// Pus pe `true` la cerere explicită (2026-08-05): secțiunea premium se vede
/// acum normal, fără blur. Fluxul de cumpărare rămâne SIMULAT — vezi
/// [realMoneyStoreEnabled], care nu s-a schimbat — deci apăsarea unui buton
/// arată în continuare dialogul "În curând", nu percepe bani reali. Dacă
/// build-ul ăsta ajunge vreodată în Play Console, [realMoneyStoreEnabled]
/// trebuie să rămână `false` până la integrarea billing-ului real.
const bool premiumShopRevealed = true;

/// Formatare unitară a prețului, cu virgulă zecimală (convenția din România).
String formatRon(double price) => '${price.toStringAsFixed(2).replaceAll('.', ',')} lei';

// TREI trepte, nu cinci. Cinci opțiuni la același lucru nu ajută pe nimeni
// să aleagă — și cele două de sus (93,99 și 233,99 lei) erau prețuri de
// balenă într-un joc care n-a fost încă lansat. Cele trei de acum sunt:
// „încerc", „mă țin de joc", „chiar investesc" — ultima e exact cât să maxeze
// o categorie (1.099 gems, vezi [_questionUnlockTierPrices]), deci prețul are
// un obiectiv de joc în spate, nu doar o cifră mai mare.
//
// Randamentul crește cu treapta (26 / 30 / 35 gems per leu), ca pachetul mare
// să fie vizibil mai bun fără să facă cele mici să pară o păcăleală.
const List<GemPack> gemPacks = [
  GemPack(productId: 'gems_130', gems: 130, priceRon: 4.99),
  GemPack(productId: 'gems_390', gems: 390, bonusLabel: '+15%', priceRon: 12.99),
  GemPack(productId: 'gems_1050', gems: 1050, bonusLabel: '+35%', priceRon: 29.99),
];

class LivesPack {
  final String productId;
  final int lives;
  final double priceRon;
  const LivesPack({required this.productId, required this.lives, required this.priceRon});
}

// Vieţile sunt resursa moale (se refac singure, plus 6 gratuite pe zi), deci
// intrarea e sub 3 lei — un preţ de impuls, nu o decizie. A treia treaptă
// e „nelimitat 24h", care nu e un număr mai mare ci alt fel de valoare:
// exact oferta pentru cine chiar stă în joc o zi întreagă.
const List<LivesPack> livesPacks = [
  LivesPack(productId: 'lives_10', lives: 10, priceRon: 2.99),
  LivesPack(productId: 'lives_30', lives: 30, priceRon: 6.99),
];

const String unlimitedLives24hProductId = 'lives_unlimited_24h';
const double unlimitedLives24hPriceRon = 9.99;

class HintPackReal {
  final String productId;
  final int hints;
  final double priceRon;
  const HintPackReal({required this.productId, required this.hints, required this.priceRon});
}

// Aceleaşi trei trepte ca la vieţi, acelaşi prag de intrare de sub 3 lei.
// Randament crescător: 8,4 / 10,0 / 11,7 hints per leu.
const List<HintPackReal> hintPacksReal = [
  HintPackReal(productId: 'hints_25', hints: 25, priceRon: 2.99),
  HintPackReal(productId: 'hints_70', hints: 70, priceRon: 6.99),
  HintPackReal(productId: 'hints_175', hints: 175, priceRon: 14.99),
];

/// Ofertă cu mai multe resurse deodată, la un preț mai bun decât cumpărate
/// separat ("ca în jocurile populare") — [permanentNoAds] marchează oferta
/// specială de eliminare a reclamelor pe veci (vezi [noAdsBundle]).
class Bundle {
  final String productId;
  final String _titleRo;
  final String _subtitleRo;
  final String _titleEn;
  final String _subtitleEn;

  /// Gettere, nu câmpuri: [bundles] e o listă `const`, iar o constantă nu
  /// poate chema tr() — se țin ambele variante și se alege la afișare.
  String get title => tr(_titleRo, _titleEn);
  String get subtitle => tr(_subtitleRo, _subtitleEn);

  final int gems;
  final int coins;
  final int hearts;
  final int hints;
  final double priceRon;
  final bool oneTimeOnly;
  final bool permanentNoAds;
  const Bundle({
    required this.productId,
    required String title,
    required String subtitle,
    required String titleEn,
    required String subtitleEn,
    this.gems = 0,
    this.coins = 0,
    this.hearts = 0,
    this.hints = 0,
    required this.priceRon,
    this.oneTimeOnly = false,
    this.permanentNoAds = false,
  })  : _titleRo = title,
        _subtitleRo = subtitle,
        _titleEn = titleEn,
        _subtitleEn = subtitleEn;
}

// TREI pachete, nu patru. „Pachet Legendar" la 117,99 lei a fost scos: era
// mai scump decât tot restul magazinului la un loc și contrazicea direct
// ideea de prețuri accesibile. Cele trei rămase acoperă exact cele trei
// buzunare — și fiecare dă mai multe gems decât ai lua pe aceiași bani din
// [gemPacks], PLUS monede/vieți/hints; de-aia sunt „pachete", nu doar gems
// cu alt nume.
const List<Bundle> bundles = [
  Bundle(
    productId: 'bundle_starter',
    title: 'Pachet de Start',
    titleEn: 'Starter Pack',
    subtitle: 'O singură dată — cea mai bună ofertă din shop',
    subtitleEn: 'One time only — the best deal in the shop',
    // Chiar TREBUIE sa fie cel mai bun raport din magazin, altfel subtitlul
    // minte — prins de test/shop_pricing_test.dart, unde prima varianta
    // (260 gems) iesea sub Pachetul Campion.
    gems: 340,
    coins: 3000,
    hearts: 15,
    hints: 35,
    priceRon: 9.99,
    oneTimeOnly: true,
  ),
  Bundle(
    productId: 'bundle_aventurier',
    title: 'Pachet Aventurier',
    titleEn: 'Adventurer Pack',
    subtitle: 'Un plus solid pentru orice sesiune',
    subtitleEn: 'A solid boost for any session',
    gems: 520,
    coins: 5000,
    hearts: 25,
    hints: 60,
    priceRon: 19.99,
  ),
  Bundle(
    productId: 'bundle_campion',
    title: 'Pachet Campion',
    titleEn: 'Champion Pack',
    subtitle: 'Pentru cine joacă mult',
    subtitleEn: 'For people who play a lot',
    gems: 1200,
    coins: 12000,
    hearts: 60,
    hints: 150,
    priceRon: 39.99,
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
  titleEn: 'No ads, forever',
  subtitle: 'Reclamele forțate rămân dezactivate definitiv, plus un bonus imediat',
  subtitleEn: 'Forced ads stay off for good, plus an instant bonus',
  gems: 150,
  coins: 1500,
  hearts: 10,
  hints: 25,
  priceRon: 24.99,
  permanentNoAds: true,
);
