import 'dart:convert';
import 'dart:io';

import 'page_fetch.dart';

class GoldQuote {
  static const url =
      'https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD';
  static bool isGold(String prompt) =>
      RegExp(
        r'\b(?:gold\s+price|price\s+of\s+gold|xau\s*/?\s*usd)\b',
        caseSensitive: false,
      ).hasMatch(prompt) &&
      !prompt.contains('₹') &&
      !RegExp(
        r'\b(?:jewel|jewellery|jewelry|ring|iphone|phone|gram|karat|carat|inr|₹)\b',
        caseSensitive: false,
      ).hasMatch(prompt);
  static FetchOutcome parse(String raw, {DateTime? now}) {
    try {
      final rows = jsonDecode(raw) as List;
      Map? best;
      for (final row in rows) {
        if (row is Map &&
            (row['ts'] as num?) != null &&
            (best == null || (row['ts'] as num) > (best['ts'] as num)))
          best = row;
      }
      if (best == null) throw const FormatException();
      final ts = (best['ts'] as num).toInt();
      final age = (now ?? DateTime.now()).millisecondsSinceEpoch - ts;
      if (age < -60000 || age > 300000)
        return FetchOutcome.failed(
          'Swissquote gold quote is stale or has an invalid timestamp',
        );
      final p = (best['spreadProfilePrices'] as List).first as Map;
      final bid = (p['bid'] as num).toDouble(),
          ask = (p['ask'] as num).toDouble();
      if (!bid.isFinite || !ask.isFinite || bid <= 0 || ask < bid)
        throw const FormatException();
      final mid = (bid + ask) / 2;
      return FetchOutcome.found(
        mid,
        'Swissquote XAU/USD mid ${mid.toStringAsFixed(2)} USD/oz (bid ${bid.toStringAsFixed(2)}, ask ${ask.toStringAsFixed(2)}), quote age ${age < 0 ? 0 : age ~/ 1000}s',
      );
    } catch (_) {
      return FetchOutcome.failed(
        'Could not read valid Swissquote XAU/USD bid/ask',
      );
    }
  }

  static Future<FetchOutcome> fetch() async {
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200)
        return FetchOutcome.failed(
          'Swissquote gold fetch failed (HTTP ${res.statusCode})',
        );
      final raw = await utf8.decoder
          .bind(res)
          .join()
          .timeout(const Duration(seconds: 10));
      return parse(raw);
    } catch (_) {
      return FetchOutcome.failed(
        'Could not reach Swissquote gold quote source',
      );
    } finally {
      client.close(force: true);
    }
  }
}
