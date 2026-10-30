import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/presentation/source_review_screen.dart';
import 'package:lookout/services/source_discovery.dart';

/// The morning failure: "Tell me when Samsung S25 drops below ₹56999" with
/// India + INR found search results but verified nothing, because a retailer
/// title ("Samsung Galaxy S25 5G (Silver Shadow, 128 GB)") never contains
/// the model phrase "samsung s25" contiguously. Storage-unpinned identity
/// now requires every model token instead, with the variant/accessory
/// guards unchanged; the user picks the exact variant page in review.
void main() {
  DiscoverySpec s25Spec() => DiscoveryTaskParser.parse(
    'Tell me when Samsung S25 drops below ₹56999',
    country: 'IN',
    currency: 'INR',
  ).spec!;

  ProductPage page(String title) => ProductPage(
    Uri.parse('https://www.croma.com/samsung-galaxy-s25-5g/p/306294'),
    200,
    '<html><head><title>$title</title></head><body>'
    '<h1>$title</h1>'
    '<p class="price">₹60,299</p><p class="price">₹60,299</p><p class="price">₹60,299</p>'
    '<button type="button">Add to Cart</button>'
    '<div>Check delivery at your pincode</div>'
    '<div>Imported by Samsung India Electronics Private Limited</div>'
    '</body></html>',
  );

  test('storage-unpinned S25: a descriptive retailer title validates', () {
    final spec = s25Spec();
    expect(spec.model, 'Samsung S25');
    expect(spec.storageGb, 0);
    final v = SourceCandidateValidator.validate(
      spec,
      page(
        'Samsung Galaxy S25 5G (Silver Shadow, 12GB RAM, 128GB Storage) | Croma',
      ),
    );
    expect(v, isNotNull);
    expect(v!.price, 60299);
    expect(v.currency, 'INR');
    expect(v.visibleOffer, isTrue);
  });

  test('a different variant still rejects: Ultra, FE, plus-suffix', () {
    final spec = s25Spec();
    for (final title in [
      'Samsung Galaxy S25 Ultra 5G (Titanium Black, 12GB RAM, 256GB Storage) | Croma',
      'Samsung Galaxy S25 FE 5G (Navy, 8GB RAM, 128GB Storage) | Croma',
      'Samsung Galaxy S25+ 5G (Silver Shadow, 12GB RAM, 256GB Storage) | Croma',
    ]) {
      expect(
        SourceCandidateValidator.validate(spec, page(title)),
        isNull,
        reason: title,
      );
    }
  });

  test('an accessory naming the model still rejects', () {
    final spec = s25Spec();
    expect(
      SourceCandidateValidator.validate(
        spec,
        page('Samsung Galaxy S25 5G Back Cover Case with Kickstand | Croma'),
      ),
      isNull,
    );
  });

  test('a different model still rejects', () {
    final spec = s25Spec();
    expect(
      SourceCandidateValidator.validate(
        spec,
        page(
          'Samsung Galaxy S24 5G (Amber Yellow, 8GB RAM, 128GB Storage) | Croma',
        ),
      ),
      isNull,
    );
  });

  test('a combined sibling-model page rejects even without marker words', () {
    final spec = DiscoveryTaskParser.parse(
      'Tell me when Sony WH-1000XM5 drops below ₹25000',
      country: 'IN',
      currency: 'INR',
    ).spec!;
    ProductPage p(String title) => ProductPage(
      Uri.parse('https://www.vijaysales.com/p/206834/sony-headphones'),
      200,
      '<html><head><title>$title</title></head><body>'
          '<h1>$title</h1>'
          '<p class="price">₹26,990</p><p class="price">₹26,990</p><p class="price">₹26,990</p>'
          '<button type="button">Add to Cart</button>'
          '<div>Check delivery at your pincode</div>'
          '<div>Imported by Sony India Private Limited</div>'
          '</body></html>',
    );
    // The asked model plus a sibling: every token matches, wrong page.
    expect(
      SourceCandidateValidator.validate(
        spec,
        p('Sony WH-1000XM4 WH-1000XM5 Wireless Headphones | Vijay Sales'),
      ),
      isNull,
    );
    // The asked model alone: RAM/storage-style numbers never false-fire.
    expect(
      SourceCandidateValidator.validate(
        spec,
        p(
          'Sony WH-1000XM5 Wireless Noise-Canceling Headphones (Black) | Vijay Sales',
        ),
      ),
      isNotNull,
    );
    // A comparison phrasing without "vs".
    expect(
      SourceCandidateValidator.validate(
        s25Spec(),
        ProductPage(
          Uri.parse('https://www.croma.com/samsung-galaxy-s25-5g/p/306294'),
          200,
          '<html><head><title>Samsung Galaxy S24 S25 Comparison | Croma</title></head><body>'
              '<h1>Samsung Galaxy S24 S25 Comparison</h1>'
              '<p class="price">₹60,299</p><p class="price">₹60,299</p><p class="price">₹60,299</p>'
              '<button type="button">Add to Cart</button>'
              '<div>Check delivery at your pincode</div>'
              '<div>Imported by Samsung India Electronics Private Limited</div>'
              '</body></html>',
        ),
      ),
      isNull,
    );
  });

  test('visibleIdentityMatches: token order and descriptors are free', () {
    final spec = s25Spec();
    expect(
      DiscoveryTaskParser.visibleIdentityMatches(
        'Samsung Galaxy S25 5G (Silver Shadow, 128 GB)',
        spec,
      ),
      isTrue,
    );
    expect(
      DiscoveryTaskParser.visibleIdentityMatches(
        'Samsung Galaxy S25 Ultra 5G',
        spec,
      ),
      isFalse,
    );
    expect(
      DiscoveryTaskParser.visibleIdentityMatches(
        'Samsung Galaxy S25 vs S24 comparison',
        spec,
      ),
      isFalse,
    );
  });

  test('query: digit-bearing commerce models are country-qualified', () {
    expect(s25Spec().query, 'Samsung S25 India price INR');
    // Quote subjects keep the region-free form that ranks live quote pages.
    final gold = DiscoveryTaskParser.parse(
      'Tell me when gold drops below ₹400000',
      country: 'IN',
      currency: 'INR',
    ).spec!;
    expect(gold.query, 'gold price INR');
    // Pinned-storage commerce keeps its existing shape.
    final pinned = DiscoveryTaskParser.parse(
      'Tell me when Samsung S25 256gb drops below ₹56000',
      country: 'IN',
      currency: 'INR',
    ).spec!;
    expect(pinned.query, contains('256GB'));
  });

  test('structured single-product page with descriptive name validates', () {
    String ldPage(String name) =>
        '<html><head><title>x</title>'
        '<script type="application/ld+json">{'
        '"@context":"http://schema.org","@type":"Product",'
        '"name":"$name",'
        '"url":"https://shop.example.in/p/s25",'
        '"offers":{"@type":"Offer","priceCurrency":"INR","price":"57999",'
        '"availability":"https://schema.org/InStock",'
        '"eligibleRegion":{"@type":"Place","name":"IN"}}'
        '}</script></head><body></body></html>';
    const url = 'https://shop.example.in/p/s25';
    final ok = SourceCandidateValidator.validate(
      s25Spec(),
      ProductPage(Uri.parse(url), 200, ldPage('Samsung Galaxy S25 5G (12GB RAM, 256GB Storage) Silver Shadow')),
    );
    expect(ok, isNotNull);
    expect(ok!.price, 57999);
    expect(
      SourceCandidateValidator.validate(
        s25Spec(),
        ProductPage(Uri.parse(url), 200, ldPage('Samsung Galaxy S25 Ultra 5G (12GB RAM, 256GB Storage)')),
      ),
      isNull,
    );
    expect(
      SourceCandidateValidator.validate(
        s25Spec(),
        ProductPage(Uri.parse(url), 200, ldPage('Samsung Galaxy S24 5G (8GB RAM, 128GB Storage)')),
      ),
      isNull,
    );
  });

  test('blocked store pages get an honest unreadable-source message', () async {
    final spec = s25Spec();
    final blocked = await SourceDiscoveryService(
      searchProvider: _Links(const [
        'https://www.flipkart.com/samsung-galaxy-s25-5g/p/itm123',
        'https://www.amazon.in/Samsung-Display/dp/B0TEST',
      ]),
      pageReader: _ThrowingReader(),
    ).discover(spec);
    expect(blocked.candidates, isEmpty);
    expect(blocked.reviewOnly, isEmpty);
    expect(blocked.issue, contains('none allowed a direct read'));
    expect(blocked.issue, isNot(contains('No page with a provable')));

    // Readable pages that prove nothing keep the original wording.
    final unproven = await SourceDiscoveryService(
      searchProvider: _Links(const ['https://news.example.com/s25-launch']),
      pageReader: _Pages({
        'https://news.example.com/s25-launch': ProductPage(
          Uri.parse('https://news.example.com/s25-launch'),
          200,
          '<html><head><title>Galaxy S25 launch coverage</title></head>'
              '<body><p>News about the phone, no offer.</p></body></html>',
        ),
      }),
    ).discover(spec);
    expect(unproven.issue, contains('No page with a provable'));
  });

  group('rendered second pass (JS-shell stores only)', () {
    const channel = MethodChannel('lookout/render');
    final renderCalls = <String>[];
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      renderCalls.clear();
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    void mockRender(Map<String, String> pages) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'readRendered');
            final url = call.arguments['url'] as String;
            renderCalls.add(url);
            final body = pages[url];
            if (body == null) {
              throw PlatformException(code: 'load_failed');
            }
            return jsonEncode({'status': 200, 'url': url, 'body': body});
          });
    }

    const shell = '<html><head><title>Croma Electronics</title></head>'
        '<body><div id="root"></div><script src="/app.js"></script></body></html>';
    const rendered =
        '<html><head><title>Samsung Galaxy S25 5G (12GB RAM, 128GB, Icyblue)</title></head><body>'
        '<h1>Samsung Galaxy S25 5G (12GB RAM, 128GB, Icyblue)</h1>'
        '<p class="price">₹57,999</p><p class="price">₹57,999</p><p class="price">₹57,999</p>'
        '<button type="button">Add to Cart</button>'
        '<div>Check delivery at your pincode</div>'
        '<div>Imported by Samsung India Electronics Private Limited</div>'
        '</body></html>';

    test('a JS-shell page is re-read rendered and validated the same way', () async {
      const url = 'https://www.croma.com/samsung-galaxy-s25-5g/p/313331';
      mockRender(const {url: rendered});
      final result = await SourceDiscoveryService(
        searchProvider: _Links(const [url]),
        pageReader: _Pages({
          url: ProductPage(Uri.parse(url), 200, shell),
        }),
      ).discover(s25Spec());
      expect(renderCalls, [url]);
      expect(result.candidates, hasLength(1));
      expect(result.candidates.single.price, 57999);
      expect(result.candidates.single.renderRequired, isTrue);
    });

    test('a refused page (access wall) is never retried rendered', () async {
      const url = 'https://www.flipkart.com/s25/p/itm123';
      mockRender(const {});
      final result = await SourceDiscoveryService(
        searchProvider: _Links(const [url]),
        pageReader: _ThrowingReader(),
      ).discover(s25Spec());
      expect(renderCalls, isEmpty);
      expect(result.candidates, isEmpty);
      expect(result.issue, contains('none allowed a direct read'));
    });

    test('a full content page that proves nothing is not re-read', () async {
      const url = 'https://news.example.com/s25-launch';
      mockRender(const {});
      await SourceDiscoveryService(
        searchProvider: _Links(const [url]),
        pageReader: _Pages({
          url: ProductPage(
            Uri.parse(url),
            200,
            '<html><head><title>Galaxy S25 launch coverage with a long descriptive title</title></head>'
                '<body><h1>Launch coverage</h1><p>${'Words about the phone. ' * 80}</p></body></html>',
          ),
        }),
      ).discover(s25Spec());
      expect(renderCalls, isEmpty);
    });

    test('a rendered page still has to prove the exact offer', () async {
      const url = 'https://www.croma.com/samsung-galaxy-s25-5g/p/313331';
      const wrongVariant =
          '<html><head><title>Samsung Galaxy S25 Ultra 5G (12GB RAM, 256GB)</title></head><body>'
          '<h1>Samsung Galaxy S25 Ultra 5G (12GB RAM, 256GB)</h1>'
          '<p class="price">₹1,09,999</p><p class="price">₹1,09,999</p><p class="price">₹1,09,999</p>'
          '<button type="button">Add to Cart</button>'
          '<div>Check delivery at your pincode</div>'
          '<div>Imported by Samsung India Electronics Private Limited</div>'
          '</body></html>';
      mockRender(const {url: wrongVariant});
      final result = await SourceDiscoveryService(
        searchProvider: _Links(const [url]),
        pageReader: _Pages({
          url: ProductPage(Uri.parse(url), 200, shell),
        }),
      ).discover(s25Spec());
      expect(result.candidates, isEmpty);
    });
  });

  test('render-required sources check through the rendered reader', () async {
    const channel = MethodChannel('lookout/render');
    TestWidgetsFlutterBinding.ensureInitialized();
    const url = 'https://www.croma.com/samsung-galaxy-s25-5g/p/313331';
    var called = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          called++;
          return jsonEncode({
            'status': 200,
            'url': url,
            'body': '<html><head><title>Samsung Galaxy S25 5G (12GB RAM, 128GB, Icyblue)</title></head><body>'
                '<h1>Samsung Galaxy S25 5G (12GB RAM, 128GB, Icyblue)</h1>'
                '<p class="price">₹57,999</p><p class="price">₹57,999</p><p class="price">₹57,999</p>'
                '<button type="button">Add to Cart</button>'
                '<div>Check delivery at your pincode</div>'
                '<div>Imported by Samsung India Electronics Private Limited</div>'
                '</body></html>',
          });
        });
    final spec = s25Spec();
    final candidate = SourceCandidate(
      url: Uri.parse(url),
      product: 'Samsung Galaxy S25 5G (12GB RAM, 128GB, Icyblue)',
      price: 57999,
      currency: 'INR',
      country: 'IN',
      checkedAt: DateTime(2026, 10, 30),
      visibleOffer: true,
      renderRequired: true,
    );
    final identity = ReviewedSource(spec, candidate).identity;
    expect((jsonDecode(identity) as Map)['renderRequired'], isTrue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('new finder flow preselects India and INR', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: SourceReviewScreen(
          task: 'Tell me when Samsung S25 drops below ₹56999',
          discovery: _StubDiscovery(),
          initialCountry: 'IN',
          initialCurrency: 'INR',
        ),
      ),
    );
    await t.pumpAndSettle();
    final dropdowns = t
        .widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .toList();
    expect(dropdowns.length, 2);
    expect(dropdowns[0].initialValue, 'IN');
    expect(dropdowns[1].initialValue, 'INR');
  });

  testWidgets('re-source flow preserves a stored USD market', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: SourceReviewScreen(
          task: 'Tell me when gold drops below \$4000',
          discovery: _StubDiscovery(),
          initialCountry: 'US',
          initialCurrency: 'USD',
        ),
      ),
    );
    await t.pumpAndSettle();
    final dropdowns = t
        .widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .toList();
    expect(dropdowns.length, 2);
    expect(dropdowns[0].initialValue, 'US');
    expect(dropdowns[1].initialValue, 'USD');
  });

  testWidgets('re-source flow without initials still asks explicitly', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: SourceReviewScreen(
          task: 'Tell me when gold drops below \$4000',
          discovery: _StubDiscovery(),
        ),
      ),
    );
    await t.pumpAndSettle();
    final dropdowns = t
        .widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .toList();
    expect(dropdowns.length, 2);
    expect(dropdowns[0].initialValue, isNull);
    expect(dropdowns[1].initialValue, isNull);
  });
}

