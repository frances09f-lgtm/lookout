import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/press_feedback.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/page_fetch.dart';
import 'package:lookout/services/source_discovery.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

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

Agent watch({String? source, double? current}) => Agent(
  title: 'iPhone 15',
  originalPrompt: 'iphone 15 below ₹60000',
  type: AgentType.valueWatch,
  status: AgentStatus.active,
  createdAt: DateTime(2026),
  nextCheckAt: DateTime(2026),
  checkInterval: const Duration(minutes: 30),
  condition: WatchCondition.lessThan,
  target: 60000,
  sourceUrl: source,
  currentValue: current,
);

class FakeSearch implements SourceSearchProvider {
  int calls = 0;
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async {
    calls++;
    return [
      SearchPage(Uri.parse('https://shop.example.com/product'), 'fixture'),
    ];
  }
}

class FakeReader implements DiscoveryPageReader {
  final ProductPage page;
  FakeReader(this.page);
  @override
  Future<ProductPage> read(Uri url) async => page;
}

const spec = DiscoverySpec(
  model: 'iphone 15',
  storageGb: 128,
  target: 60000,
  condition: WatchCondition.lessThan,
  country: 'IN',
  currency: 'INR',
);
ProductPage fixture({
  String name = 'Apple iPhone 15 128GB Black',
  String currency = 'INR',
  String region = 'IN',
  String stock = 'InStock',
  int status = 200,
  dynamic price = 59000,
  int copies = 1,
}) {
  final product = {
    '@type': 'Product',
    'name': name,
    'url': 'https://shop.example.com/product',
    'offers': {
      '@type': 'Offer',
      'price': price,
      'priceCurrency': currency,
      'availability': stock,
      'eligibleRegion': region,
      'itemCondition': 'NewCondition',
    },
  };
  return ProductPage(
    Uri.parse('https://shop.example.com/product'),
    status,
    '<script type="application/ld+json">${jsonEncode(List.generate(copies, (_) => product))}</script>',
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final sql in [false, true]) {
    test(
      'legacy source-less task waits without mutation; resolving restores due checks (${sql ? 'SQLite' : 'memory'})',
      () async {
        final AgentRepository repo = sql
            ? await SqfliteAgentRepository.open(path: inMemoryDatabasePath)
            : InMemoryAgentRepository();
        final id = await repo.insertAgent(watch());
        await repo.logActivity(id, 'existing history', DateTime(2026));
        final a = (await repo.agentById(id))!;
        expect(a.needsSourceResolution, true);
        expect(a.statusLabel, 'Needs source');
        expect(await repo.dueAgents(DateTime(2026, 2)), isEmpty);
        final notifier = RecordingNotifier();
        final checker = AgentChecker(
          repo: repo,
          notifier: notifier,
          clock: () => DateTime(2026, 2),
        );
        final result = await checker.checkAgent(a);
        expect(result.evaluated, false);
        final messages = (await repo.activityFor(id))
            .map((e) => e.message)
            .toList();
        expect(messages, contains('existing history'));
        expect(messages, isNot(contains('Condition not met')));
        expect(messages.any((m) => m.startsWith('Fetched data:')), false);
        expect(
          messages.any((m) => m.startsWith('Next check scheduled')),
          false,
        );
        expect(await checker.checkDueAgents(), 0);
        expect(notifier.shown, isEmpty);
        await repo.updateAgent(
          (await repo.agentById(id))!.copyWith(currentValue: 61000),
        );
        expect((await repo.agentById(id))!.id, id);
        expect((await repo.dueAgents(DateTime(2026, 3))).single.id, id);
        await repo.close();
      },
    );
  }
  test('unreadable price never evaluates a stale stored price; retry later succeeds', () async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(
      watch(source: 'https://shop.example.com/product', current: 59000),
    );
    var valid = false;
    final notifier = RecordingNotifier();
    final at = DateTime(2026, 2);
    final checker = AgentChecker(
      repo: repo,
      notifier: notifier,
      clock: () => at,
      fetcher: (_) async => valid
          ? FetchOutcome.found(61000, 'Verified test value')
          : FetchOutcome.failed('HTTP 403'),
    );
    final a = (await repo.agentById(id))!;
    final bad = await checker.checkAgent(a);
    expect(bad.evaluated, false);
    expect(bad.conditionMet, false);
    expect(notifier.shown, isEmpty);
    final stored = (await repo.agentById(id))!;
    expect(stored.currentValue, 59000);
    expect(stored.lastSuccessfulReadAt, isNull);
    expect(stored.nextCheckAt, at.add(const Duration(minutes: 30)));
    final logs = (await repo.activityFor(id)).map((e) => e.message);
    expect(logs, isNot(contains('Condition not met')));
    expect(logs.any((m) => m.startsWith('Fetched data:')), false);
    expect(logs.any((m) => m.startsWith('Read retry scheduled')), true);
    valid = true;
    final good = await checker.checkAgent(stored);
    expect(good.evaluated, true);
    expect(good.conditionMet, false);
    expect(
      (await repo.activityFor(id)).map((e) => e.message),
      contains('Condition not met'),
    );
    expect((await repo.agentById(id))!.lastSuccessfulReadAt, at);
  });
  test('discovery requests actual model/storage instead of guessing; target is not storage', () {
    final ambiguous = DiscoveryTaskParser.parse(
      'check iphone price below 58000',
      country: 'IN',
      currency: 'INR',
    );
    expect(ambiguous.spec, isNull);
    expect(ambiguous.questions.length, 2);
    final exact = DiscoveryTaskParser.parse(
      'check iphone 15 128 GB price below ₹60000',
      country: 'IN',
      currency: 'INR',
    );
    expect(exact.questions, isEmpty);
    expect(exact.spec!.target, 60000);
    expect(exact.spec!.storageGb, 128);
    expect(exact.spec!.query, isNot(contains('60000')));
  });
  test('strict candidate validator rejects variant, access, currency and stock mismatches', () {
    expect(SourceCandidateValidator.validate(spec, fixture()), isNotNull);
    for (final page in [
      fixture(name: 'Apple iPhone 15 Pro 128GB'),
      fixture(name: 'Apple iPhone 15 256GB'),
      fixture(name: 'iPhone 15 128GB case'),
      fixture(name: 'Renewed iPhone 15 128GB'),
      fixture(currency: 'USD'),
      fixture(region: 'US'),
      fixture(stock: 'OutOfStock'),
      fixture(status: 403),
      fixture(price: 0),
      fixture(price: 'NaN'),
      fixture(copies: 2),
    ]) {
      expect(SourceCandidateValidator.validate(spec, page), isNull);
    }
  });
  test(
    'unconfigured and unreadable searches yield no source and no candidate',
    () async {
      final search = FakeSearch();
      final unavailable = SourceDiscoveryService(
        searchProvider: const UnconfiguredSourceSearch(),
        pageReader: FakeReader(fixture()),
      );
      final blocked = SourceDiscoveryService(
        searchProvider: search,
        pageReader: FakeReader(fixture(status: 403)),
      );
      expect((await unavailable.discover(spec)).candidates, isEmpty);
      final r = await blocked.discover(spec);
      expect(r.candidates, isEmpty);
      expect(r.issue, isNotNull);
      expect((await blocked.discover(spec)).candidates, isEmpty);
      expect(search.calls, 2);
    },
  );
  for (final dark in [false, true]) {
    for (final width in [320.0, 336.0, 390.0, 600.0]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets(
          'horizontal example cards ${width}px dark=$dark text=$textScale',
          (t) async {
            await t.binding.setSurfaceSize(Size(width, 900));
            addTearDown(() => t.binding.setSurfaceSize(null));
            await t.pumpWidget(
              MaterialApp(
                theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: CreateAgentScreen(repo: InMemoryAgentRepository()),
              ),
            );
            await t.pumpAndSettle();
            await switchToDescribeMode(t);
            await t.scrollUntilVisible(
              find.text('Watch a value'),
              150,
              scrollable: find.byType(Scrollable).first,
            );
            await t.pumpAndSettle();
            final left = t.getRect(find.text('Watch a value'));
            final right = t.getRect(find.text('Set a reminder'));
            expect(left.left, lessThan(right.left));
            expect((left.top - right.top).abs(), lessThan(1));
            expect(right.right, lessThanOrEqualTo(width));
            expect(t.takeException(), isNull);
          },
        );
      }
    }
    for (final reduced in [false, true]) {
      for (final enabled in [false, true]) {
        for (final kind in [
          'filled',
          'outlined',
          'text',
          'elevated',
          'icon',
          'fab',
          'chip',
          'ink',
          'dropdown',
        ]) {
          testWidgets(
            'press $kind dark=$dark reduced=$reduced enabled=$enabled',
            (t) async {
              int calls = 0;
              final callback = enabled ? () => calls++ : null;
              final child = switch (kind) {
                'filled' => FilledButton(
                  onPressed: callback,
                  child: const Text('Tap'),
                ),
                'outlined' => OutlinedButton(
                  onPressed: callback,
                  child: const Text('Tap'),
                ),
                'text' => TextButton(
                  onPressed: callback,
                  child: const Text('Tap'),
                ),
                'elevated' => ElevatedButton(
                  onPressed: callback,
                  child: const Text('Tap'),
                ),
                'icon' => IconButton(
                  onPressed: callback,
                  icon: const Icon(Icons.add),
                ),
                'fab' => LookoutPressFeedback(
                  child: FloatingActionButton(
                    onPressed: callback,
                    child: const Icon(Icons.add),
                  ),
                ),
                'chip' => LookoutPressFeedback(
                  child: ActionChip(
                    onPressed: callback,
                    label: const Text('Tap'),
                  ),
                ),
                'dropdown' => LookoutPressFeedback(
                  enabled: enabled,
                  child: DropdownButton<String>(
                    value: 'one',
                    items: const [
                      DropdownMenuItem(value: 'one', child: Text('One')),
                    ],
                    onChanged: enabled ? (_) => calls++ : null,
                  ),
                ),
                _ => LookoutPressFeedback(
                  child: InkWell(
                    onTap: callback,
                    child: const SizedBox(
                      width: 80,
                      height: 48,
                      child: Text('Tap'),
                    ),
                  ),
                ),
              };
              await t.pumpWidget(
                MaterialApp(
                  theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: reduced),
                    child: child!,
                  ),
                  home: Scaffold(body: Center(child: child)),
                ),
              );
              await t.pumpAndSettle();
              final target = find.byWidget(child);
              final g = await t.startGesture(t.getCenter(target));
              await t.pump(const Duration(milliseconds: 150));
              final scales = t.widgetList<AnimatedScale>(
                find.byType(AnimatedScale),
              );
              expect(scales, isNotEmpty);
              expect(scales.any((s) => s.scale < 1), enabled && !reduced);
              await g.up();
              await t.pumpAndSettle();
              expect(
                t
                    .widgetList<AnimatedScale>(find.byType(AnimatedScale))
                    .every((s) => s.scale == 1),
                true,
              );
              if (kind != 'dropdown') expect(calls, enabled ? 1 : 0);
              expect(t.takeException(), isNull);
            },
          );
        }
      }
    }
  }
}
