import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/data/sqflite_repository.dart';

import 'dart:convert';

import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/presentation/source_review_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/page_fetch.dart';
import 'package:lookout/services/source_discovery.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'next_update_test.dart' as helpers;

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

Future<void> visibleTap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> clarifyAndFind(WidgetTester t) async {
  await t.enterText(
    find.byType(TextField).first,
    'check iphone 15 128GB price below 60000',
  );
  await visibleTap(t, find.byType(DropdownButtonFormField<String>).at(0));
  await visibleTap(t, find.text('India').last);
  await visibleTap(t, find.byType(DropdownButtonFormField<String>).at(1));
  await visibleTap(t, find.text('INR — ₹').last);
  await visibleTap(t, find.text('Find matching pages'));
}

SourceDiscoveryService fakeService({int status = 200}) =>
    SourceDiscoveryService(
      searchProvider: helpers.FakeSearch(),
      pageReader: helpers.FakeReader(helpers.fixture(status: status)),
    );
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('confirmed identity persists and every scheduled read uses strict path; no generic fallback', () async {
    final repo = await SqfliteAgentRepository.open(path: inMemoryDatabasePath);
    final candidate = SourceCandidateValidator.validate(
      helpers.spec,
      helpers.fixture(),
    )!;
    final reviewed = ReviewedSource(helpers.spec, candidate);
    final id = await repo.insertAgent(
      helpers
          .watch(source: candidate.url.toString())
          .copyWith(sourceIdentity: reviewed.identity),
    );
    final a = (await repo.agentById(id))!;
    expect(DiscoverySpec.forAgent(a).reviewedProduct, candidate.product);
    var reads = 0;
    final checker = AgentChecker(
      repo: repo,
      notifier: RecordingNotifier(),
      fetcher: (_) async => throw StateError('unsafe generic fallback'),
      strictFetcher: (agent) async {
        reads++;
        return FetchOutcome.failed('unreadable');
      },
    );
    final r = await checker.checkAgent(a);
    expect(r.evaluated, false);
    expect(reads, 1);
    expect(
      (await repo.activityFor(id)).any((e) => e.message == 'Condition not met'),
      false,
    );
    final strict = DiscoverySpec.forAgent(a);
    expect(
      SourceCandidateValidator.validate(
        strict,
        helpers.fixture(name: 'Apple iPhone 15 128GB Blue'),
      ),
      isNull,
    );
    await repo.close();
  });
  test('v3 database migration preserves task ID, history and old missing-source state', () async {
    final dir = await Directory.systemTemp.createTemp('lookout-migrate');
    final path = '${dir.path}/old.db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE agents(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,originalPrompt TEXT NOT NULL,type TEXT NOT NULL,status TEXT NOT NULL,createdAt INTEGER NOT NULL,lastCheckedAt INTEGER,nextCheckAt INTEGER,checkIntervalMinutes INTEGER NOT NULL,condition TEXT NOT NULL,target REAL NOT NULL,currentValue REAL,previousValue REAL,sourceUrl TEXT,lastSuccessfulReadAt INTEGER,lastSuccessfulValue REAL,lastReadMethod TEXT,lastReadSourceUrl TEXT,notificationEnabled INTEGER NOT NULL DEFAULT 1)',
          );
          await db.execute(
            'CREATE TABLE activity(id INTEGER PRIMARY KEY AUTOINCREMENT,agentId INTEGER NOT NULL,timestamp INTEGER NOT NULL,message TEXT NOT NULL)',
          );
        },
      ),
    );
    final map = helpers.watch().toMap()
      ..remove('sourceIdentity')
      ..remove('completedAt')
      ..remove('consecutiveSourceBlocks')
      ..['id'] = 7;
    await db.insert('agents', map);
    await db.insert('activity', {
      'agentId': 7,
      'timestamp': 1,
      'message': 'original history',
    });
    await db.close();
    var repo = await SqfliteAgentRepository.open(path: path);
    expect((await repo.agentById(7))!.needsSourceResolution, true);
    // Migrated records carry no completion timestamp; they stay visible.
    expect((await repo.agentById(7))!.completedAt, isNull);
    expect(await repo.dueAgents(DateTime(2027)), isEmpty);
    await repo.updateAgent(
      (await repo.agentById(7))!.copyWith(
        sourceIdentity: helpers.spec.encode(),
        sourceUrl: 'https://shop.example.com/product',
      ),
    );
    await repo.close();
    repo = await SqfliteAgentRepository.open(path: path);
    expect((await repo.agentById(7))!.sourceIdentity, isNotNull);
    expect((await repo.activityFor(7)).single.message, 'original history');
    await repo.close();
    await dir.delete(recursive: true);
  });
  test(
    'network guards reject local IPv4, IPv6, DNS-mapped and reserved addresses',
    () {
      for (final address in [
        '127.0.0.1',
        '10.1.2.3',
        '192.168.1.1',
        '172.16.0.1',
        '169.254.1.1',
        '100.64.0.1',
        '0.0.0.0',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
        'fe80::1',
        '2001:db8::1',
      ]) {
        expect(
          HttpDiscoveryPageReader.publicAddress(InternetAddress(address)),
          false,
          reason: address,
        );
      }
      expect(
        HttpDiscoveryPageReader.publicAddress(InternetAddress('8.8.8.8')),
        true,
      );
    },
  );
  testWidgets(
    'task-only create clarifies then reviews a source; it never activates before Create',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final repo = InMemoryAgentRepository();
      await t.pumpWidget(
        MaterialApp(
          theme: LookoutTheme.light(),
          home: CreateAgentScreen(repo: repo, discovery: fakeService()),
        ),
      );
      await switchToDescribeMode(t);
      await t.enterText(
        find.byType(TextField).first,
        'check iphone price below 60000',
      );
      await t.pumpAndSettle();
      await visibleTap(t, find.text('Find matching source'));
      expect(find.byType(SourceReviewScreen), findsOneWidget);
      await visibleTap(t, find.text('Find matching pages'));
      expect(find.textContaining('Which iPhone model'), findsOneWidget);
      expect(await repo.allAgents(), isEmpty);
      await clarifyAndFind(t);
      expect(find.text('Apple iPhone 15 128GB Black'), findsOneWidget);
      expect(await repo.allAgents(), isEmpty);
      await visibleTap(t, find.text('Apple iPhone 15 128GB Black'));
      await visibleTap(t, find.text('Use this source'));
      expect(await repo.allAgents(), isEmpty);
      expect(find.text('Reviewed source'), findsOneWidget);
      await visibleTap(t, find.widgetWithText(FilledButton, 'Create Agent'));
      final a = (await repo.allAgents()).single;
      expect(a.sourceUrl, 'https://shop.example.com/product');
      expect(a.sourceIdentity, isNotNull);
      expect(a.currentValue, isNull);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'existing source-less watch resolves in place and keeps only its own history',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final repo = InMemoryAgentRepository();
      final id = await repo.insertAgent(helpers.watch());
      final other = await repo.insertAgent(helpers.watch());
      await repo.logActivity(id, 'old task history', DateTime(2026));
      await repo.logActivity(other, 'different task history', DateTime(2026));
      await t.pumpWidget(
        MaterialApp(
          theme: LookoutTheme.dark(),
          home: AgentDetailsScreen(
            repo: repo,
            checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
            agentId: id,
            discovery: fakeService(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await visibleTap(t, find.text('Find matching source'));
      await clarifyAndFind(t);
      await visibleTap(t, find.text('Apple iPhone 15 128GB Black'));
      await visibleTap(t, find.text('Use this source'));
      expect((await repo.agentById(id))!.sourceIdentity, isNotNull);
      expect((await repo.agentById(other))!.sourceUrl, isNull);
      expect(
        (await repo.activityFor(id))
            .any((e) => e.message == 'old task history'),
        true,
      );
      expect(
        (await repo.activityFor(id))
            .any((e) => e.message == 'different task history'),
        false,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('review retains colour and saved target without activation', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    ReviewedSource? returned;
    await t.pumpWidget(
      MaterialApp(
        theme: LookoutTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                returned = await Navigator.of(context).push<ReviewedSource>(
                  MaterialPageRoute(
                    builder: (_) => SourceReviewScreen(
                      task: 'iphone 15 black 128GB price below 58000',
                      discovery: fakeService(),
                      fixedTarget: 60000,
                      fixedCondition: helpers.spec.condition,
                    ),
                  ),
                );
              },
              child: const Text('Open review'),
            ),
          ),
        ),
      ),
    );
    await visibleTap(t, find.text('Open review'));
    await visibleTap(t, find.byType(DropdownButtonFormField<String>).at(0));
    await visibleTap(t, find.text('India').last);
    await visibleTap(t, find.byType(DropdownButtonFormField<String>).at(1));
    await visibleTap(t, find.text('INR — ₹').last);
    await visibleTap(t, find.text('Find matching pages'));
    await visibleTap(t, find.text('Apple iPhone 15 128GB Black'));
    await visibleTap(t, find.text('Use this source'));
    expect(returned, isNotNull);
    final identity = jsonDecode(returned!.identity) as Map;
    expect(identity['colour'], 'black');
    expect(identity['reviewedProduct'], 'Apple iPhone 15 128GB Black');
    expect(returned!.spec.target, 60000);
    expect(returned!.spec.condition, helpers.spec.condition);
    expect(t.takeException(), isNull);
  });
  testWidgets('failed page lookup never offers activation and supports retry', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: LookoutTheme.light(),
        home: SourceReviewScreen(
          task: 'check iphone 15 128GB price below 60000',
          discovery: fakeService(status: 403),
        ),
      ),
    );
    await clarifyAndFind(t);
    expect(find.text('Use this source'), findsNothing);
    expect(find.textContaining('No exact, in-stock'), findsOneWidget);
    await visibleTap(t, find.text('Find matching pages'));
    expect(find.text('Use this source'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
