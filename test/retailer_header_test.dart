import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/page_fetch.dart';

void main() {
  const url = 'https://www.reliancedigital.in/product/exact';
  test('selling header separate from MRP; description/EMI ignored', () {
    final r = PageValueFetcher.retailerHeader(
      '<div class="product-price">₹58,990</div><div class="product-price"><span class="mrp-text">MRP</span>₹59,900</div><p>EMI ₹180, description ₹54000</p>',
      url,
    );
    expect(r.price, 58990);
    expect(r.mrpOnly, false);
  });
  test('MRP only is no confirmed offer', () {
    final r = PageValueFetcher.retailerHeader(
      '<div class="product-price"><span>MRP</span>₹59,900</div><p>currently going for Rs.58990</p>',
      url,
    );
    expect(r.price, isNull);
    expect(r.mrpOnly, true);
  });
  test('unavailable page cannot become in stock from schema', () {
    expect(
      PageValueFetcher.retailerHeader(
        '<p>Currently unavailable online. Visit nearest store.</p><div class="product-price">₹58,990</div>',
        url,
      ).unavailable,
      true,
    );
  });
  test('conflicting header prices ambiguous', () {
    expect(
      PageValueFetcher.retailerHeader(
        '<div class="product-price">₹58,990</div><div class="product-price">₹57,990</div>',
        url,
      ).price,
      isNull,
    );
  });
  test('other site generic product-price not trusted', () {
    expect(
      PageValueFetcher.retailerHeader(
        '<div class="product-price">₹180</div>',
        'https://other.test',
      ).price,
      isNull,
    );
  });
}
