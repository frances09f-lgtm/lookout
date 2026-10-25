import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookout/update/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('compareVersions', () {
    expect(compareVersions('1.0.20', '1.0.19'), greaterThan(0));
    expect(compareVersions('v1.0.20', '1.0.20'), 0);
    expect(compareVersions('22', '1.0.22'), greaterThan(0)); // old tag shape
  });
  test('fetchLatest parses latest release and compares', () async {
    const body = '{"tag_name":"v1.0.20","body":"notes here",'
        '"assets":[{"name":"Lookout.apk","browser_download_url":"https://x/L.apk"}]}';
    final c = UpdateChecker(
      client: MockClient((_) async => http.Response(body, 200)),
      currentVersion: () async => '1.0.19',
    );
    final info = await c.fetchLatest();
    expect(info!.version, '1.0.20');
    expect(info.apkUrl, endsWith('L.apk'));
    final same = UpdateChecker(
      client: MockClient((_) async => http.Response(body, 200)),
      currentVersion: () async => '1.0.20',
    );
    expect(await same.fetchLatest(), isNull);
  });
  test('autoCheck backs off briefly on failure, fully on success', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    var now = DateTime.now();
    final c = UpdateChecker(
      client: MockClient((_) async {
        calls++;
        return http.Response('x', 500);
      }),
      currentVersion: () async => '1.0.19',
      clock: () => now,
    );
    // One failed check = feed request + GitHub fallback request.
    expect(await c.autoCheck(), isNull);
    expect(calls, 2);
    // Within the short failure backoff: no new fetch.
    now = now.add(const Duration(minutes: 5));
    expect(await c.autoCheck(), isNull);
    expect(calls, 2);
    // After the short retry window (not 6h): fetches again.
    now = now.add(kAutoCheckRetryAfterFailure);
    expect(await c.autoCheck(), isNull);
    expect(calls, 4);
  });
}
