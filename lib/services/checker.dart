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
import 'source_discovery.dart';
import 'usage_reporter.dart';

class CheckResult {
  final bool conditionMet;
  final String summary;

  /// False is not the same as a verified condition result of false.
  final bool evaluated;
  const CheckResult(this.conditionMet, this.summary, {this.evaluated = true});
}

class AgentChecker {
  final AgentRepository repo;
  final LookoutNotifier notifier;
  final DateTime Function() now;
  final Future<FetchOutcome> Function(String url) fetcher;
  final String readMethod;
  final Future<FetchOutcome> Function(Agent agent) strictFetcher;

  AgentChecker({
    required this.repo,
    required this.notifier,
    DateTime Function()? clock,
    Future<FetchOutcome> Function(String url)? fetcher,
    this.readMethod = 'Automatic page read',
    Future<FetchOutcome> Function(Agent agent)? strictFetcher,
  }) : now = clock ?? DateTime.now,
       fetcher = fetcher ?? PageValueFetcher.fetchValue,
       strictFetcher = strictFetcher ?? DiscoveredSourceReader.fetch;

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
    bool successfulRead = false;
    bool evaluated = true;
    switch (agent.type) {
      case AgentType.reminder:
        final dueAt = DateTime.fromMillisecondsSinceEpoch(agent.target.round());
        met = !at.isBefore(dueAt);
        detail = met ? 'Due time reached' : 'Not due yet';
        break;
      case AgentType.valueWatch:
        if (agent.sourceUrl != null && agent.sourceUrl!.trim().isNotEmpty) {
          final outcome = agent.sourceIdentity == null
              ? await fetcher(agent.sourceUrl!)
              : await strictFetcher(agent);
          UsageReporter.report('watch_fetch');
          if (outcome.ok &&
              outcome.value != null &&
              outcome.value!.isFinite &&
              (agent.isTextWatch
                  ? (outcome.value == 0 || outcome.value == 1)
                  : outcome.value! > 0)) {
            successfulRead = true;
            if (outcome.value != agent.currentValue) {
              newCurrent = outcome.value;
              currentChanged = true;
            }
            met = switch (agent.condition) {
              WatchCondition.lessThan => outcome.value! < agent.target,
              WatchCondition.greaterThan => outcome.value! > agent.target,
              WatchCondition.remindAt => false,
            };
            detail = agent.isTextWatch
                ? outcome.detail
                : '${outcome.detail} - target ${_fmt(agent.target)}';
          } else {
            // Honest failure: keep the last known value, do not evaluate
            // against stale data, say exactly why.
            met = false;
            evaluated = false;
            detail = '${outcome.detail} - no fresh value to check';
          }
        } else {
          final current = agent.currentValue;
          if (current == null || agent.isTextWatch) {
            met = false;
            evaluated = false;
            detail = 'Source resolution needed. No evidence was read or compared; automatic checks are waiting for a confirmed source.';
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
    await repo.logActivity(
      id,
      evaluated
          ? '${agent.type == AgentType.reminder
                ? 'Clock checked'
                : successfulRead
                ? 'Fetched data'
                : 'Manual value checked'}: $detail'
          : 'Unable to check: $detail',
      at,
    );
    if (evaluated) {
      await repo.logActivity(
        id,
        met ? 'Condition met' : 'Condition not met',
        at,
      );
    }

    var updated = agent.copyWith(
      lastCheckedAt: at,
      lastSuccessfulReadAt: successfulRead ? at : null,
      lastSuccessfulValue: successfulRead ? newCurrent : null,
      lastReadMethod: successfulRead ? readMethod : null,
      lastReadSourceUrl: successfulRead ? agent.sourceUrl : null,
      nextCheckAt: at.add(agent.checkInterval),
      currentValue: newCurrent,
      previousValue: currentChanged ? agent.currentValue : agent.previousValue,
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
      UsageReporter.report(
        agent.type == AgentType.reminder ? 'reminder_fired' : 'watch_triggered',
      );
      updated = updated.copyWith(status: AgentStatus.completed);
      await repo.logActivity(id, 'Agent completed', at);
    } else if (agent.needsSourceResolution) {
      await repo.logActivity(
        id,
        'Waiting for source resolution; no empty checks scheduled',
        at,
      );
    } else {
      await repo.logActivity(
        id,
        '${evaluated ? 'Next check' : 'Read retry'} scheduled for ${_fmtTime(at.add(agent.checkInterval))}',
        at,
      );
    }
    await repo.updateAgent(updated);
    return CheckResult(met, detail, evaluated: evaluated);
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _fmtTime(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
