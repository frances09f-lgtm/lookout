/// Exact-alarm engine (prototype): the on-time closed-app check path.
///
/// WorkManager's 15-minute floor makes it a poor primary scheduler for
/// sub-hour intervals, so this engine arms one exact alarm for the earliest
/// upcoming check (setExactAndAllowWhileIdle via android_alarm_manager_plus,
/// RTC_WAKEUP). Each alarm fire runs the SAME instrumented background cycle
/// as the WorkManager path and then re-arms for the next due check, so the
/// chain continues while the app stays closed. WorkManager stays registered
/// as the fallback for the cases alarms cannot cover (denied permission,
/// force-stop, OEM task killers).
///
/// Honest limits (official sources, verified against Android 16 / target 36):
/// - In Doze, Android caps these alarms at one fire per 9 minutes per app,
///   so a 5-minute interval is not guaranteed (developer.android.com/
///   training/monitoring-device-state/doze-standby).
/// - SCHEDULE_EXACT_ALARM is denied by default on Android 14+ for apps
///   targeting 33+; the user grants it once via the in-app deep-link
///   (developer.android.com/about/versions/14/changes/schedule-exact-alarms).
/// - A force-stopped app gets no alarms until reopened - Android-hard, no
///   local fix.
library;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/services.dart';

import '../data/agent_repository.dart';
import '../data/sqflite_repository.dart';
import '../domain/agent.dart';
import 'background.dart';
import 'checker.dart';
import 'notifications.dart';

/// Single alarm slot: one armed alarm always points at the earliest due
/// check, whatever agent owns it.
const int checkAlarmId = 0;

/// Native bridge for the permission and settings surfaces the plugins do
/// not expose (MainActivity, channel lookout/alarms).
class AlarmPermissions {
  static const _channel = MethodChannel('lookout/alarms');

  /// Whether setExactAndAllowWhileIdle will actually fire (Android 12+).
  /// Pre-12 there is no grant, so this reports true. Null = the native
  /// check is unavailable (e.g. no engine in tests), never a guess.
  static Future<bool?> canScheduleExactAlarms() async {
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms');
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Opens the system Alarms & reminders screen for this app (Android 12+).
  static Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod<void>('openExactAlarmSettings');
    } catch (_) {}
  }

  static Future<bool?> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel
          .invokeMethod<bool>('isIgnoringBatteryOptimizations');
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Opens the system battery-optimization exemption prompt for this app.
  static Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
    } catch (_) {}
  }
}

/// Test seam over the plugin so the scheduling logic is unit-testable on
/// the host (the plugin needs a running Android engine).
abstract class AlarmClock {
  Future<void> initialize();
  Future<bool> scheduleExactWakeup(int id, DateTime at);
  Future<bool> cancel(int id);
}

class PluginAlarmClock implements AlarmClock {
  @override
  Future<void> initialize() => AndroidAlarmManager.initialize();

  @override
  Future<bool> scheduleExactWakeup(int id, DateTime at) {
    return AndroidAlarmManager.oneShotAt(
      at,
      id,
      lookoutAlarmCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }

  @override
  Future<bool> cancel(int id) => AndroidAlarmManager.cancel(id);
}

AlarmClock _clock = PluginAlarmClock();

/// Tests replace the native permission check.
Future<bool?> Function() canScheduleExactAlarmsForTest =
    AlarmPermissions.canScheduleExactAlarms;

/// Tests swap in a fake clock.
void debugSetAlarmClock(AlarmClock clock) => _clock = clock;

/// The earliest moment any agent wants a check: the smallest nextCheckAt
/// among active, unblocked agents. Agents that never ran (nextCheckAt null)
/// are due immediately, mirroring dueAgents ordering. Null = nothing to arm.
DateTime? nextDueAt(List<Agent> agents) {
  DateTime? best;
  for (final a in agents) {
    if (a.status != AgentStatus.active) continue;
    if (a.needsSourceResolution || a.sourceBlocked) continue;
    final at = a.nextCheckAt;
    if (at == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (best == null || at.isBefore(best)) best = at;
  }
  return best;
}

/// (Re)arms the exact alarm for the earliest due check, or cancels it when
/// nothing is due. Never throws: a scheduling failure must not break the
/// caller's own work (the WorkManager fallback still runs).
Future<void> rescheduleCheckAlarm({AgentRepository? repo}) async {
  final ownRepo = repo == null;
  AgentRepository? r;
  try {
    r = repo ?? await SqfliteAgentRepository.open();
    if (!(await canScheduleExactAlarmsForTest() ?? false)) {
      // No grant: leave the chain to the WorkManager fallback.
      await _clock.cancel(checkAlarmId);
      return;
    }
    final due = nextDueAt(await r.allAgents());
    if (due == null) {
      await _clock.cancel(checkAlarmId);
      return;
    }
    var at = due;
    final soon = DateTime.now().add(const Duration(seconds: 10));
    if (at.isBefore(soon)) at = soon;
    await _clock.scheduleExactWakeup(checkAlarmId, at);
  } catch (_) {
    // The fallback worker still covers the checks; never surface this.
  } finally {
    if (ownRepo && r != null) {
      try {
        await r.close();
      } catch (_) {}
    }
  }
}

/// Alarm entry point: runs the same instrumented cycle as WorkManager, then
/// re-arms for the next due check. Split so tests can drive the body with
/// fakes via [runAlarmTask].
@pragma('vm:entry-point')
void lookoutAlarmCallback() {
  runAlarmTask();
}

Future<bool> runAlarmTask({
  Future<AgentRepository> Function()? openRepo,
  Future<LookoutNotifier> Function()? makeNotifier,
}) async {
  final ok = await runWorkmanagerTask(
    openRepo: openRepo,
    makeNotifier: makeNotifier,
  );
  // Re-arm from a fresh store read inside this isolate.
  try {
    final repo = await SqfliteAgentRepository.open();
    try {
      await rescheduleCheckAlarm(repo: repo);
    } finally {
      await repo.close();
    }
  } catch (_) {}
  return ok;
}
