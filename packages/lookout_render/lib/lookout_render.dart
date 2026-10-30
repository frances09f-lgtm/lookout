import 'dart:convert';

import 'package:flutter/services.dart';

/// One headless on-device rendered read of a public https page. The page is
/// loaded by a real browser engine on the user's own device, exactly once;
/// what the site serves (including a verification wall) is what comes back.
class RenderedPage {
  final Uri finalUrl;
  final String body;
  const RenderedPage(this.finalUrl, this.body);
}

class LookoutRender {
  static const _channel = MethodChannel('lookout/render');

  /// True when the native reader exists (Android). Missing plugin = false.
  static Future<RenderedPage?> read(Uri url) async {
    if (url.scheme != 'https' || url.host.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod<String>('readRendered', {
        'url': url.toString(),
      });
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map;
      if (data['status'] != 200) return null;
      final body = data['body']?.toString() ?? '';
      if (body.isEmpty) return null;
      return RenderedPage(Uri.parse(data['url']?.toString() ?? url.toString()), body);
    } catch (_) {
      // Any platform failure (no plugin, busy, wall, timeout) = no read.
      return null;
    }
  }
}
