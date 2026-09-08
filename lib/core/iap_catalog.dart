import '../data/shop.dart';

/// Legătura dintre produsele desenate în magazin ([gemPacks], [livesPacks],
/// [hintPacksReal], [bundles], [noAdsBundle], „vieți nelimitate 24h") și
/// id-urile lor de la Google Play.
///
/// De ce un fișier separat: `shop.dart` descrie CE se vinde, iar asta descrie
/// cum se numesc lucrurile în afara jocului. Id-urile sunt IMUTABILE odată
/// create în Play Console — nu se redenumesc și nu se refolosesc după
/// ștergere — deci lista de mai jos e, practic, definitivă.
///
/// Serverul are propriul catalog ([functions/iap_products.json]) și el e cel
/// care decide ce se acordă; `test/iap_catalog_test.dart` verifică bidirecțional
/// că cele două nu au divergat.

/// Toate id-urile de produs pe care jocul le poate cumpăra vreodată. Se dau
/// la `queryProductDetails` ca să afle Play ce prețuri să afișeze.
Set<String> get allProductIds => {
      for (final p in gemPacks) p.productId,
      for (final p in livesPacks) p.productId,
      for (final p in hintPacksReal) p.productId,
      unlimitedLives24hProductId,
      for (final b in bundles) b.productId,
      noAdsBundle.productId,
    };

/// Produsele care NU se consumă: Play însuși ține minte că le deții, deci se
/// pot restaura pe alt telefon. Restul se consumă după livrare, ca să poată fi
/// cumpărate din nou.
///
/// `bundle_starter` e aici fiindcă e `oneTimeOnly` în [bundles]: dacă nu-i
/// consumăm tokenul, Play impune el unicitatea („ITEM_ALREADY_OWNED" la a doua
/// încercare) — altfel un jucător care reinstalează l-ar putea lua a doua oară.
Set<String> get nonConsumableProductIds => {
      noAdsBundle.productId,
      for (final b in bundles.where((b) => b.oneTimeOnly)) b.productId,
    };

bool isNonConsumable(String productId) =>
    nonConsumableProductIds.contains(productId);

/// Eticheta scurtă a unui produs, pentru dialogul de confirmare și pentru
/// mesajele de eroare. Gol dacă id-ul nu e cunoscut.
String productLabel(String productId) {
  for (final p in gemPacks) {
    if (p.productId == productId) return '${p.gems} gems';
  }
  for (final p in livesPacks) {
    if (p.productId == productId) return '${p.lives} ♥';
  }
  for (final p in hintPacksReal) {
    if (p.productId == productId) return '${p.hints} hints';
  }
  if (productId == unlimitedLives24hProductId) return '∞ 24h';
  for (final b in [...bundles, noAdsBundle]) {
    if (b.productId == productId) return b.title;
  }
  return productId;
}

/// Prețul în lei declarat de joc pentru produsul ăsta. E doar pentru afișare
/// înainte ca Play să răspundă cu prețul REAL (localizat, cu taxe) — la plată
/// contează exclusiv ce spune Play.
double? productPriceRon(String productId) {
  for (final p in gemPacks) {
    if (p.productId == productId) return p.priceRon;
  }
  for (final p in livesPacks) {
    if (p.productId == productId) return p.priceRon;
  }
  for (final p in hintPacksReal) {
    if (p.productId == productId) return p.priceRon;
  }
  if (productId == unlimitedLives24hProductId) return unlimitedLives24hPriceRon;
  for (final b in [...bundles, noAdsBundle]) {
    if (b.productId == productId) return b.priceRon;
  }
  return null;
}
