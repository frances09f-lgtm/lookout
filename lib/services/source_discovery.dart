import 'dart:convert';
import 'dart:io';

import 'page_fetch.dart';

import 'package:html/parser.dart' as html;

import '../domain/agent.dart';
import '../domain/parser.dart';
import '../domain/ticket_task.dart';

/// Foreground discovery only. No automatic subscription, page substitution,
/// broad search scraping, or model/API credentials embedded in the app.
class DiscoverySpec {
  /// Exact subject/product, not a phone-specific model.
  final String model;
  final String kind;
  final String? phrase;
  final int storageGb;
  final double target;
  final WatchCondition condition;
  final String country;
  final String currency;
  final String? reviewedProduct;
  final String? colour;

  /// Persisted only after a reviewed deterministic-provider quote candidate
  /// is activated; routes later reads to quote validation, never to relax
  /// arbitrary pages.
  final bool marketQuote;
  const DiscoverySpec({
    required this.model,
    this.kind = 'productPrice',
    this.phrase,
    required this.storageGb,
    required this.target,
    required this.condition,
    required this.country,
    required this.currency,
    this.reviewedProduct,
    this.colour,
    this.marketQuote = false,
  });
  String encode() => jsonEncode({
    'model': model,
    'kind': kind,
    'phrase': phrase,
    'storageGb': storageGb,
    'country': country,
    'currency': currency,
    'reviewedProduct': reviewedProduct,
    'colour': colour,
    'marketQuote': marketQuote,
  });
  static DiscoverySpec forAgent(Agent agent) {
    final data = jsonDecode(agent.sourceIdentity!) as Map;
    return DiscoverySpec(
      model: data['model'] as String,
      kind: data['kind'] as String? ?? 'productPrice',
      phrase: data['phrase'] as String?,
      storageGb: data['storageGb'] as int,
      target: agent.target,
      condition: agent.condition,
      country: data['country'] as String,
      currency: data['currency'] as String,
      reviewedProduct: data['reviewedProduct'] as String?,
      colour: data['colour'] as String?,
      marketQuote: data['marketQuote'] as bool? ?? false,
    );
  }

  bool get isText => kind == 'textPresence';
  String get query {
    if (isText) return '$model official';
    if (storageGb == 0 && colour == null) {
      // Region-free subjects (market quotes, instruments): a commerce-shaped
      // "buy" query buries live price pages under SEO/news results.
      return '$model price $currency';
    }
    return '$model ${colour ?? ''} ${storageGb > 0 ? '${storageGb}GB' : ''} ${country == 'IN'
          ? 'India'
          : country == 'US'
          ? 'United States'
          : country} buy';
  }
}

class TaskClarification {
  final DiscoverySpec? spec;
  final List<String> questions;
  const TaskClarification(this.spec, this.questions);
}

