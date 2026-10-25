import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/activity_screen.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home renders empty state and summary', (tester) async {
    final repo = InMemoryAgentRepository();
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await tester.pumpWidget(MaterialApp(home: HomeScreen(repo: repo, checker: checker)));
    await tester.pumpAndSettle();
    expect(find.text('Lookout'), findsOneWidget);
    expect(find.byTooltip('Create Agent'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('No agents yet'), findsOneWidget);
  });

  Agent doneAgent(String title, DateTime? completedAt) => Agent(
        title: title,
        originalPrompt: 'p',
        type: AgentType.valueWatch,
        status: AgentStatus.completed,
        createdAt: DateTime(2026, 1, 1),
        completedAt: completedAt,
        checkInterval: const Duration(minutes: 30),
        condition: WatchCondition.lessThan,
        target: 50000,
        currentValue: 49000,
      );

  testWidgets('completed cards leave the watchlist 3h after completion; '
      'older records without a timestamp stay', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    await repo.insertAgent(
      doneAgent('Recent done', DateTime.now().subtract(const Duration(hours: 1))),
    );
    await repo.insertAgent(
      doneAgent('Old done', DateTime.now().subtract(const Duration(hours: 4))),
    );
    await repo.insertAgent(doneAgent('Legacy done', null));
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(repo: repo, checker: checker)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent done'), findsOneWidget);
    expect(find.text('Old done'), findsNothing);
    expect(find.text('Legacy done'), findsOneWidget);
    // Nothing deleted: all records remain in the repository (History).
    expect((await repo.allAgents()).length, 3);
  });

  testWidgets('a card at its 3h mark leaves while the watchlist is open; '
      'history keeps its record', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(
      doneAgent(
        'Expiring done',
        DateTime.now()
            .subtract(const Duration(hours: 3))
            .add(const Duration(seconds: 2)),
      ),
    );
    await repo.logActivity(id, 'Agent completed', DateTime.now());
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(repo: repo, checker: checker)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expiring done'), findsOneWidget);
    // The scheduled expiry fires without any navigation: real time crosses
    // the 3-hour mark and the open watchlist drops the card.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2500)),
    );
    // The expiry timer lives on the widget-test clock; advance it past the
    // scheduled fire so the open watchlist re-evaluates.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Expiring done'), findsNothing);
    // History still lists the hidden card and keeps its record.
    await tester.pumpWidget(
      MaterialApp(home: ActivityScreen(repo: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expiring done'), findsOneWidget);
    await tester.tap(find.text('Expiring done'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Agent completed'), findsWidgets);
  });

  testWidgets('home lists an agent card', (tester) async {
    final repo = InMemoryAgentRepository();
    await repo.insertAgent(Agent(
      title: 'Laptop watch', originalPrompt: 'p', type: AgentType.valueWatch,
      status: AgentStatus.active, createdAt: DateTime(2026, 1, 1),
      checkInterval: const Duration(minutes: 30),
      condition: WatchCondition.lessThan, target: 50000, currentValue: 52000,
    ));
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await tester.pumpWidget(MaterialApp(home: HomeScreen(repo: repo, checker: checker)));
    await tester.pumpAndSettle();
    expect(find.text('Laptop watch'), findsOneWidget);
    expect(find.text('Run now'), findsOneWidget);
  });

  testWidgets('card groups long values and ghosts Run now when completed',
      (tester) async {
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await repo.insertAgent(Agent(
      title: 'iPhone 15 128GB',
      originalPrompt: 'iphone 15 below 80100',
      type: AgentType.valueWatch,
      status: AgentStatus.completed,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      checkInterval: const Duration(hours: 1),
      condition: WatchCondition.lessThan,
      target: 80100,
      currentValue: 80199.0223364612,
      previousValue: 80200,
      sourceUrl: 'https://www.flipkart.com/item',
    ));
    await tester
        .pumpWidget(MaterialApp(home: HomeScreen(repo: repo, checker: checker)));
    await tester.pumpAndSettle();
    // Legacy completed watch (no completedAt) still shows, value grouped.
    expect(find.text('80,199.02'), findsOneWidget);
    expect(find.text('Run now'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Run now'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
