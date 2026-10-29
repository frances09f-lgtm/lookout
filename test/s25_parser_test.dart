import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/source_discovery.dart';

ProductPage _page(Map<String, Object?> product, String url) {
  final ld = '<script type="application/ld+json">${jsonEncode(product)}</script>';
  return ProductPage(Uri.parse(url), 200, '<html><head>$ld</head><body></body></html>');
}

Map<String, Object?> _sellerProduct({
  required String name,
  String? productUrl,
  Object? offeredBy,
  Object? eligibleRegion,
  Object? offerType = 'Offer',
  String price = '62999',
}) => {
  '@type': 'Product',
  'name': name,
  if (productUrl != null) 'url': productUrl,
  'offers': {
    '@type': offerType,
    'priceCurrency': 'INR',
    'price': price,
    'availability': 'https://schema.org/InStock',
    if (offeredBy != null) 'offeredBy': offeredBy,
    if (eligibleRegion != null) 'eligibleRegion': eligibleRegion,
  },
};

void main() {
  final spec = DiscoveryTaskParser.parse(
    'Tell me when Samsung S25 256gb drops below ₹56000',
    country: 'IN',
    currency: 'INR',
  ).spec!;
  const pageUrl =
      'https://pricehistory.app/p/samsung-galaxy-s25-5g-12gb-ram-256gb-OYh05sce';
  const variantName = 'Samsung Galaxy S25 5G 12GB RAM 256GB Storage Mint';

  test('S25 user prompt parses storage out of the model', () {
    expect(spec.model, 'Samsung S25');
    expect(spec.storageGb, 256);
    expect(spec.target, 56000);
    expect(spec.currency, 'INR');
  });
  test('conflicting storage sizes ask instead of guessing', () {
    final clar = DiscoveryTaskParser.parse(
      'Tell me when Samsung S25 12gb ram 256gb drops below 56000',
      country: 'IN',
      currency: 'INR',
    );
    expect(clar.spec, isNull);
    expect(clar.questions, isNotEmpty);
  });
  test('quote and plain-product prompts keep storage zero', () {
    final q = DiscoveryTaskParser.parse(
      'Tell me when bitcoin drops below 9000000',
      country: 'IN',
      currency: 'INR',
    );
    expect(q.spec!.storageGb, 0);
    final p = DiscoveryTaskParser.parse(
      'Check Sony WH-1000XM5 price below 25000',
      country: 'IN',
      currency: 'INR',
    );
    expect(p.spec!.model, 'Sony WH-1000XM5');
    expect(p.spec!.storageGb, 0);
  });

  test('seller offer on country ccTLD proves region without eligibleRegion', () {
    final page = _page(
      _sellerProduct(
        name: variantName,
        offeredBy: {'@type': 'Organization', 'name': 'amazon.in'},
      ),
      pageUrl,
    );
    final v = SourceCandidateValidator.validate(spec, page);
    expect(v, isNotNull);
    expect(v!.price, 62999);
    expect(v.currency, 'INR');
    expect(v.country, 'IN');
  });
  test('foreign storefront domain does not prove the requested country', () {
    final page = _page(
      _sellerProduct(
        name: variantName,
        offeredBy: {'@type': 'Organization', 'name': 'amazon.com'},
      ),
      pageUrl,
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('bare seller name without domain proves neither seller nor region', () {
    final page = _page(
      _sellerProduct(
        name: variantName,
        offeredBy: {'@type': 'Organization', 'name': 'Amazon'},
      ),
      pageUrl,
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('no self-link and no seller evidence still rejects', () {
    final page = _page(_sellerProduct(name: variantName), pageUrl);
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('self-link to a different page still rejects', () {
    final page = _page(
      _sellerProduct(
        name: variantName,
        productUrl: 'https://pricehistory.app/other-product',
        eligibleRegion: 'IN',
      ),
      pageUrl,
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('matching self-link with explicit eligibleRegion still accepts', () {
    final page = _page(
      _sellerProduct(
        name: variantName,
        productUrl: pageUrl,
        eligibleRegion: 'IN',
      ),
      pageUrl,
    );
    expect(SourceCandidateValidator.validate(spec, page), isNotNull);
  });
  test('aggregate offer range still rejects even on a country ccTLD', () {
    final page = _page(
      _sellerProduct(
        name: variantName,
        productUrl: pageUrl,
        offerType: 'AggregateOffer',
        offeredBy: {'@type': 'Organization', 'name': 'amazon.in'},
      ),
      pageUrl,
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
  test('family name without the pinned storage still rejects', () {
    final page = _page(
      _sellerProduct(
        name: 'Samsung Galaxy S25',
        productUrl: pageUrl,
        offeredBy: {'@type': 'Organization', 'name': 'amazon.in'},
      ),
      pageUrl,
    );
    expect(SourceCandidateValidator.validate(spec, page), isNull);
  });
}
