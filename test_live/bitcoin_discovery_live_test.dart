import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/source_discovery.dart';

void main() {
  test('LIVE: natural bitcoin prompts end-to-end after fix', () async {
    final cases = [
      ('watch bitcoin under \$90000', 'US', 'USD'),
      ('tell me when bitcoin drops below 9000000', 'IN', 'INR'),
    ];
    for (final c in cases) {
      final clar = DiscoveryTaskParser.parse(c.$1, country: c.$2, currency: c.$3);
      print('PARSE "${c.$1}" [${c.$2}/${c.$3}]: questions=${clar.questions}');
      expect(clar.spec, isNotNull, reason: 'parser must accept natural prompt');
      final spec = clar.spec!;
      print('  spec query="${spec.query}"');
      final svc = SourceDiscoveryService(
        searchProvider: const TavilyKeylessSearch(),
        pageReader: HttpDiscoveryPageReader(),
      );
      final res = await svc.discover(spec);
      print('  DISCOVER: candidates=${res.candidates.length} reviewOnly=${res.reviewOnly.length} issue=${res.issue}');
      for (final h in res.candidates) {
        print('    HIT: ${h.url} product=${h.product} price=${h.price} ${h.currency} marketQuote=${h.marketQuote}');
      }
      expect(res.candidates, isNotEmpty, reason: 'discovery must find a real source');
      final cand = res.candidates.first;
      // revalidate tolerates live price drift for quotes
      final fresh = await svc.revalidate(spec, cand);
      print('  REVALIDATE: ${fresh == null ? "NULL (review would fail)" : "ok price ${fresh.price}"}');
      expect(fresh, isNotNull, reason: 'review-step revalidation must survive price drift');
      // real reader path used by the checker for discovered agents
      // Mirror SourceReviewScreen: the persisted spec carries the reviewed
      // candidate's marketQuote flag.
      final reviewedSpec = DiscoverySpec(
        model: spec.model, kind: spec.kind, phrase: spec.phrase,
        storageGb: spec.storageGb, target: spec.target,
        condition: spec.condition, country: spec.country,
        currency: spec.currency, colour: spec.colour,
        marketQuote: cand.marketQuote,
      );
      final agent = Agent(
        title: 't', originalPrompt: c.$1, type: AgentType.valueWatch,
        status: AgentStatus.active, createdAt: DateTime.now(),
        target: spec.target, condition: spec.condition,
        sourceUrl: cand.url.toString(), sourceIdentity: reviewedSpec.encode(),
        checkInterval: const Duration(minutes: 60),
      );
      final outcome = await DiscoveredSourceReader.fetch(agent);
      print('  READER: ok=${outcome.ok} value=${outcome.value} detail=${outcome.detail}');
      expect(outcome.value, isNotNull, reason: 'checker must read a real value');
    }
  }, timeout: const Timeout(Duration(seconds: 150)));
}
