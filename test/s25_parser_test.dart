import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/source_discovery.dart';

void main() {
  test('S25 user prompt parses storage out of the model', () {
    final clar = DiscoveryTaskParser.parse(
      'Tell me when Samsung S25 256gb drops below ₹56000',
      country: 'IN',
      currency: 'INR',
    );
    expect(clar.questions, isEmpty);
    final spec = clar.spec!;
    expect(spec.model, 'Samsung S25');
    expect(spec.storageGb, 256);
    expect(spec.target, 56000);
    expect(spec.currency, 'INR');
  });
  test('conflicting storage sizes ask instead of guessing', () {
    final clar = DiscoveryTaskParser.parse(
      'Tell me when Samsung S25 12gb ram 256gb drops below 56000',
      country: 'IN',
      currency: 'INR',
    );
    expect(clar.spec, isNull);
    expect(clar.questions, isNotEmpty);
  });
  test('quote and plain-product prompts keep storage zero', () {
    final q = DiscoveryTaskParser.parse(
      'Tell me when bitcoin drops below 9000000',
      country: 'IN',
      currency: 'INR',
    );
    expect(q.spec!.storageGb, 0);
    final p = DiscoveryTaskParser.parse(
      'Check Sony WH-1000XM5 price below 25000',
      country: 'IN',
      currency: 'INR',
    );
    expect(p.spec!.model, 'Sony WH-1000XM5');
    expect(p.spec!.storageGb, 0);
  });
}
