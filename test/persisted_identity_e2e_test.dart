// End-to-end proof that a persisted source identity survives a real
// save/reload and drives the scheduled checker path - for both the new
// flag-carrying identity and the legacy 1.1.18 identity without flags.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/source_discovery.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'next_update_test.dart' as h;

const spec = DiscoverySpec(
  kind: 'productPrice',
  model: 'Gold Price',
  country: 'United States',
  currency: 'USD',
  storageGb: 0,
  target: 4030,
  condition: WatchCondition.greaterThan,
);

ProductPage goldPage() => ProductPage(
      Uri.parse('https://goldpricez.com/us/ounce'),
      200,
      File('test/fixtures/goldpricez_us_ounce.html').readAsStringSync(),
    );

Agent watch(String identity) => Agent(
      title: 'Gold watch',
      originalPrompt: 'gold price above 4030',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 10, 29),
      nextCheckAt: DateTime(2026, 10, 29), // already due
      checkInterval: const Duration(minutes: 30),
      condition: spec.condition,
      target: spec.target,
      sourceUrl: 'https://goldpricez.com/us/ounce',
      sourceIdentity: identity,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final legacy in [false, true]) {
    test(
      legacy
          ? 'legacy 1.1.18 flag-less identity reads through save/reload and a scheduled check'
          : 'new flagged identity reads through save/reload and a scheduled check',
      () async {
        final page = goldPage();
        final candidate = SourceCandidateValidator.validateReadableQuote(
          spec,
          page,
          now: DateTime(2026, 10, 29, 15),
        )!;
        var identity = ReviewedSource(spec, candidate).identity;
        if (legacy) {
          identity = identity
              .replaceAll(',"marketQuote":true', '')
              .replaceAll(',"readableQuote":true', '');
          expect(identity, isNot(contains('readableQuote')));
        }

        // Save, close, reopen: the identity must survive a real reload.
        final path =
            '${Directory.systemTemp.path}/e2e_${legacy ? 'legacy' : 'new'}_${DateTime.now().microsecondsSinceEpoch}.db';
        final writer = await SqfliteAgentRepository.open(path: path);
        final id = await writer.insertAgent(watch(identity));
        await writer.close();
        final repo = await SqfliteAgentRepository.open(path: path);
        final reloaded = await repo.agentById(id);
        expect(reloaded, isNotNull);
        expect(reloaded!.sourceIdentity, identity,
            reason: 'identity must persist byte-for-byte');

        // The scheduled path: due-agents sweep with the app's strict fetcher.
        final checker = AgentChecker(
          repo: repo,
          notifier: RecordingNotifier(),
          strictFetcher: (a) => DiscoveredSourceReader.fetch(
            a,
            reader: h.FakeReader(page),
          ),
        );
        final cycle = await checker.checkDueAgents();
        expect(cycle.checked, 1, reason: 'the due watch must be checked');

        final after = await repo.agentById(id);
        expect(after!.currentValue, 4022.28,
            reason: 'the checker must read the same value discovery proved');
        expect(after.status, AgentStatus.active,
            reason: '4022.28 < 4030: watch keeps monitoring, no false alert');
        await repo.close();
      },
    );
  }
}
