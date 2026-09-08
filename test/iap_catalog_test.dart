import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/shop.dart';

/// Catalogul de pe SERVER (`functions/iap_products.json`) trebuie sa fie
/// identic cu cel din client (`lib/data/shop.dart`).
///
/// DE CE EXISTA testul asta: serverul e cel care decide ce primesti dupa ce
/// Google confirma bonul — clientul nu are voie sa ceara „da-mi 1050 gems",
/// fiindca exact asta e gaura pe care o inchidem. Dar atunci apar DOUA liste
/// de preturi si cantitati, in doua limbaje, care pot diverge tacut: UI-ul
/// vinde 390 de gems, serverul acorda 130, iar jucatorul a platit degeaba.
///
/// Comparatia e in AMBELE sensuri dinadins: un produs adaugat doar in Dart
/// n-ar putea fi cumparat, iar unul adaugat doar in JSON ar fi un produs
/// fantoma pe care serverul l-ar onora fara ca magazinul sa-l arate.
///
/// Preturile din Play Console sunt a treia copie si NU pot fi verificate din
/// cod — raman de facut de mana (vezi planul de IAP).
void main() {
  late Map<String, dynamic> server;

  setUpAll(() {
    // `flutter test` ruleaza cu cwd = radacina proiectului.
    final f = File('functions/iap_products.json');
    expect(f.existsSync(), isTrue,
        reason: 'nu gasesc functions/iap_products.json (cwd: ${Directory.current.path})');
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    server = {
      for (final e in raw.entries)
        if (!e.key.startsWith('_')) e.key: e.value as Map<String, dynamic>,
    };
  });

  /// Toate produsele din client, aplatizate la aceeasi forma ca in JSON.
  Map<String, ({double priceRon, Map<String, int> grant})> clientCatalog() {
    final out = <String, ({double priceRon, Map<String, int> grant})>{};
    Map<String, int> nz(Map<String, int> m) =>
        {for (final e in m.entries) if (e.value != 0) e.key: e.value};

    for (final p in gemPacks) {
      out[p.productId] = (priceRon: p.priceRon, grant: {'gems': p.gems});
    }
    for (final p in livesPacks) {
      out[p.productId] = (priceRon: p.priceRon, grant: {'hearts': p.lives});
    }
    for (final p in hintPacksReal) {
      out[p.productId] = (priceRon: p.priceRon, grant: {'hints': p.hints});
    }
    out[unlimitedLives24hProductId] =
        (priceRon: unlimitedLives24hPriceRon, grant: {'unlimitedLivesHours': 24});
    for (final b in [...bundles, noAdsBundle]) {
      out[b.productId] = (
        priceRon: b.priceRon,
        grant: nz({'gems': b.gems, 'coins': b.coins, 'hearts': b.hearts, 'hints': b.hints}),
      );
    }
    return out;
  }

  test('aceleasi id-uri de produs in ambele parti', () {
    final client = clientCatalog().keys.toSet();
    final srv = server.keys.toSet();
    expect(client.difference(srv), isEmpty,
        reason: 'exista in shop.dart dar NU pe server (nu s-ar putea cumpara)');
    expect(srv.difference(client), isEmpty,
        reason: 'exista pe server dar NU in shop.dart (produs fantoma)');
  });

  test('acelasi pret pentru fiecare produs', () {
    clientCatalog().forEach((id, c) {
      expect((server[id]!['priceRon'] as num).toDouble(), c.priceRon,
          reason: '$id: pret diferit intre client si server');
    });
  });

  test('aceleasi cantitati acordate', () {
    clientCatalog().forEach((id, c) {
      final g = Map<String, dynamic>.from(server[id]!['grant'] as Map);
      final srvGrant = {for (final e in g.entries) e.key: (e.value as num).toInt()};
      expect(srvGrant, c.grant, reason: '$id: serverul acorda altceva decat vinde magazinul');
    });
  });

  test('produsele one-time sunt non-consumabile (Play impune atunci unicitatea)', () {
    for (final b in bundles.where((b) => b.oneTimeOnly)) {
      expect(server[b.productId]!['consumable'], isFalse,
          reason: '${b.productId} e oneTimeOnly in shop.dart dar consumabil pe server: '
              's-ar putea cumpara de doua ori dupa o reinstalare');
    }
    expect(server[noAdsBundle.productId]!['consumable'], isFalse,
        reason: 'perkul permanent trebuie sa fie restaurabil, deci non-consumabil');
  });

  test('produsele cu drept permanent au numele dreptului', () {
    expect(server['no_ads_forever']!['entitlement'], 'noAdsForever');
    expect(server['bundle_starter']!['entitlement'], 'starterPackBought');
  });

  test('niciun produs de pe server nu acorda monede', () {
    server.forEach((id, p) {
      final g = Map<String, dynamic>.from(p['grant'] as Map);
      expect(g.containsKey('coins'), isFalse,
          reason: '$id acorda monede — vezi conformitatea din lib/data/shop.dart');
    });
  });
}
