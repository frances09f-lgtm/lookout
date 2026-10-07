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
  /// honest FetchOutcome.failed descriptions.
  static Future<FetchOutcome> fetchValue(String url) async {
    String host = url;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return FetchOutcome.failed('The page link "$url" is not a valid URL');
    }
    host = uri.host;
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android) Lookout/1.0');
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return FetchOutcome.failed(
            'Could not fetch page (HTTP ${response.statusCode}) from $host');
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      if (body.length > 2000000) {
        return FetchOutcome.failed('Page from $host was too large to read');
      }
      final text = htmlToText(body);
      final value = extractValue(text);
      if (value == null) {
        return FetchOutcome.failed('No price or value found on $host');
      }
      return FetchOutcome.found(value, 'Found $value on $host');
    } on TimeoutException {
      return FetchOutcome.failed('Fetching $host timed out');
    } on SocketException catch (e) {
      return FetchOutcome.failed('Could not reach $host (${e.message})');
    } on HandshakeException {
      return FetchOutcome.failed('Secure connection to $host failed');
    } catch (e) {
      return FetchOutcome.failed('Fetching $host failed ($e)');
    } finally {
      client.close(force: true);
    }
  }
}
