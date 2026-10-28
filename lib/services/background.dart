/// Background execution: Flutter -> workmanager plugin (native Kotlin
/// WorkManager) -> this Dart dispatcher. WorkManager survives process death
/// and device restarts, and Android enforces a 15-minute minimum period -
/// so agent check intervals in V1 are >= 15 minutes by platform rule.
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/agent_repository.dart';
import '../data/sqflite_repository.dart';
import 'checker.dart';
import 'notifications.dart';

const checkTaskName = 'lookout.periodic_check';

/// How long one background cycle may work before it stops picking up new
/// tasks and reports honestly. Android stops any worker after about 10
/// minutes; staying far under that keeps a cycle from being killed
/// mid-write with nothing recorded - the failure this version diagnoses.
const backgroundCycleBudget = Duration(minutes: 4);

/// Preference keys mirroring the kv diagnostics. SharedPreferences does not
/// depend on the SQLite store, so the app can still say what the worker did
/// when the database itself is what failed.
const prefLastStartedAt = 'bg.lastStartedAt';
const prefLastCompletedAt = 'bg.lastCompletedAt';
const prefLastError = 'bg.lastError';
const prefLastNote = 'bg.lastNote';

Future<void> _mirrorPrefs(Map<String, String> values) async {
  try {
    // Best effort and bounded: a wedged preferences channel must never
    // stall the worker past its time budget.
    final prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 5));
    for (final e in values.entries) {
      await prefs.setString(e.key, e.value);
    }
  } catch (_) {
    // The kv record is primary; the mirror is best effort.
  }
}

/// One instrumented background cycle, wired to real stores by the
/// dispatcher and to fakes by tests. Liveness is recorded honestly:
/// - a STARTED marker lands before any work, so a killed cycle reads as
///   "started but never completed" instead of "never ran";
/// - a COMPLETED marker lands only when the sweep returned, with honest
///   checked/total counts - a partial cycle is reported, not hidden;
/// - an ERROR marker lands in both stores when the cycle fails.
Future<bool> runBackgroundCycle({
  required AgentRepository repo,
  required AgentChecker checker,
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  final startedAt = clock().toIso8601String();
  await repo.putKv('lastBackgroundRunStartedAt', startedAt);
  await _mirrorPrefs({prefLastStartedAt: startedAt});
  try {
    final result = await checker.checkDueAgents(
      timeBudget: backgroundCycleBudget,
    );
    final completedAt = clock().toIso8601String();
    await repo.putKv('lastBackgroundRunAt', completedAt);
    await repo.putKv('lastBackgroundRunChecked', '${result.checked}');
    final note = result.budgetExhausted
        ? 'Checked ${result.checked} of ${result.totalDue} due tasks within the background time budget; the rest stay due for the next cycle.'
        : '';
    await repo.putKv('lastBackgroundNote', note);
    await _mirrorPrefs({prefLastCompletedAt: completedAt, prefLastNote: note});
    return true;
  } catch (e) {
    final at = clock().toIso8601String();
    try {
      await repo.putKv('lastBackgroundError', '$at $e');
    } catch (_) {
      // The store itself may be what failed; the mirror below still lands.
    }
    await _mirrorPrefs({prefLastError: '$at $e'});
    // Return false so WorkManager retries with backoff instead of dropping
    // the cycle silently.
    return false;
  }
}

@pragma('vm:entry-point')
void lookoutCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) => runWorkmanagerTask());
}

/// One Workmanager task execution, split from the entry point so tests can
/// drive it with fakes.
///
/// The error record must survive a broken database: SharedPreferences is
/// written even when the SQLite store cannot be opened at all.
///
/// This isolate's store is closed on the way out - which is only safe
/// because every opener gets its own native connection
/// (singleInstance: false in SqfliteAgentRepository.open). sqflite's
/// default shares one native connection per path process-wide, so closing
/// the shared handle here used to break the foreground app's live
/// connection: every later read threw DatabaseException(database_closed)
/// (tekartik/sqflite#558; the v1.1.13 task-history failure).
Future<bool> runWorkmanagerTask({
  Future<AgentRepository> Function()? openRepo,
  Future<LookoutNotifier> Function()? makeNotifier,
}) async {
  AgentRepository? repo;
  try {
    final notifier = await (makeNotifier?.call() ??
        () async {
          final n = LocalNotificationsService();
          await n.init(requestPermission: false);
          return n;
        }());
    repo = await (openRepo?.call() ?? SqfliteAgentRepository.open());
    try {
      return await runBackgroundCycle(
        repo: repo,
        checker: AgentChecker(repo: repo, notifier: notifier),
      );
    } finally {
      // Safe to close: every opener gets its own native connection
      // (singleInstance: false in SqfliteAgentRepository.open), so this
      // only releases the worker's handle, never the foreground app's.
      // Closing the formerly SHARED connection here was the v1.1.13
      // database_closed failure (tekartik/sqflite#558).
      await repo.close();
    }
  } catch (e) {
    final at = DateTime.now().toIso8601String();
    try {
      await repo?.putKv('lastBackgroundError', '$at $e');
      await repo?.close();
    } catch (_) {
      // The store itself may be what failed; the mirror still lands.
    }
    await _mirrorPrefs({prefLastError: '$at $e'});
    return false;
  }
}

class BackgroundScheduler {
  Future<void> init() async {
    await Workmanager().initialize(lookoutCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      checkTaskName,
      checkTaskName,
      frequency: const Duration(minutes: 15),
      // The same dispatcher handles offline reminders and online watches.
      // Do not block reminders while offline. Watch fetch failures are logged
      // without evaluating stale prices, then retried on the next due cycle.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}
