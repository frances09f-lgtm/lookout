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
import '../domain/ticket_task.dart';
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

/// The outcome of one sweep over due agents.
class CheckCycleResult {
  /// Agents fully checked in this sweep.
  final int checked;

  /// Agents that were due when the sweep started.
  final int totalDue;

  /// True when the sweep stopped picking up new agents to stay inside its
  /// time budget. Unchecked agents keep their past-due nextCheckAt and are
  /// served by the next sweep, most overdue first.
  final bool budgetExhausted;

  /// True when another sweep was already running on this checker, so this
  /// call did nothing. Overlapping sweeps would double every fetch and
  /// every history line (the foreground ticker fires once a minute and
  /// never awaited a slow sweep).
  final bool skippedBusy;

  const CheckCycleResult({
    required this.checked,
    required this.totalDue,
    required this.budgetExhausted,
    this.skippedBusy = false,
  });
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

  bool _cycleRunning = false;

  /// Background entry point: check every due active agent, most overdue
  /// first (repository order). Stops picking up new agents once
  /// [timeBudget] is spent: Android stops any background worker after about
  /// 10 minutes, and a sweep killed mid-write looks exactly like "the
  /// worker never ran". A bounded sweep finishes, records what it did, and
  /// leaves the rest due for the next cycle.
  Future<CheckCycleResult> checkDueAgents({
    Duration timeBudget = const Duration(minutes: 4),
  }) async {
    if (_cycleRunning) {
      return const CheckCycleResult(
        checked: 0,
        totalDue: 0,
        budgetExhausted: false,
        skippedBusy: true,
      );
    }
    _cycleRunning = true;
    try {
      final startedAt = now();
      final due = await repo.dueAgents(startedAt);
      var checked = 0;
      var exhausted = false;
      for (final agent in due) {
        if (now().difference(startedAt) >= timeBudget) {
          exhausted = true;
          break;
        }
        await checkAgent(agent);
        checked++;
      }
      return CheckCycleResult(
        checked: checked,
        totalDue: due.length,
        budgetExhausted: exhausted,
      );
    } finally {
      _cycleRunning = false;
    }
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
    // Hard source block (HTTP 401/403) as opposed to a transient failure:
    /// only these count toward pausing automatic checks.
    bool hardBlock = false;
    switch (agent.type) {
      case AgentType.reminder:
        final dueAt = DateTime.fromMillisecondsSinceEpoch(agent.target.round());
        met = !at.isBefore(dueAt);
        detail = met ? 'Due time reached' : 'Not due yet';
        break;
      case AgentType.valueWatch:
        if (agent.isUnsupportedTicketWatch) {
          met = false;
          evaluated = false;
          detail = TicketTaskPolicy.limitation;
          break;
        }
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
            hardBlock = _isHardBlock(outcome.detail);
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

    // A successful read always clears the block count; a hard block
    /// increments it; any other failure leaves it unchanged (mixed
    /// transient noise must not mask a wall, nor inflate it).
    var blockCount = successfulRead
        ? 0
        : hardBlock
        ? agent.consecutiveSourceBlocks + 1
        : agent.consecutiveSourceBlocks;
    if (hardBlock && agent.consecutiveSourceBlocks == 0) {
      // Installs upgraded after a wall was already established have a zero
      // counter. Ground the pause in the recorded history instead of
      // polling the wall three more times: count the current consecutive
      // run of hard-block failures, newest first (the current failure is
      // already logged, so the scan starts from zero). A transient failure
      // neither counts nor breaks the run; a successful read ends it.
      blockCount = 0;
      final recent = await repo.activityFor(id, limit: 20);
      for (final e in recent) {
        if (e.message.startsWith('Unable to check:')) {
          if (_isHardBlock(e.message)) blockCount++;
        } else if (e.message.startsWith('Fetched data') ||
            e.message.startsWith('Manual value checked')) {
          break;
        }
      }
    }
    var updated = agent.copyWith(
      consecutiveSourceBlocks: blockCount,
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
        // A notification that cannot be shown (notifications switched off,
        // a plugin hiccup in the background isolate) must not fail the
        // check: the result is recorded either way, and the reason lands in
        // the task's history instead of as a worker error.
        try {
          await notifier.showAgentResult(agentId: id, title: title, body: body);
          await repo.logActivity(id, 'Notification sent', at);
        } catch (e) {
          await repo.logActivity(
            id,
            e is NotificationsDisabled
                ? 'Notification not shown: notifications are turned off for Lookout in Android settings'
                : 'Notification could not be shown',
            at,
          );
        }
      }
      UsageReporter.report(
        agent.type == AgentType.reminder ? 'reminder_fired' : 'watch_triggered',
      );
      updated = updated.copyWith(
        status: AgentStatus.completed,
        completedAt: at,
      );
      await repo.logActivity(id, 'Agent completed', at);
    } else if (agent.needsSourceResolution) {
      await repo.logActivity(
        id,
        agent.isUnsupportedTicketWatch
            ? 'Waiting for ticket-monitoring support; no checks scheduled'
            : 'Waiting for source resolution; no empty checks scheduled',
        at,
      );
    } else if (updated.sourceBlocked &&
        !agent.sourceBlocked &&
        updated.type == AgentType.valueWatch) {
      // Just crossed the threshold: say plainly that automatic checks stop
      // here. No retry promise - the wall will still be there in 15 min.
      await repo.logActivity(
        id,
        'Source is blocking checks (hard block $blockCount times in a row). Automatic checks paused until the source page changes.',
        at,
      );
    } else if (!updated.sourceBlocked) {
      await repo.logActivity(
        id,
        '${evaluated ? 'Next check' : 'Read retry'} scheduled for ${_fmtTime(at.add(agent.checkInterval))}',
        at,
      );
    }
    await repo.updateAgent(updated);
    return CheckResult(met, detail, evaluated: evaluated);
  }

  static final _hardBlockPattern = RegExp(r'HTTP (401|403)\b');
  static bool _isHardBlock(String detail) => _hardBlockPattern.hasMatch(detail);

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _fmtTime(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
