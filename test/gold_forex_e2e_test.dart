// End-to-end: the exact device prompt flows discovery -> save/reload ->
// scheduled checker, for both the current model and the legacy 1.1.18/19
// identity wording. India + USD, target 4030 preserved throughout.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/domain/parser.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/source_discovery.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'next_update_test.dart' as h;

class EmptySearch implements SourceSearchProvider {
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async => const [];
}

ProductPage goldPage() => ProductPage(
      Uri.parse('https://goldpricez.com/us/ounce'),
      200,
      File('test/fixtures/goldpricez_us_ounce.html').readAsStringSync(),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final legacy in [false, true]) {
    test(
      legacy
          ? 'legacy "Gold In Forex rises" identity: discovery to scheduled check agrees'
          : 'exact device prompt "Gold In Forex": discovery to scheduled check agrees',
      () async {
        final parsed = DiscoveryTaskParser.parse(
          'Tell me when Gold Price In Forex rises above ₹4030',
          country: 'India',
          currency: 'USD',
        );
        var spec = parsed.spec!;
        expect(spec.target, 4030);
        expect(spec.currency, 'USD');
        expect(spec.country, 'India');
        final page = goldPage();
        final discovered = await SourceDiscoveryService(
          searchProvider: EmptySearch(),
          pageReader: h.FakeReader(page),
        ).discover(spec);
        expect(discovered.candidates, hasLength(1));
        expect(discovered.candidates.single.price, 4022.28);
        if (legacy) {
          // The identity wording 1.1.18/1.1.19 would have persisted.
          spec = DiscoverySpec(
            kind: spec.kind,
            model: 'Gold In Forex rises',
            country: spec.country,
            currency: spec.currency,
            storageGb: 0,
            target: spec.target,
            condition: spec.condition,
          );
        }
        final reviewed = ReviewedSource(spec, discovered.candidates.single);
        final path =
            '${Directory.systemTemp.path}/fxe2e_${legacy}_${DateTime.now().microsecondsSinceEpoch}.db';
        final writer = await SqfliteAgentRepository.open(path: path);
        final id = await writer.insertAgent(Agent(
          title: 'Gold watch',
          originalPrompt: 'Tell me when Gold Price In Forex rises above ₹4030',
          type: AgentType.valueWatch,
          status: AgentStatus.active,
          createdAt: DateTime(2026, 10, 29),
          nextCheckAt: DateTime(2026, 10, 29),
          checkInterval: const Duration(minutes: 30),
          condition: spec.condition,
          target: spec.target,
          sourceUrl: reviewed.candidate.url.toString(),
          sourceIdentity: reviewed.identity,
        ));
        await writer.close();
        final repo = await SqfliteAgentRepository.open(path: path);
        final checker = AgentChecker(
          repo: repo,
          notifier: RecordingNotifier(),
          strictFetcher: (a) => DiscoveredSourceReader.fetch(
            a,
            reader: h.FakeReader(page),
          ),
        );
        final cycle = await checker.checkDueAgents();
        expect(cycle.checked, 1);
        final after = await repo.agentById(id);
        expect(after!.currentValue, 4022.28);
        expect(after.status, AgentStatus.active,
            reason: '4022.28 < 4030: monitoring continues, no false alert');
        await repo.close();
      },
    );
  }
}
