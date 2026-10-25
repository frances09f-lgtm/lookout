/// Background execution: Flutter -> workmanager plugin (native Kotlin
/// WorkManager) -> this Dart dispatcher. WorkManager survives process death
/// and device restarts, and Android enforces a 15-minute minimum period -
/// so agent check intervals in V1 are >= 15 minutes by platform rule.
library;

import 'package:workmanager/workmanager.dart';

import '../data/sqflite_repository.dart';
import 'checker.dart';
import 'notifications.dart';

const checkTaskName = 'lookout.periodic_check';

@pragma('vm:entry-point')
void lookoutCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final notifier = LocalNotificationsService();
      await notifier.init();
      final repo = await SqfliteAgentRepository.open();
      final checker = AgentChecker(repo: repo, notifier: notifier);
      final checked = await checker.checkDueAgents();
      // Liveness diagnostics, not task activity: lets the app show when the
      // background worker last ran (and how much was due) without inventing
      // per-task history entries.
      await repo.putKv(
        'lastBackgroundRunAt',
        DateTime.now().toIso8601String(),
      );
      await repo.putKv('lastBackgroundRunChecked', '$checked');
      await repo.close();
      return true;
    } catch (e) {
      // Persist the failure so the app can surface it later - a swallowed
      // exception here is otherwise indistinguishable from never running.
      try {
        final repo = await SqfliteAgentRepository.open();
        await repo.putKv(
          'lastBackgroundError',
          '${DateTime.now().toIso8601String()} $e',
        );
        await repo.close();
      } catch (_) {
        // The store itself may be what failed; nothing more we can record.
      }
      // Return false so WorkManager retries with backoff instead of dropping
      // the cycle silently.
      return false;
    }
  });
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
