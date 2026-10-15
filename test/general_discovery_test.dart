// All sources and offer values here are synthetic fixtures, not live evidence.
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/domain/parser.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/source_discovery.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'next_update_test.dart' as h;

DiscoverySpec price(
  String item, {
  String country = 'IN',
  String currency = 'INR',
}) => DiscoveryTaskParser.parse(
  'Check $item price below 25000',
  country: country,
  currency: currency,
).spec!;
DiscoverySpec text(String task) => DiscoveryTaskParser.parse(task).spec!;
const resultTask =
    'Check Example University results page contains "Results published"';
ProductPage page(
  String title,
  String content, {
  int status = 200,
}) => ProductPage(
  Uri.parse('https://public.example.com/results'),
  status,
  '<html><head><title>$title</title></head><body><main>$content</main></body></html>',
);

class Search implements SourceSearchProvider {
  final ProductPage page;
  String? query;
  Search(this.page);
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async {
    query = spec.query;
    return [
      SearchPage(page.finalUrl, 'Fixture snippet with wrong price or phrase'),
    ];
  }
}

Agent agent(ReviewedSource reviewed) => Agent(
  title: 'Fixture watch',
  originalPrompt: reviewed.spec.isText ? resultTask : 'Fixture price',
  type: AgentType.valueWatch,
  status: AgentStatus.active,
  createdAt: DateTime(2026),
  nextCheckAt: DateTime(2026),
  checkInterval: const Duration(minutes: 30),
  condition: reviewed.spec.condition,
  target: reviewed.spec.target,
  sourceUrl: reviewed.candidate.url.toString(),
  sourceIdentity: reviewed.identity,
);
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final item in [
    'Sony WH-1000XM5',
    'Samsung Galaxy S25 256GB',
    'Bosch Series 4 Dishwasher',
    'Acme USB Charger',
  ]) {
    test('exact structured product price: $item', () async {
      final spec = price(item);
      expect(spec.model, item);
      final result = await SourceDiscoveryService(
        searchProvider: h.FakeSearch(),
        pageReader: h.FakeReader(h.fixture(name: item, price: 24000)),
      ).discover(spec);
      expect(result.candidates, hasLength(1));
      final reviewed = ReviewedSource(spec, result.candidates.single);
      final repo = InMemoryAgentRepository();
      final id = await repo.insertAgent(agent(reviewed));
      final notifier = RecordingNotifier();
      final checker = AgentChecker(
        repo: repo,
        notifier: notifier,
        strictFetcher: (a) => DiscoveredSourceReader.fetch(
          a,
          reader: h.FakeReader(h.fixture(name: item, price: 24000)),
        ),
      );
      final check = await checker.checkAgent((await repo.agentById(id))!);
      expect(check.evaluated, true);
      expect(check.conditionMet, true);
      expect((await repo.agentById(id))!.status, AgentStatus.completed);
    });
  }
  test('generic product identity is exact: no Ultra substitution, missing country, out of stock or aggregate range', () {
    final spec = price('Samsung Galaxy S25 256GB');
    expect(
      SourceCandidateValidator.validate(
        spec,
        h.fixture(name: 'Samsung Galaxy S25 Ultra 256GB'),
      ),
      isNull,
    );
    expect(
      SourceCandidateValidator.validate(
        spec,
        h.fixture(name: spec.model, region: ''),
      ),
      isNull,
    );
    expect(
      SourceCandidateValidator.validate(
        spec,
        h.fixture(name: spec.model, stock: 'OutOfStock'),
      ),
      isNull,
    );
    expect(
      SourceCandidateValidator.validate(
        spec,
        h.fixture(name: spec.model, copies: 2),
      ),
      isNull,
    );
  });
  for (final task in [
    resultTask,
    'Check Example Space Agency announcements contains "Launch scheduled"',
  ]) {
    test(
      'non-shopping public text: search -> review -> persistent checker ($task)',
      () async {
        final spec = text(task);
        expect(spec.isText, true);
        final original = page(
          spec.model,
          'This public information page is regularly updated. Please return for the next announcement.',
        );
        final search = Search(original);
        final discovered = await SourceDiscoveryService(
          searchProvider: search,
          pageReader: h.FakeReader(original),
        ).discover(spec);
        expect(discovered.candidates, hasLength(1));
        expect(discovered.candidates.single.price, 0);
        expect(search.query, contains(spec.model));
        expect(search.query, isNot(contains(spec.phrase!)));
        final reviewed = ReviewedSource(spec, discovered.candidates.single);
        final repo = await SqfliteAgentRepository.open(
          path: inMemoryDatabasePath,
        );
        final id = await repo.insertAgent(agent(reviewed));
        final saved = (await repo.agentById(id))!;
        expect(DiscoverySpec.forAgent(saved).phrase, spec.phrase);
        expect(saved.isTextWatch, true);
        var current = original;
        final checker = AgentChecker(
          repo: repo,
          notifier: RecordingNotifier(),
          strictFetcher: (a) =>
              DiscoveredSourceReader.fetch(a, reader: h.FakeReader(current)),
        );
        final no = await checker.checkAgent(saved);
        expect(no.evaluated, true);
        expect(no.conditionMet, false);
        expect((await repo.agentById(id))!.currentValue, 0);
        current = page(
          spec.model,
          'This is a full public notice on the same reviewed source. ${spec.phrase!}. Please read the official details on this page.',
        );
        final yes = await checker.checkAgent((await repo.agentById(id))!);
        expect(yes.evaluated, true);
        expect(yes.conditionMet, true);
        expect((await repo.agentById(id))!.currentValue, 1);
        await repo.close();
      },
    );
  }
  test(
    'text evidence excludes scripts/navigation/hidden text and empty shells',
    () {
      final spec = text(resultTask);
      final valid = page(
        spec.model,
        'This public information page is regularly updated. Please return for the next announcement.',
      );
      final noise = ProductPage(
        valid.finalUrl,
        200,
        valid.body.replaceFirst(
          '</body>',
          '<script>Results published</script><nav>Results published</nav><div hidden>Results published</div></body>',
        ),
      );
      expect(SourceCandidateValidator.validate(spec, noise)!.price, 0);
      expect(
        SourceCandidateValidator.validate(
          spec,
          page(spec.model, 'Enable JavaScript'),
        ),
        isNull,
      );
      expect(
        SourceCandidateValidator.validate(
          spec,
          page(
            'Different University results',
            'Results published. This unrelated announcement is not about the requested institution.',
          ),
        ),
        isNull,
      );
    },
  );
  test('blocked page never becomes condition-not-met; exact source and unsupported kind fail closed', () async {
    final spec = text(resultTask);
    final p = page(
      spec.model,
      'Full public notice for this particular source. The results have not yet been announced.',
    );
    final a = agent(
      ReviewedSource(spec, SourceCandidateValidator.validate(spec, p)!),
    );
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(a);
    final checker = AgentChecker(
      repo: repo,
      notifier: RecordingNotifier(),
      strictFetcher: (a) => DiscoveredSourceReader.fetch(
        a,
        reader: h.FakeReader(page(spec.model, 'Blocked', status: 403)),
      ),
    );
    final r = await checker.checkAgent((await repo.agentById(id))!);
    expect(r.evaluated, false);
    expect(
      (await repo.activityFor(id)).any((e) => e.message == 'Condition not met'),
      false,
    );
    final changed = ProductPage(
      Uri.parse('https://other.example.com/results'),
      200,
      p.body,
    );
    expect(
      (await DiscoveredSourceReader.fetch(a, reader: h.FakeReader(changed))).ok,
      false,
    );
    final unsupported = DiscoverySpec(
      model: 'whatever',
      kind: 'semanticGuess',
      storageGb: 0,
      target: .5,
      condition: WatchCondition.greaterThan,
      country: '',
      currency: '',
    );
    expect(SourceCandidateValidator.validate(unsupported, p), isNull);
  });
  test('unimplemented semantic tasks have no active parser result', () {
    for (final task in [
      'tell me when the results are officially announced',
      'check whether tickets are available',
      'tell me when this webpage changes',
      'monitor my private chats',
    ]) {
      expect(GoalParser.parse(task).outcome, isNot(ParseOutcome.ok));
      expect(DiscoveryTaskParser.parse(task).spec, isNull);
    }
  });
}
