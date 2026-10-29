/// Android notifications (spec V1). Real notifications only.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification sink. Abstract so tests capture instead of showing.
abstract class LookoutNotifier {
  Future<void> showAgentResult(
      {required int agentId, required String title, required String body});
}

class LocalNotificationsService implements LookoutNotifier {
  static const channelId = 'lookout_checks';
  static const channelName = 'Agent checks';

  final FlutterLocalNotificationsPlugin _plugin;
  final void Function(int agentId)? onTapAgent;

  LocalNotificationsService({FlutterLocalNotificationsPlugin? plugin, this.onTapAgent})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Prepares the plugin. Safe in every isolate: it never asks Android for
  /// a permission. The WorkManager dispatcher runs without an Activity, and
  /// the plugin's permission request needs one - asking from there threw
  /// "Attempt to invoke virtual method 'int android.content.Context
  /// .checkPermission(...)' on a null object reference" and failed the whole
  /// background cycle (the 1.1.8 "Background worker error"). The prompt is
  /// [requestPermissionFromForeground], called only by the visible app.
  Future<void> init() async {
    const init = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.startsWith('agent:')) {
          final id = int.tryParse(payload.substring(6));
          if (id != null) onTapAgent?.call(id);
        }
      },
    );
  }

  /// Android 13+ runtime permission prompt. FOREGROUND ONLY: call it from
  /// the visible app (startup, creating a task), never from background code.
  /// Never throws; returns whether notifications are allowed afterwards.
  Future<bool> requestPermissionFromForeground() async {
    try {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Whether Android currently lets Lookout post notifications. Reads only;
  /// safe without an Activity. Unknown counts as allowed so a plugin hiccup
  /// never suppresses an alert.
  Future<bool> notificationsAllowed() async {
    try {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return enabled ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Shows a result without asking for any permission. When Android has
  /// notifications turned off for Lookout this throws
  /// [NotificationsDisabled] so the caller can record why nothing appeared;
  /// it never prompts.
  @override
  Future<void> showAgentResult(
      {required int agentId, required String title, required String body}) async {
    if (!await notificationsAllowed()) {
      throw const NotificationsDisabled();
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Results from your background agents',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(agentId, title, body, details,
        payload: 'agent:$agentId');
  }
}

/// Android has notifications switched off for Lookout.
class NotificationsDisabled implements Exception {
  const NotificationsDisabled();
  @override
  String toString() => 'Notifications are turned off for Lookout';
}

/// Test/headless sink: records what would have been shown.
class RecordingNotifier implements LookoutNotifier {
  final List<({int agentId, String title, String body})> shown = [];
  @override
  Future<void> showAgentResult(
      {required int agentId, required String title, required String body}) async {
    shown.add((agentId: agentId, title: title, body: body));
  }
}
