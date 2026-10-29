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