class _StubDiscovery implements SourceDiscoveryService {
  @override
  final DiscoveryPageReader pageReader = _NoReader();
  @override
  final SourceSearchProvider searchProvider = _NoSearch();
  @override
  Future<DiscoveryResult> discover(DiscoverySpec spec) async =>
      const DiscoveryResult([], null);
  @override
  Future<SourceCandidate?> revalidate(
    DiscoverySpec spec,
    SourceCandidate selected, {
    DateTime? now,
  }) async => selected;
}

class _NoReader implements DiscoveryPageReader {
  @override
  Future<ProductPage> read(Uri url) => throw StateError('unused');
}

class _NoSearch implements SourceSearchProvider {
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async => const [];
}

class _Links implements SourceSearchProvider {
  final List<String> urls;
  const _Links(this.urls);
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async =>
      urls.map((u) => SearchPage(Uri.parse(u), u)).toList();
}

class _ThrowingReader implements DiscoveryPageReader {
  @override
  Future<ProductPage> read(Uri url) => throw StateError('blocked');
}

class _Pages implements DiscoveryPageReader {
  final Map<String, ProductPage> pages;
  const _Pages(this.pages);
  @override
  Future<ProductPage> read(Uri url) async =>
      pages[url.toString()] ?? (throw StateError('missing'));
}
