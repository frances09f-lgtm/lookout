// Pinned evidence for the guided market-quote extraction shared by
// discovery, revalidation and the ongoing checker.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/source_discovery.dart';

import 'next_update_test.dart' as h;

ProductPage fixturePage(String url, String file) => ProductPage(
      Uri.parse(url),
      200,
      File('test/fixtures/$file').readAsStringSync(),
    );

void main() {
  final now = DateTime(2026, 10, 29, 15, 0);

  test('silver fixture fails closed on its login form, not the value', () {
    // sdbullion carries an account password form in the page chrome; the
    // readable tier refuses gated pages even though a clean 53.57 USD
    // quote would otherwise extract. Silver stays unsupported, honestly.
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'Silver Price',
      country: 'United States',
      currency: 'USD',
      storageGb: 0,
      target: 50,
      condition: WatchCondition.lessThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(
        spec,
        fixturePage('https://sdbullion.com/silver', 'sdbullion_silver.html'),
        now: now,
      ),
      isNull,
    );
  });

  test('FX fixture without a current date near the rate fails closed', () {
    // The equation regex isolates exactly 95.2181 INR per 1 USD (never the
    // 1 from "1 USD", never the split-digit headline artifact), but xe shows
    // only the word "today" near the rate, no explicit date. Freshness is
    // not provable, so the page rejects instead of activating an unverifiable
    // value. FX stays unsupported until a dated source passes end to end.
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'USD INR rate',
      country: 'United States',
      currency: 'INR',
      storageGb: 0,
      target: 90,
      condition: WatchCondition.greaterThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(
        spec,
        fixturePage('https://www.xe.com/currency/usd-us-dollar', 'xe_usdinr.html'),
        now: now,
      ),
      isNull,
    );
  });

  test('the reverse FX pair never reads the forward equation', () {
    // Direction is pinned by the pair order: an INR->USD task matches only
    // "1 INR = value USD" rows (0.0105022 on this page) and can never pick
    // up the 95.2181 forward rate; here the page still rejects on freshness.
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'INR USD rate',
      country: 'India',
      currency: 'USD',
      storageGb: 0,
      target: 0.01,
      condition: WatchCondition.lessThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(
        spec,
        fixturePage('https://www.xe.com/currency/inr-indian-rupee', 'xe_usdinr.html'),
        now: now,
      ),
      isNull,
    );
  });

  test('two distinct fresh quote values on one page reject', () {
    final body = '<html><body>'
        '<p>Gold Price = \$4,022.28 USD 29-OCT-2026</p>'
        '<p>Spot: \$4,101.50 USD 29-OCT-2026</p>'
        '</body></html>';
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold Price',
      country: 'United States',
      currency: 'USD',
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(
        spec,
        ProductPage(Uri.parse('https://example.com/gold'), 200, body),
        now: now,
      ),
      isNull,
      reason: 'ambiguity must fail closed, never pick a number',
    );
  });

  test('signed, percent and fee figures are never the quote', () {
    final body = '<html><body>'
        '<p>29-OCT-2026 Today -45.46 USD -1.12%</p>'
        '<p>commission 12.50 USD 29-OCT-2026</p>'
        '</body></html>';
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold Price',
      country: 'United States',
      currency: 'USD',
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );
    expect(
      SourceCandidateValidator.validateReadableQuote(
        spec,
        ProductPage(Uri.parse('https://example.com/gold'), 200, body),
        now: now,
      ),
      isNull,
    );
  });

  test('ongoing checker reads the same value discovery proved', () async {
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold Price',
      country: 'United States',
      currency: 'USD',
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );
    final page = fixturePage(
      'https://goldpricez.com/us/ounce',
      'goldpricez_us_ounce.html',
    );
    final candidate = SourceCandidateValidator.validateReadableQuote(
      spec,
      page,
      now: now,
    )!;
    final reviewed = ReviewedSource(spec, candidate);
    final agent = Agent(
      title: 'Gold watch',
      originalPrompt: 'gold price above 4030',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026),
      nextCheckAt: DateTime(2026),
      checkInterval: const Duration(minutes: 30),
      condition: spec.condition,
      target: spec.target,
      sourceUrl: reviewed.candidate.url.toString(),
      sourceIdentity: reviewed.identity,
    );
    final outcome = await DiscoveredSourceReader.fetch(
      agent,
      reader: h.FakeReader(page),
    );
    expect(outcome.value, 4022.28,
        reason: 'checker must agree with discovery and revalidation');
  });

  test('a pre-flag identity from 1.1.18 still reads via the fallback chain',
      () async {
    const spec = DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold Price',
      country: 'United States',
      currency: 'USD',
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );
    final page = fixturePage(
      'https://goldpricez.com/us/ounce',
      'goldpricez_us_ounce.html',
    );
    final candidate = SourceCandidateValidator.validateReadableQuote(
      spec,
      page,
      now: now,
    )!;
    final reviewed = ReviewedSource(spec, candidate);
    // Simulate an identity saved by 1.1.18, which dropped the tier flags.
    final legacyIdentity = reviewed.identity
        .replaceAll(',"marketQuote":true', '')
        .replaceAll(',"readableQuote":true', '');
    expect(legacyIdentity, isNot(contains('readableQuote')));
    final agent = Agent(
      title: 'Gold watch',
      originalPrompt: 'gold price above 4030',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026),
      nextCheckAt: DateTime(2026),
      checkInterval: const Duration(minutes: 30),
      condition: spec.condition,
      target: spec.target,
      sourceUrl: reviewed.candidate.url.toString(),
      sourceIdentity: legacyIdentity,
    );
    final outcome = await DiscoveredSourceReader.fetch(
      agent,
      reader: h.FakeReader(page),
    );
    expect(outcome.value, 4022.28,
        reason: 'sources saved before the flag fix must keep reading');
  });
}
