import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

/// Simulates the user's actual upgrade path: a database file created and
/// filled by the v1.1.8 app (schema v6 - unchanged in v1.1.9/1.1.10, so no
/// migration runs on his phone either) is opened by the current code. The
/// open must succeed and the data must read back; v1.1.9 hung or crashed
/// here on his device, before the first frame.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('a v1.1.8-shaped database opens and reads under the current code',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('lookout-upgrade-test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/lookout.db';

    // v1.1.8 era: create the schema and fill it the way his phone did.
    final repoV118 = await SqfliteAgentRepository.open(path: path);
    final created = DateTime(2026, 10, 20, 9);
    final id = await repoV118.insertAgent(Agent(
      title: 'iphone 15 128gb below 67999',
      originalPrompt: 'below 67999',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: created,
      checkInterval: const Duration(hours: 1),
      condition: WatchCondition.lessThan,
      target: 67999,
      currentValue: 72990,
      nextCheckAt: DateTime(2026, 10, 25, 16, 30),
    ));
    await repoV118.logActivity(id, 'Started check', created);
    await repoV118.logActivity(
        id,
        'Fetched data: Product offer 72990.0 on www.flipkart.com - target 67999',
        created);
    // v1.1.8 background worker liveness keys.
    await repoV118.putKv(
        'lastBackgroundRunAt', '2026-10-25T03:17:00.000000');
    await repoV118.putKv('lastBackgroundRunChecked', '3');
    await repoV118.close();

    // Upgrade: the current code opens the SAME file.
    final repo = await SqfliteAgentRepository.open(path: path);
    final agents = await repo.allAgents();
    expect(agents, hasLength(1));
    expect(agents.single.title, 'iphone 15 128gb below 67999');
    expect(agents.single.currentValue, 72990);
    final activity = await repo.activityFor(id);
    expect(activity, hasLength(2));
    expect(await repo.getKv('lastBackgroundRunAt'),
        '2026-10-25T03:17:00.000000');
    // Writes still land on the upgraded store.
    await repo.putKv('lastBackgroundRunStartedAt',
        '2026-10-25T17:20:00.000000');
    expect(await repo.getKv('lastBackgroundRunStartedAt'),
        '2026-10-25T17:20:00.000000');
    await repo.close();
  });
}
