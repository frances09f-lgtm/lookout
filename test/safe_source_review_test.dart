// Synthetic fixtures grounded in the inspected multi-offer/missing-region shape.
// These prices, colours and screenshots do not represent a live retailer read.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/source_review_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/source_discovery.dart';

import 'general_discovery_test.dart' as general;
import 'next_update_test.dart' as h;
import 'recovery_capture_test.dart' as capture;

/// The create screen opens on the price-boxes view; these flows exercise the
/// describe flow, one tap away. Scroll offset survives the mode switch, so
/// return to the top before driving the describe form.
Future<void> switchToDescribeMode(WidgetTester t) async {
  await t.scrollUntilVisible(
    find.text('Set a reminder or watch text on a page instead'),
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 80,
  );
  await t.ensureVisible(
    find.text('Set a reminder or watch text on a page instead'),
  );
  await t.pumpAndSettle();
  await t.tap(
    find.text('Set a reminder or watch text on a page instead'),
    warnIfMissed: false,
  );
  await t.pumpAndSettle();
  await t.drag(find.byType(Scrollable).first, const Offset(0, 4000));
  await t.pumpAndSettle();
}

const task = 'Check Sony WH-1000XM5 price below 25000';
final spec = general.price('Sony WH-1000XM5');
ProductPage fixture({
  int offers = 4,
  bool region = false,
  String name = 'Sony WH-1000XM5',
  String stock = 'InStock',
  String currency = 'INR',
  dynamic price = 22990,
  int status = 200,
  String url = 'https://shop.example.com/product',
  String? country,
}) => ProductPage(
  Uri.parse(url),
  status,
  '<script type="application/ld+json">${jsonEncode({
    '@type': 'Product',
    'name': name,
    'url': url,
    'offers': List.generate(offers, (i) => {
      '@type': 'Offer',
      'name': ['Black', 'Silver', 'Blue', 'Pink'][i % 4],
      'price': price,
      'priceCurrency': currency,
      'availability': stock,
      if (region) 'eligibleRegion': country ?? 'IN',
    }),
  })}</script>',
);

class MutableReader implements DiscoveryPageReader {
  ProductPage page;
  Completer<ProductPage>? pending;
  int calls = 0;
  MutableReader(this.page);
  @override
  Future<ProductPage> read(Uri url) async {
    calls++;
    return pending?.future ?? page;
  }
}

SourceDiscoveryService service(MutableReader reader) => SourceDiscoveryService(
  searchProvider: general.Search(reader.page),
  pageReader: reader,
);
Future<void> chooseMarket(WidgetTester t) async {
  await capture.tap(t, find.byType(DropdownButtonFormField<String>).at(0));
  await capture.tap(t, find.text('India').last);
  await capture.tap(t, find.byType(DropdownButtonFormField<String>).at(1));
  await capture.tap(t, find.text('INR — ₹').last);
  await capture.tap(t, find.text('Find matching pages'));
}

