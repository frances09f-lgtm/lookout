import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/page_fetch.dart';

void main() {
  const url = 'https://www.amazon.in/dp/B0EXAMPLE1';

  String page({required String priceBlock, String extra = ''}) =>
      '<html><body>$priceBlock$extra</body></html>';

  group('PageValueFetcher.amazonOffer', () {
    test('reads the buy-box price, not the EMI amount', () {
      final body = page(
        priceBlock:
            '<div id="corePrice_feature_div"><span class="a-price"><span class="a-offscreen">₹59,900.00</span></span></div>',
        extra:
            '<div id="installmentCalculator_feature_div">EMI starts at ₹2,904.00 per month.</div>',
      );
      final r = PageValueFetcher.amazonOffer(body, url);
      expect(r.price, 59900);
      expect(r.unavailable, isFalse);
    });

    test('a page with only EMI amounts yields no price', () {
      final body = page(
        priceBlock: '<div>No cost EMI starts at ₹2,904.00 per month</div>',
      );
      expect(PageValueFetcher.amazonOffer(body, url).price, isNull);
    });

    test('flags currently unavailable items via the availability block', () {
      final body = page(
        priceBlock:
            '<div id="corePrice_feature_div"><span class="a-offscreen">₹59,900.00</span></div>',
        extra:
            '<div id="availability"><span>Currently unavailable. We don\'t know when this item will be back in stock.</span></div>',
      );
      final r = PageValueFetcher.amazonOffer(body, url);
      expect(r.unavailable, isTrue);
    });

    test('unavailable strings outside the availability block do not flag', () {
      // Real in-stock pages still carry "currently unavailable" text in
      // hidden variant slots; only the #availability block counts.
      final body = page(
        priceBlock:
            '<div id="corePrice_feature_div"><span class="a-price"><span class="a-offscreen">₹59,900.00</span></span></div>',
        extra:
            '<div id="twister"><span>Currently unavailable.</span></div><div id="availability"><span class="a-color-success">In stock</span></div>',
      );
      final r = PageValueFetcher.amazonOffer(body, url);
      expect(r.unavailable, isFalse);
      expect(r.price, 59900);
    });

    test('conflicting buy-box prices are ambiguous, never guessed', () {
      final body = page(
        priceBlock:
            '<div id="corePrice_feature_div"><span class="a-offscreen">₹59,900.00</span><span class="a-offscreen">₹62,999.00</span></div>',
      );
      expect(PageValueFetcher.amazonOffer(body, url).price, isNull);
    });

    test('ignores non-Amazon pages', () {
      final body = page(
        priceBlock:
            '<div id="corePrice_feature_div"><span class="a-offscreen">₹59,900.00</span></div>',
      );
      final r = PageValueFetcher.amazonOffer(
        body,
        'https://www.flipkart.com/item/p/itm123',
      );
      expect(r.price, isNull);
      expect(r.unavailable, isFalse);
    });

    test('host detection covers regional Amazon stores', () {
      expect(PageValueFetcher.isAmazonHost('https://www.amazon.in/dp/X'), isTrue);
      expect(PageValueFetcher.isAmazonHost('https://amazon.co.uk/dp/X'), isTrue);
      expect(PageValueFetcher.isAmazonHost('https://www.amazon.com/dp/X'), isTrue);
      expect(PageValueFetcher.isAmazonHost('https://www.amazonin.example.com/x'), isFalse);
      expect(PageValueFetcher.isAmazonHost('https://www.flipkart.com/x'), isFalse);
    });
  });
}
