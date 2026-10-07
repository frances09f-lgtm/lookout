import 'dart:convert';

import 'package:flutter/services.dart';

import 'page_fetch.dart';

/// Explicit foreground browser check. Never used by the background worker.
class BrowserPriceCheck {
  static const _channel = MethodChannel('lookout/browser');

  static Future<FetchOutcome> read(String url) async {
    final api = PageValueFetcher.bookMyShowApiUrl(url);
    if (api == null) {
      return FetchOutcome.failed('Not a supported BookMyShow show link');
    }
    try {
      final response = await _channel.invokeMethod<String>('readBookMyShow', {
        'url': url,
        'api': api,
      });
      final envelope = jsonDecode(response ?? '') as Map;
      if (envelope['status'] != 200) {
        return FetchOutcome.failed(
          'Browser price read failed (HTTP ${envelope['status']})',
        );
      }
      final hit = PageValueFetcher.extractBookMyShowPrice(
        envelope['body'] as String,
        sessionId: PageValueFetcher.bookMyShowSessionId(url),
      );
      if (hit == null) {
        return FetchOutcome.failed(
          'No prices for the exact watched show. It may have expired',
        );
      }
      return FetchOutcome.found(hit.$1, 'BookMyShow ticket prices: ${hit.$2}');
    } on PlatformException catch (e) {
      return FetchOutcome.failed(e.message ?? 'Browser check failed');
    } catch (_) {
      return FetchOutcome.failed(
        'Could not read ticket prices from the browser response',
      );
    }
  }
}