void main() {
  test(
    'four offers without region remain review-only, never a reading',
    () async {
      final page = fixture();
      expect(SourceCandidateValidator.validate(spec, page), isNull);
      final result = await service(MutableReader(page)).discover(spec);
      expect(result.candidates, isEmpty);
      final lead = result.reviewOnly.single;
      expect(lead.reportedOffers.length, 4);
      expect(
        lead.blockers.where((s) => s.contains('eligible country')).length,
        1,
      );
      expect(lead.blockers.any((s) => s.contains('4 offers')), true);
      expect(
        lead.blockers.any((s) => s.startsWith('Offers 1, 2, 3, 4:')),
        true,
      );
    },
  );
  test('single offer missing region is review-only; country selection is not evidence', () {
    final page = fixture(offers: 1);
    expect(SourceCandidateValidator.validate(spec, page), isNull);
    expect(
      SourceCandidateValidator.reviewOnly(spec, page)!.blockers,
      contains('Offer 1: seller does not specify an eligible country.'),
    );
  });
  test('explicit matching country and single exact offer validate; no review-only copy', () async {
    final result = await service(
      MutableReader(fixture(offers: 1, region: true)),
    ).discover(spec);
    expect(result.candidates.length, 1);
    expect(result.reviewOnly, isEmpty);
  });
  test(
    'descriptive retailer title remains identity-unverified, not relaxed',
    () {
      final page = fixture(
        name: 'Sony WH-1000XM5 Wireless The Best Active Noise Cancelling Headphones Black',
      );
      expect(SourceCandidateValidator.validate(spec, page), isNull);
      expect(
        SourceCandidateValidator.reviewOnly(spec, page)!.blockers.first,
        contains('Exact product identity'),
      );
    },
  );
  test('wrong model, iPhone variant, colour, reviewed identity and unsafe pages excluded', () {
    expect(
      SourceCandidateValidator.reviewOnly(
        spec,
        fixture(name: 'Sony WH-1000XM4'),
      ),
      isNull,
    );
    expect(
      SourceCandidateValidator.reviewOnly(
        h.spec,
        h.fixture(name: 'Apple iPhone 15 Pro 128GB Black'),
      ),
      isNull,
    );
    final black = general.price('Sony WH-1000XM5 black');
    expect(
      SourceCandidateValidator.reviewOnly(
        black,
        fixture(name: 'Sony WH-1000XM5 Silver'),
      ),
      isNull,
    );
    final reviewed = DiscoverySpec(
      model: spec.model,
      storageGb: 0,
      target: spec.target,
      condition: spec.condition,
      country: spec.country,
      currency: spec.currency,
      reviewedProduct: 'Sony WH-1000XM5',
    );
    expect(
      SourceCandidateValidator.reviewOnly(
        reviewed,
        fixture(name: 'Sony WH-1000XM5 different item'),
      ),
      isNull,
    );
    for (final page in [
      fixture(status: 403),
      fixture(url: 'https://127.0.0.1/product'),
      ProductPage(
        fixture().finalUrl,
        200,
        '<form id="challenge-form"></form>${fixture().body}',
      ),
    ]) {
      expect(SourceCandidateValidator.reviewOnly(spec, page), isNull);
    }
  });
  test(
    'wrong market, stock, currency, malformed price remain explicit blockers',
    () {
      final lead = SourceCandidateValidator.reviewOnly(
        spec,
        fixture(
          offers: 1,
          region: true,
          country: 'US',
          stock: 'OutOfStock',
          currency: 'USD',
          price: 'bad',
        ),
      )!;
      expect(lead.blockers.length, 4);
      expect(
        SourceCandidateValidator.validate(
          spec,
          fixture(offers: 1, region: true, country: 'US'),
        ),
        isNull,
      );
    },
  );
  test('fresh strict confirmation rejects stale, changed, redirected or unreadable candidate', () async {
    final reader = MutableReader(fixture(offers: 1, region: true));
    final discovery = service(reader);
    final now = DateTime(2026, 10, 17, 9);
    final selected = SourceCandidateValidator.validate(
      spec,
      reader.page,
      now: now,
    )!;
    expect(
      await discovery.revalidate(
        spec,
        selected,
        now: now.add(const Duration(minutes: 6)),
      ),
      isNull,
    );
    expect(
      await discovery.revalidate(
        spec,
        selected,
        now: now.subtract(const Duration(seconds: 1)),
      ),
      isNull,
    );
    expect(reader.calls, 0);
    expect(await discovery.revalidate(spec, selected, now: now), isNotNull);
    for (final page in [
      fixture(),
      fixture(offers: 1, region: true, price: 23000),
      fixture(offers: 1, region: true, name: 'Sony WH-1000XM4'),
      fixture(offers: 1, region: true, status: 403),
      fixture(
        offers: 1,
        region: true,
        url: 'https://other.example.com/product',
      ),
    ]) {
      reader.page = page;
      expect(await discovery.revalidate(spec, selected, now: now), isNull);
    }
  });
  for (final dark in [false, true]) {
    testWidgets(
      'review-only flow ${dark ? 'dark' : 'light'} has no activation; synthetic Flutter capture',
      (t) async {
        await capture.fonts(t);
        await t.binding.setSurfaceSize(const Size(336, 750));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final key = GlobalKey();
        final repo = InMemoryAgentRepository();
        final reader = MutableReader(fixture());
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
            builder: (_, child) => RepaintBoundary(key: key, child: child!),
            home: CreateAgentScreen(repo: repo, discovery: service(reader)),
          ),
        );
        await switchToDescribeMode(t);
        await t.enterText(find.byType(TextField).first, task);
        await capture.tap(t, find.text('Find matching source'));
        await chooseMarket(t);
        await t.scrollUntilVisible(
          find.text('Pages needing more evidence'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await capture.capture(
          t,
          key,
          'review-only-${dark ? 'dark' : 'light'}-FIXTURE',
        );
        expect(find.text('Use this source'), findsNothing);
        expect(find.byType(SourceReviewScreen), findsOneWidget);
        await t.scrollUntilVisible(
          find.text('Unable to monitor'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        final button = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Unable to monitor'),
        );
        expect(button.onPressed, isNull);
        await capture.capture(
          t,
          key,
          'blocked-offers-${dark ? 'dark' : 'light'}-FIXTURE',
        );
        expect(await repo.allAgents(), isEmpty);
        // Correcting task invalidates previous candidates rather than keeping them.
        t
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await t.pumpAndSettle();
        await t.enterText(
          find.byType(TextField).first,
          'Check Sony WH-1000XM4 price below 25000',
        );
        await t.pumpAndSettle();
        expect(find.text('Unable to monitor'), findsNothing);
        expect(find.text('Pages needing more evidence'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('changed accepted candidate cannot leave review', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final reader = MutableReader(fixture(offers: 1, region: true));
    await t.pumpWidget(
      MaterialApp(
        home: SourceReviewScreen(task: task, discovery: service(reader)),
      ),
    );
    await chooseMarket(t);
    await capture.tap(t, find.text('Sony WH-1000XM5'));
    reader.page = fixture();
    await capture.tap(t, find.text('Use this source'));
    expect(find.byType(SourceReviewScreen), findsOneWidget);
    expect(find.textContaining('source changed, expired'), findsOneWidget);
    expect(find.text('Use this source'), findsNothing);
  });
  testWidgets('task edit during confirmation discards in-flight result', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final reader = MutableReader(fixture(offers: 1, region: true));
    await t.pumpWidget(
      MaterialApp(
        home: SourceReviewScreen(task: task, discovery: service(reader)),
      ),
    );
    await chooseMarket(t);
    await capture.tap(t, find.text('Sony WH-1000XM5'));
    reader.pending = Completer<ProductPage>();
    await t.tap(find.text('Use this source'));
    await t.pump();
    await t.enterText(
      find.byType(TextField).first,
      'Check Sony WH-1000XM4 price below 25000',
    );
    reader.pending!.complete(reader.page);
    await t.pumpAndSettle();
    expect(find.byType(SourceReviewScreen), findsOneWidget);
    expect(find.text('Use this source'), findsNothing);
  });
  testWidgets(
    'Create rechecks after source review; changed offer creates no watch',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final reader = MutableReader(fixture(offers: 1, region: true));
      final repo = InMemoryAgentRepository();
      await t.pumpWidget(
        MaterialApp(
          home: CreateAgentScreen(repo: repo, discovery: service(reader)),
        ),
      );
      await switchToDescribeMode(t);
      await t.enterText(find.byType(TextField).first, task);
      await capture.tap(t, find.text('Find matching source'));
      await chooseMarket(t);
      await capture.tap(t, find.text('Sony WH-1000XM5'));
      await capture.tap(t, find.text('Use this source'));
      expect(await repo.allAgents(), isEmpty);
      reader.page = fixture();
      await capture.tap(t, find.widgetWithText(FilledButton, 'Create Agent'));
      expect(await repo.allAgents(), isEmpty);
      expect(find.text('Find matching source'), findsOneWidget);
      expect(find.textContaining('no watch was created'), findsOneWidget);
    },
  );
}
