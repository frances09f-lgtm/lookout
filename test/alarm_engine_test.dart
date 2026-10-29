import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/alarm_engine.dart';

class FakeAlarmClock implements AlarmClock {
  int? scheduledId;
  DateTime? scheduledAt;
  int cancelCalls = 0;
  bool initialized = false;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<bool> scheduleExactWakeup(int id, DateTime at) async {
    scheduledId = id;
    scheduledAt = at;
    return true;
  }

  @override
  Future<bool> cancel(int id) async {
    cancelCalls++;
    scheduledId = null;
    scheduledAt = null;
    return true;
  }
}

Agent agent({
  int? id,
  DateTime? nextCheckAt,
  AgentStatus status = AgentStatus.active,
  int sourceBlocks = 0,
  String? sourceUrl = 'https://example.com/p',
}) {
  return Agent(
    id: id,
    title: 't$id',
    originalPrompt: 'p',
    type: AgentType.valueWatch,
    status: status,
    createdAt: DateTime(2026, 1, 1),
    lastCheckedAt: null,
    completedAt: null,
    nextCheckAt: nextCheckAt,
    checkInterval: const Duration(minutes: 5),
    condition: WatchCondition.lessThan,
    target: 100,
    currentValue: null,
    previousValue: null,
    sourceUrl: sourceUrl,
    sourceIdentity: null,
    notificationEnabled: true,
    lastSuccessfulReadAt: null,
    lastSuccessfulValue: null,
    lastReadMethod: null,
    lastReadSourceUrl: null,
    consecutiveSourceBlocks: sourceBlocks,
  );
}

void main() {
  late FakeAlarmClock clock;
  setUp(() {
    clock = FakeAlarmClock();
    debugSetAlarmClock(clock);
    canScheduleExactAlarmsForTest = () async => true;
  });

  test('nextDueAt picks the earliest future check among active agents', () {
    final now = DateTime.now();
    final agents = [
      agent(id: 1, nextCheckAt: now.add(const Duration(minutes: 30))),
      agent(id: 2, nextCheckAt: now.add(const Duration(minutes: 5))),
      agent(id: 3, status: AgentStatus.completed),
    ];
    expect(nextDueAt(agents), agents[1].nextCheckAt);
  });

  test('nextDueAt treats a never-checked agent as due immediately', () {
    final agents = [agent(id: 1, nextCheckAt: null)];
    final due = nextDueAt(agents);
    expect(due, isNotNull);
    expect(due!.isBefore(DateTime.now()), isTrue);
  });

  test('nextDueAt ignores blocked agents', () {
    final agents = [
      agent(id: 1, sourceBlocks: Agent.sourceBlockThreshold),
    ];
    expect(nextDueAt(agents), isNull);
  });

  test('rescheduleCheckAlarm cancels when nothing is due', () async {
    final repo = InMemoryAgentRepository();
    await rescheduleCheckAlarm(repo: repo);
    expect(clock.cancelCalls, 1);
    expect(clock.scheduledAt, isNull);
  });

  test('rescheduleCheckAlarm arms near-now for an overdue agent', () async {
    final repo = InMemoryAgentRepository();
    await repo.insertAgent(agent(nextCheckAt: null));
    final before = DateTime.now();
    await rescheduleCheckAlarm(repo: repo);
    expect(clock.scheduledId, checkAlarmId);
    expect(clock.scheduledAt, isNotNull);
    // Overdue work is armed a few seconds out, not in the past.
    expect(
      clock.scheduledAt!.isAfter(before.add(const Duration(seconds: 5))),
      isTrue,
    );
    expect(
      clock.scheduledAt!.isBefore(before.add(const Duration(minutes: 1))),
      isTrue,
    );
  });

  test('rescheduleCheckAlarm arms at the earliest future due time', () async {
    final repo = InMemoryAgentRepository();
    final at = DateTime.now().add(const Duration(minutes: 12));
    await repo.insertAgent(agent(nextCheckAt: at));
    await rescheduleCheckAlarm(repo: repo);
    expect(clock.scheduledAt!.difference(at).inSeconds.abs() <= 1, isTrue);
  });

  test('rescheduleCheckAlarm cancels when the grant is missing', () async {
    canScheduleExactAlarmsForTest = () async => false;
    final repo = InMemoryAgentRepository();
    await repo.insertAgent(agent(nextCheckAt: null));
    await rescheduleCheckAlarm(repo: repo);
    expect(clock.cancelCalls, 1);
    expect(clock.scheduledAt, isNull);
  });
}
