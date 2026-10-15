import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/activity_screen.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final at = DateTime(2026, 10, 15, 12);
Agent task({String title = 'Same title'}) => Agent(
  title: title,
  originalPrompt: 'below 500',
  type: AgentType.valueWatch,
  status: AgentStatus.active,
  createdAt: at,
  checkInterval: const Duration(minutes: 30),
  condition: WatchCondition.lessThan,
  target: 500,
  currentValue: 550,
);

Future<List<int>> seed(AgentRepository repo) async {
  final a = await repo.insertAgent(task());
  final b = await repo.insertAgent(task());
  await repo.logActivity(a, 'Only A event', at);
  await repo.logActivity(b, 'Only B event', at.add(const Duration(minutes: 1)));
  return [a, b];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final sqlite in [false, true]) {
    test(
      '${sqlite ? 'SQLite' : 'memory'} keeps same-title tasks isolated through lifecycle',
      () async {
        final AgentRepository repo = sqlite
            ? await SqfliteAgentRepository.open(path: inMemoryDatabasePath)
            : InMemoryAgentRepository();
        addTearDown(repo.close);
        final ids = await seed(repo);
        var a = (await repo.agentById(ids[0]))!;
        final checker = AgentChecker(
          repo: repo,
          notifier: RecordingNotifier(),
          clock: () => at,
        );
        await checker.checkAgent(a);
        expect(
          (await repo.activityFor(ids[0]))
              .any((e) => e.message == 'Started check'),
          isTrue,
        );
        expect(
          (await repo.activityFor(ids[0])).every((e) => e.agentId == ids[0]),
          isTrue,
        );
        expect((await repo.activityFor(ids[1])).map((e) => e.message), [
          'Only B event',
        ]);
        a = (await repo.agentById(ids[0]))!;
        await repo.updateAgent(
          a.copyWith(title: 'Renamed', status: AgentStatus.paused),
        );
        expect(
          (await repo.activityFor(ids[0]))
              .any((e) => e.message == 'Only A event'),
          isTrue,
        );
        final pausedCount = (await repo.activityFor(ids[0])).length;
        await checker.checkDueAgents();
        expect((await repo.activityFor(ids[0])).length, pausedCount);
        await repo.updateAgent(a.copyWith(currentValue: 450));
        await checker.checkAgent((await repo.agentById(ids[0]))!);
        expect(
          (await repo.activityFor(ids[0]))
              .any((e) => e.message == 'Agent completed'),
          isTrue,
        );
        expect(
          (await repo.activityFor(ids[1])).every((e) => e.agentId == ids[1]),
          isTrue,
        );
        await repo.deleteAgent(ids[0]);
        final replacement = await repo.insertAgent(task());
        expect(replacement, isNot(ids[0]));
        expect(await repo.activityFor(replacement), isEmpty);
        expect(
          (await repo.activityFor(ids[1]))
              .any((e) => e.message == 'Only B event'),
          isTrue,
        );
      },
    );
  }

  test('SQLite preserves old attribution across reopen without guessing', () async {
    final dir = await Directory.systemTemp.createTemp('lookout-history-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/history.db';
    var repo = await SqfliteAgentRepository.open(path: path);
    final ids = await seed(repo);
    // Simulate an old orphan row: retain it, never guess a task by title/text.
    final db = await databaseFactory.openDatabase(path);
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('activity', {
      'agentId': 99999,
      'message': 'Ambiguous old event',
      'timestamp': at.millisecondsSinceEpoch,
    });
    await db.execute('PRAGMA foreign_keys = ON');
    await repo.close();
    repo = await SqfliteAgentRepository.open(path: path);
    expect((await repo.activityFor(ids[0])).map((e) => e.message), [
      'Only A event',
    ]);
    expect((await repo.activityFor(ids[1])).map((e) => e.message), [
      'Only B event',
    ]);
    expect(
      (await repo.recentActivity()).any(
        (e) => e.message == 'Ambiguous old event' && e.agentId == 99999,
      ),
      isTrue,
    );
    await repo.close();
  });

  testWidgets(
    'history chooser shows tasks, never a blended feed; same names stay separate',
    (t) async {
      final repo = InMemoryAgentRepository();
      final ids = await seed(repo);
      await t.pumpWidget(MaterialApp(home: ActivityScreen(repo: repo)));
      await t.pumpAndSettle();
      expect(find.text('Same title'), findsNWidgets(2));
      expect(find.text('Only A event'), findsNothing);
      expect(find.text('Only B event'), findsNothing);
      await t.tap(find.byKey(ValueKey('history-task-${ids[1]}')));
      await t.pumpAndSettle();
      expect(find.text('Only B event'), findsOneWidget);
      expect(find.text('Only A event'), findsNothing);
    },
  );

  testWidgets(
    'changing selected task clears previous activity and empty task stays empty',
    (t) async {
      final repo = InMemoryAgentRepository();
      final ids = await seed(repo);
      Future<void> show(int id) async {
        await t.pumpWidget(
          MaterialApp(
            home: ActivityScreen(repo: repo, agentId: id),
          ),
        );
        await t.pumpAndSettle();
      }

      await show(ids[0]);
      expect(find.text('Only A event'), findsOneWidget);
      await show(ids[1]);
      expect(find.text('Only A event'), findsNothing);
      expect(find.text('Only B event'), findsOneWidget);
      final empty = await repo.insertAgent(task());
      await show(empty);
      expect(find.text('Only B event'), findsNothing);
      expect(
        find.text('No activity recorded for this task yet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('home has a history action for each task and no mixed events', (
    t,
  ) async {
    final repo = InMemoryAgentRepository();
    final ids = await seed(repo);
    await t.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repo: repo,
          checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Only A event'), findsNothing);
    expect(find.text('Only B event'), findsNothing);
    await t.ensureVisible(find.text('History').first);
    await t.tap(find.text('History').first);
    await t.pumpAndSettle();
    // Either same-title task can sort first, but only one identity is shown.
    final aShown = find.text('Only A event').evaluate().isNotEmpty;
    expect(find.text(aShown ? 'Only B event' : 'Only A event'), findsNothing);
    expect(find.text(aShown ? 'Only A event' : 'Only B event'), findsOneWidget);
    expect(ids.toSet().length, 2);
  });

  testWidgets('details history switches by ID, not matching titles', (t) async {
    final repo = InMemoryAgentRepository();
    final ids = await seed(repo);
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    Future<void> show(int id) async {
      await t.pumpWidget(
        MaterialApp(
          home: AgentDetailsScreen(repo: repo, checker: checker, agentId: id),
        ),
      );
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView).first, const Offset(0, -3000));
      await t.pumpAndSettle();
    }

    await show(ids[0]);
    expect(find.text('Only A event'), findsOneWidget);
    expect(find.text('Only B event'), findsNothing);
    await show(ids[1]);
    expect(find.text('Only A event'), findsNothing);
    expect(find.text('Only B event'), findsOneWidget);
  });
}
