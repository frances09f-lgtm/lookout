// Exact on-device failure reported 2026-10-29 18:01 on 1.1.19:
// task "Tell me when Gold Price In Forex rises above ₹4030",
// shopping country India, price currency USD -> "no exact page verified".
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/parser.dart';
import 'package:lookout/services/source_discovery.dart';

import 'next_update_test.dart' as h;

class EmptySearch implements SourceSearchProvider {
  String? query;
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async {
    query = spec.query;
    return const [];
  }
}

void main() {
  test('exact device task: parse and discovery against the goldpricez page', () async {
    final parsed = DiscoveryTaskParser.parse(
      'Tell me when Gold Price In Forex rises above ₹4030',
      country: 'India',
      currency: 'USD',
    );
    final spec = parsed.spec!;
    print('  MODEL="${spec.model}" currency=${spec.currency} country=${spec.country} target=${spec.target} condition=${spec.condition}');
    final search = EmptySearch();
    final goldPage = ProductPage(
      Uri.parse('https://goldpricez.com/us/ounce'),
      200,
      File('test/fixtures/goldpricez_us_ounce.html').readAsStringSync(),
    );
    final result = await SourceDiscoveryService(
      searchProvider: search,
      pageReader: h.FakeReader(goldPage),
    ).discover(spec);
    print('  QUERY="$search.query"'.replaceFirst('\$search.query', '${search.query}'));
    print('  CANDIDATES=${result.candidates.length} issue=${result.issue}');
    for (final c in result.candidates) {
      print('  OFFER ${c.url} ${c.currency} ${c.price}');
    }
    final direct = SourceCandidateValidator.validateReadableQuote(
      spec,
      goldPage,
      now: DateTime(2026, 10, 29, 18),
    );
    print('  DIRECT-VALIDATE=${direct?.price}');
    expect(result.candidates, isNotEmpty,
        reason: 'the gold lead must be offered for this exact task');
    expect(result.candidates.first.price, 4022.28);
    expect(result.candidates.first.currency, 'USD');
    expect(spec.target, 4030);
  });
}
