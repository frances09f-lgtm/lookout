/// The V1 check engine. One pure-ish evaluation function shared by the
/// WorkManager background dispatcher and the "Run now" button, so background
/// and manual checks behave identically.
///
/// V1 data sources are honest: reminders use the clock, value watches use
/// the value the user entered. There is no web fetching until V2 - nothing
/// here fakes a data feed.
library;

import '../data/agent_repository.dart';
import '../domain/agent.dart';
import 'notifications.dart';

class CheckResult {
  final bool conditionMet;
  final String summary;
  const CheckResult(this.conditionMet, this.summary);
}

class AgentChecker {
  final AgentRepository repo;
  final LookoutNotifier notifier;
  final DateTime Function() now;

  AgentChecker({required this.repo, required this.notifier, DateTime Function()? clock})
      : now = clock ?? DateTime.now;

  /// Background entry point: check every due active agent.
  Future<int> checkDueAgents() async {
    final due = await repo.dueAgents(now());
    var checked = 0;
    for (final agent in due) {
      await checkAgent(agent);
      checked++;
    }
    return checked;
  }

  /// One full check cycle for a single agent, with activity logging that
  /// matches the spec (started check, fetched data, compared, result,
  /// next check scheduled).
  Future<CheckResult> checkAgent(Agent agent) async {
    final at = now();
    final id = agent.id!;
    await repo.logActivity(id, 'Started check', at);

    bool met;
    String detail;
    switch (agent.type) {
      case AgentType.reminder:
        final dueAt = DateTime.fromMillisecondsSinceEpoch(agent.target.round());
        met = !at.isBefore(dueAt);
        detail = met ? 'Due time reached' : 'Not due yet';
        break;
      case AgentType.valueWatch:
        final current = agent.currentValue;
        if (current == null) {
          met = false;
          detail = 'Waiting for a current value (update it from the agent page)';
        } else {
          met = switch (agent.condition) {
            WatchCondition.lessThan => current < agent.target,
            WatchCondition.greaterThan => current > agent.target,
            WatchCondition.remindAt => false,
          };
          detail = 'Current ${_fmt(current)} vs target ${_fmt(agent.target)}';
        }
        break;
    }
    await repo.logActivity(id, 'Fetched data: $detail', at);
    await repo.logActivity(
        id, met ? 'Condition met' : 'Condition not met', at);

    var updated = agent.copyWith(
      lastCheckedAt: at,
      nextCheckAt: at.add(agent.checkInterval),
      previousValue: agent.currentValue,
    );

    if (met) {
      final title = agent.type == AgentType.reminder
          ? 'Reminder: ${agent.title}'
          : '${agent.title}: condition met';
      final body = agent.type == AgentType.reminder
          ? agent.originalPrompt
          : '$detail - ${agent.conditionLabel}';
      if (agent.notificationEnabled) {
        await notifier.showAgentResult(agentId: id, title: title, body: body);
        await repo.logActivity(id, 'Notification sent', at);
      }
      updated = updated.copyWith(status: AgentStatus.completed);
      await repo.logActivity(id, 'Agent completed', at);
    } else {
      await repo.logActivity(
          id,
          'Next check scheduled for ${_fmtTime(at.add(agent.checkInterval))}',
          at);
    }
    await repo.updateAgent(updated);
    return CheckResult(met, detail);
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _fmtTime(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
