import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/source_discovery.dart';

ProductPage gpz() => ProductPage(
      Uri.parse('https://goldpricez.com/us/ounce'),
      200,
      File('test/fixtures/goldpricez_us_ounce.html').readAsStringSync(),
    );

DiscoverySpec goldSpec() => const DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold Price',
      country: 'United States',
      currency: 'USD',
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );

void main() {
  test('live goldpricez page proves as a review-required readable quote', () {
    final c = SourceCandidateValidator.validateReadableQuote(
      goldSpec(),
      gpz(),
      now: DateTime(2026, 10, 29, 15, 0),
    );
    expect(c, isNotNull);
    expect(c!.price, 4022.28);
    expect(c.currency, 'USD');
    expect(c.marketQuote, isTrue);
    expect(c.readableQuote, isTrue);
    expect(c.readingLabel, contains('confirm'));
  });

  test('a stale-dated quote page is not offered', () {
    // An archived copy from a month ago: every visible date is old.
    final body = File('test/fixtures/goldpricez_us_ounce.html')
        .readAsStringSync()
        .replaceAllMapped(
          RegExp(r'\d{2}-OCT-2026'),
          (m) => '15-SEP-2026',
        )
        .replaceAll('2026-10-29', '2026-09-15')
        .replaceAll('2026-10-28', '2026-09-15')
        .replaceAll('Oct  29, 2026', 'Sep  15, 2026')
        .replaceAll('October 29, 2026', 'September 15, 2026');
    final c = SourceCandidateValidator.validateReadableQuote(
      goldSpec(),
      ProductPage(Uri.parse('https://goldpricez.com/us/ounce'), 200, body),
      now: DateTime(2026, 10, 29, 15, 0),
    );
    expect(c, isNull);
  });

  test('wrong subject on the same page shape is not offered', () {
    const silver = DiscoverySpec(
      kind: 'productPrice',
      model: 'Silver Price',
      country: 'United States',
      currency: 'USD',
      storageGb: 0,
      target: 40,
      condition: WatchCondition.greaterThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(
        silver,
        gpz(),
        now: DateTime(2026, 10, 29, 15, 0),
      ),
      isNull,
    );
  });

  test('currency mismatch between task and page is not offered', () {
    const eur = DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold Price',
      country: 'United States',
      currency: 'EUR',
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(
        eur,
        gpz(),
        now: DateTime(2026, 10, 29, 15, 0),
      ),
      isNull,
    );
  });

  test('discovery offers the gold provider lead for a gold quote task',
      () async {
    final service = SourceDiscoveryService(
      searchProvider: _EmptySearch(),
      pageReader: _FixtureReader(gpz()),
    );
    final result = await service.discover(goldSpec());
    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.url.host, 'goldpricez.com');
    expect(result.candidates.single.readableQuote, isTrue);
    expect(result.issue, isNull);
  });

  test('revalidation keeps a stable readable quote and rejects a swap',
      () async {
    final service = SourceDiscoveryService(
      searchProvider: _EmptySearch(),
      pageReader: _FixtureReader(gpz()),
    );
    final selected = SourceCandidateValidator.validateReadableQuote(
      goldSpec(),
      gpz(),
      now: DateTime(2026, 10, 29, 14, 58),
    )!;
    final fresh = await service.revalidate(
      goldSpec(),
      selected,
      now: DateTime(2026, 10, 29, 15, 0),
    );
    expect(fresh, isNotNull);
    expect(fresh!.price, 4022.28);

    final moved = ProductPage(
      Uri.parse('https://goldpricez.com/us/ounce'),
      200,
      File('test/fixtures/goldpricez_us_ounce.html')
          .readAsStringSync()
          .replaceAll('Gold Price', 'Copper Price'),
    );
    final swapped = await SourceDiscoveryService(
      searchProvider: _EmptySearch(),
      pageReader: _FixtureReader(moved),
    ).revalidate(goldSpec(), selected, now: DateTime(2026, 10, 29, 15, 0));
    expect(swapped, isNull);
  });
}

class _EmptySearch implements SourceSearchProvider {
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async => const [];
}

class _FixtureReader implements DiscoveryPageReader {
  final ProductPage page;
  _FixtureReader(this.page);
  @override
  Future<ProductPage> read(Uri url) async {
    if (url.host == 'goldpricez.com') return page;
    throw StateError('unreachable in test');
  }
}
