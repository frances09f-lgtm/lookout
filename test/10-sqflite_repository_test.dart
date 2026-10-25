import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('agent + activity round-trip and due filter', () async {
    final repo = await SqfliteAgentRepository.open(path: inMemoryDatabasePath);
    final now = DateTime.now();
    final id = await repo.insertAgent(Agent(
      title: 't', originalPrompt: 'p', type: AgentType.reminder,
      status: AgentStatus.active, createdAt: now,
      checkInterval: const Duration(minutes: 15),
      condition: WatchCondition.remindAt,
      target: now.millisecondsSinceEpoch.toDouble(),
      nextCheckAt: now.subtract(const Duration(minutes: 1)),
    ));
    expect(id, greaterThan(0));
    final fetched = await repo.agentById(id);
    expect(fetched!.title, 't');
    expect(fetched.notificationEnabled, isTrue);

    await repo.logActivity(id, 'hello', now);
    final log = await repo.activityFor(id);
    expect(log.single.message, 'hello');

    final due = await repo.dueAgents(now);
    expect(due.map((a) => a.id), contains(id));

    await repo.updateAgent(fetched.copyWith(status: AgentStatus.paused));
    expect(await repo.dueAgents(now), isEmpty);

    await repo.deleteAgent(id);
    expect(await repo.agentById(id), isNull);
    await repo.close();
  });

  test('one unreadable activity row does not blank the history', () async {
    final dir = await Directory.systemTemp.createTemp('lookout-decode-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/decode.db';
    final repo = await SqfliteAgentRepository.open(path: path);
    final now = DateTime.now();
    final id = await repo.insertAgent(Agent(
      title: 't', originalPrompt: 'p', type: AgentType.reminder,
      status: AgentStatus.active, createdAt: now,
      checkInterval: const Duration(minutes: 15),
      condition: WatchCondition.remindAt,
      target: now.millisecondsSinceEpoch.toDouble(),
    ));
    await repo.logActivity(id, 'good row', now);
    // SQLite dynamic typing: force one row's timestamp to TEXT and one
    // row's agentId to TEXT, plus one row nothing can decode.
    final db = await databaseFactory.openDatabase(path);
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('activity', {
      'agentId': id.toString(),
      'timestamp': now.add(const Duration(minutes: 1)).millisecondsSinceEpoch.toString(),
      'message': 'text-typed row',
    });
    await db.insert('activity', {
      'agentId': 'not-a-number',
      'timestamp': 'also-not',
      'message': 'undecodable row',
    });
    await db.execute('PRAGMA foreign_keys = ON');
    final log = await repo.activityFor(id);
    expect(log.map((e) => e.message),
        containsAll(<String>['good row', 'text-typed row']));
    expect(log.length, 2);
    await repo.close();
  });

  test('dueAgents returns most overdue first, never-checked first', () async {
    final repo = await SqfliteAgentRepository.open(path: inMemoryDatabasePath);
    final now = DateTime.now();
    Agent watch(String title, DateTime? next) => Agent(
          title: title, originalPrompt: 'p', type: AgentType.valueWatch,
          status: AgentStatus.active, createdAt: now,
          checkInterval: const Duration(hours: 1),
          condition: WatchCondition.lessThan, target: 10, currentValue: 20,
          nextCheckAt: next,
        );
    final neverChecked = await repo.insertAgent(watch('never', null));
    final longOverdue = await repo.insertAgent(
        watch('long', now.subtract(const Duration(hours: 5))));
    final justDue = await repo.insertAgent(
        watch('just', now.subtract(const Duration(minutes: 1))));
    await repo.insertAgent(watch('notdue', now.add(const Duration(hours: 1))));
    final due = await repo.dueAgents(now);
    expect(due.map((a) => a.id).toList(),
        [neverChecked, longOverdue, justDue]);
    await repo.close();
  });
}
