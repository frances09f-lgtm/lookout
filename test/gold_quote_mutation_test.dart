// Mutation pins for the readable-quote proof: each test takes a page that
// presents a gold quote and mutates ONE property. The proof must keep
// reading the real headline quote, and must reject stale, ambiguous,
// wrong-unit, or integer-only presentations instead of guessing.
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/source_discovery.dart';

DiscoverySpec goldSpec({String currency = 'USD'}) => DiscoverySpec(
      kind: 'productPrice',
      model: 'Gold',
      country: 'India',
      currency: currency,
      storageGb: 0,
      target: 4030,
      condition: WatchCondition.greaterThan,
    );

String page({
  String h1 = 'Gold Price per Ounce in US Dollar',
  String headlineValue = '= \$4,025.66 USD',
  String stamp = '29-OCT-2026 08:45:20 AM',
  String stampLabel = 'Updated: ',
  bool stampNearHeadline = false,
  int stampPadChars = 0,
  bool stats = true,
  bool statsFirst = false,
}) {
  const title = '<title>Gold Price per Ounce in US Dollar (USD) Today</title>';
  final headline = stampNearHeadline
      ? '<p>$headlineValue ($stamp)</p>'
      : '<p>$headlineValue</p>';
  const statBlock = '<p>Current price stats: Open: 4,067.73 USD '
      'High: 4,069.15 USD Low: 4,015.76 USD '
      'Difference (High-Low)= 53.39 USD</p>';
  final stampBlock = stampNearHeadline ? '' : '<p>$stampLabel$stamp (UTC-04:00, New-York Time)</p>';
  final pad = stampPadChars > 0 ? '<p>${'padding filler text ' * (stampPadChars ~/ 20)}</p>' : '';
  final body = statsFirst
      ? '$statBlock <h1>$h1</h1> $headline $pad $stampBlock'
      : '<h1>$h1</h1> $headline $statBlock $pad $stampBlock';
  return '<html><head>$title</head><body>$body</body></html>';
}

ProductPage at(String html, [String url = 'https://goldpricez.com/us/ounce']) =>
    ProductPage(Uri.parse(url), 200, html);

void main() {
  final now = DateTime(2026, 10, 29, 18);

  test('baseline: headline quote read, stats ignored', () {
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(), at(page()), now: now);
    expect(r?.price, 4025.66);
  });

  test('mutation: stats block before the headline still reads the headline', () {
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(), at(page(statsFirst: true)), now: now);
    expect(r?.price, 4025.66);
  });

  test('mutation: stale headline stamp + current stats rejects', () {
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(),
      at(page(stamp: '25-OCT-2026 08:45:20 AM', stampNearHeadline: true)),
      now: now,
    );
    expect(r, isNull,
        reason: 'a stale date glued to the quote is explicit stale evidence; '
            'fresh stats must not rescue it');
  });

  test('mutation: integer-only quote rejects (cannot prove quote vs counter)', () {
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(), at(page(headlineValue: '= \$4,025 USD')), now: now);
    expect(r, isNull);
  });

  test('mutation: wrong unit in headline rejects (ounce URL, gram headline)', () {
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(),
      at(page(h1: 'Gold Price per Gram in US Dollar',
          headlineValue: '= \$129.42 USD')),
      now: now,
    );
    expect(r, isNull, reason: 'a gram quote must never stand in for an ounce');
  });

  test('mutation: second currency value does not disturb the USD quote', () {
    final html = page(headlineValue: '= \$4,025.66 USD = €3,480.20 EUR');
    final usd = SourceCandidateValidator.validateReadableQuote(
      goldSpec(), at(html), now: now);
    expect(usd?.price, 4025.66);
    expect(usd?.currency, 'USD');
  });

  test('mutation: fresh stamp tied to stats only (no quote label) rejects', () {
    // The stamp after goldpricez's stats block belongs to the Performance
    // section; a headline with no stamp of its own must not borrow it.
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(),
      at(page(
        stampLabel: 'Performance (Gold/Ounce) in USD, as shown live ',
        stampPadChars: 400,
      )),
      now: now,
    );
    expect(r, isNull,
        reason: 'a stamp not labeled as the quote update time is no proof');
  });

  test('mutation: unitless gold task never accepts a gram page', () {
    final gramPage = page(
      h1: 'Gold Price per Gram in US Dollar',
      headlineValue: '= \$129.42 USD',
    ).replaceAll('Gold Price per Ounce in US Dollar (USD) Today',
        'Gold Price per Gram in US Dollar (USD) Today');
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(),
      at(gramPage, 'https://goldpricez.com/us/gram'),
      now: now,
    );
    expect(r, isNull,
        reason: 'a unitless gold task intends the ounce price; gram never substitutes');
  });

  test('mutation: EUR task against a USD-only quote rejects', () {
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(currency: 'EUR'), at(page()), now: now);
    expect(r, isNull);
  });

  test('mutation: two distinct dated USD values reject as ambiguous', () {
    final html = page(
      headlineValue: '= \$4,025.66 USD and a second quote \$4,111.11 USD');
    final r = SourceCandidateValidator.validateReadableQuote(
      goldSpec(), at(html), now: now);
    expect(r, isNull, reason: 'two provable distinct values is ambiguous');
  });
}
