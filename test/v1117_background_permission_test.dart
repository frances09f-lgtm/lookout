import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/activity_screen.dart';
import 'package:lookout/services/background.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/page_fetch.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1.1.17: the background worker must never ask Android for a permission
/// (no Activity there - the Oct 25 "checkPermission on a null object
/// reference" error), and a later successful run clears an old error.

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

/// The exact failure Android gave the background isolate.
PlatformException _nullActivity() => PlatformException(
      code: 'error',
      message: "Attempt to invoke virtual method 'int android.content.Context"
          ".checkPermission(java.lang.String, int, int)' on a null object "
          'reference',
    );

Agent iphoneWatch({double? current}) => Agent(
      title: 'Tell me when iphone 15 128gb becomes cheaper than ₹60,000',
      originalPrompt: 'Tell me when iphone 15 128gb becomes cheaper than ₹60,000',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 10, 25, 9),
      checkInterval: const Duration(hours: 6),
      condition: WatchCondition.lessThan,
      target: 60000,
      currentValue: current,
      sourceUrl: 'https://shop.example/iphone-15-128gb',
      nextCheckAt: DateTime(2026, 10, 29, 12, 0),
    );

class ClosableRepo extends InMemoryAgentRepository {
  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('background path never requests a permission', () {
    final calls = <String>[];

    setUp(() {
      calls.clear();
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'initialize':
            return true;
          case 'areNotificationsEnabled':
            return true;
          case 'requestNotificationsPermission':
            // What a background isolate gets from the real plugin.
            throw _nullActivity();
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('a real Workmanager run with the real notifier: no permission '
        'request, the alert is shown, no worker error', () async {
      final repo = ClosableRepo();
      final now = DateTime.now();
      await repo.insertAgent(Agent(
        title: 'Pay rent',
        originalPrompt: 'remind me to pay rent',
        type: AgentType.reminder,
        status: AgentStatus.active,
        createdAt: now,
        checkInterval: const Duration(minutes: 15),
        condition: WatchCondition.remindAt,
        target: now.subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch
            .toDouble(),
        nextCheckAt: now.subtract(const Duration(minutes: 1)),
      ));
      // Default makeNotifier: exactly what the dispatcher builds on a phone.
      final ok = await runWorkmanagerTask(openRepo: () async => repo);
      expect(ok, isTrue);
      expect(calls, contains('initialize'));
      expect(calls, contains('show'));
      expect(calls, isNot(contains('requestNotificationsPermission')));
      expect(calls, isNot(contains('requestExactAlarmsPermission')));
      expect(await repo.getKv('lastBackgroundError') ?? '', isEmpty);
    });

    test('init() alone never asks; only the foreground call does', () async {
      final n = LocalNotificationsService();
      await n.init();
      expect(calls, ['initialize']);
      // The foreground prompt swallows the platform failure instead of
      // throwing into startup.
      expect(await n.requestPermissionFromForeground(), isFalse);
      expect(calls.last, 'requestNotificationsPermission');
    });

    test('notifications switched off: the check still completes and the '
        'history says why there was no alert', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        if (call.method == 'areNotificationsEnabled') return false;
        if (call.method == 'initialize') return true;
        if (call.method == 'requestNotificationsPermission') {
          throw _nullActivity();
        }
        return null;
      });
      final repo = InMemoryAgentRepository();
      final n = LocalNotificationsService();
      await n.init();
      final id = await repo.insertAgent(iphoneWatch());
      final checker = AgentChecker(
        repo: repo,
        notifier: n,
        clock: () => DateTime(2026, 10, 29, 18),
        fetcher: (_) async => FetchOutcome.found(59999, 'Product offer 59999'),
      );
      final r = await checker.checkDueAgents();
      expect(r.checked, 1);
      expect(calls, isNot(contains('show')));
      expect(calls, isNot(contains('requestNotificationsPermission')));
      final log = (await repo.activityFor(id)).map((e) => e.message);
      expect(log, contains('Condition met'));
      expect(log.any((m) => m.startsWith('Notification not shown')), isTrue);
    });

    test('background sources contain no permission request', () {
      for (final path in [
        'lib/services/background.dart',
        'lib/services/checker.dart',
        'lib/services/page_fetch.dart',
        'lib/services/source_discovery.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, isNot(contains('requestNotificationsPermission')),
            reason: path);
        expect(src, isNot(contains('requestPermissionFromForeground')),
            reason: path);
        expect(src, isNot(contains('requestExactAlarmsPermission')),
            reason: path);
      }
    });
  });

  group('worker error is cleared by a later successful run', () {
    setUp(() => SharedPreferences.setMockInitialValues({
          prefLastError: '2026-10-25T14:16:58.000 PlatformException(error, '
              'checkPermission on a null object reference)',
        }));

    test('success clears the kv record and the preferences mirror', () async {
      final repo = InMemoryAgentRepository();
      await repo.putKv('lastBackgroundError',
          '2026-10-25T14:16:58.000 PlatformException(error, boom)');
      final checker = AgentChecker(
        repo: repo,
        notifier: RecordingNotifier(),
        clock: () => DateTime(2026, 10, 29, 12, 54),
      );
      expect(await runBackgroundCycle(repo: repo, checker: checker), isTrue);
      expect(await repo.getKv('lastBackgroundError'), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(prefLastError) ?? '', isEmpty);
    });

    test('a failure AFTER the last success is kept', () async {
      final repo = InMemoryAgentRepository();
      final ok = await runBackgroundCycle(
        repo: repo,
        checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
      );
      expect(ok, isTrue);
      // The next cycle fails: its error must stay visible.
      await repo.putKv('lastBackgroundError',
          '${DateTime.now().add(const Duration(minutes: 1)).toIso8601String()} boom');
      expect(
        currentWorkerError(await repo.getKv('lastBackgroundError'),
            DateTime.parse((await repo.getKv('lastBackgroundRunAt'))!)),
        isNotNull,
      );
    });

    test('currentWorkerError hides errors older than the last completion', () {
      final done = DateTime(2026, 10, 29, 12, 54);
      expect(currentWorkerError('2026-10-25T14:16:58 boom', done), isNull);
      expect(currentWorkerError('2026-10-29T13:00:00 boom', done), isNotNull);
      expect(currentWorkerError('', done), isNull);
      expect(currentWorkerError(null, done), isNull);
      // No parsable time: shown (cannot prove it is stale).
      expect(currentWorkerError('boom', done), 'boom');
    });

    testWidgets('screen: a stale error under a newer completed run is gone',
        (t) async {
      final repo = InMemoryAgentRepository();
      final id = await repo.insertAgent(iphoneWatch(current: 69999));
      await repo.putKv('lastBackgroundRunAt', '2026-10-29T12:54:00.000');
      await repo.putKv('lastBackgroundError',
          '2026-10-25T14:16:58.000 PlatformException(error, null object)');
      await t.pumpWidget(
          MaterialApp(home: ActivityScreen(repo: repo, agentId: id)));
      await t.pumpAndSettle();
      expect(find.textContaining('Background worker last completed'),
          findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('had a problem'), findsNothing);
    });

    testWidgets('screen: a current error is one calm line, raw text behind '
        'Details', (t) async {
      final repo = InMemoryAgentRepository();
      final id = await repo.insertAgent(iphoneWatch(current: 69999));
      await repo.putKv('lastBackgroundRunAt', '2026-10-29T12:54:00.000');
      await repo.putKv('lastBackgroundError',
          '2026-10-29T18:54:00.000 PlatformException(error, null object)');
      await t.pumpWidget(
          MaterialApp(home: ActivityScreen(repo: repo, agentId: id)));
      await t.pumpAndSettle();
      expect(find.textContaining('Last check had a problem'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('Background worker error'), findsNothing);
      await t.tap(find.byKey(const ValueKey('worker-problem-toggle')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('worker-problem-details')),
          findsOneWidget);
      expect(find.textContaining('PlatformException'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
    });
  });

  test('the iPhone watch checks every 6 h and alerts once below ₹60,000',
      () async {
    final repo = InMemoryAgentRepository();
    final notifier = RecordingNotifier();
    final id = await repo.insertAgent(iphoneWatch(current: 69999));
    var now = DateTime(2026, 10, 29, 12, 54);
    var price = 69999.0;
    final checker = AgentChecker(
      repo: repo,
      notifier: notifier,
      clock: () => now,
      fetcher: (_) async =>
          FetchOutcome.found(price, 'Product offer ${price.round()}'),
    );
    await checker.checkDueAgents();
    var a = (await repo.agentById(id))!;
    expect(notifier.shown, isEmpty);
    expect(a.status, AgentStatus.active);
    expect(a.nextCheckAt, now.add(const Duration(hours: 6)));

    // A worker cycle 15 min later does not re-check before the 6 h are up.
    now = now.add(const Duration(minutes: 15));
    expect((await checker.checkDueAgents()).checked, 0);

    // Six hours on, the price drops under the target: one alert.
    now = DateTime(2026, 10, 29, 18, 54);
    price = 59999;
    expect((await checker.checkDueAgents()).checked, 1);
    a = (await repo.agentById(id))!;
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.title, contains('condition met'));
    expect(a.status, AgentStatus.completed);
  });
}
