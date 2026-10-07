import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/page_fetch.dart';
import 'package:lookout/services/browser_price_check.dart';

void main() {
  const base = 'https://in.bookmyshow.com/movies/c/seat-layout/ET1/V/123/';
  final now = DateTime.utc(2026, 10, 7, 18, 31); // Oct 8 in India.
  test('generic listing needs exact session even if it contains a price', () {
    expect(
      PageValueFetcher.sourceIssue(
        'https://in.bookmyshow.com/movies',
        now: now,
      ),
      contains('not an exact'),
    );
  });
  test('date code uses India day not UTC and rejects invalid dates', () {
    expect(
      PageValueFetcher.sourceIssue('${base}20261007', now: now),
      contains('past date'),
    );
    expect(PageValueFetcher.sourceIssue('${base}20261008', now: now), isNull);
    expect(
      PageValueFetcher.sourceIssue('${base}20260230', now: now),
      contains('invalid date'),
    );
  });
  test('other sources unaffected and no silent show substitution', () {
    expect(
      PageValueFetcher.sourceIssue('https://shop.example/item', now: now),
      isNull,
    );
    expect(
      PageValueFetcher.sourceIssue('https://in.bookmyshow.com/movie', now: now),
      contains('Set source page'),
    );
  });
  test('manual browser rejects past link before native call', () async {
    final result = await BrowserPriceCheck.read('${base}20261007', now: now);
    expect(result.ok, false);
    expect(result.detail, contains('past date'));
  });
}
