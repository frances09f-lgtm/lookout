import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One webpage fetch + value extraction attempt.
class FetchOutcome {
  final bool ok;

  /// The extracted value, when one was found.
  final double? value;

  /// Human-readable explanation, e.g. 'Found 180.0 on bookmyshow.com' or
  /// 'Could not fetch page (HTTP 403)' or 'No price found on the page'.
  final String detail;
  const FetchOutcome._(this.ok, this.value, this.detail);
  factory FetchOutcome.found(double value, String detail) =>
      FetchOutcome._(true, value, detail);
  factory FetchOutcome.failed(String detail) =>
      FetchOutcome._(false, null, detail);
}

/// Fetches a web page and extracts the most plausible numeric value from it.
/// Uses only dart:io (no new dependencies).
class PageValueFetcher {
  /// Extracts a value from raw page text. Exposed for testing.
  /// Preference: numbers tagged with a currency symbol, then numbers sitting
  /// next to price words, then nothing (we never invent a value).
  static double? extractValue(String pageText) {
    final currency = RegExp(
        '(?:\u20B9|Rs\\.?|INR|\\\$|USD)\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)',
        caseSensitive: false);
    final m = currency.firstMatch(pageText);
    if (m != null) return _toNumber(m.group(1)!);
    final keyword = RegExp(
        '(?:price|ticket|fare|cost|rate|amount)[^0-9]{0,40}([0-9][0-9,]*(?:\\.[0-9]+)?)'
        '|([0-9][0-9,]*(?:\\.[0-9]+)?)[^0-9]{0,40}(?:price|ticket|fare|cost|rate|amount)',
        caseSensitive: false);
    final k = keyword.firstMatch(pageText);
    if (k != null) return _toNumber(k.group(1) ?? k.group(2)!);
    return null;
  }

  static double? _toNumber(String raw) {
    final cleaned = raw.replaceAll(',', '');
    final v = double.tryParse(cleaned);
    if (v == null || v <= 0 || v > 1000000000) return null;
    return v;
  }


  /// BookMyShow seat-layout pages draw seats and prices with JavaScript
  /// (canvas), so a plain HTML fetch never contains the ticket price. The
  /// page itself loads prices from a JSON endpoint - verified against a live
  /// Ichalkaranji show on 2026-10-07 - so watches on those URLs read that
  /// endpoint instead of scraping HTML.
  /// Shape: data.showTimes[].sessionId + .showTime + .categories[].curPrice/.priceDesc
  static final _bmsSeatLayout = RegExp(
      r'bookmyshow\.com/movies/[^/]+/seat-layout/'
      r'([A-Za-z0-9]+)/([A-Za-z0-9]+)/(\d+)/(\d{8})',
      caseSensitive: false);

  /// Maps a BookMyShow seat-layout page URL to the JSON endpoint the page
  /// itself calls. Null for any other URL.
  static String? bookMyShowApiUrl(String pageUrl) {
    final m = _bmsSeatLayout.firstMatch(pageUrl);
    if (m == null) return null;
    return 'https://in.bookmyshow.com/api/movies-data/seatlayout/v1/primary'
        '?eventCode=${m.group(1)}&dateCode=${m.group(4)}&venueCode=${m.group(2)}';
  }

  /// Session id embedded in a seat-layout page URL.
  static String? bookMyShowSessionId(String pageUrl) =>
      _bmsSeatLayout.firstMatch(pageUrl)?.group(3);

