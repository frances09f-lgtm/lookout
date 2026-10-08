import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;

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
      caseSensitive: false,
    );
    final m = currency.firstMatch(pageText);
    if (m != null) return _toNumber(m.group(1)!);
    final keyword = RegExp(
      '(?:price|ticket|fare|cost|rate|amount)[^0-9]{0,40}([0-9][0-9,]*(?:\\.[0-9]+)?)'
      '|([0-9][0-9,]*(?:\\.[0-9]+)?)[^0-9]{0,40}(?:price|ticket|fare|cost|rate|amount)',
      caseSensitive: false,
    );
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
  /// page loads a JSON endpoint. Its response/parser shape was verified in a
  /// browser, but plain Dart HTTP returned 403 on 2026-10-07. This adapter
  /// remains experimental until device transport/session handling is tested.
  /// Shape: data.showTimes[].sessionId + .showTime + .categories[].curPrice/.priceDesc
  static final _bmsSeatLayout = RegExp(
    r'bookmyshow\.com/movies/[^/]+/seat-layout/'
    r'([A-Za-z0-9]+)/([A-Za-z0-9]+)/(\d+)/(\d{8})',
    caseSensitive: false,
  );

  /// Guard exact show identity before any network read. Dates are compared
  /// in India, where BookMyShow's dateCode is a calendar day.
  static String? sourceIssue(String url, {DateTime? now}) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return 'Enter a valid page link.';
    }
    if (uri.host.toLowerCase() != 'in.bookmyshow.com') return null;
    final m = _bmsSeatLayout.firstMatch(url);
    if (m == null || bookMyShowApiUrl(url) == null) {
      return 'This is not an exact BookMyShow show link. Open your cinema, date and showtime, then copy the seat-layout link and use Set source page. A movies listing cannot give this watch a ticket price.';
    }
    final code = m.group(4)!;
    final year = int.parse(code.substring(0, 4)),
        month = int.parse(code.substring(4, 6)),
        day = int.parse(code.substring(6, 8));
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day)
      return 'The show link contains an invalid date. Set the exact show link again.';
    final india = (now ?? DateTime.now()).toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final today = DateTime.utc(india.year, india.month, india.day);
    if (date.isBefore(today))
      return 'This show link is for $day/$month/$year, a past date. Open the date and showtime you want and set its exact seat-layout link. Lookout will not switch shows automatically.';
    return null;
  }

  /// Maps a BookMyShow seat-layout page URL to the JSON endpoint the page
  /// itself calls. Null for any other URL.
  static String? bookMyShowApiUrl(String pageUrl) {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'in.bookmyshow.com') {
      return null;
    }
    final m = _bmsSeatLayout.firstMatch(pageUrl);
    if (m == null) return null;
    return 'https://in.bookmyshow.com/api/movies-data/seatlayout/v1/primary'
        '?eventCode=${m.group(1)}&dateCode=${m.group(4)}&venueCode=${m.group(2)}';
  }

  /// Session id embedded in a seat-layout page URL.
  static String? bookMyShowSessionId(String pageUrl) =>
      _bmsSeatLayout.firstMatch(pageUrl)?.group(3);

  /// Reads the lowest current ticket price from seat-layout JSON.
  /// Requires the exact sessionId from the watched URL. Missing or expired
  /// sessions fail rather than substitute a different show.
  /// Returns (price, category detail) or null when there is no price.
  static (double, String)? extractBookMyShowPrice(
    String jsonBody, {
    String? sessionId,
  }) {
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
    for (final s in shows) {
      if (s is Map && s['sessionId']?.toString() == sessionId) {
        show = s;
        break;
      }
    }
    if (show == null) return null;
    final cats = show['categories'];
    if (cats is! List || cats.isEmpty) return null;
    final prices = <String, double>{};
    for (final c in cats) {
      if (c is! Map) continue;
      final v = double.tryParse(c['curPrice']?.toString() ?? '');
      if (v == null || !v.isFinite || v <= 0) continue;
      prices[c['priceDesc']?.toString() ?? 'Category'] = v;
    }
    if (prices.isEmpty) return null;
    final lowest = prices.values.reduce((a, b) => a < b ? a : b);
    final parts = prices.entries
        .map((e) => '${e.key} ₹${e.value.toStringAsFixed(0)}')
        .join(', ');
    return (lowest, parts);
  }

  /// Converts raw HTML into readable text: drops scripts/styles/tags,
  /// decodes the most common entities, collapses whitespace.
  static String htmlToText(String html) {
    var t = html.replaceAll(
      RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
      ' ',
    );
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

  /// Reliance's current product-header price overrides stale SEO offers.
  /// Marketing, EMI, description and MRP amounts are never header prices.
  static ({double? price, bool unavailable, bool mrpOnly}) retailerHeader(
    String body,
    String url,
  ) {
    if (Uri.parse(url).host != 'www.reliancedigital.in')
      return (price: null, unavailable: false, mrpOnly: false);
    final doc = html_parser.parse(body);
    final visible = htmlToText(body).toLowerCase();
    final unavailable = visible.contains('currently unavailable online');
    final nodes = doc.querySelectorAll('.product-price');
    final prices = <double>{};
    var mrp = false;
    for (final n in nodes) {
      if (n.text.toLowerCase().contains('mrp') ||
          n.querySelector('.mrp-text') != null) {
        mrp = true;
        continue;
      }
      final price = extractValue(n.text);
      if (price != null) prices.add(price);
    }
    return (
      price: prices.length == 1 ? prices.single : null,
      unavailable: unavailable,
      mrpOnly: mrp && prices.isEmpty,
    );
  }

  /// Prefer product-bound JSON-LD offers; never use MRP or related-card text.
  static ({bool productPage, double? price}) productOffer(
    String html,
    String url,
  ) {
    final products = <Map>[];
    void collect(dynamic n) {
      if (n is List) {
        for (final x in n) {
          collect(x);
        }
      }
      if (n is Map) {
        final type = n['@type'];
        if (type == 'Product' || (type is List && type.contains('Product')))
          products.add(n);
        if (n['@graph'] != null) collect(n['@graph']);
      }
    }

    for (final m in RegExp(
      r'''<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>''',
      caseSensitive: false,
    ).allMatches(html)) {
      try {
        collect(jsonDecode(m.group(1)!));
      } catch (_) {}
    }
    if (products.isEmpty) return (productPage: false, price: null);
    final names = products
        .map((p) => p['name']?.toString().toLowerCase().trim())
        .toSet();
    final prices = <double>{};
    final uri = Uri.parse(url);
    for (final p in products) {
      final productUrl = p['url']?.toString();
      if (productUrl != null) {
        final u = Uri.tryParse(productUrl);
        if (u == null || u.host != uri.host || u.path != uri.path) continue;
      } else if (names.length != 1 || names.contains(null))
        continue;
      final offers = p['offers'];
      final items = offers is List ? offers : [offers];
      for (final o in items) {
        if (o is! Map) continue;
        if (o['@type'] != 'Offer' ||
            o['availability']?.toString().contains('OutOfStock') == true)
          continue;
        final c = o['priceCurrency']?.toString();
        if (c == null || c.isEmpty) continue;
        final v = double.tryParse(o['price']?.toString() ?? '');
        if (v != null && v.isFinite && v > 0) prices.add(v);
      }
    }
    return (
      productPage: true,
      price: prices.length == 1 ? prices.single : null,
    );
  }

  /// Fetches [url] and extracts a value. Never throws: failures come back as
  /// honest FetchOutcome.failed descriptions. Transient network failures
  /// (the phone's radio or DNS still waking up when a background check
  /// fires) get short retries before we give up honestly.
  static Future<FetchOutcome> fetchValue(String url) async {
    final issue = sourceIssue(url);
    if (issue != null) return FetchOutcome.failed(issue);
    FetchOutcome outcome = FetchOutcome.failed('not attempted');
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt == 1 ? 2 : 6));
      }
      outcome = await _fetchValueOnce(url);
      if (outcome.value != null) return outcome;
      final transient =
          outcome.detail.contains('Could not reach') ||
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
      final hit = extractBookMyShowPrice(
        raw.body!,
        sessionId: bookMyShowSessionId(url),
      );
      if (hit != null) {
        return FetchOutcome.found(
          hit.$1,
          'Found ₹${hit.$1.toStringAsFixed(0)} (${hit.$2}) on bookmyshow.com',
        );
      }
      return FetchOutcome.failed(
        'BookMyShow returned no ticket prices for this show on $host',
      );
    }

    final raw = await _fetchBody(url);
    if (raw.error != null) return FetchOutcome.failed(raw.error!);
    final body = raw.body!;
    final offer = productOffer(body, url);
    final header = retailerHeader(body, url);
    if (header.unavailable || header.mrpOnly)
      return FetchOutcome.failed(
        'Product page from $host is unavailable or shows MRP only; no current offer price confirmed',
      );
    if (header.price != null) {
      final conflict = offer.price != null && offer.price != header.price;
      return FetchOutcome.found(
        header.price!,
        'Product header price ${header.price} on $host${conflict ? ' (structured offer ${offer.price} differs; current header used)' : ''}',
      );
    }
    if (offer.productPage) {
      if (offer.price != null)
        return FetchOutcome.found(
          offer.price!,
          'Product offer ${offer.price} on $host',
        );
      return FetchOutcome.failed(
        'Product page from $host has no unambiguous current offer price. MRP and related product prices were not used',
      );
    }
    if ([
      'www.amazon.in',
      'amazon.in',
      'www.flipkart.com',
      'flipkart.com',
    ].contains(uri.host))
      return FetchOutcome.failed(
        'Retailer has no product-bound offer price. Search cards, MRP, EMI and related products were not used',
      );
    if (body.length > 2000000)
      return FetchOutcome.failed(
        'Large page from $host has no product offer data. No price was guessed',
      );
    final text = htmlToText(body);
    final value = extractValue(text);
    if (value == null) {
      return FetchOutcome.failed(
        'No readable price found on $host. Set a page showing the exact item/show price, or update the value manually; no price was guessed.',
      );
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
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android) Lookout/1.0',
      );
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return (
          body: null,
          error:
              'Could not fetch page (HTTP ${response.statusCode}) from $host',
        );
      }
      final buffer = StringBuffer();
      var size = 0;
      await for (final chunk
          in response
              .transform(utf8.decoder)
              .timeout(const Duration(seconds: 20))) {
        size += chunk.length;
        if (size > 12000000)
          return (
            body: null,
            error:
                'Page from $host exceeds the safe read limit; no price guessed',
          );
        buffer.write(chunk);
      }
      final body = buffer.toString();
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
