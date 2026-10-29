// Instrument distinctions must survive arena canonicalization: contract
// type (spot vs futures), weight/unit and karat stay enforced; only the
// matching USD/oz proof may pass.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/source_discovery.dart';

ProductPage goldPage() => ProductPage(
      Uri.parse('https://goldpricez.com/us/ounce'),
      200,
      File('test/fixtures/goldpricez_us_ounce.html').readAsStringSync(),
    );

DiscoverySpec q(String model, {String currency = 'USD'}) => DiscoverySpec(
      kind: 'productPrice',
      model: model,
      country: 'India',
      currency: currency,
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );

void main() {
  final now = DateTime(2026, 10, 29, 18);

  test('a futures task never activates the spot page', () {
    expect(
      SourceCandidateValidator.validateReadableQuote(
        q('Gold Futures'),
        goldPage(),
        now: now,
      ),
      isNull,
      reason: 'futures is a different instrument; spot must not substitute',
    );
  });

  test('a per-gram task never activates the per-ounce page', () {
    expect(
      SourceCandidateValidator.validateReadableQuote(
        q('Gold Price per Gram'),
        goldPage(),
        now: now,
      ),
      isNull,
      reason: 'weight unit is identity; ounce must not substitute for gram',
    );
  });

  test('a karat task never activates the generic ounce page', () {
    expect(
      SourceCandidateValidator.validateReadableQuote(
        q('22K Gold Price'),
        goldPage(),
        now: now,
      ),
      isNull,
      reason: 'karat is identity; 24K-equivalent spot must not substitute',
    );
  });

  test('an expiry-style contract task never activates the spot page', () {
    expect(
      SourceCandidateValidator.validateReadableQuote(
        q('Gold December Contract'),
        goldPage(),
        now: now,
      ),
      isNull,
    );
  });

  test('the exact USD/oz subject still proves with matching unit', () {
    final c = SourceCandidateValidator.validateReadableQuote(
      q('Gold Price'),
      goldPage(),
      now: now,
    );
    expect(c, isNotNull);
    expect(c!.price, 4022.28);
    expect(c.currency, 'USD');
  });

  test('currency mismatch still rejects even with matching instrument', () {
    expect(
      SourceCandidateValidator.validateReadableQuote(
        q('Gold Price', currency: 'EUR'),
        goldPage(),
        now: now,
      ),
      isNull,
      reason: 'USD page must never serve an EUR watch',
    );
  });
}
