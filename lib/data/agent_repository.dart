/// Repository interface (spec V1 architecture: repositories + interfaces so
/// the storage engine can be swapped). Two implementations:
/// [InMemoryAgentRepository] for tests and [SqfliteAgentRepository] for prod.
library;

import '../domain/agent.dart';
import '../domain/activity.dart';

abstract class AgentRepository {
  Future<List<Agent>> allAgents();
  Future<Agent?> agentById(int id);
  Future<int> insertAgent(Agent agent);
  Future<void> updateAgent(Agent agent);
  Future<void> deleteAgent(int id);

  /// Active agents whose nextCheckAt has passed (or was never set).
  Future<List<Agent>> dueAgents(DateTime now);

  Future<void> logActivity(int agentId, String message, DateTime at);
  Future<List<ActivityEntry>> activityFor(int agentId, {int limit = 100});
  Future<List<ActivityEntry>> recentActivity({int limit = 50});

  Future<void> close();
}

class InMemoryAgentRepository implements AgentRepository {
  final List<Agent> _agents = [];
  final List<ActivityEntry> _activity = [];
  int _agentSeq = 0;
  int _activitySeq = 0;

  @override
  Future<List<Agent>> allAgents() async =>
      List.unmodifiable(_agents..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<Agent?> agentById(int id) async {
    for (final a in _agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Future<int> insertAgent(Agent agent) async {
    final id = ++_agentSeq;
    _agents.add(_withId(agent, id));
    return id;
  }

  Agent _withId(Agent a, int id) => Agent(
        id: id,
        title: a.title,
        originalPrompt: a.originalPrompt,
        type: a.type,
        status: a.status,
        createdAt: a.createdAt,
        lastCheckedAt: a.lastCheckedAt,
        nextCheckAt: a.nextCheckAt,
        checkInterval: a.checkInterval,
        condition: a.condition,
        target: a.target,
        currentValue: a.currentValue,
        previousValue: a.previousValue,
        notificationEnabled: a.notificationEnabled,
      );

  @override
  Future<void> updateAgent(Agent agent) async {
    final i = _agents.indexWhere((a) => a.id == agent.id);
    if (i >= 0) _agents[i] = agent;
  }

  @override
  Future<void> deleteAgent(int id) async {
    _agents.removeWhere((a) => a.id == id);
    _activity.removeWhere((e) => e.agentId == id);
  }

  @override
  Future<List<Agent>> dueAgents(DateTime now) async => _agents
      .where((a) =>
          a.status == AgentStatus.active &&
          (a.nextCheckAt == null || !a.nextCheckAt!.isAfter(now)))
      .toList();

  @override
  Future<void> logActivity(int agentId, String message, DateTime at) async {
    _activity.add(ActivityEntry(
        id: ++_activitySeq, agentId: agentId, timestamp: at, message: message));
  }

  @override
  Future<List<ActivityEntry>> activityFor(int agentId, {int limit = 100}) async {
    final list = _activity.where((e) => e.agentId == agentId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.take(limit).toList();
  }

  @override
  Future<List<ActivityEntry>> recentActivity({int limit = 50}) async {
    final list = List<ActivityEntry>.of(_activity)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.take(limit).toList();
  }

  @override
  Future<void> close() async {}
}
