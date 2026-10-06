import 'package:flutter/material.dart';

import 'data/agent_repository.dart';
import 'data/sqflite_repository.dart';
import 'presentation/agent_details_screen.dart';
import 'presentation/home_screen.dart';
import 'presentation/theme.dart';
import 'services/background.dart';
import 'services/checker.dart';
import 'services/notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repo = await SqfliteAgentRepository.open();

  final navigatorKey = GlobalKey<NavigatorState>();
  final notifications = LocalNotificationsService(onTapAgent: (agentId) {
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => AgentDetailsScreen(
            repo: repo, checker: checker, agentId: agentId)));
  });
  await notifications.init();

  final checker = AgentChecker(repo: repo, notifier: notifications);

  // Register the WorkManager periodic task (15-min platform minimum).
  await BackgroundScheduler().init();

  runApp(LookoutApp(repo: repo, checker: checker, navigatorKey: navigatorKey));
}

class LookoutApp extends StatelessWidget {
  final AgentRepository repo;
  final AgentChecker checker;
  final GlobalKey<NavigatorState>? navigatorKey;

  const LookoutApp(
      {super.key, required this.repo, required this.checker, this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lookout',
      theme: LookoutTheme.light(),
      darkTheme: LookoutTheme.dark(),
      themeMode: ThemeMode.system,
      navigatorKey: navigatorKey,
      home: HomeScreen(repo: repo, checker: checker),
    );
  }
}
