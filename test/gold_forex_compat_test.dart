// Compatibility and safety pins for the forex/verb canonicalization.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/source_discovery.dart';

ProductPage goldPage() => ProductPage(
      Uri.parse('https://goldpricez.com/us/ounce'),
      200,
      File('test/fixtures/goldpricez_us_ounce.html').readAsStringSync(),
    );

void main() {
  final now = DateTime(2026, 10, 29, 18);

  test('legacy identity saved with the pre-fix model still validates', () {
    // A watch saved by 1.1.18/1.1.19 carries model "Gold In Forex rises".
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold In Forex rises',
      country: 'India',
      currency: 'USD',
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );
    final c = SourceCandidateValidator.validateReadableQuote(
      spec,
      goldPage(),
      now: now,
    );
    expect(c, isNotNull);
    expect(c!.price, 4022.28);
  });

  test('a different metal behind identical phrasing still rejects', () {
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'Silver In Forex',
      country: 'India',
      currency: 'USD',
      storageGb: 0,
      target: 40,
      condition: WatchCondition.greaterThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(spec, goldPage(), now: now),
      isNull,
      reason: 'canonicalization must never widen to another instrument',
    );
  });

  test('an FX-shaped phrasing does not turn a gold page into an FX source', () {
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'USD INR rate',
      country: 'India',
      currency: 'INR',
      storageGb: 0,
      target: 90,
      condition: WatchCondition.greaterThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(spec, goldPage(), now: now),
      isNull,
    );
  });
}
