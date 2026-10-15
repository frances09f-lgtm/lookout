// Direct public-page evidence only. Does not establish search discovery.
import 'dart:io';

import 'package:lookout/services/source_discovery.dart';
import 'package:lookout/domain/agent.dart';

Future<void> main() async {
  final spec = DiscoverySpec(
    model: 'Python',
    kind: 'textPresence',
    phrase: 'Python',
    storageGb: 0,
    target: .5,
    condition: WatchCondition.greaterThan,
    country: '',
    currency: '',
  );
  final url = Uri.parse('https://www.python.org/downloads/');
  try {
    final page = await const HttpDiscoveryPageReader()
        .read(url)
        .timeout(const Duration(seconds: 15));
    final result = SourceCandidateValidator.validate(spec, page);
    stdout.writeln(
      'Direct read (NOT search): ${page.finalUrl}; HTTP ${page.status}; HTML chars ${page.body.length}; title ${result?.product}; accepted=${result != null}; reading=${result?.readingLabel}',
    );
  } catch (e) {
    stdout.writeln('Direct read unresolved: $e');
  }
}
