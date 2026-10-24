import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/main.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/page_fetch.dart';

Agent dueReminder() => Agent(
  title: 'Stand up',
  originalPrompt: 'remind me to stand up',
  type: AgentType.reminder,
  status: AgentStatus.active,
  createdAt: DateTime(2026, 1, 1),
  checkInterval: const Duration(minutes: 5),
  condition: WatchCondition.remindAt,
  target: DateTime(2026, 1, 1).millisecondsSinceEpoch.toDouble(),
  nextCheckAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets('5-minute checks run while the app is open', (t) async {
    SharedPreferences.setMockInitialValues({});
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final id = await repo.insertAgent(dueReminder());
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await t.pumpWidget(LookoutApp(repo: repo, checker: checker));
    await t.pumpAndSettle();
    // The foreground ticker fires once a minute; nothing has run yet.
    expect((await repo.agentById(id))!.status, AgentStatus.active);
    await t.pump(const Duration(minutes: 1, seconds: 5));
    await t.pumpAndSettle();
    expect((await repo.agentById(id))!.status, AgentStatus.completed);
  });

  testWidgets(
    '5-minute value watch rechecks at cadence, pauses, resumes once',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final repo = InMemoryAgentRepository();
      addTearDown(repo.close);
      var fakeNow = DateTime(2026, 10, 25, 12);
      final id = await repo.insertAgent(
        Agent(
          title: 'boAt Airdopes',
          originalPrompt: 'boAt below 1299',
          type: AgentType.valueWatch,
          status: AgentStatus.active,
          createdAt: fakeNow.subtract(const Duration(days: 1)),
          checkInterval: const Duration(minutes: 5),
          condition: WatchCondition.lessThan,
          target: 1299,
          sourceUrl: 'https://shop.example.com/item',
          nextCheckAt: fakeNow.subtract(const Duration(minutes: 1)),
        ),
      );
      var fetches = 0;
      final checker = AgentChecker(
        repo: repo,
        notifier: RecordingNotifier(),
        clock: () => fakeNow,
        fetcher: (url) async {
          fetches++;
          return FetchOutcome.found(1599, 'Found 1599 on shop.example.com');
        },
      );
      await t.pumpWidget(LookoutApp(repo: repo, checker: checker));
      await t.pumpAndSettle();
      expect(fetches, 0);
      // First foreground tick: the due watch is checked once.
      await t.pump(const Duration(minutes: 1, seconds: 5));
      await t.pumpAndSettle();
      expect(fetches, 1);
      var a = (await repo.agentById(id))!;
      expect(a.status, AgentStatus.active);
      expect(a.currentValue, 1599);
      expect(a.nextCheckAt, fakeNow.add(const Duration(minutes: 5)));
      // Next tick before the cadence elapses: no duplicate check.
      fakeNow = fakeNow.add(const Duration(minutes: 2));
      await t.pump(const Duration(minutes: 1, seconds: 5));
      await t.pumpAndSettle();
      expect(fetches, 1);
      // Cadence elapsed: the watch is rechecked.
      fakeNow = fakeNow.add(const Duration(minutes: 4));
      await t.pump(const Duration(minutes: 1, seconds: 5));
      await t.pumpAndSettle();
      expect(fetches, 2);
      // App closed: cadence passes with no checks at all.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      fakeNow = fakeNow.add(const Duration(minutes: 6));
      await t.pump(const Duration(minutes: 6));
      await t.pumpAndSettle();
      expect(fetches, 2);
      // Resume: the now-overdue watch is checked exactly once, and the
      // following tick does not duplicate it.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(fetches, 3);
      a = (await repo.agentById(id))!;
      expect(a.nextCheckAt, fakeNow.add(const Duration(minutes: 5)));
      await t.pump(const Duration(minutes: 1, seconds: 5));
      await t.pumpAndSettle();
      expect(fetches, 3);
    },
  );

  testWidgets('checks pause when closed and run again on resume', (t) async {
    SharedPreferences.setMockInitialValues({});
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final id = await repo.insertAgent(dueReminder());
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await t.pumpWidget(LookoutApp(repo: repo, checker: checker));
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(minutes: 3));
    await t.pumpAndSettle();
    // Closed: no foreground cadence; WorkManager (>=15 min) owns checks.
    expect((await repo.agentById(id))!.status, AgentStatus.active);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect((await repo.agentById(id))!.status, AgentStatus.completed);
  });
}
