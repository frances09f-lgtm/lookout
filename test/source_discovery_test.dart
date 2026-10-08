import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:lookout/services/source_discovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exact sources reject listings, lookalikes and unrelated hosts', () {
    expect(
      SourceDiscovery.exact('https://www.flipkart.com/search?q=iphone'),
      false,
    );
    expect(
      SourceDiscovery.exact(
        'https://www.flipkart.com/apple-iphone/p/itm123abc',
      ),
      true,
    );
    expect(
      SourceDiscovery.exact('https://www.amazon.in/a/dp/B0DGHZWBYB'),
      true,
    );
    expect(SourceDiscovery.exact('https://www.amazon.in/s?k=iphone'), false);
    expect(
      SourceDiscovery.exact('https://www.amazon.in.evil.test/a/dp/B0DGHZWBYB'),
      false,
    );
    expect(
      SourceDiscovery.exact('http://www.amazon.in/a/dp/B0DGHZWBYB'),
      false,
    );
    expect(
      SourceDiscovery.exact('https://in.bookmyshow.com/movies/ichalkaranji'),
      false,
    );
    expect(
      SourceDiscovery.exact(
        'https://in.bookmyshow.com/movies/movie/seat-layout/ET00123456/RKIC/12345/20261010',
      ),
      true,
    );
  });
  test('browser result must still be an exact source', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SourceDiscovery.channel,
          (call) async => 'https://www.flipkart.com/search?q=iphone',
        );
    expect(
      () => SourceDiscovery.pick('iPhone price below 60000'),
      throwsStateError,
    );
  });
  test('phone and movie routing', () {
    expect(SourceDiscovery.movie('Drishyam ticket below 180'), true);
    expect(SourceDiscovery.phone('iPhone below 60000'), true);
    expect(SourceDiscovery.movie('iPhone below 60000'), false);
  });
}
