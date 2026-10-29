// Regression: live goldpricez page shape (captured 2026-10-29 ~18:15 IST).
// The page carries the headline quote "= $4,025.66 USD" AND derived stats
// ("Difference (High-Low)= 53.39 USD", Open/High/Low rows) with the current
// update stamp AFTER the stats block, not glued to the headline number.
// The extractor must read the headline quote, never a derived stat.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/source_discovery.dart';

import 'next_update_test.dart' as h;

class EmptySearch implements SourceSearchProvider {
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async => const [];
}

ProductPage livePage() => ProductPage(
      Uri.parse('https://goldpricez.com/us/ounce'),
      200,
      File('test/fixtures/goldpricez_us_ounce_v2.html').readAsStringSync(),
    );

void main() {
  final now = DateTime(2026, 10, 29, 18);
  const texts = [
    'Tell me when Gold Price In Forex rises above ₹4030',
    'Tell me when Gold Price rises above ₹4030',
    'Tell me when Gold Price  rises above ₹4030', // whitespace variant
  ];
  for (final text in texts) {
    test('live-shaped page reads headline quote: "$text"', () {
      final spec = DiscoveryTaskParser.parse(
        text, country: 'India', currency: 'USD').spec!;
      final r = SourceCandidateValidator.validateReadableQuote(
        spec, livePage(), now: now);
      expect(r, isNotNull, reason: 'live-shaped page must validate');
      expect(r!.price, 4025.66,
          reason: 'must read the headline quote, not a derived stat');
      expect(r.price, isNot(53.39));
      expect(r.currency, 'USD');
    });
  }

  test('legacy identity "Gold In Forex rises" also reads the headline quote', () {
    final spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold In Forex rises',
      country: 'India',
      currency: 'USD',
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );
    final r = SourceCandidateValidator.validateReadableQuote(
      spec, livePage(), now: now);
    expect(r?.price, 4025.66);
  });

  test('discovery path offers the headline quote, not the stat', () async {
    final spec = DiscoveryTaskParser.parse(
      'Tell me when Gold Price rises above ₹4030',
      country: 'India', currency: 'USD').spec!;
    final result = await SourceDiscoveryService(
      searchProvider: EmptySearch(),
      pageReader: h.FakeReader(livePage()),
    ).discover(spec);
    expect(result.candidates, isNotEmpty);
    expect(result.candidates.first.price, 4025.66);
  });
}
