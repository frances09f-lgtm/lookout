import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/page_fetch.dart';

void main() {
  Agent a() => Agent(
    title: 'Watch',
    originalPrompt: 'Watch price',
    type: AgentType.valueWatch,
    status: AgentStatus.active,
    createdAt: DateTime(2026),
    checkInterval: const Duration(minutes: 30),
    condition: WatchCondition.lessThan,
    target: 100,
    sourceUrl: 'https://example.com/price',
  );
  test('read provenance persists even when value does not change; failure preserves it', () async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(a());
    var time = DateTime(2026, 10, 7, 20);
    var ok = true;
    final c = AgentChecker(
      repo: repo,
      notifier: RecordingNotifier(),
      clock: () => time,
      fetcher: (_) async => ok
          ? FetchOutcome.found(150, 'Price')
          : FetchOutcome.failed('HTTP403'),
    );
    await c.checkAgent((await repo.agentById(id))!);
    final first = (await repo.agentById(id))!;
    expect(first.lastSuccessfulValue, 150);
    expect(first.lastReadMethod, 'Automatic page read');
    time = time.add(const Duration(minutes: 30));
    await c.checkAgent(first);
    expect((await repo.agentById(id))!.lastSuccessfulReadAt, time);
    ok = false;
    time = time.add(const Duration(minutes: 30));
    await c.checkAgent((await repo.agentById(id))!);
    final fail = (await repo.agentById(id))!;
    expect(
      fail.lastSuccessfulReadAt,
      time.subtract(const Duration(minutes: 30)),
    );
    expect(fail.lastCheckedAt, time);
  });
  test('browser records its method and exact source; roundtrip and source change stay honest', () async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(a());
    final c = AgentChecker(
      repo: repo,
      notifier: RecordingNotifier(),
      readMethod: 'Browser read (user started)',
      fetcher: (_) async => FetchOutcome.found(150, 'Price'),
    );
    await c.checkAgent((await repo.agentById(id))!);
    final read = Agent.fromMap((await repo.agentById(id))!.toMap());
    expect(read.lastReadMethod, 'Browser read (user started)');
    expect(read.lastReadSourceUrl, read.sourceUrl);
    expect(
      read.copyWith(sourceUrl: 'https://example.com/other').lastReadSourceUrl,
      'https://example.com/price',
    );
  });
  test('old records never invent read success', () {
    final map = a().toMap()
      ..remove('lastSuccessfulReadAt')
      ..remove('lastSuccessfulValue')
      ..remove('lastReadMethod')
      ..remove('lastReadSourceUrl');
    expect(Agent.fromMap(map).lastSuccessfulReadAt, isNull);
  });
}
