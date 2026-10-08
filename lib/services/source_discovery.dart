import 'package:flutter/services.dart';

import 'page_fetch.dart';

/// Opens known sources for exact-item selection. Never treats search-list
/// prices as a watched value. No copied page link is required.
class SourceDiscovery {
  static const channel = MethodChannel('lookout/browser');
  static bool movie(String prompt) => RegExp(
    r'\b(movie|cinema|show|ticket|drishyam|cineplex)\b',
    caseSensitive: false,
  ).hasMatch(prompt);
  static bool phone(String prompt) => RegExp(
    r'\b(iphone|phone|mobile|samsung|pixel|oneplus)\b',
    caseSensitive: false,
  ).hasMatch(prompt);
  static bool exact(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https') return false;
    if (u.host == 'in.bookmyshow.com')
      return PageValueFetcher.bookMyShowApiUrl(url) != null;
    if (['www.flipkart.com', 'flipkart.com'].contains(u.host))
      return RegExp(r'/p/itm[a-zA-Z0-9]+(?:/|$)').hasMatch(u.path);
    if (['www.amazon.in', 'amazon.in'].contains(u.host))
      return RegExp(r'/(?:dp|gp/product)/[A-Z0-9]{10}(?:/|$)').hasMatch(u.path);
    return false;
  }

  static Future<String?> pick(String prompt, {String? retailer}) async {
    final start = movie(prompt)
        ? 'https://in.bookmyshow.com/'
        : retailer == 'Amazon'
        ? 'https://www.amazon.in/'
        : Uri.https('www.flipkart.com', '/search', {
            'q': prompt
                .replaceFirst(
                  RegExp(
                    r'\b(?:cheaper than|below|under|less than).*',
                    caseSensitive: false,
                  ),
                  '',
                )
                .replaceFirst(
                  RegExp(
                    r'^(?:tell me when|watch|notify me when)\s*',
                    caseSensitive: false,
                  ),
                  '',
                )
                .trim(),
          }).toString();
    final url = await channel.invokeMethod<String>('findSource', {
      'url': start,
      'prompt': prompt,
      'movie': movie(prompt),
    });
    if (url == null) return null;
    if (!exact(url))
      throw StateError(
        'Choose an exact product or dated show page, not a search listing.',
      );
    final issue = PageValueFetcher.sourceIssue(url);
    if (issue != null) throw StateError(issue);
    return url;
  }
}
