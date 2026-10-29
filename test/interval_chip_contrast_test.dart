import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/theme.dart';

void main() {
  testWidgets('Review & schedule interval chips use contrasting label colors',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: LookoutTheme.dark(),
        home: CreateAgentScreen(repo: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Gold Price In Forex');
    await tester.enterText(find.byType(TextField).at(1), '4030');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Review watch'));
    await tester.pumpAndSettle();

    expect(find.text('Review & schedule'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '10 min'));
    await tester.pumpAndSettle();

    for (final label in ['5 min', '15 min', '1 h']) {
      final chip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, label),
      );
      expect(chip.backgroundColor, Colors.white);
      expect(chip.labelStyle?.color, Colors.black);
    }
    final selected = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, '10 min'),
    );
    expect(selected.backgroundColor, const Color(0xFF201A17));
    expect(selected.labelStyle?.color, Colors.white);
    expect(tester.takeException(), isNull);
  });
}
