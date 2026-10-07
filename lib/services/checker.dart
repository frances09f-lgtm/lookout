/// The check engine. One pure-ish evaluation function shared by the
/// WorkManager background dispatcher and the "Run now" button, so background
/// and manual checks behave identically.
///
/// Data sources are honest: reminders use the clock, value watches with a
/// source page fetch the real page and read a number from it, value watches
/// without one use the value the user entered. Fetch failures are logged as
/// failures - nothing here fakes a data feed.
library;

import '../data/agent_repository.dart';
import '../domain/agent.dart';
import 'notifications.dart';
import 'page_fetch.dart';
import 'usage_reporter.dart';

class CheckResult {
  final bool conditionMet;
  final String summary;
  const CheckResult(this.conditionMet, this.summary);
}

class AgentChecker {
  final AgentRepository repo;
  final LookoutNotifier notifier;
  final DateTime Function() now;
  final Future<FetchOutcome> Function(String url) fetcher;

  AgentChecker(
      {required this.repo,
      required this.notifier,
      DateTime Function()? clock,
      Future<FetchOutcome> Function(String url)? fetcher})
      : now = clock ?? DateTime.now,
        fetcher = fetcher ?? PageValueFetcher.fetchValue;

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
    double? newCurrent = agent.currentValue;
    bool currentChanged = false;
    switch (agent.type) {
      case AgentType.reminder:
        final dueAt = DateTime.fromMillisecondsSinceEpoch(agent.target.round());
        met = !at.isBefore(dueAt);
        detail = met ? 'Due time reached' : 'Not due yet';
        break;
      case AgentType.valueWatch:
        if (agent.sourceUrl != null) {
          final outcome = await fetcher(agent.sourceUrl!);
          UsageReporter.report('watch_fetch');
          if (outcome.ok && outcome.value != null) {
            if (outcome.value != agent.currentValue) {
              newCurrent = outcome.value;
              currentChanged = true;
            }
            met = switch (agent.condition) {
              WatchCondition.lessThan => outcome.value! < agent.target,
              WatchCondition.greaterThan => outcome.value! > agent.target,
              WatchCondition.remindAt => false,
            };
            detail = '${outcome.detail} - target ${_fmt(agent.target)}';
          } else {
            // Honest failure: keep the last known value, do not evaluate
            // against stale data, say exactly why.
            met = false;
            detail = '${outcome.detail} - no fresh value to check';
          }
        } else {
          final current = agent.currentValue;
          if (current == null) {
            met = false;
            detail =
                'No source page set and no manual value (add a page link or update the value on the agent page)';
          } else {
            met = switch (agent.condition) {
              WatchCondition.lessThan => current < agent.target,
              WatchCondition.greaterThan => current > agent.target,
              WatchCondition.remindAt => false,
            };
            detail = 'Current ${_fmt(current)} vs target ${_fmt(agent.target)}';
          }
        }
        break;
    }
    await repo.logActivity(id, 'Fetched data: $detail', at);
    await repo.logActivity(
        id, met ? 'Condition met' : 'Condition not met', at);

    var updated = agent.copyWith(
      lastCheckedAt: at,
      nextCheckAt: at.add(agent.checkInterval),
      currentValue: newCurrent,
      previousValue:
          currentChanged ? agent.currentValue : agent.previousValue,
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
      UsageReporter.report(agent.type == AgentType.reminder
          ? 'reminder_fired'
          : 'watch_triggered');
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
