import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/page_fetch.dart';

void main() {
  group('PageValueFetcher.extractValue', () {
    test('picks the currency-tagged number', () {
      expect(
        PageValueFetcher.extractValue(
          'Drishyam 3 tickets now booking. Price: ₹180 onwards. 3 shows',
        ),
        180,
      );
    });
    test('prefers the first currency tag when several exist', () {
      expect(PageValueFetcher.extractValue('Rs. 250 was Rs. 300'), 250);
    });
    test('falls back to a number next to price words', () {
      expect(PageValueFetcher.extractValue('ticket price 175 today'), 175);
      expect(PageValueFetcher.extractValue('175 is the current price'), 175);
    });
    test('returns null when nothing looks like a value', () {
      expect(
        PageValueFetcher.extractValue('hello world, no numbers here'),
        isNull,
      );
    });
    test('handles thousands separators', () {
      expect(PageValueFetcher.extractValue('₹50,000'), 50000);
    });
  });

  group('PageValueFetcher.htmlToText', () {
    test('strips scripts, styles and tags', () {
      final html =
          '<html><head><style>body{color:red}</style><script>var x=1000;</script></head>'
          '<body><div class="price">₹199</div></body></html>';
      final text = PageValueFetcher.htmlToText(html);
      expect(text.contains('1000'), isFalse);
      expect(text.contains('color'), isFalse);
      expect(text, contains('₹199'));
    });
    test('decodes the rupee entity', () {
      expect(
        PageValueFetcher.htmlToText('<p>&#8377;200</p>'),
        contains('₹200'),
      );
    });
    test('full pipeline finds a price inside a page', () {
      final html =
          '<html><script>var bogus=99999;</script><body><span>Ticket Price</span>'
          '<b>&#8377;180</b></body></html>';
      expect(
        PageValueFetcher.extractValue(PageValueFetcher.htmlToText(html)),
        180,
      );
    });
  });

  group('BookMyShow seat-layout support', () {
    const watchUrl =
        'https://in.bookmyshow.com/movies/ichalkaranji/seat-layout/ET00507738/frts/33328/20261007';
    // Real response shape captured from in.bookmyshow.com on 2026-10-07.
    const liveJson =
        '{"data":{"meta":{"version":23},"eventData":'
        '{"eventTitle":"Hanuman Ansh"},"showTimes":[{"sessionId":"33328",'
        '"showTime":"07:00 PM","availStatus":"0","categories":'
        '[{"priceCode":"0003","curPrice":"100.00","priceDesc":"CLUB"},'
        '{"priceCode":"0004","curPrice":"100.00","priceDesc":"GOLD"}]}]}}';

    test('maps a seat-layout watch URL to the JSON endpoint', () {
      expect(
        PageValueFetcher.bookMyShowApiUrl(watchUrl),
        'https://in.bookmyshow.com/api/movies-data/seatlayout/v1/primary'
        '?eventCode=ET00507738&dateCode=20261007&venueCode=frts',
      );
      expect(PageValueFetcher.bookMyShowSessionId(watchUrl), '33328');
    });

    test('ignores non-BookMyShow URLs', () {
      expect(
        PageValueFetcher.bookMyShowApiUrl('https://example.com/p'),
        isNull,
      );
      expect(
        PageValueFetcher.bookMyShowApiUrl('https://in.bookmyshow.com/movies'),
        isNull,
      );
    });

    test('reads the lowest category price for the matching session', () {
      final hit = PageValueFetcher.extractBookMyShowPrice(
        liveJson,
        sessionId: '33328',
      );
      expect(hit, isNotNull);
      expect(hit!.$1, 100.0);
      expect(hit.$2, contains('CLUB'));
      expect(hit.$2, contains('GOLD'));
    });

    test('missing watched session fails instead of choosing another show', () {
      expect(
        PageValueFetcher.extractBookMyShowPrice(liveJson, sessionId: '99999'),
        isNull,
      );
      expect(PageValueFetcher.extractBookMyShowPrice(liveJson), isNull);
    });

    test('never invents a price from bad payloads', () {
      expect(PageValueFetcher.extractBookMyShowPrice('not json'), isNull);
      expect(PageValueFetcher.extractBookMyShowPrice('{"data":{}}'), isNull);
      expect(
        PageValueFetcher.extractBookMyShowPrice(
          '{"data":{"showTimes":[{"sessionId":"1","categories":[]}]}}',
        ),
        isNull,
      );
    });
  });
}
