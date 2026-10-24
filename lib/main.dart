import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/agent_repository.dart';
import 'data/sqflite_repository.dart';
import 'presentation/agent_details_screen.dart';
import 'presentation/home_screen.dart';
import 'presentation/theme.dart';
import 'services/background.dart';
import 'services/checker.dart';
import 'services/notifications.dart';
import 'services/usage_reporter.dart';

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
  UsageReporter.report('app_start');

  final checker = AgentChecker(repo: repo, notifier: notifications);

  // Register the WorkManager periodic task (15-min platform minimum).
  await BackgroundScheduler().init();

  runApp(LookoutApp(repo: repo, checker: checker, navigatorKey: navigatorKey));
}

class LookoutApp extends StatefulWidget {
  final AgentRepository repo;
  final AgentChecker checker;
  final GlobalKey<NavigatorState>? navigatorKey;

  const LookoutApp(
      {super.key, required this.repo, required this.checker, this.navigatorKey});

  @override
  State<LookoutApp> createState() => _LookoutAppState();
}

class _LookoutAppState extends State<LookoutApp>
    with WidgetsBindingObserver {
  static const _prefKey = 'lookout_theme_dark';
  bool? _dark; // null = follow system until the user taps the toggle
  Timer? _foregroundChecks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startForegroundChecks();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_prefKey);
      if (saved != null && mounted) setState(() => _dark = saved);
    });
  }

  /// 5/10-minute intervals run only while the app is open: this ticker runs
  /// due checks once a minute in the foreground. Closed-app checks stay on
  /// WorkManager, which floors at the 15-minute platform minimum.
  void _startForegroundChecks() {
    _foregroundChecks?.cancel();
    _foregroundChecks = Timer.periodic(const Duration(minutes: 1), (_) {
      widget.checker.checkDueAgents();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundChecks();
      widget.checker.checkDueAgents();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _foregroundChecks?.cancel();
      _foregroundChecks = null;
    }
  }

  @override
  void dispose() {
    _foregroundChecks?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _toggleTheme(bool dark) {
    setState(() => _dark = dark);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_prefKey, dark));
  }

  @override
  Widget build(BuildContext context) {
    final mode = _dark == null
        ? ThemeMode.system
        : (_dark! ? ThemeMode.dark : ThemeMode.light);
    return MaterialApp(
      title: 'Lookout',
      theme: LookoutTheme.light(),
      darkTheme: LookoutTheme.dark(),
      themeMode: mode,
      navigatorKey: widget.navigatorKey,
      home: Builder(
        builder: (context) => HomeScreen(
          repo: widget.repo,
          checker: widget.checker,
          isDark: Theme.of(context).brightness == Brightness.dark,
          onToggleTheme: _toggleTheme,
        ),
      ),
    );
  }
}
