import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/domain/parser.dart';
import 'package:lookout/domain/ticket_task.dart';
import 'package:lookout/presentation/source_review_screen.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/source_discovery.dart';

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

class NoSearch implements SourceSearchProvider {
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async =>
      throw StateError('Ticket must not retail search');
}

class NoRead implements DiscoveryPageReader {
  @override
  Future<ProductPage> read(Uri url) async =>
      throw StateError('Ticket must not retail read');
}

final noDiscovery = SourceDiscoveryService(
  searchProvider: NoSearch(),
  pageReader: NoRead(),
);
const task =
    'Tell me when Movie Drishyam 3 at fortune cineplex at ichalkaranji Ticket Price becomes cheaper than 200';
Agent ticket({double? value, String? source}) => Agent(
  title: 'Drishyam 3',
  originalPrompt: task,
  type: AgentType.valueWatch,
  status: AgentStatus.active,
  createdAt: DateTime(2026, 10, 17),
  checkInterval: const Duration(minutes: 30),
  condition: WatchCondition.lessThan,
  target: 200,
  currentValue: value,
  sourceUrl: source,
);

void main() {
  test('exact owner task retains strict threshold, not the film number', () {
    final goal = GoalParser.parse(task);
    expect(goal.outcome, ParseOutcome.ok);
    expect(goal.target, 200);
    expect(goal.condition, WatchCondition.lessThan);
    expect(TicketTaskPolicy.isPriceTask(task), isTrue);
    final parsed = DiscoveryTaskParser.parse(
      task,
      country: 'IN',
      currency: 'INR',
    );
    expect(parsed.spec, isNull);
    expect(parsed.questions, [TicketTaskPolicy.limitation]);
  });
  test(
    'date show and class text cannot silently manufacture ticket support',
    () {
      for (final text in [
        task,
        '$task on 17 October at 10 pm Club seats',
        'Check concert tickets price below 200',
        'Check cinema admission cost under 200',
      ]) {
        expect(
          DiscoveryTaskParser.parse(text, country: 'IN', currency: 'INR').spec,
          isNull,
        );
        expect(TicketTaskPolicy.isPriceTask(text), isTrue);
      }
      for (final dimension in [
        'event',
        'venue',
        'date',
        'showtime',
        'seat class',
        'available seats',
        'booking fees',
      ]) {
        expect(TicketTaskPolicy.requirements, contains(dimension));
      }
    },
  );
  test(
    'retail products and explicit literal-page text retain their evaluator',
    () {
      for (final text in [
        'Check Sony WH-1000XM5 price below 25000',
        'Check ticket printer price below 200',
      ]) {
        expect(TicketTaskPolicy.isPriceTask(text), isFalse);
        expect(
          DiscoveryTaskParser.parse(
            text,
            country: 'IN',
            currency: 'INR',
          ).spec!.kind,
          'productPrice',
        );
      }
      const literal =
          'Check cinema ticket announcements contains "Prices below 200"';
      expect(TicketTaskPolicy.isPriceTask(literal), isFalse);
      expect(DiscoveryTaskParser.parse(literal).spec!.isText, isTrue);
    },
  );
  for (final value in [null, 199.0, 200.0]) {
    test(
      'legacy ticket with value $value remains unknown; stable id and history',
      () async {
        final repo = InMemoryAgentRepository();
        final id = await repo.insertAgent(
          ticket(
            value: value,
            source: value == null ? null : 'https://example.com/tickets',
          ),
        );
        await repo.logActivity(
          id,
          'Existing task history',
          DateTime(2026, 10, 16),
        );
        final stored = (await repo.agentById(id))!;
        expect(stored.needsSourceResolution, isTrue);
        expect(stored.statusLabel, 'Ticket monitoring unavailable');
        expect(await repo.dueAgents(DateTime(2026, 10, 18)), isEmpty);
        final notifier = RecordingNotifier();
        final checker = AgentChecker(
          repo: repo,
          notifier: notifier,
          fetcher: (_) =>
              throw StateError('Ticket must not use retail fetcher'),
        );
        final result = await checker.checkAgent(stored);
        expect(result.evaluated, isFalse);
        expect(result.conditionMet, isFalse);
        expect(notifier.shown, isEmpty);
        final after = (await repo.agentById(id))!;
        expect(after.id, id);
        expect(after.target, 200);
        expect(after.condition, WatchCondition.lessThan);
        expect(after.currentValue, value);
        expect(after.lastSuccessfulReadAt, isNull);
        final messages = (await repo.activityFor(id))
            .map((e) => e.message)
            .toList();
        expect(messages, contains('Existing task history'));
        expect(messages, isNot(contains('Condition not met')));
        expect(messages, isNot(contains('Condition met')));
        expect(
          messages,
          contains(
            'Waiting for ticket-monitoring support; no checks scheduled',
          ),
        );
      },
    );
  }
  test(
    'SQLite legacy record preserves persisted task target and history',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final repo = await SqfliteAgentRepository.open(
        path: inMemoryDatabasePath,
      );
      addTearDown(repo.close);
      final id = await repo.insertAgent(ticket());
      await repo.logActivity(
        id,
        'Previously saved task history',
        DateTime(2026, 10, 16),
      );
      final before = (await repo.agentById(id))!;
      expect(before.originalPrompt, task);
      expect(before.isUnsupportedTicketWatch, isTrue);
      expect(await repo.dueAgents(DateTime(2026, 10, 18)), isEmpty);
      await AgentChecker(
        repo: repo,
        notifier: RecordingNotifier(),
      ).checkAgent(before);
      final after = (await repo.agentById(id))!;
      expect(after.id, id);
      expect(after.target, 200);
      expect(after.condition, WatchCondition.lessThan);
      expect(after.originalPrompt, task);
      expect(
        (await repo.activityFor(id)).map((e) => e.message),
        contains('Previously saved task history'),
      );
    },
  );
  for (final dark in [true, false]) {
    testWidgets(
      'ticket limits render without retail controls ${dark ? 'dark' : 'light'}',
      (t) async {
        await capture.fonts(t);
        await t.binding.setSurfaceSize(const Size(336, 900));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final key = GlobalKey();
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
            builder: (_, child) => RepaintBoundary(key: key, child: child!),
            home: SourceReviewScreen(
              task: task,
              discovery: noDiscovery,
              fixedTarget: 200,
              fixedCondition: WatchCondition.lessThan,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text(TicketTaskPolicy.title), findsOneWidget);
        expect(
          find.text('Saved target: strictly below 200. Unchanged.'),
          findsOneWidget,
        );
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Find matching pages'), findsNothing);
        expect(find.text('Use a manual page link instead'), findsNothing);
        await capture.capture(
          t,
          key,
          'ticket-limits-${dark ? 'dark' : 'light'}',
        );
        await t.scrollUntilVisible(
          find.text('Back to task'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(TicketTaskPolicy.transport), findsOneWidget);
        await capture.capture(
          t,
          key,
          'ticket-transport-${dark ? 'dark' : 'light'}',
        );
      },
    );
  }
  testWidgets(
    'existing source-less ticket detail has no pretend manual-value workaround',
    (t) async {
      final repo = InMemoryAgentRepository();
      final id = await repo.insertAgent(ticket());
      await t.pumpWidget(
        MaterialApp(
          home: AgentDetailsScreen(
            repo: repo,
            checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
            agentId: id,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Ticket monitoring unavailable'), findsWidgets);
      await t.scrollUntilVisible(
        find.text('View ticket-check limits'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('View ticket-check limits'), findsOneWidget);
      expect(find.text('Update current value'), findsNothing);
      expect(find.text('Set source page'), findsNothing);
      expect((await repo.agentById(id))!.target, 200);
    },
  );
  testWidgets('new ticket task cannot create a retail watch', (t) async {
    final repo = InMemoryAgentRepository();
    await t.pumpWidget(MaterialApp(home: CreateAgentScreen(repo: repo)));
    await switchToDescribeMode(t);
    await t.enterText(find.byType(TextField).first, task);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Ticket price check — unavailable'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ticket price check — unavailable'), findsOneWidget);
    expect(find.text('Current value (optional)'), findsNothing);
    await capture.tap(t, find.text('View ticket-check limits'));
    expect(find.byType(SourceReviewScreen), findsOneWidget);
    expect(await repo.allAgents(), isEmpty);
  });
}