  /// Reads the lowest current ticket price from seat-layout JSON.
  /// Uses the show whose sessionId matches the watched URL; if it is absent,
  /// falls back to the first show and names its time in the detail so the
  /// value is never silently from the wrong show.
  /// Returns (price, category detail) or null when there is no price.
  static (double, String)? extractBookMyShowPrice(String jsonBody,
      {String? sessionId}) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonBody);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final data = decoded['data'];
    if (data is! Map) return null;
    final shows = data['showTimes'];
    if (shows is! List || shows.isEmpty) return null;
    Map? show;
    var fellBack = false;
    for (final s in shows) {
      if (s is Map && s['sessionId']?.toString() == sessionId) {
        show = s;
        break;
      }
    }
    if (show == null) {
      if (shows.first is! Map) return null;
      show = shows.first as Map;
      fellBack = sessionId != null;
    }
    final cats = show['categories'];
    if (cats is! List || cats.isEmpty) return null;
    final prices = <String, double>{};
    for (final c in cats) {
      if (c is! Map) continue;
      final v = double.tryParse(c['curPrice']?.toString() ?? '');
      if (v == null || v <= 0) continue;
      prices[c['priceDesc']?.toString() ?? 'Category'] = v;
    }
    if (prices.isEmpty) return null;
    final lowest = prices.values.reduce((a, b) => a < b ? a : b);
    final parts = prices.entries
        .map((e) => '${e.key} ₹${e.value.toStringAsFixed(0)}')
        .join(', ');
    final time = show['showTime']?.toString();
    final scope = fellBack && time != null ? ' ($time show)' : '';
    return (lowest, '$parts$scope');
  }

  /// Converts raw HTML into readable text: drops scripts/styles/tags,
  /// decodes the most common entities, collapses whitespace.
  static String htmlToText(String html) {
    var t = html.replaceAll(
        RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
        ' ');
    t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');
    t = t
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&#8377;', '\u20B9')
        .replaceAll('&rupee;', '\u20B9')
        .replaceAll('&#x20B9;', '\u20B9')
        .replaceAll('&#36;', '\$')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Fetches [url] and extracts a value. Never throws: failures come back as
  /// honest FetchOutcome.failed descriptions. Transient network failures
  /// (the phone's radio or DNS still waking up when a background check
  /// fires) get short retries before we give up honestly.
  static Future<FetchOutcome> fetchValue(String url) async {
    FetchOutcome outcome = FetchOutcome.failed('not attempted');
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt == 1 ? 2 : 6));
      }
      outcome = await _fetchValueOnce(url);
      if (outcome.value != null) return outcome;
      final transient = outcome.detail.contains('Could not reach') ||
          outcome.detail.contains('timed out');
      if (!transient) return outcome;
    }
    return outcome;
  }

  static Future<FetchOutcome> _fetchValueOnce(String url) async {
    String host = url;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return FetchOutcome.failed('The page link "$url" is not a valid URL');
    }
    host = uri.host;

    // BookMyShow seat-layout pages: prices only exist in their JSON feed.
    final bmsApi = bookMyShowApiUrl(url);
    if (bmsApi != null) {
      final raw = await _fetchBody(bmsApi);
      if (raw.error != null) return FetchOutcome.failed(raw.error!);
      final hit = extractBookMyShowPrice(raw.body!,
          sessionId: bookMyShowSessionId(url));
      if (hit != null) {
        return FetchOutcome.found(hit.$1,
            'Found ₹${hit.$1.toStringAsFixed(0)} (${hit.$2}) on bookmyshow.com');
      }
      return FetchOutcome.failed(
          'BookMyShow returned no ticket prices for this show on $host');
    }

    final raw = await _fetchBody(url);
    if (raw.error != null) return FetchOutcome.failed(raw.error!);
    final body = raw.body!;
    if (body.length > 2000000) {
      return FetchOutcome.failed('Page from $host was too large to read');
    }
    final text = htmlToText(body);
    final value = extractValue(text);
    if (value == null) {
      return FetchOutcome.failed('No price or value found on $host');
    }
    return FetchOutcome.found(value, 'Found $value on $host');
  }

  /// Plain GET of [url]; returns the body or an honest error description.
  static Future<({String? body, String? error})> _fetchBody(String url) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android) Lookout/1.0');
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return (
          body: null,
          error: 'Could not fetch page (HTTP ${response.statusCode}) from $host'
        );
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      return (body: body, error: null);
    } on TimeoutException {
      return (body: null, error: 'Fetching $host timed out');
    } on SocketException catch (e) {
      return (body: null, error: 'Could not reach $host (${e.message})');
    } on HandshakeException {
      return (body: null, error: 'Secure connection to $host failed');
    } catch (e) {
      return (body: null, error: 'Fetching $host failed ($e)');
    } finally {
      client.close(force: true);
    }
  }
}
