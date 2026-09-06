import 'leagues.dart';

/// Recompensa de sfârşit de sezon, după cel mai bun tier atins în sezonul
/// respectiv (`seasonBestTierIndex` din player_profiles). Ligile + sezoanele
/// există deja, dar se resetau lazy fără nimic la capăt — asta e „motivul să
/// joci în ultima săptămână". Vezi notele de plan, secţiunea RETENŢIE, punctul 6.
///
/// Fără job programat / Cloud Function: clientul, la prima pornire dintr-o
/// lună nouă, vede că `seasonKey`-ul propriu e din luna trecută cu puncte > 0,
/// îşi salvează local tier-ul atins ca „recompensă în aşteptare" ÎNAINTE ca
/// primul meci din luna nouă să reseteze totul, apoi arată un dialog de
/// revendicare. Acelaşi tipar lazy ca tot restul multiplayer-ului din proiect.

/// Monede pentru [tierIndex] (0=Bronze .. 4=Diamond). Bronze primeşte şi el
/// ceva — altfel jucătorul de nivel mic n-are niciun semnal că sezonul a
/// contat.
int seasonRewardCoins(int tierIndex) {
  switch (tierIndex.clamp(0, LeagueTier.values.length - 1)) {
    case 0:
      return 100;
    case 1:
      return 250;
    case 2:
      return 500;
    case 3:
      return 1000;
    default:
      return 2000;
  }
}

LeagueTier seasonRewardTier(int tierIndex) =>
    LeagueTier.values[tierIndex.clamp(0, LeagueTier.values.length - 1)];
