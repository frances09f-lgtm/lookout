// Deterministic, synthetic preview data only. No live account or network calls.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';

import 'recovery_capture_test.dart' as capture;

void main() {
  const captureDir = String.fromEnvironment('CAPTURE_DIR');
  for (final dark in [false, true]) {
    for (final screen in ['home', 'create', 'empty', 'details']) {
      testWidgets('UI capture $screen ${dark ? 'dark' : 'light'}', (t) async {
        await capture.fonts(t);
        await t.binding.setSurfaceSize(const Size(336, 750));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final repo = InMemoryAgentRepository();
        if (screen == 'home' || screen == 'details') {
          for (final a in [
            Agent(
              title: 'Noise-cancelling headphones',
              originalPrompt: 'below 8000',
              type: AgentType.valueWatch,
              status: AgentStatus.active,
              createdAt: DateTime(2026, 10, 15),
              checkInterval: const Duration(minutes: 30),
              condition: WatchCondition.lessThan,
              target: 8000,
              currentValue: 8990,
              sourceUrl: 'https://example.com/headphones',
              lastCheckedAt: DateTime(2026, 10, 15, 18, 30),
            ),
            Agent(
              title: 'Pick up the parcel',
              originalPrompt: 'remind me',
              type: AgentType.reminder,
              status: AgentStatus.active,
              createdAt: DateTime(2026, 10, 15),
              checkInterval: const Duration(minutes: 30),
              condition: WatchCondition.remindAt,
              target: DateTime(
                2026,
                10,
                16,
                10,
              ).millisecondsSinceEpoch.toDouble(),
            ),
            Agent(
              title: 'Weekend ticket',
              originalPrompt: 'below 150',
              type: AgentType.valueWatch,
              status: AgentStatus.paused,
              createdAt: DateTime(2026, 10, 15),
              checkInterval: const Duration(minutes: 30),
              condition: WatchCondition.lessThan,
              target: 150,
            ),
          ]) {
            await repo.insertAgent(a);
          }
          await repo.logActivity(
            1,
            'Watch created',
            DateTime(2026, 10, 15, 18, 0),
          );
        }
        final key = GlobalKey();
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
            home: RepaintBoundary(
              key: key,
              child: screen == 'create'
                  ? CreateAgentScreen(repo: repo)
                  : screen == 'details'
                  ? AgentDetailsScreen(
                      repo: repo,
                      checker: AgentChecker(
                        repo: repo,
                        notifier: RecordingNotifier(),
                      ),
                      agentId: 1,
                    )
                  : HomeScreen(
                      repo: repo,
                      checker: AgentChecker(
                        repo: repo,
                        notifier: RecordingNotifier(),
                      ),
                    ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (captureDir.isNotEmpty) {
          await t.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              '$captureDir/$screen-${dark ? 'dark' : 'light'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