/// Domain-neutral discovery with explicit evaluators: structured product offers
/// and literal public-page text. Unrestricted semantic judgements fail closed.
class DiscoveryTaskParser {
  static final _model = RegExp(
    r'\biphone\s+(\d{1,2}e?)(?:\s+(pro\s+max|pro|plus|air|mini))?\b',
    caseSensitive: false,
  );
  static final _storage = RegExp(r'\b(\d+)\s*(gb|tb)\b', caseSensitive: false);
  static TaskClarification parse(
    String task, {
    String? country,
    String? currency,
  }) {
    // Quoted text provides an explicit, inspectable condition. No LLM guesses.
    final textTask = RegExp(
      r'^(?:tell me when|notify me when|check|watch)\s+(.+?)\s+(?:page\s+)?(?:contains|shows|mentions)\s+["“]([^"”]+)["”]\s*$',
      caseSensitive: false,
    ).firstMatch(task.trim());
    if (textTask != null) {
      final subject = textTask.group(1)!.trim();
      final phrase = textTask.group(2)!.trim();
      if (subject.length < 3 || phrase.length < 3) {
        return const TaskClarification(null, [
          'Name the public subject and a phrase of at least three characters to check.',
        ]);
      }
      return TaskClarification(
        DiscoverySpec(
          model: subject,
          storageGb: 0,
          target: .5,
          condition: WatchCondition.greaterThan,
          country: '',
          currency: '',
          kind: 'textPresence',
          phrase: phrase,
        ),
        const [],
      );
    }
    if (TicketTaskPolicy.isPriceTask(task)) {
      return const TaskClarification(null, [TicketTaskPolicy.limitation]);
    }
    final q = <String>[];
    final colours = RegExp(
      r'\b(natural titanium|blue titanium|white titanium|black titanium|desert titanium|space black|cosmic orange|deep blue|mist blue|black|blue|green|pink|yellow|white|teal|ultramarine|silver|lavender|sage)\b',
      caseSensitive: false,
    ).allMatches(task).map((m) => m.group(0)!.toLowerCase()).toSet();
    if (colours.length > 1) {
      q.add(
        'Choose one colour, or remove colour to review any matching colour.',
      );
    }
    final goal = GoalParser.parse(task);
    if (goal.outcome != ParseOutcome.ok || goal.type != AgentType.valueWatch) {
      q.add(
        'Supported automatic checks: an exact product price target, or a public-page subject followed by contains “exact phrase”. Other tasks need an evaluator and cannot start yet.',
      );
    }
    if (RegExp(r'\biphone\b', caseSensitive: false).hasMatch(task) &&
        RegExp(
          r'\b(case|cover|charger|cable|screen protector|refurbished|renewed|used)\b',
          caseSensitive: false,
        ).hasMatch(task)) {
      return const TaskClarification(null, [
        'Accessories and used/refurbished devices need a manual source page for now.',
      ]);
    }
    final isIphone = RegExp(r'\biphone\b', caseSensitive: false).hasMatch(task);
    if (!isIphone) {
      var subject = task
          .split(
            RegExp(
              r'\b(?:below|above|under|over|less than|more than|cheaper than|costlier than|drops?\s+(?:to|below)|falls?\s+(?:to|below))\b',
              caseSensitive: false,
            ),
          )
          .first;
      subject = subject.replaceFirst(
        RegExp(
          r'^(?:tell me when|notify me when|check|watch|monitor)\s+',
          caseSensitive: false,
        ),
        '',
      );
      subject = subject
          .replaceAll(
            RegExp(
              r'\b(?:price|becomes?|go(?:es)?|is|to|drop|falls?)\b',
              caseSensitive: false,
            ),
            ' ',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (subject.length < 3 ||
          RegExp(
            r'^(this|it|product|something)$',
            caseSensitive: false,
          ).hasMatch(subject)) {
        q.add('Which exact product and variant should be checked?');
      }
      if (country == null || country.trim().isEmpty) {
        q.add('Which shopping country?');
      }
      if (currency == null || !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
        q.add('Which currency?');
      }
      if (q.isNotEmpty) return TaskClarification(null, q);
      return TaskClarification(
        DiscoverySpec(
          model: subject,
          storageGb: 0,
          target: goal.target!,
          condition: goal.condition!,
          country: country!,
          currency: currency!,
        ),
        const [],
      );
    }
    final models = _model
        .allMatches(task)
        .map((m) => _normal('iPhone ${m.group(1)} ${m.group(2) ?? ''}'))
        .toSet();
    if (models.length != 1) {
      q.add(
        'Which iPhone model and edition (for example iPhone 16, not 16 Pro)?',
      );
    }
    final storages = _storage
        .allMatches(task)
        .map(
          (m) =>
              int.parse(m.group(1)!) *
              (m.group(2)!.toLowerCase() == 'tb' ? 1024 : 1),
        )
        .toSet();
    if (storages.length != 1 || storages.single <= 0) {
      q.add('Which storage size (for example 128 GB)?');
    }
    // Currency cannot be inferred merely from the numeric threshold.
    if (country == null || country.trim().isEmpty) {
      q.add('Which shopping country?');
    }
    if (currency == null || !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      q.add('Which currency?');
    }
    if (goal.target != null && (!goal.target!.isFinite || goal.target! <= 0)) {
      q.add('Enter a positive price target.');
    }
    if (q.isNotEmpty) return TaskClarification(null, q);
    return TaskClarification(
      DiscoverySpec(
        model: models.single,
        storageGb: storages.single,
        target: goal.target!,
        condition: goal.condition!,
        country: country!.trim(),
        currency: currency!,
        colour: colours.isEmpty ? null : colours.single,
      ),
      const [],
    );
  }

  static String _normal(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  static bool identityMatches(String name, DiscoverySpec spec) {
    if (RegExp(r'\biphone\b', caseSensitive: false).hasMatch(spec.model) &&
        RegExp(
          r'\b(case|cover|charger|cable|protector|refurbished|renewed|used)\b',
          caseSensitive: false,
        ).hasMatch(name)) {
      return false;
    }
    if (!RegExp(r'\biphone\b', caseSensitive: false).hasMatch(spec.model)) {
      String canonical(String v) =>
          _normal(v).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      // Exact reviewed item name. Subsets are unsafe (S25 vs S25 Ultra).
      return canonical(name) == canonical(spec.model);
    }
    final models = _model
        .allMatches(name)
        .map((m) => _normal('iPhone ${m.group(1)} ${m.group(2) ?? ''}'))
        .toSet();
    final storage = _storage
        .allMatches(name)
        .map(
          (m) =>
              int.parse(m.group(1)!) *
              (m.group(2)!.toLowerCase() == 'tb' ? 1024 : 1),
        )
        .toSet();
    return models.length == 1 &&
        models.single == spec.model &&
        storage.length == 1 &&
        storage.single == spec.storageGb;
  }
}

class SearchPage {
  final Uri url;
  final String title;
  const SearchPage(this.url, this.title);
}

abstract interface class SourceSearchProvider {
  /// Returns observed links from a provider, never synthesized merchant URLs.
  Future<List<SearchPage>> search(DiscoverySpec spec);
}

class DiscoveryUnavailable implements Exception {
  final String message;
  const DiscoveryUnavailable(this.message);
}

class UnconfiguredSourceSearch implements SourceSearchProvider {
  const UnconfiguredSourceSearch();
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async =>
      throw const DiscoveryUnavailable(
        'Automatic search is not connected in this local proposal. No source was selected. You can still paste an exact product-page link.',
      );
}

class ProductPage {
  final Uri finalUrl;
  final int status;
  final String body;
  const ProductPage(this.finalUrl, this.status, this.body);
}

abstract interface class DiscoveryPageReader {
  Future<ProductPage> read(Uri url);
}

class SourceCandidate {
  final Uri url;
  final String product;
  final double price;
  final String currency;
  final String country;
  final DateTime checkedAt;
  final bool marketQuote;
  String get readingLabel => currency.isEmpty
      ? (price == 1
            ? 'Exact phrase present on this page'
            : 'Exact phrase not present on this page')
      : '$currency ${price.toStringAsFixed(2)} • $country';
  const SourceCandidate({
    required this.url,
    required this.product,
    required this.price,
    required this.currency,
    required this.country,
    required this.checkedAt,
    this.marketQuote = false,
  });
}

/// A page worth inspecting, never a current reading or activation credential.
/// Deliberately not a SourceCandidate: it cannot enter ReviewedSource.
class ReviewOnlySource {
  final Uri url;
  final String product;
  final List<String> blockers;
  final List<String> reportedOffers;
  const ReviewOnlySource({
    required this.url,
    required this.product,
    required this.blockers,
    required this.reportedOffers,
  });
}

/// Discovery requires stronger evidence than the old generic "first currency
/// value" extractor. Search snippets are never a price or matching proof.
class SourceCandidateValidator {
  static bool publicHttps(Uri u) {
    if (u.scheme != 'https' ||
        u.userInfo.isNotEmpty ||
        (u.hasPort && u.port != 443)) {
      return false;
    }
    final h = u.host.toLowerCase();
    if (!h.contains('.') ||
        h.endsWith('.local') ||
        h.endsWith('.localhost') ||
        h.endsWith('.internal') ||
        h.endsWith('.test') ||
        h == 'localhost') {
      return false;
    }
    // Hostnames only, no IP literals; reader must also check DNS/redirects.
    if (h.contains(':') || RegExp(r'^\d+(\.\d+){3}$').hasMatch(h)) return false;
    return true;
  }

  static SourceCandidate? validate(
    DiscoverySpec spec,
    ProductPage page, {
    DateTime? now,
  }) {
    if (!['productPrice', 'textPresence'].contains(spec.kind)) return null;
    if (spec.isText &&
        (spec.condition != WatchCondition.greaterThan || spec.target != .5)) {
      return null;
    }
    if (page.status != 200 ||
        !publicHttps(page.finalUrl) ||
        page.body.length > 2000000) {
      return null;
    }
    final doc = html.parse(page.body);
    if (doc.querySelector('input[type="password"]') != null ||
        doc.querySelector('#challenge-form') != null) {
      return null;
    }
    if (spec.isText) {
      if (spec.phrase == null || spec.phrase!.trim().isEmpty) return null;
      final title = doc.querySelector('title')?.text.trim() ?? '';
      if (title.isEmpty) return null;
      if (spec.reviewedProduct != null && title != spec.reviewedProduct) {
        return null;
      }
      final titleTokens = title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .split(' ')
          .toSet();
      final subjectTokens = spec.model
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .split(' ')
          .where((t) => t.isNotEmpty);
      if (subjectTokens.isEmpty || !subjectTokens.every(titleTokens.contains)) {
        return null;
      }
      for (final el in doc.querySelectorAll(
        'script,style,noscript,template,nav,header,footer,[hidden],[aria-hidden="true"]',
      )) {
        el.remove();
      }
      final body =
          doc.querySelector('main') ?? doc.querySelector('article') ?? doc.body;
      final text = body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      // Empty shells/error pages are not evidence of absence.
      if (text.length < 40 ||
          RegExp(
            r'access denied|verify you are human|enable javascript|too many requests',
            caseSensitive: false,
          ).hasMatch(text)) {
        return null;
      }
      final present = text.toLowerCase().contains(
        spec.phrase!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
      );
      return SourceCandidate(
        url: page.finalUrl,
        product: title,
        price: present ? 1 : 0,
        currency: '',
        country: '',
        checkedAt: now ?? DateTime.now(),
      );
    }
    final products = <Map>[];
    void collect(dynamic node) {
      if (node is List) {
        for (final n in node) {
          collect(n);
        }
      }
      if (node is Map) {
        final t = node['@type'];
        if (t == 'Product' || t is List && t.contains('Product')) {
          products.add(node);
        }
        if (node['@graph'] != null) collect(node['@graph']);
      }
    }

    for (final script in doc.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      try {
        collect(jsonDecode(script.text));
      } catch (_) {
        /* malformed is not evidence */
      }
    }
    // Reject carousels/listings even when one card happens to match.
    if (products.length != 1) return null;
    final p = products.single;
    final name = p['name']?.toString() ?? '';
    if (!DiscoveryTaskParser.identityMatches(name, spec)) return null;
    if (spec.colour != null &&
        !RegExp(
          '\\b${RegExp.escape(spec.colour!)}\\b',
          caseSensitive: false,
        ).hasMatch(name)) {
      return null;
    }
    if (spec.reviewedProduct != null &&
        name.toLowerCase().trim() !=
            spec.reviewedProduct!.toLowerCase().trim()) {
      return null;
    }
    final rawProductUrl = p['url']?.toString() ?? '';
    final productUrl = Uri.tryParse(rawProductUrl);
    if (productUrl == null ||
        !productUrl.hasScheme ||
        productUrl.host != page.finalUrl.host ||
        productUrl.path != page.finalUrl.path) {
      return null;
    }
    final offers = p['offers'] is List ? p['offers'] as List : [p['offers']];
    // Seller/variant offer ranges and aggregate prices require a separate adapter.
    if (offers.length != 1 || offers.single is! Map) return null;
    final o = offers.single as Map;
    if (o['@type'] != 'Offer' || o['priceCurrency'] != spec.currency) {
      return null;
    }
    final availability = o['availability']?.toString() ?? '';
    if (![
      'https://schema.org/InStock',
      'http://schema.org/InStock',
      'InStock',
    ].contains(availability)) {
      return null;
    }
    final condition = o['itemCondition']?.toString();
    if (condition != null &&
        !condition.endsWith('/NewCondition') &&
        condition != 'NewCondition') {
      return null;
    }
    final price = double.tryParse(o['price']?.toString() ?? '');
    if (price == null || !price.isFinite || price <= 0) return null;
    // A region cannot be established by currency alone. The seller's offer
    // must explicitly name the requested country (ISO code supplied by UI).
    final region = o['eligibleRegion'];
    final regionCode = region is Map
        ? region['name']?.toString()
        : region?.toString();
    if (regionCode?.toUpperCase() != spec.country.toUpperCase()) return null;
    return SourceCandidate(
      url: page.finalUrl,
      product: name,
      price: price,
      currency: spec.currency,
      country: spec.country,
      checkedAt: now ?? DateTime.now(),
    );
  }

  /// Region-free live market quotes (crypto/FX/instrument pages). Used only
  /// for deterministic provider leads and persisted quote watches - never to
  /// relax a search hit. Identity, currency and a live structured price are
  /// still proven; seller/region semantics simply do not exist on these
  /// pages, and a moving price between review reads is expected.
  static SourceCandidate? validateQuote(
    DiscoverySpec spec,
    ProductPage page, {
    DateTime? now,
  }) {
    if (spec.kind != 'productPrice' || spec.storageGb != 0 || spec.colour != null) {
      return null;
    }
    if (page.status != 200 ||
        !publicHttps(page.finalUrl) ||
        page.body.length > 2000000) {
      return null;
    }
    final doc = html.parse(page.body);
    final products = <Map>[];
    void collect(dynamic node) {
      if (node is List) {
        for (final n in node) {
          collect(n);
        }
      }
      if (node is Map) {
        final t = node['@type'];
        if (t == 'Product' || t is List && t.contains('Product')) {
          products.add(node);
        }
        if (node['@graph'] != null) collect(node['@graph']);
      }
    }

    for (final script in doc.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      try {
        collect(jsonDecode(script.text));
      } catch (_) {
        /* malformed is not evidence */
      }
    }
    if (products.length != 1) return null;
    final p = products.single;
    final name = p['name']?.toString() ?? '';
    if (!DiscoveryTaskParser.identityMatches(name, spec)) return null;
    final offers = p['offers'] is List ? p['offers'] as List : [p['offers']];
    if (offers.length != 1 || offers.single is! Map) return null;
    final o = offers.single as Map;
    if (o['@type'] != 'Offer' || o['priceCurrency'] != spec.currency) {
      return null;
    }
    final availability = o['availability']?.toString();
    if (availability != null &&
        ![
          'https://schema.org/InStock',
          'http://schema.org/InStock',
          'InStock',
        ].contains(availability)) {
      return null;
    }
    final price = double.tryParse(o['price']?.toString() ?? '');
    if (price == null || !price.isFinite || price <= 0) return null;
    return SourceCandidate(
      url: page.finalUrl,
      product: name,
      price: price,
      currency: spec.currency,
      country: spec.country,
      checkedAt: now ?? DateTime.now(),
      marketQuote: true,
    );
  }

  /// Retain useful structured product pages without granting monitoring status.
  /// Search snippets/currency/domain never prove identity, stock or market.
  static ReviewOnlySource? reviewOnly(DiscoverySpec spec, ProductPage page) {
    if (spec.kind != 'productPrice' ||
        page.status != 200 ||
        !publicHttps(page.finalUrl) ||
        page.body.length > 2000000 ||
        validate(spec, page) != null) {
      return null;
    }
    final doc = html.parse(page.body);
    if (doc.querySelector('input[type="password"],#challenge-form') != null) {
      return null;
    }
    final products = <Map>[];
    void collect(dynamic node) {
      if (node is List) {
        for (final n in node) {
          collect(n);
        }
      }
      if (node is Map) {
        final type = node['@type'];
        if (type == 'Product' || type is List && type.contains('Product')) {
          products.add(node);
        }
        if (node['@graph'] != null) collect(node['@graph']);
      }
    }

    for (final script in doc.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      try {
        collect(jsonDecode(script.text));
      } catch (_) {
        /* not evidence */
      }
    }
    if (products.length != 1) return null;
    final product = products.single;
    final name = product['name']?.toString().trim() ?? '';
    final exact = DiscoveryTaskParser.identityMatches(name, spec);
    // General product titles often append descriptions. These can be leads,
    // but never pass as verified identities. iPhone's variant rules stay strict.
    String words(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final tokens = words(spec.model)
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    final nameTokens = words(name).split(' ').toSet();
    if (!exact &&
        (RegExp(r'\biphone\b', caseSensitive: false).hasMatch(spec.model) ||
            tokens.isEmpty ||
            !tokens.every(nameTokens.contains))) {
      return null;
    }
    if (spec.colour != null &&
        !RegExp(
          '\\b${RegExp.escape(spec.colour!)}\\b',
          caseSensitive: false,
        ).hasMatch(name)) {
      return null;
    }
    if (spec.reviewedProduct != null &&
        words(name) != words(spec.reviewedProduct!)) {
      return null;
    }
    final productUrl = Uri.tryParse(product['url']?.toString() ?? '');
    if (productUrl == null ||
        productUrl.host != page.finalUrl.host ||
        productUrl.path != page.finalUrl.path ||
        !publicHttps(productUrl)) {
      return null;
    }
    final raw = product['offers'];
    final offers = raw is List ? raw : [raw];
    final blockers = <String>[];
    if (!exact) {
      blockers.add('Exact product identity is not verified by this adapter.');
    }
    if (offers.length != 1) {
      blockers.add(
        '${offers.length} offers are listed. A single exact variant and offer must be verified.',
      );
    }
    final reports = <String>[];
    final missingCountry = <String>[];
    for (var i = 0; i < offers.length && i < 12; i++) {
      final offer = offers[i];
      if (offer is! Map || offer['@type'] != 'Offer') {
        blockers.add('Offer ${i + 1}: unsupported offer structure.');
        continue;
      }
      final label = 'Offer ${i + 1}';
      final region = offer['eligibleRegion'];
      final regionCode = region is Map
          ? region['name']?.toString()
          : region?.toString();
      if (regionCode == null || regionCode.trim().isEmpty) {
        missingCountry.add('${i + 1}');
      } else if (regionCode.toUpperCase() != spec.country.toUpperCase()) {
        blockers.add(
          '$label: eligible country does not match ${spec.country}.',
        );
      }
      final price = double.tryParse(offer['price']?.toString() ?? '');
      if (price == null || !price.isFinite || price <= 0) {
        blockers.add('$label: no valid price.');
      }
      if (offer['priceCurrency'] != spec.currency) {
        blockers.add('$label: currency does not match ${spec.currency}.');
      }
      final stock = offer['availability']?.toString() ?? '';
      if (![
        'https://schema.org/InStock',
        'http://schema.org/InStock',
        'InStock',
      ].contains(stock)) {
        blockers.add('$label: in-stock availability is not verified.');
      }
      final condition = offer['itemCondition']?.toString();
      if (condition != null &&
          !condition.endsWith('/NewCondition') &&
          condition != 'NewCondition') {
        blockers.add('$label: not a verified new-condition offer.');
      }
      // Report exactly what is present, not a selected/current price or variant.
      reports.add(
        '$label: ${offer['name'] ?? 'variant not specified'}; '
        '${price != null && price.isFinite && price > 0 ? '${offer['priceCurrency'] ?? 'currency missing'} ${price.toStringAsFixed(2)}' : 'price missing'}',
      );
    }
    if (missingCountry.isNotEmpty) {
      blockers.add(
        '${missingCountry.length == 1 ? 'Offer' : 'Offers'} ${missingCountry.join(', ')}: seller does not specify an eligible country.',
      );
    }
    if (blockers.isEmpty) return null;
    return ReviewOnlySource(
      url: page.finalUrl,
      product: name,
      blockers: List.unmodifiable(blockers),
      reportedOffers: List.unmodifiable(reports),
    );
  }
}

class DiscoveryResult {
  final List<SourceCandidate> candidates;
  final String? issue;
  final List<ReviewOnlySource> reviewOnly;
  const DiscoveryResult(
    this.candidates, [
    this.issue,
    this.reviewOnly = const [],
  ]);
}

class SourceDiscoveryService {
  final SourceSearchProvider searchProvider;
  final DiscoveryPageReader pageReader;
  const SourceDiscoveryService({
    required this.searchProvider,
    required this.pageReader,
  });

  /// Fresh strict read before returning a source to the creation/resolution flow.
  /// A changed price/page requires a new review, not silent substitution.
  Future<SourceCandidate?> revalidate(
    DiscoverySpec spec,
    SourceCandidate selected, {
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final age = time.difference(selected.checkedAt);
    if (age.isNegative || age > const Duration(minutes: 5)) return null;
    try {
      final page = await pageReader
          .read(selected.url)
          .timeout(const Duration(seconds: 8));
      if (page.finalUrl != selected.url) return null;
      final fresh = selected.marketQuote
          ? SourceCandidateValidator.validateQuote(spec, page, now: time)
          : SourceCandidateValidator.validate(spec, page, now: time);
      if (fresh == null ||
          fresh.product != selected.product ||
          (!selected.marketQuote && fresh.price != selected.price) ||
          fresh.country != selected.country ||
          fresh.currency != selected.currency) {
        return null;
      }
      return fresh;
    } catch (_) {
      return null;
    }
  }

  Future<DiscoveryResult> discover(DiscoverySpec spec) async {
    try {
      final links = await searchProvider
          .search(spec)
          .timeout(const Duration(seconds: 12));
      final hits = <SourceCandidate>[];
      final review = <ReviewOnlySource>[];
      final seen = <String>{};
      final candidates = links
          .where(
            (link) =>
                SourceCandidateValidator.publicHttps(link.url) &&
                seen.add(link.url.toString()),
          )
          .take(8);
      final pages = await Future.wait(
        candidates.map((link) async {
          try {
            return await pageReader
                .read(link.url)
                .timeout(const Duration(seconds: 8));
          } catch (_) {
            /* blocked/unreadable page isn't a candidate */
            return null;
          }
        }),
      );
      for (final page in pages.whereType<ProductPage>()) {
        final match = SourceCandidateValidator.validate(spec, page);
        if (match != null && !hits.any((h) => h.url == match.url)) {
          hits.add(match);
        } else if (match == null) {
          final lead = SourceCandidateValidator.reviewOnly(spec, page);
          if (lead != null && !review.any((h) => h.url == lead.url)) {
            review.add(lead);
          }
        }
      }
      // Quote subjects: search ranks SEO/news above the structured quote
      // pages the validator can prove. Deterministic provider leads are not
      // evidence - each is read and passes the same strict validation
      // (identity, currency, live structured price) before it is offered.
      if (hits.isEmpty &&
          !spec.isText &&
          spec.storageGb == 0 &&
          spec.colour == null) {
        final slug = spec.model
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
        if (slug.isNotEmpty) {
          final currencyPath =
              spec.currency == 'USD' ? '' : '/${spec.currency.toLowerCase()}';
          final leads = <Uri>[
            Uri.parse(
              'https://www.coingecko.com/en/coins/$slug$currencyPath',
            ),
            if (spec.currency == 'USD')
              Uri.parse('https://www.coinbase.com/price/$slug'),
          ];
          final leadPages = await Future.wait(
            leads.map((url) async {
              try {
                return await pageReader
                    .read(url)
                    .timeout(const Duration(seconds: 8));
              } catch (_) {
                return null;
              }
            }),
          );
          for (final page in leadPages.whereType<ProductPage>()) {
            final match = SourceCandidateValidator.validateQuote(spec, page);
            if (match != null && !hits.any((h) => h.url == match.url)) {
              hits.add(match);
            }
          }
        }
      }
      return DiscoveryResult(
        List.unmodifiable(hits),
        hits.isEmpty && review.isEmpty
            ? (spec.isText
                  ? 'No readable public page matching this subject was verified. No watch was started.'
                  : 'No exact, in-stock product page with a readable current price was verified. Try again later or use an optional manual URL. No watch was started.')
            : null,
        List.unmodifiable(review),
      );
    } on DiscoveryUnavailable catch (e) {
      return DiscoveryResult(const [], e.message);
    } catch (_) {
      return const DiscoveryResult(
        [],
        'Source search could not be completed. Try again or paste a product-page link; no watch was started.',
      );
    }
  }
}

/// Free, documented keyless endpoint. Foreground, user-started searches only;
/// no credentials or subscriptions. Rate limits are surfaced, not bypassed.
class TavilyKeylessSearch implements SourceSearchProvider {
  const TavilyKeylessSearch();
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('https://api.tavily.com/search'),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('X-Tavily-Access-Mode', 'keyless');
      request.write(
        jsonEncode({
          'query': spec.query,
          'max_results': 8,
          'search_depth': 'basic',
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode == 429) {
        throw const DiscoveryUnavailable(
          'Free source search is temporarily rate-limited. Try later; no watch was started.',
        );
      }
      if (response.statusCode != 200) {
        throw const DiscoveryUnavailable(
          'Source search is unavailable. Try later or use an optional page link; no watch was started.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 1000000) {
          throw const DiscoveryUnavailable(
            'Source search returned too much data. Try again later.',
          );
        }
      }
      final data = jsonDecode(utf8.decode(bytes)) as Map;
      final results = data['results'] as List? ?? [];
      return results
          .whereType<Map>()
          .map(
            (row) => SearchPage(
              Uri.parse(row['url'] as String),
              row['title']?.toString() ?? '',
            ),
          )
          .toList();
    } finally {
      client.close(force: true);
    }
  }
}

/// Public HTML pages only. No JS execution, logins, redirects or network-guard
/// bypasses. Private/reserved addresses fail closed, including DNS results.
class HttpDiscoveryPageReader implements DiscoveryPageReader {
  const HttpDiscoveryPageReader();
  static bool publicAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return false;
    final b = address.rawAddress;
    if (b.length == 4) {
      return !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          b[0] == 169 && b[1] == 254 ||
          b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
          b[0] == 192 && (b[1] == 168 || b[1] == 0 || b[1] == 2) ||
          b[0] == 100 && b[1] >= 64 && b[1] <= 127 ||
          b[0] == 198 && (b[1] == 18 || b[1] == 19 || b[1] == 51) ||
          b[0] == 203 && b[1] == 0 && b[2] == 113);
    }
    // Public global-unicast only. Excludes mapped IPv4 and local IPv6.
    return (b[0] & 0xe0) == 0x20 &&
        !(b[0] == 0x20 && b[1] == 1 && b[2] == 0x0d && b[3] == 0xb8);
  }

  @override
  Future<ProductPage> read(Uri url) async {
    if (!SourceCandidateValidator.publicHttps(url)) {
      throw const DiscoveryUnavailable('Unsupported source address.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    // Pin the checked address to the connection, avoiding a second DNS lookup.
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null || uri.host != url.host) {
        throw const DiscoveryUnavailable('Unsupported source routing.');
      }
      final addresses = await InternetAddress.lookup(uri.host)
          .timeout(const Duration(seconds: 5));
      if (addresses.isEmpty || addresses.any((a) => !publicAddress(a))) {
        throw const DiscoveryUnavailable('Source is not a public webpage.');
      }
      final pending = await Socket.startConnect(addresses.first, uri.port);
      SecureSocket? connected;
      final secure = pending.socket.then((socket) async {
        connected = await SecureSocket.secure(socket, host: uri.host);
        return connected!;
      });
      return ConnectionTask.fromSocket(secure, () {
        pending.cancel();
        connected?.destroy();
      });
    };
    try {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Lookout/next-source-review',
      );
      final response = await request.close();
      final type = response.headers.contentType?.mimeType;
      if (response.statusCode != 200 || type != 'text/html') {
        return ProductPage(url, response.statusCode, '');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000) {
          throw const DiscoveryUnavailable('Source page is too large.');
        }
      }
      return ProductPage(
        url,
        response.statusCode,
        utf8.decode(bytes, allowMalformed: true),
      );
    } finally {
      client.close(force: true);
    }
  }
}

