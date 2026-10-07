import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/browser_price_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lookout/browser');
  const url =
      'https://in.bookmyshow.com/movies/ichalkaranji/seat-layout/ET00507738/frts/33328/20261007';
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('foreground response uses exact watched session', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'readBookMyShow');
          expect(call.arguments['url'], url);
          return jsonEncode({
            'status': 200,
            'body': jsonEncode({
              'data': {
                'showTimes': [
                  {
                    'sessionId': '33328',
                    'categories': [
                      {'priceDesc': 'CLUB', 'curPrice': '100.00'},
                    ],
                  },
                ],
              },
            }),
          });
        });
    final result = await BrowserPriceCheck.read(url);
    expect(result.ok, true);
    expect(result.value, 100);
  });
  test('403 and cancel never become a price', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => jsonEncode({'status': 403, 'body': 'challenge'}),
        );
    expect((await BrowserPriceCheck.read(url)).ok, false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async =>
              throw PlatformException(code: 'cancelled', message: 'Cancelled'),
        );
    expect((await BrowserPriceCheck.read(url)).value, isNull);
  });
  test('expired session and spoofed host fail', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => jsonEncode({
            'status': 200,
            'body': jsonEncode({
              'data': {
                'showTimes': [
                  {
                    'sessionId': 'another',
                    'categories': [
                      {'curPrice': '100'},
                    ],
                  },
                ],
              },
            }),
          }),
        );
    expect((await BrowserPriceCheck.read(url)).value, isNull);
    expect(
      (await BrowserPriceCheck.read(
        'https://evilbookmyshow.com/movies/c/seat-layout/ET1/V/1/20261007',
      )).ok,
      false,
    );
  });
}
