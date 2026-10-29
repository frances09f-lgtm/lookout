import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/source_discovery.dart';

ProductPage _mk({
  required String url,
  required String title,
  required List<String> priceElements,
  String stock = 'In stock',
}) {
  final els = priceElements
      .map((e) => e)
      .join('\n');
  return ProductPage(
    Uri.parse(url),
    200,
    '<html><head><title>$title</title></head><body>$els<div id="availability">$stock</div></body></html>',
  );
}

void main() {
  final spec = DiscoveryTaskParser.parse(
    'Tell me when Samsung S25 256gb drops below ₹56000',
    country: 'IN',
    currency: 'INR',
  ).spec!;
  const url =
      'https://www.amazon.in/Samsung-Icyblue-Storage-Snapdragon-Display/dp/B0DVC79X2W';
  const title =
      'Samsung Galaxy S25 5G (Icyblue, 12GB RAM, 256GB Storage) | Amazon.in';
  String priceEl(String amount, [String cls = 'a-price']) =>
      '<span class="$cls">₹$amount</span>';

  ProductPage xm5Page(String body) => ProductPage(
        Uri.parse(
          'https://www.vijaysales.com/p/206834/sony-wh-1000xm5-headphones-black',
        ),
        200,
        '<html><head><title>'
        'Sony WH-1000XM5 Wireless Noise-Canceling Headphones (Black) | Vijay Sales'
        '</title></head><body>'
        '<h1>Sony WH-1000XM5 Wireless Noise-Canceling Headphones (Black)</h1>'
        '<p class="price">₹26,990</p><p class="price">₹26,990</p><p class="price">₹26,990</p>'
        '$body</body></html>',
      );

  DiscoverySpec xm5Spec() => DiscoveryTaskParser.parse(
        'Tell me when Sony WH-1000XM5 drops below ₹25000',
        country: 'IN',
        currency: 'INR',
      ).spec!;

  test('.com merchant with own checkout CTA and India signal accepts', () {
    final v = SourceCandidateValidator.validate(
      xm5Spec(),
      xm5Page('<button type="button">Add to Cart</button>'
          '<div>Check delivery at your pincode</div>'
          '<div>Imported by Sony India Private Limited</div>'),
    );
    expect(v, isNotNull);
    expect(v!.price, 26990);
    expect(v.currency, 'INR');
  });

  test('a Notify Me page is not available stock', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<button type="button">Notify Me</button>'
            '<div>Check delivery at your pincode</div>'
            '<div>Imported by Sony India Private Limited</div>'),
      ),
      isNull,
    );
  });

  test('disabled-only CTA does not prove stock', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<button type="button" disabled>Add to Cart</button>'
            '<div>Check delivery at your pincode</div>'
            '<div>Imported by Sony India Private Limited</div>'),
      ),
      isNull,
    );
  });

  test('pre-order pages reject even with an enabled CTA', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<button type="button">Add to Cart</button>'
            '<div>Pre-order now, ships soon. Check pincode</div>'
            '<div>Imported by Sony India Private Limited</div>'),
      ),
      isNull,
    );
  });

  test('.com page without an explicit India signal rejects (currency is not evidence)', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<button type="button">Add to Cart</button>'),
      ),
      isNull,
    );
  });

  test('pincode wording without the country named anywhere rejects', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<button type="button">Add to Cart</button>'
            '<div>Check delivery at your pincode</div>'),
      ),
      isNull,
    );
  });

  test('manufacturer or importer India address alone is not storefront evidence', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<button type="button">Add to Cart</button>'
            '<div>Imported by Sony India Private Limited</div>'),
      ),
      isNull,
    );
  });

  test('picker page with in-stock text outside the buy box rejects', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<div id="twister"><span>Black</span><span>Silver</span></div>'
            '<p class="promo">In stock</p>'
            '<button type="button">Add to Cart</button>'
            '<div>Check delivery at your pincode</div>'
            '<div>Imported by Sony India Private Limited</div>'),
      ),
      isNull,
    );
  });

  test('picker page with only a generic enabled CTA cannot prove the selected variant', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<div id="twister"><span>Black</span><span>Silver</span></div>'
            '<button type="button">Add to Cart</button>'
            '<div>Imported by Sony India Private Limited</div>'),
      ),
      isNull,
    );
  });

  test('picker page with explicit in-stock text for the titled variant accepts', () {
    final v = SourceCandidateValidator.validate(
      xm5Spec(),
      xm5Page('<div id="twister"><span>Black</span><span>Silver</span></div>'
          '<div id="availability">In stock</div>'
          '<button type="button">Add to Cart</button>'
          '<div>Check delivery at your pincode</div>'
          '<div>Imported by Sony India Private Limited</div>'),
    );
    expect(v, isNotNull);
    expect(v!.price, 26990);
  });

  test('a buy link that leads to another domain is a tracker, not a checkout', () {
    expect(
      SourceCandidateValidator.validate(
        xm5Spec(),
        xm5Page('<a href="https://www.amazon.in/dp/B09XS7JWHH">Buy Now</a>'
            '<div>Check delivery at your pincode</div>'),
      ),
      isNull,
    );
  });

  test('accessory pages naming the model are not the product', () {
    final xm5 = DiscoveryTaskParser.parse(
      'Tell me when Sony WH-1000XM5 drops below ₹25000',
      country: 'IN',
      currency: 'INR',
    ).spec!;
    for (final t in [
      'Replacement Ear Pads for Sony WH-1000XM5 | Vijay Sales',
      'Sony WH-1000XM5 Hard Case Cover | Vijay Sales',
      'Sony WH-1000XM4 Wireless Noise-Canceling Headphones (Black) | Vijay Sales',
    ]) {
      final page = _mk(
        url: 'https://www.vijaysales.com/p/1/accessory',
        title: t,
        priceElements: [
          '<p class="price">₹1,299</p>',
          '<p class="price">₹1,299</p>',
          '<p class="price">₹1,299</p>',
          '<button type="button">Add to Cart</button>',
          '<div>Check delivery at your pincode</div>',
          '<div>Imported by Sony India Private Limited</div>',
        ],
      );
      expect(SourceCandidateValidator.validate(xm5, page), isNull, reason: t);
    }
  });

  test('a Notify Me page is not available stock', () {
    final xm5 = DiscoveryTaskParser.parse(
      'Tell me when Sony WH-1000XM5 drops below ₹25000',
      country: 'IN',
      currency: 'INR',
    ).spec!;
    final page = _mk(
      url: 'https://www.vijaysales.com/p/206834/sony-wh-1000xm5-headphones-black',
      title:
          'Sony WH-1000XM5 Wireless Noise-Canceling Headphones (Black) | Vijay Sales',
      priceElements: [
        '<p class="price">₹26,990</p>',
        '<p class="price">₹26,990</p>',
        '<p class="price">₹26,990</p>',
      ],
      stock: 'Notify Me',
    );
    expect(SourceCandidateValidator.validate(xm5, page), isNull);
  });

  test('merchant page with dominant current price accepts, labelled as HTML reading', () {
    final page = _mk(
      url: url,
      title: title,
      priceElements: [
        priceEl('62,999.00'),
        priceEl('62,999.00', 'tp_price_block_total_price'),
        priceEl('62,999.00'),
        '<span class="a-price a-text-price apex-basisprice-value">₹94,999</span>',
        '<span class="a-color-price">₹2,799.00</span>',
      ],
    );
    final v = SourceCandidateValidator.validate(spec, page);
    expect(v, isNotNull);
    expect(v!.price, 62999);
    expect(v.visibleOffer, isTrue);
    expect(v.readingLabel, contains('read from merchant page text'));
  });
  test('wrong variant title rejects before any price is read', () {
    final page = _mk(
      url: url,
      title: 'Samsung Galaxy S25 Ultra 5G (12GB RAM, 256GB Storage)',
      priceElements: [priceEl('1,29,999.00')],
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('MRP-only page rejects: strikethrough/basis price is not a current offer', () {
    final page = _mk(
      url: url,
      title: title,
      priceElements: [
        '<span class="a-price a-text-price apex-basisprice-value">M.R.P.: ₹94,999.00</span>',
        '<span class="list-price">₹94,999.00</span>',
      ],
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('EMI amount is never read as the price', () {
    final page = _mk(
      url: url,
      title: title,
      priceElements: [
        '<span class="emi-price">EMI starting ₹3,058/month</span>',
        '<span class="a-price">No Cost EMI ₹5,250 per month</span>',
      ],
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('two equal-strength distinct prices are ambiguous and reject', () {
    final page = _mk(
      url: url,
      title: title,
      priceElements: [
        priceEl('62,999.00'),
        priceEl('62,999.00'),
        priceEl('58,999.00'),
        priceEl('58,999.00'),
      ],
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('savings-framed amount is excluded', () {
    final page = _mk(
      url: url,
      title: title,
      priceElements: [
        '<span class="apex-pricetopay-accessibility-label">₹62,999.00 with 34 percent savings</span>',
      ],
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('out of stock rejects even with a clean price', () {
    final page = _mk(
      url: url,
      title: title,
      priceElements: [priceEl('62,999.00')],
      stock: 'Currently unavailable',
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('missing explicit stock text rejects', () {
    final page = _mk(
      url: url,
      title: title,
      priceElements: [priceEl('62,999.00')],
      stock: 'Free delivery tomorrow',
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('non-ccTLD merchant host cannot prove the country', () {
    final page = _mk(
      url: 'https://www.example.com/samsung-s25-256gb',
      title: title,
      priceElements: [priceEl('62,999.00')],
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('wrong currency tokens are ignored, no INR price means reject', () {
    final page = _mk(
      url: url,
      title: title,
      priceElements: ['<span class="a-price">\$999.00</span>'],
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
}
