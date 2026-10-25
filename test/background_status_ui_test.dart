import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/activity.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/activity_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Agent task({int? id}) => Agent(
      id: id,
      title: 'Watch the thing',
      originalPrompt: 'below 500',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 10, 15, 12),
      checkInterval: const Duration(minutes: 30),
      condition: WatchCondition.lessThan,
      target: 500,
      currentValue: 550,
      nextCheckAt: DateTime(2026, 10, 15, 12, 30),
    );

class BrokenKvRepo extends InMemoryAgentRepository {
  @override
  Future<String?> getKv(String key) => throw StateError('kv store unreadable');
}

class BrokenActivityRepo extends InMemoryAgentRepository {
  @override
  Future<List<ActivityEntry>> activityFor(int agentId, {int limit = 100}) =>
      Future.error(StateError('activity table gone'));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('store read failure is shown, never masked as "no recorded run"',
      (t) async {
    final repo = BrokenKvRepo();
    final id = await repo.insertAgent(task());
    await t.pumpWidget(
      MaterialApp(home: ActivityScreen(repo: repo, agentId: id)),
    );
    await t.pumpAndSettle();
    expect(
      find.textContaining('Background worker status could not be read'),
      findsOneWidget,
    );
    expect(
      find.text('Background worker has no recorded run yet (app-wide).'),
      findsNothing,
    );
  });

  testWidgets('empty store still shows the honest empty state', (t) async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(task());
    await t.pumpWidget(
      MaterialApp(home: ActivityScreen(repo: repo, agentId: id)),
    );
    await t.pumpAndSettle();
    expect(
      find.text('Background worker has no recorded run yet (app-wide).'),
      findsOneWidget,
    );
  });

  testWidgets('started without completion is flagged as an anomaly',
      (t) async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(task());
    await repo.putKv(
        'lastBackgroundRunStartedAt', DateTime(2026, 10, 25, 3, 15).toIso8601String());
    await t.pumpWidget(
      MaterialApp(home: ActivityScreen(repo: repo, agentId: id)),
    );
    await t.pumpAndSettle();
    expect(
      find.textContaining('no completed run was recorded'),
      findsOneWidget,
    );
  });

  testWidgets('completed run and a partial-cycle note are shown', (t) async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(task());
    await repo.putKv(
        'lastBackgroundRunStartedAt', DateTime(2026, 10, 25, 3, 15).toIso8601String());
    await repo.putKv(
        'lastBackgroundRunAt', DateTime(2026, 10, 25, 3, 17).toIso8601String());
    await repo.putKv('lastBackgroundNote',
        'Checked 4 of 9 due tasks within the background time budget; the rest stay due for the next cycle.');
    await t.pumpWidget(
      MaterialApp(home: ActivityScreen(repo: repo, agentId: id)),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Background worker last completed: 25/10 03:17'),
        findsOneWidget);
    expect(find.textContaining('Checked 4 of 9 due tasks'), findsOneWidget);
  });

  testWidgets('history load failure shows the underlying error', (t) async {
    final repo = BrokenActivityRepo();
    final id = await repo.insertAgent(task());
    await t.pumpWidget(
      MaterialApp(home: ActivityScreen(repo: repo, agentId: id)),
    );
    await t.pumpAndSettle();
    expect(find.text('Could not load this task\u2019s history.'), findsOneWidget);
    expect(find.textContaining('activity table gone'), findsOneWidget);
  });

  testWidgets('a deleted task is labeled, not silently nameless', (t) async {
    final repo = InMemoryAgentRepository();
    await t.pumpWidget(
      MaterialApp(home: ActivityScreen(repo: repo, agentId: 999)),
    );
    await t.pumpAndSettle();
    expect(
      find.text('This task was deleted; only its recorded activity remains.'),
      findsOneWidget,
    );
  });
}