SourceDiscoveryService defaultSourceDiscovery() => const SourceDiscoveryService(
  searchProvider: TavilyKeylessSearch(),
  pageReader: HttpDiscoveryPageReader(),
);

class ReviewedSource {
  final DiscoverySpec spec;
  final SourceCandidate candidate;
  const ReviewedSource(this.spec, this.candidate);
  String get identity => DiscoverySpec(
    model: spec.model,
    kind: spec.kind,
    phrase: spec.phrase,
    storageGb: spec.storageGb,
    target: spec.target,
    condition: spec.condition,
    country: spec.country,
    currency: spec.currency,
    reviewedProduct: candidate.product,
    colour: spec.colour,
  ).encode();
}

/// Every later check revalidates the saved identity and current offer; never
/// falls back to the first number on a page or a search snippet.
class DiscoveredSourceReader {
  static Future<FetchOutcome> fetch(
    Agent agent, {
    DiscoveryPageReader? reader,
  }) async {
    try {
      final spec = DiscoverySpec.forAgent(agent);
      final page = await (reader ?? const HttpDiscoveryPageReader())
          .read(Uri.parse(agent.sourceUrl!))
          .timeout(const Duration(seconds: 8));
      if (page.finalUrl != Uri.parse(agent.sourceUrl!)) {
        return FetchOutcome.failed(
          'The saved source address changed; review it again',
        );
      }
      final value = spec.marketQuote
          ? SourceCandidateValidator.validateQuote(spec, page)
          : SourceCandidateValidator.validate(spec, page);
      if (value == null) {
        return FetchOutcome.failed(
          'The reviewed source and current evidence could not be verified on its page',
        );
      }
      return FetchOutcome.found(
        value.price,
        spec.isText
            ? '${value.readingLabel}: “${spec.phrase}” on ${value.url.host}; this page only'
            : '${value.product}: ${value.currency} ${value.price} on ${value.url.host}',
      );
    } catch (_) {
      return FetchOutcome.failed(
        'The reviewed source could not be read; no current evidence was verified',
      );
    }
  }
}
