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
    // Android 13+ runtime permission.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> showAgentResult(
      {required int agentId, required String title, required String body}) {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Results from your background agents',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    return _plugin.show(agentId, title, body, details,
        payload: 'agent:$agentId');
  }
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
