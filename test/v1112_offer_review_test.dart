// Exact page evidence: the JSON-LD Product blocks below are copied verbatim
// from the live pages the user tried (fetched 2026-10-25):
// - iplanet.one/products/iphone-15-mtp93hn-a (Offer, OutOfStock, no region)
// - vijaysales.com/p/220954/apple-iphone-15-256-gb-storage-blue (AggregateOffer)
// Diagnosis messages must name what the page actually says; acceptance rules
// (exact Offer, stock, variant, country) are unchanged.
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/source_discovery.dart';

const _iplanetProduct = r'''{"@context": "https://schema.org", "@type": "Product", "@id": "https://iplanet.one/products/iphone-15-mtp93hn-a#product", "name": "Apple iPhone 15 256GB Blue", "description": "Apple iPhone 15 brings you Dynamic Island, a 48MP Main camera, and USB-C\u0097all in a durable color-infused glass and aluminum design.", "image": ["https://iplanet.one/cdn/shop/files/iPhone_15_Blue_PDP_Image_Position-1__en-IN_dd67c045-7eab-42df-8594-221b12345acd.jpg"], "sku": "MTP93HN/A", "mpn": "MTP93HN/A", "brand": {"@type": "Brand", "name": "Apple"}, "category": "Mobile & Smart Phones", "url": "https://iplanet.one/products/iphone-15-mtp93hn-a", "color": "Blue", "offers": [{"@type": "Offer", "sku": "MTP93HN/A", "gtin12": "195949037375", "availability": "http://schema.org/OutOfStock", "price": "69900.0", "priceCurrency": "INR", "url": "https://iplanet.one/products/iphone-15-mtp93hn-a?variant=46896641671477", "itemCondition": "https://schema.org/NewCondition"}]}''';
const _vijaysalesProduct = r'''{"@context": "http://schema.org", "@type": "Product", "name": "Apple iPhone 15 (256 GB Storage, Blue)", "url": "https://www.vijaysales.com/p/220954/apple-iphone-15-256-gb-storage-blue", "sku": "220954", "mpn": "", "gtin": "", "category": "Mobiles and Accessories", "description": "Buy Apple iPhone 15 (256 GB Storage, Blue) online at best prices from Vijay Sales. Check product details, expert reviews, ratings, and more. Shop now!", "image": ["https://vsprod.vijaysales.com/media/catalog/product/2/2/220954-image1_2.jpg", "https://vsprod.vijaysales.com/media/catalog/product/2/2/220954-image2_2.jpg", "https://vsprod.vijaysales.com/media/catalog/product/2/2/220954-image3_2.jpg", "https://vsprod.vijaysales.com/media/catalog/product/2/2/220954-image4_2.jpg", "https://vsprod.vijaysales.com/media/catalog/product/2/2/220954-image5_2.jpg", "https://vsprod.vijaysales.com/media/catalog/product/2/2/220954-image6_2.jpg"], "brand": {"@type": "Brand", "name": "Apple"}, "offers": {"availability": "https://schema.org/OutofStock", "@type": "AggregateOffer", "priceCurrency": "INR", "price": "69900", "lowPrice": "69900", "offerCount": "0", "itemCondition": "https://schema.org/NewCondition"}}''';

ProductPage _page(String url, String productJson) => ProductPage(
      Uri.parse(url),
      200,
      '<html><head><script type="application/ld+json">$productJson</script></head><body></body></html>',
    );

const _spec = DiscoverySpec(
  model: 'iphone 15',
  storageGb: 256,
  target: 60000,
  condition: WatchCondition.lessThan,
  country: 'IN',
  currency: 'INR',
  colour: 'Blue',
);

void main() {
  test('iPlanet: affirmative out-of-stock and missing country are named; variant inherited from the single product', () {
    final page = _page(
      'https://iplanet.one/products/iphone-15-mtp93hn-a',
      _iplanetProduct,
    );
    // Never accepted for monitoring (out of stock, no eligible country).
    expect(SourceCandidateValidator.validate(_spec, page), isNull);
    final review = SourceCandidateValidator.reviewOnly(_spec, page)!;
    expect(
      review.blockers,
      contains('Offer 1: the page reports this offer out of stock.'),
    );
    expect(
      review.blockers,
      contains('Offer 1: seller does not specify an eligible country.'),
    );
    expect(
      review.blockers.any((s) => s.contains('in-stock availability is not verified')),
      isFalse,
      reason: 'the page affirmatively says out of stock; do not call it unverified',
    );
    expect(
      review.reportedOffers.single,
      'Offer 1: Apple iPhone 15 256GB Blue; INR 69900.00',
    );
  });

  test('VijaySales: AggregateOffer is read for an honest report, still never accepted', () {
    final page = _page(
      'https://www.vijaysales.com/p/220954/apple-iphone-15-256-gb-storage-blue',
      _vijaysalesProduct,
    );
    expect(SourceCandidateValidator.validate(_spec, page), isNull);
    final review = SourceCandidateValidator.reviewOnly(_spec, page)!;
    expect(
      review.blockers,
      contains('Offer 1: the page aggregates seller offers instead of naming one exact offer.'),
    );
    expect(
      review.blockers,
      contains('Offer 1: the page reports this offer out of stock.'),
    );
    expect(
      review.blockers,
      contains('Offer 1: seller does not specify an eligible country.'),
    );
    expect(
      review.blockers.any((s) => s.contains('unsupported offer structure')),
      isFalse,
    );
    expect(
      review.reportedOffers.single,
      'Offer 1: Apple iPhone 15 (256 GB Storage, Blue); INR 69900.00',
    );
  });

  test('in-stock single-price AggregateOffer is reported but still blocked as not one exact offer', () {
    final page = _page(
      'https://shop.example.com/product',
      '{"@type":"Product","name":"Apple iPhone 15 256GB Blue","url":"https://shop.example.com/product","offers":{"@type":"AggregateOffer","price":"61000","lowPrice":"61000","priceCurrency":"INR","availability":"https://schema.org/InStock","offerCount":"3","eligibleRegion":"IN"}}',
    );
    expect(SourceCandidateValidator.validate(_spec, page), isNull);
    final review = SourceCandidateValidator.reviewOnly(_spec, page)!;
    expect(
      review.blockers,
      contains('Offer 1: the page aggregates seller offers instead of naming one exact offer.'),
    );
    expect(
      review.blockers.any((s) => s.contains('out of stock')),
      isFalse,
    );
    expect(
      review.reportedOffers.single,
      'Offer 1: Apple iPhone 15 256GB Blue; INR 61000.00',
    );
  });

  test('unrecognized availability stays "not verified"; multi-offer pages never inherit the variant', () {
    final page = _page(
      'https://shop.example.com/product',
      '{"@type":"Product","name":"Apple iPhone 15 256GB Blue","url":"https://shop.example.com/product","offers":[{"@type":"Offer","price":"61000","priceCurrency":"INR","availability":"https://schema.org/LimitedAvailability","eligibleRegion":"IN"},{"@type":"Offer","price":"62000","priceCurrency":"INR","availability":"InStock","eligibleRegion":"IN"}]}',
    );
    final review = SourceCandidateValidator.reviewOnly(_spec, page)!;
    expect(
      review.blockers,
      contains('Offer 1: in-stock availability is not verified.'),
    );
    expect(
      review.reportedOffers.first,
      'Offer 1: variant not specified; INR 61000.00',
    );
  });
}
