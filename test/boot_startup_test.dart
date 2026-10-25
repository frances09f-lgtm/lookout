import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/main.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/services/background.dart';
import 'package:lookout/services/notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AgentRepository> goodStore() async => InMemoryAgentRepository();
  Future<LookoutNotifier> goodNotifications(onTap) async =>
      RecordingNotifier();
  Future<void> goodBackground() async {}

  testWidgets('happy path: boot screen first, then the app opens', (t) async {
    await t.pumpWidget(LookoutRoot(
      openStore: goodStore,
      initNotifications: goodNotifications,
      initBackground: goodBackground,
    ));
    // First frame is the boot screen, not a stuck logo.
    expect(find.text('Lookout'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    // Home screen reached.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('store open failure shows the step and reason, retry works',
      (t) async {
    var fail = true;
    await t.pumpWidget(LookoutRoot(
      openStore: () async {
        if (fail) throw StateError('database is corrupted');
        return InMemoryAgentRepository();
      },
      initNotifications: goodNotifications,
      initBackground: goodBackground,
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Lookout could not start'), findsOneWidget);
    expect(find.textContaining('opening your watches'), findsOneWidget);
    expect(find.textContaining('database is corrupted'), findsOneWidget);
    // Not a dead end: retry after the cause clears.
    fail = false;
    await t.tap(find.text('Try again'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a hung store open times out to the error screen, never the logo',
      (t) async {
    await t.pumpWidget(LookoutRoot(
      openStore: () => Completer<AgentRepository>().future, // never returns
      initNotifications: goodNotifications,
      initBackground: goodBackground,
    ));
    await t.pump();
    // Still booting before the timeout.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.pump(const Duration(seconds: 16));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Lookout could not start'), findsOneWidget);
    expect(find.textContaining('opening your watches'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('notification failure opens the app with a visible warning',
      (t) async {
    await t.pumpWidget(LookoutRoot(
      openStore: goodStore,
      initNotifications: (onTap) async =>
          throw StateError('notification channel broken'),
      initBackground: goodBackground,
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Notifications could not be set up'),
        findsOneWidget);
    expect(t.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(prefLastError), contains('notifications setup'));
  });

  testWidgets(
      'background scheduling failure opens the app with a plain warning - '
      'nothing implies automatic checks work', (t) async {
    await t.pumpWidget(LookoutRoot(
      openStore: goodStore,
      initNotifications: goodNotifications,
      initBackground: () async => throw StateError('workmanager init failed'),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Automatic checks could not be scheduled'),
        findsOneWidget);
    expect(
        find.textContaining(
            'Watches run only while the app is open until this works.'),
        findsOneWidget);
    expect(t.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(prefLastError), contains('background scheduling'));
  });
}
