import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/agent_repository.dart';
import 'data/sqflite_repository.dart';
import 'presentation/agent_details_screen.dart';
import 'presentation/boot_screen.dart';
import 'presentation/home_screen.dart';
import 'presentation/theme.dart';
import 'services/background.dart';
import 'services/checker.dart';
import 'services/notifications.dart';
import 'services/usage_reporter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The first frame renders BEFORE any startup work: a failed or stuck
  // startup step shows on screen instead of leaving the native splash
  // (the logo) up forever with no explanation.
  runApp(const LookoutRoot());
}

/// How long one startup step may take before it counts as failed. Android
/// kills nothing here; the bound exists so a wedged plugin or store shows
/// the error screen instead of hanging silently.
const startupStepTimeout = Duration(seconds: 15);

typedef StoreOpener = Future<AgentRepository> Function();
typedef NotificationsInitializer = Future<LookoutNotifier> Function(
    void Function(int agentId) onTapAgent);
typedef BackgroundInitializer = Future<void> Function();

class LookoutRoot extends StatefulWidget {
  // Injectable for tests; production leaves all three null and uses the
  // real stores below. The boot sequence itself is the production path.
  final StoreOpener? openStore;
  final NotificationsInitializer? initNotifications;
  final BackgroundInitializer? initBackground;

  const LookoutRoot({
    super.key,
    this.openStore,
    this.initNotifications,
    this.initBackground,
  });

  @override
  State<LookoutRoot> createState() => LookoutRootState();
}

class LookoutRootState extends State<LookoutRoot> {
  final navigatorKey = GlobalKey<NavigatorState>();

  String _step = 'Starting up';
  Object? _error;
  String _failedStep = '';
  bool _booting = false;
  bool _warningDismissed = false;
  final List<String> _startupWarnings = [];
  AgentRepository? _repo;
  LookoutNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<AgentRepository> _openStoreReal() => SqfliteAgentRepository.open();

  Future<LookoutNotifier> _initNotificationsReal(
      void Function(int agentId) onTapAgent) async {
    final notifications = LocalNotificationsService(onTapAgent: onTapAgent);
    await notifications.init();
    return notifications;
  }

  Future<void> _initBackgroundReal() => BackgroundScheduler().init();

  /// Records a non-fatal startup failure where the history screen's
  /// background-status line will surface it: the SharedPreferences mirror
  /// the worker also writes. Best effort, bounded, never blocks boot.
  Future<void> _mirrorStartupIssue(String step, Object error) async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      await prefs.setString(prefLastError,
          '${DateTime.now().toIso8601String()} App start: $step: $error');
    } catch (_) {
      // The on-screen banner still carries the warning.
    }
  }

  Future<void> _boot() async {
    // One boot at a time. A retry after a store timeout may overlap the
    // orphaned first open still completing in the background: that
    // connection is never referenced again, and busy_timeout (4s) covers
    // the brief lock contention with the retry's fresh connection.
    if (_booting) return;
    _booting = true;
    setState(() {
      _error = null;
      _step = 'Starting up';
    });

    // Step 1: the watch store. The only truly blocking step - the app is
    // its data, so a failure here must be visible, not bypassed.
    AgentRepository repo;
    try {
      setState(() => _step = 'Opening your watches');
      repo = await (widget.openStore ?? _openStoreReal)()
          .timeout(startupStepTimeout);
    } catch (e) {
      _booting = false;
      setState(() {
        _failedStep = 'opening your watches';
        _error = e;
      });
      return;
    }

    // Step 2: notifications. Non-blocking: the app still works without
    // them, but the user must SEE that alerting is off.
    LookoutNotifier notifier;
    try {
      setState(() => _step = 'Setting up notifications');
      notifier =
          await (widget.initNotifications ?? _initNotificationsReal)((agentId) {
        final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
        navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) => AgentDetailsScreen(
                repo: repo, checker: checker, agentId: agentId)));
      }).timeout(startupStepTimeout);
    } catch (e) {
      notifier = RecordingNotifier();
      _startupWarnings.add(
          'Notifications could not be set up: ${_redactDiagnostic('$e')} '
          'You will not be alerted when a watch matches.');
      unawaited(_mirrorStartupIssue('notifications setup', e));
    }

    // Step 3: background scheduling. Non-blocking, and the warning must
    // stay plainly visible - nothing may silently imply automatic checks
    // are working when they are not.
    try {
      setState(() => _step = 'Scheduling automatic checks');
      await (widget.initBackground ?? _initBackgroundReal)()
          .timeout(startupStepTimeout);
    } catch (e) {
      _startupWarnings.add(
          'Automatic checks could not be scheduled: ${_redactDiagnostic('$e')} '
          'Watches run only while the app is open until this works.');
      unawaited(_mirrorStartupIssue('background scheduling', e));
    }

    UsageReporter.report('app_start');
    _booting = false;
    setState(() {
      _repo = repo;
      _notifier = notifier;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final repo = _repo;
    final notifier = _notifier;

    Widget child;
    if (error != null) {
      child = MaterialApp(
        theme: LookoutTheme.light(),
        darkTheme: LookoutTheme.dark(),
        home: LookoutBootErrorScreen(
          step: _failedStep,
          error: error,
          onRetry: _boot,
        ),
      );
    } else if (repo == null || notifier == null) {
      child = MaterialApp(
        theme: LookoutTheme.light(),
        darkTheme: LookoutTheme.dark(),
        home: LookoutBootScreen(step: _step),
      );
    } else {
      final warnings = _startupWarnings;
      child = Column(
        children: [
          if (warnings.isNotEmpty && !_warningDismissed)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Material(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFFFF3CD),
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          warnings.join('\n\n'),
                          style: const TextStyle(
                              color: Color(0xFF5C4400), fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Color(0xFF5C4400)),
                        onPressed: () =>
                            setState(() => _warningDismissed = true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
          Expanded(
            child: LookoutApp(
                repo: repo, checker: AgentChecker(repo: repo, notifier: notifier), navigatorKey: navigatorKey),
          ),
        ],
      );
    }
    return child;
  }
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

/// Redacts links and file paths from a diagnostic string before it is
/// shown: an error may contain a watched URL or a storage path, and a
/// screenshot of the screen must never leak those.
String _redactDiagnostic(String raw) {
  var out = raw.replaceAll(RegExp(r'https?://\S+'), '<link>');
  out = out.replaceAll(
      RegExp(r'(/[A-Za-z0-9_.-]+){2,}[A-Za-z0-9_/.-]*'), '<path>');
  return out.length > 300 ? '${out.substring(0, 300)}...' : out;
}
