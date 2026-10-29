import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lookout/update/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('LIVE: feed-first updater still reaches a real update for 1.1.5 '
      '(feed 404 until CI publishes update.json -> GitHub fallback)', () async {
    final c = UpdateChecker(
      client: http.Client(),
      currentVersion: () async => '1.1.5',
    );
    final r = await c.checkLatest();
    print('LIVE: failed=${r.failed} version=${r.update?.version} url=${r.update?.apkUrl}');
    expect(r.failed, isFalse, reason: 'feed miss must fall back to GitHub');
    expect(r.update, isNotNull);
    expect(compareVersions(r.update!.version, '1.1.5'), greaterThan(0));
  });

  test('FIXED: network failure is reported as failure, never as up-to-date',
      () async {
    final c = UpdateChecker(
      client: _FailClient(),
      currentVersion: () async => '1.1.5',
    );
    final r = await c.checkLatest();
    expect(r.failed, isTrue);
    expect(r.update, isNull);
  });

  test('FIXED: failed autoCheck earns only a short retry, not the 6h cooldown',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime.now();
    final c = UpdateChecker(
      client: _FailClient(),
      currentVersion: () async => '1.1.5',
      clock: () => now,
    );
    await c.autoCheck();
    final stamp = prefs.getInt('app_update_last_check_ms')!;
    final blockedFor = stamp + kAutoCheckInterval.inMilliseconds -
        now.millisecondsSinceEpoch;
    expect(blockedFor, kAutoCheckRetryAfterFailure.inMilliseconds,
        reason: 'failure must not hide updates for the full interval');
    // After the short retry window, autoCheck fetches again (still failing).
    now = now.add(kAutoCheckRetryAfterFailure);
    final again = await c.autoCheck();
    expect(prefs.getInt('app_update_last_check_ms'),
        isNot(stamp)); // it actually re-ran and re-stamped
    expect(again, isNull);
  });

  test('FIXED: feed wins when healthy; malformed feed falls back to GitHub',
      () async {
    final feedJson = jsonEncode({
      'lookout': {
        'version': '9.9.9',
        'notes': 'n',
        'apk': 'https://lookout-apk.pages.dev/Lookout.apk',
      }
    });
    final githubJson = jsonEncode({
      'tag_name': 'v8.8.8',
      'body': 'g',
      'assets': [
        {'name': 'Lookout.apk', 'browser_download_url': 'https://github.com/x/Lookout.apk'}
      ]
    });
    // Healthy feed wins (9.9.9, not GitHub's 8.8.8).
    var c = UpdateChecker(
      client: _RouterClient({
        'lookout-apk.pages.dev': _Resp(200, feedJson),
        'api.github.com': _Resp(200, githubJson),
      }),
      currentVersion: () async => '1.1.5',
    );
    var r = await c.checkLatest();
    expect(r.failed, isFalse);
    expect(r.update!.version, '9.9.9');
    // Malformed feed -> GitHub fallback.
    c = UpdateChecker(
      client: _RouterClient({
        'lookout-apk.pages.dev': _Resp(200, '{"lookout": {"version": ""}}'),
        'api.github.com': _Resp(200, githubJson),
      }),
      currentVersion: () async => '1.1.5',
    );
    r = await c.checkLatest();
    expect(r.failed, isFalse);
    expect(r.update!.version, '8.8.8');
    // Feed OK but not newer -> honest none, no GitHub consult needed.
    c = UpdateChecker(
      client: _RouterClient({'lookout-apk.pages.dev': _Resp(200, feedJson)}),
      currentVersion: () async => '9.9.9',
    );
    r = await c.checkLatest();
    expect(r.failed, isFalse);
    expect(r.update, isNull);
    // Both down -> failure.
    c = UpdateChecker(client: _FailClient(), currentVersion: () async => '1.1.5');
    r = await c.checkLatest();
    expect(r.failed, isTrue);
  });
}

class _FailClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw http.ClientException('simulated network failure');
}

class _Resp {
  final int status;
  final String body;
  const _Resp(this.status, this.body);
}

class _RouterClient extends http.BaseClient {
  final Map<String, _Resp> routes;
  _RouterClient(this.routes);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = routes[request.url.host];
    if (r == null) throw http.ClientException('no route ${request.url.host}');
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.body)),
      r.status,
      request: request,
    );
  }
}
