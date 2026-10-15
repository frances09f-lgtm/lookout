import 'dart:convert';
import 'dart:io';

import 'package:lookout/services/source_discovery.dart';
import 'package:lookout/domain/agent.dart';

Future<void> main() async {
  const spec = DiscoverySpec(
    model: 'iphone 15',
    storageGb: 128,
    target: 58000,
    condition: WatchCondition.lessThan,
    country: 'IN',
    currency: 'INR',
  );
  final links = await const TavilyKeylessSearch().search(spec);
  final rows = <Map>[];
  for (final link in links) {
    try {
      final page = await const HttpDiscoveryPageReader()
          .read(link.url)
          .timeout(const Duration(seconds: 10));
      final candidate = SourceCandidateValidator.validate(spec, page);
      rows.add({
        'url': link.url.toString(),
        'status': page.status,
        'bytes': page.body.length,
        'accepted': candidate != null,
      });
    } catch (e) {
      rows.add({'url': link.url.toString(), 'error': e.toString()});
    }
  }
  final data = {
    'searchedAt': DateTime.now().toUtc().toIso8601String(),
    'provider': 'Tavily free keyless',
    'query': spec.query,
    'results': rows,
    'note': 'No search snippet was used as a verified current price.',
  };
  await File('/home/user/workspace/lookout-next-evidence/dart-live-probe.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  print(jsonEncode(data));
}
