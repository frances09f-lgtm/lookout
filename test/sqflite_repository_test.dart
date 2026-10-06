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
}
