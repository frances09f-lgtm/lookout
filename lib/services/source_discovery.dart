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

  /// Persisted only after a reviewed readable-quote candidate (page without
  /// structured data, proven by subject + currency-guided value + freshness)
  /// is activated; routes later reads to the same readable-quote proof.
  final bool readableQuote;
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
    this.readableQuote = false,
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
    'readableQuote': readableQuote,
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
      readableQuote: data['readableQuote'] as bool? ?? false,
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
              r'\b(?:price|becomes?|go(?:es)?|is|to|drops?|falls?|rises?)\b',
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
      final storages = _storage
          .allMatches(subject)
          .map(
            (m) =>
                int.parse(m.group(1)!) *
                (m.group(2)!.toLowerCase() == 'tb' ? 1024 : 1),
          )
          .toSet();
      if (storages.length > 1) {
        return const TaskClarification(null, [
          'Which storage size (for example 256 GB)?',
        ]);
      }
      var model = subject;
      var storageGb = 0;
      if (storages.length == 1) {
        storageGb = storages.single;
        model = subject
            .replaceAll(_storage, ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
      return TaskClarification(
        DiscoverySpec(
          model: model,
          storageGb: storageGb,
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
      // Without a pinned storage size, keep the exact-equality rule: extra
      // words in a descriptive retailer title leave the exact product
      // unverified, so it goes to review instead of counting as a source.
      if (spec.storageGb <= 0) {
        return canonical(name) == canonical(spec.model);
      }
      // With storage pinned by the task, every model token must appear (pages
      // add "Galaxy", "5G", RAM, colour) and the name must show that exact
      // size, but a page naming a different variant
      // (Ultra/FE/Plus/Edge/Pro/Max/Mini) or an accessory/used listing the
      // task did not ask for is a different product. Bare subset matching
      // without these guards is unsafe (S25 vs S25 Ultra).
      final modelTokens = canonical(
        spec.model,
      ).split(' ').where((t) => t.isNotEmpty).toSet();
      final nameTokens = canonical(
        name,
      ).split(' ').where((t) => t.isNotEmpty).toSet();
      if (!nameTokens.containsAll(modelTokens)) return false;
      const markers = [
        'ultra', 'plus', 'pro', 'max', 'fe', 'edge', 'mini',
        'case', 'cover', 'charger', 'cable', 'protector',
        'refurbished', 'renewed', 'used',
      ];
      for (final m in markers) {
        if (!modelTokens.contains(m) && nameTokens.contains(m)) return false;
      }
      // "S25+" style plus-suffix vanishes in canonicalisation; check raw text.
      final family = modelTokens.firstWhere(
        (t) => t.contains(RegExp(r'\d')),
        orElse: () => '',
      );
      if (family.isNotEmpty &&
          !spec.model.contains('+') &&
          RegExp('\\b${RegExp.escape(family)}\\+', caseSensitive: false)
              .hasMatch(name)) {
        return false;
      }
      // The pinned storage size must be shown by the page name itself; a
      // page silent on size cannot prove the variant.
      {
        final sizes = _storage
            .allMatches(name)
            .map(
              (m) =>
                  int.parse(m.group(1)!) *
                  (m.group(2)!.toLowerCase() == 'tb' ? 1024 : 1),
            )
            .toSet();
        if (!sizes.contains(spec.storageGb)) return false;
      }
      return true;
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
  final bool readableQuote;

  /// The seller domain the offer explicitly named, when it is not this page's
  /// own site: the reading then comes from a third-party tracker page, not the
  /// merchant, and is labelled as such instead of looking merchant-current.
  final String? trackedSellerHost;

  /// True when the price was read from the merchant page's visible HTML
  /// rather than machine-readable structured data - a looser evidence class,
  /// labelled as such.
  final bool visibleOffer;
  bool get thirdPartyTracker =>
      trackedSellerHost != null &&
      SourceCandidateValidator.registrableDomain(trackedSellerHost!) !=
          SourceCandidateValidator.registrableDomain(url.host);
  String get readingLabel => currency.isEmpty
      ? (price == 1
            ? 'Exact phrase present on this page'
            : 'Exact phrase not present on this page')
      : readableQuote
          ? '$currency ${price.toStringAsFixed(2)} • quote page without structured data - confirm it shows this price'
          : thirdPartyTracker
              ? '$currency ${price.toStringAsFixed(2)} • $country • tracked from $trackedSellerHost'
              : visibleOffer
                  ? '$currency ${price.toStringAsFixed(2)} • $country • read from merchant page text'
                  : '$currency ${price.toStringAsFixed(2)} • $country';
  const SourceCandidate({
    required this.url,
    required this.product,
    required this.price,
    required this.currency,
    required this.country,
    required this.checkedAt,
    this.marketQuote = false,
    this.readableQuote = false,
    this.trackedSellerHost,
    this.visibleOffer = false,
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
    // No parseable Product structured data: try the visible merchant offer.
    if (products.isEmpty) return validateVisibleOffer(spec, page, now: now);
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
    final offers = p['offers'] is List ? p['offers'] as List : [p['offers']];
    // Seller/variant offer ranges and aggregate prices require a separate adapter.
    if (offers.length != 1 || offers.single is! Map) return null;
    final o = offers.single as Map;
    final rawProductUrl = p['url']?.toString() ?? '';
    final productUrl = Uri.tryParse(rawProductUrl);
    if (productUrl != null && productUrl.hasScheme) {
      // A self-link must point at this exact page.
      if (productUrl.host != page.finalUrl.host ||
          productUrl.path != page.finalUrl.path) {
        return null;
      }
    } else if (_sellerDomain(o) == null) {
      // Without a self-link, the single embedded product only counts as this
      // page's own offer when the offer explicitly names a seller domain.
      return null;
    }
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
    // A region cannot be established by currency alone. The offer must
    // explicitly anchor the requested country (ISO code supplied by UI):
    // either eligibleRegion names it, or the named seller operates on that
    // country's own ccTLD storefront (amazon.in is an India offer; amazon.com
    // in INR would prove nothing).
    final region = o['eligibleRegion'];
    final regionCode = region is Map
        ? region['name']?.toString()
        : region?.toString();
    final sellerHost = _sellerDomain(o);
    if (regionCode?.toUpperCase() != spec.country.toUpperCase() &&
        !_onCountryTld(sellerHost, spec.country)) {
      return null;
    }
    final pageDomain = registrableDomain(page.finalUrl.host);
    final sellerDomain =
        sellerHost == null ? null : registrableDomain(sellerHost);
    if (productUrl != null &&
        productUrl.hasScheme &&
        sellerDomain != null &&
        registrableDomain(productUrl.host) != sellerDomain) {
      // Self-link and named seller contradict each other about who sells this.
      return null;
    }
    if (sellerDomain != null && sellerDomain != pageDomain) {
      // A third-party tracker's claim about another seller's price carries no
      // authority of its own, and no shared machine-checkable freshness signal
      // is established yet (priceValidUntil marks a validity window, not when
      // the tracker's reading was taken). Trackers are rejected until a
      // grounded freshness check exists.
      return null;
    }
    return SourceCandidate(
      url: page.finalUrl,
      product: name,
      price: price,
      currency: spec.currency,
      country: spec.country,
      checkedAt: now ?? DateTime.now(),
      trackedSellerHost: sellerHost,
    );
  }

  /// Visible-HTML offer reading for a merchant's own product page that
  /// serves no parseable structured data. The page host is the seller, so a
  /// fresh read of this page IS the merchant's current offer; third-party
  /// tracker pages never feed this path. Every leg must be proven from the
  /// page itself: product identity (including pinned variant/storage) from
  /// the title or main heading BEFORE any price is read, region from the
  /// merchant's own ccTLD, stock from explicit in-stock text, and exactly one
  /// dominant current price among price-marked elements after MRP/EMI/
  /// savings/accessory contexts are excluded. Any ambiguity rejects.
  static SourceCandidate? validateVisibleOffer(
    DiscoverySpec spec,
    ProductPage page, {
    DateTime? now,
  }) {
    if (spec.kind != 'productPrice') return null;
    // Region: the merchant's own domain must sit on the requested country's
    // ccTLD. A .com page in an INR task proves nothing about the country.
    if (!_onCountryTld(page.finalUrl.host, spec.country)) return null;
    final doc = html.parse(page.body);
    doc
        .querySelectorAll(
          'script, style, noscript, template, [hidden], [aria-hidden="true"]',
        )
        .forEach((e) => e.remove());
    // Identity first: the page must be ABOUT the requested product+variant.
    final title = doc.querySelector('title')?.text.trim() ?? '';
    final h1 = doc.querySelector('h1')?.text.trim() ?? '';
    if (!DiscoveryTaskParser.identityMatches(title, spec) &&
        (h1.isEmpty || !DiscoveryTaskParser.identityMatches(h1, spec))) {
      return null;
    }
    if (spec.colour != null &&
        !RegExp(
          '\\b\${RegExp.escape(spec.colour!)}\\b',
          caseSensitive: false,
        ).hasMatch(title)) {
      return null;
    }
    final visible = doc.body?.text ?? '';
    // Stock must be explicit, never assumed.
    final low = visible.toLowerCase();
    if (low.contains('out of stock') ||
        low.contains('currently unavailable') ||
        low.contains('sold out')) {
      return null;
    }
    if (!low.contains('in stock')) return null;
    // Currency tokens matching the task's currency only.
    final symbols = _currencySymbols[spec.currency];
    if (symbols == null) return null;
    final tokenRe = RegExp(
      '(?:${symbols.map(RegExp.escape).join('|')})\\s?(\\d[\\d,]*(?:\\.\\d{1,2})?)',
      caseSensitive: false,
    );
    double? amount(String raw) {
      final v = double.tryParse(raw.replaceAll(',', ''));
      return v != null && v.isFinite && v > 0 ? v : null;
    }
    // Only elements that mark themselves as prices; strike/MRP/EMI/savings/
    // accessory/warranty/bundle contexts are excluded, as is any element whose
    // own text frames the amount as a non-current price.
    final markerRe = RegExp(r'price|amount|cost', caseSensitive: false);
    final excludedClass = RegExp(
      r'warrant|accessor|fbt|bundle|emi|sav|basis|was|strike|mrp|list|old|cross',
      caseSensitive: false,
    );
    final excludedText = RegExp(
      r'm\.?r\.?p|list price|emi|per month|/\s?mo(nth)?|you save|save up to|\d+%\s*(off|savings)|percent (savings|off)|cashback|bank offer|exchange|without exchange|effective|rental|subscribe',
      caseSensitive: false,
    );
    final counts = <double, int>{};
    for (final e in doc.querySelectorAll('[class], [id]')) {
      final sig = '${e.attributes['class'] ?? ''} ${e.attributes['id'] ?? ''}';
      if (!markerRe.hasMatch(sig)) continue;
      if (excludedClass.hasMatch(sig)) continue;
      if (e.parent?.localName == 's' ||
          e.parent?.localName == 'del' ||
          e.parent?.localName == 'strike') {
        continue;
      }
      final text = e.text;
      if (excludedText.hasMatch(text)) continue;
      for (final m in tokenRe.allMatches(text)) {
        final v = amount(m.group(1)!);
        if (v != null) counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    // One clean price alone is strong; several distinct amounts need a clear
    // modal winner so variant/accessory prices cannot impersonate the offer.
    if (ranked.length > 1 && (best.value < 3 || best.value < ranked[1].value * 2)) {
      return null;
    }
    return SourceCandidate(
      url: page.finalUrl,
      product: title.isNotEmpty ? title : h1,
      price: best.key,
      currency: spec.currency,
      country: spec.country,
      checkedAt: now ?? DateTime.now(),
      visibleOffer: true,
    );
  }

  static const _currencySymbols = {
    'INR': ['₹', 'Rs.', 'Rs', 'INR'],
    'USD': ['US\$', '\$'],
    'EUR': ['€'],
    'GBP': ['£'],
    'JPY': ['¥'],
    'AUD': ['A\$'],
    'CAD': ['C\$'],
  };

  /// The seller's domain from an offer's offeredBy/url field, when it is
  /// explicitly a domain (amazon.in), else null. A bare name like "Amazon"
  /// is not seller evidence.
  static String? _sellerDomain(Map offer) {
    final by = offer['offeredBy'];
    String? raw;
    if (by is Map) {
      raw = by['url']?.toString() ?? by['name']?.toString();
    } else {
      raw = by?.toString() ?? offer['url']?.toString();
    }
    if (raw == null) return null;
    final host = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw')?.host;
    if (host == null || !host.contains('.')) return null;
    return host.toLowerCase();
  }

  /// Registrable domain (last two labels; common second-level prefixes like
  /// .co.in/.com.au count as one). Used to tell a merchant's own page from a
  /// third-party tracker quoting that merchant.
  static String registrableDomain(String host) {
    final labels = host.toLowerCase().split('.');
    if (labels.length <= 2) return host.toLowerCase();
    const secondLevel = {'co', 'com', 'org', 'net', 'ac', 'gov', 'edu'};
    final tld = labels.last;
    if (tld.length == 2 &&
        labels.length >= 3 &&
        secondLevel.contains(labels[labels.length - 2])) {
      return labels.sublist(labels.length - 3).join('.');
    }
    return labels.sublist(labels.length - 2).join('.');
  }

  /// True when the seller host sits on the country's own ccTLD. ISO alpha-2
  /// matches the ccTLD for almost every country; GB uses .uk.
  static bool _onCountryTld(String? host, String country) {
    if (host == null) return false;
    var tld = country.toLowerCase();
    if (tld == 'gb') tld = 'uk';
    if (tld.length != 2) return false;
    return host == tld || host.endsWith('.$tld');
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
  /// Some live quote pages (metals, forex) carry no schema.org markup, so
  /// strict structured validation can never prove them. A weaker tier still
  /// can: the subject must name the page, the number the checker will read
  /// must sit next to its currency, and the page must show a current date.
  /// These candidates always require explicit review, and activation
  /// re-reads the page through this same proof.
  static SourceCandidate? validateReadableQuote(
    DiscoverySpec spec,
    ProductPage page, {
    DateTime? now,
  }) {
    if (spec.kind != 'productPrice' ||
        spec.storageGb != 0 ||
        spec.colour != null ||
        spec.isText ||
        page.status != 200 ||
        !publicHttps(page.finalUrl) ||
        page.body.length > 2000000 ||
        validate(spec, page) != null ||
        validateQuote(spec, page) != null) {
      return null;
    }
    final doc = html.parse(page.body);
    if (doc.querySelector('input[type="password"],#challenge-form') != null) {
      return null;
    }
    final title = doc.querySelector('title')?.text.trim() ?? '';
    final h1 = doc.querySelector('h1')?.text.trim() ?? '';
    if (!_subjectNamesPage('$title $h1', spec)) return null;
    // The page's headline unit must agree with the unit the URL promises:
    // an /ounce URL whose headline reads "per Gram" is not the page it
    // claims to be, and a gram quote must never stand in for an ounce one.
    if (!_headlineUnitAgrees(page.finalUrl, h1, spec.model)) return null;
    final text = PageValueFetcher.htmlToText(page.body);
    // One extraction the offer, the activation re-read and every later check
    // agree on: an FX equation row for pair subjects, or the single
    // currency-adjacent, currently-dated amount otherwise. Signed changes,
    // percentages, fee-labelled numbers, date/time fragments, and ambiguous
    // or stale values reject instead of guessing.
    final guided = _guidedQuoteValue(
      text,
      spec,
      now ?? DateTime.now(),
      headline: h1.isNotEmpty ? h1 : title,
    );
    if (guided == null) return null;
    final value = guided.value;
    return SourceCandidate(
      url: page.finalUrl,
      product: title.isNotEmpty ? title : spec.model,
      price: value,
      currency: spec.currency,
      country: spec.country,
      checkedAt: now ?? DateTime.now(),
      marketQuote: true,
      readableQuote: true,
    );
  }

  /// Every subject word must appear in the page title or heading. Weaker
  /// than structured identity, so it is only one of three proofs here and
  /// the candidate stays review-required.
  static bool _subjectNamesPage(String heading, DiscoverySpec spec) {
    String canonical(String v) =>
        v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    const arena = {
      'forex', 'spot', 'market', 'markets', 'live', 'today', 'trading',
      'rise', 'rises', 'fall', 'falls',
    };
    final tokens = canonical(
      spec.model,
    ).split(' ').where((t) => t.length >= 3 && !arena.contains(t)).toSet();
    if (tokens.isEmpty) return false;
    final page = canonical(heading).split(' ').toSet();
    return tokens.every(page.contains);
  }

  static String? _unitOf(String v) {
    const units = [
      'ounce', 'gram', 'kilogram', 'kilo', 'tola',
      'baht', 'tael', 'carat', 'grain', 'ratti', 'masha',
    ];
    final c = v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    for (final u in units) {
      if (RegExp('\\b' + u + '\\b').hasMatch(c)) return u;
    }
    return null;
  }

  static bool _headlineUnitAgrees(Uri url, String h1, String model) {
    final urlUnit = _unitOf(url.path);
    final headUnit = _unitOf(h1);
    final modelUnit = _unitOf(model);
    // A task that names its unit fixes it; the page and its headline must
    // agree with the task, not merely with each other.
    if (modelUnit != null) {
      if (urlUnit != null && urlUnit != modelUnit) return false;
      if (headUnit != null && headUnit != modelUnit) return false;
      return true;
    }
    // A metal quote without an explicit unit intends the standard ounce
    // price: a gram/tola page or headline never substitutes for it.
    if (RegExp(r'\b(gold|silver)\b', caseSensitive: false).hasMatch(model)) {
      if (urlUnit != null && urlUnit != 'ounce') return false;
      if (headUnit != null && headUnit != 'ounce') return false;
      return true;
    }
    if (urlUnit == null || headUnit == null) return true;
    return urlUnit == headUnit;
  }

  /// Every position where the number the checker will read sits next to the
  /// watched currency, so the reading is provably that price.
  /// Every position where the number the checker will read sits next to the
  /// task currency was the 1.1.18 proof; it validated the FIRST plausible
  /// number on the page, so pages whose first number is not the quote (fee
  /// rows, unit counts, conversion tables) could never be proven. The guided
  /// extraction below picks the quote itself or rejects.
  static ({double value, int at})? _guidedQuoteValue(
    String text,
    DiscoverySpec spec,
    DateTime now, {
    String headline = '',
  }) {
    final pair = _fxPair(spec);
    if (pair != null) {
      // FX: the watched unit is the quote side; an inverted page/task pair
      // rejects instead of reading the inverse rate.
      if (spec.currency.toUpperCase() != pair.$2) return null;
      return _fxGuidedValue(text, pair.$1, pair.$2, now);
    }
    return _currencyGuidedValue(text, spec, now, headline: headline);
  }

  /// Two currency codes in the subject name an FX pair, base first:
  /// "USD INR rate" watches INR per 1 USD.
  static (String, String)? _fxPair(DiscoverySpec spec) {
    final seen = <String>[];
    for (final m in RegExp(
      r'\b(USD|INR|EUR|GBP|AED|AUD|CAD)\b',
    ).allMatches(spec.model.toUpperCase())) {
      if (!seen.contains(m.group(1)!)) seen.add(m.group(1)!);
    }
    return seen.length >= 2 ? (seen[0], seen[1]) : null;
  }

  /// The rate is taken only from an explicit "1 BASE = value QUOTE" equation
  /// row, so split-digit headlines and bulk conversion rows cannot be misread;
  /// exactly one distinct equation value with a current date near it proves.
  static ({double value, int at})? _fxGuidedValue(
    String text,
    String base,
    String quote,
    DateTime now,
  ) {
    final rx = RegExp(
      '(?<![0-9.])1(?:\\.0+)?(?![0-9.])\\s+$base\\s*=?\\s*'
      '([0-9][0-9,]*(?:\\.[0-9]+)?)\\s+$quote(?![A-Z])',
      caseSensitive: false,
    );
    final values = <double, int>{};
    for (final m in rx.allMatches(text)) {
      final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v == null || v <= 0 || v > 1000000000) continue;
      values[v] ??= m.start;
    }
    if (values.length != 1) return null;
    final e = values.entries.single;
    if (!_showsCurrentDate(text, now, near: e.value)) return null;
    return (value: e.key, at: e.value);
  }

  /// The single amount adjacent to the currency CODE (symbols are shared
  /// across currencies, so only the code proves the unit). Signed changes,
  /// percentages, fee-labelled numbers and date/time fragments are excluded;
  /// when several distinct amounts remain, exactly one may carry a current
  /// date near it, otherwise the page is ambiguous and rejects.
  static ({double value, int at})? _currencyGuidedValue(
    String text,
    DiscoverySpec spec,
    DateTime now, {
    String headline = '',
  }) {
    final code = spec.currency.toUpperCase();
    final codeRx = RegExp('\\b$code\\b');
    final numRx = RegExp(r'[0-9][0-9,]*(?:\.[0-9]+)?');
    final candidates = <double, int>{};
    for (final m in codeRx.allMatches(text)) {
      final a = m.start - 40 < 0 ? 0 : m.start - 40;
      final b = m.end + 40 > text.length ? text.length : m.end + 40;
      for (final nm in numRx.allMatches(text.substring(a, b))) {
        final pos = a + nm.start;
        final raw = nm.group(0)!;
        final v = double.tryParse(raw.replaceAll(',', ''));
        if (v == null || v <= 0 || v > 1000000000) continue;
        // A market quote on these pages always carries decimals; whole
        // numbers are counters, karat labels or date/time fragments.
        if (!raw.contains('.')) continue;
        // The value names its own unit: the currency code must follow it
        // within a few characters ("$4,022.28 USD"). Unit tables whose
        // header carries the code ("Price in USD" over gram/tola rows)
        // and narrative figures cannot satisfy this.
        final gapEnd = pos + raw.length + 12 > text.length
            ? text.length
            : pos + raw.length + 12;
        if (!codeRx.hasMatch(text.substring(pos + raw.length, gapEnd))) {
          continue;
        }
        if (_excludedNumber(text, pos, raw)) continue;
        candidates[v] ??= pos;
      }
    }
    if (candidates.isEmpty) return null;
    // The quote is the value the page's own headline presents: the amount
    // inside or right after the heading that names the instrument, unit
    // and currency ("Gold Price per Ounce in US Dollar = $4,025.66 USD").
    // Every occurrence of the headline: the title often repeats the
    // heading, so the quote-linked occurrence is the one the value
    // actually follows.
    final hStarts = <int>[];
    if (headline.isNotEmpty) {
      var i = text.indexOf(headline);
      while (i >= 0) {
        hStarts.add(i);
        i = text.indexOf(headline, i + 1);
      }
    }
    bool headlineLinked(int pos) => hStarts.any(
          (h) => pos >= h && pos <= h + headline.length + 160,
        );
    final fresh = <double, int>{};
    for (final e in candidates.entries) {
      final pos = e.value;
      // Explicit stale evidence next to the value always rejects.
      if (_hasStaleDate(text, now, near: pos)) continue;
      if (_showsCurrentDate(text, now, near: pos)) {
        fresh[e.key] ??= pos;
        continue;
      }
      // The headline quote's freshness comes from a stamp the page ties
      // to this instrument or to the quote by label ("Gold/Ounce
      // 29-OCT-2026", "Gold update time ...", "Updated: ..."). A bare
      // nearby date proves nothing: goldpricez's stats block ends in a
      // stamp that belongs to the Performance section, not the quote.
      if (headlineLinked(pos) &&
          _hasLabeledCurrentStamp(text, spec, now)) {
        fresh[e.key] ??= pos;
      }
    }
    if (fresh.length == 1) {
      return (value: fresh.keys.single, at: fresh.values.single);
    }
    return null;
  }

  static bool _excludedNumber(String text, int pos, String raw) {
    final before = text.substring(pos - 24 < 0 ? 0 : pos - 24, pos);
    // Signed change figures ("$-0.96", "+12").
    if (RegExp(r'[-+]\s*\$?\s*$').hasMatch(before)) return true;
    // Fee/tax/shipping/MRP-style labels are not the quote.
    if (RegExp(
      r'(fee|fees|shipping|tax|taxes|mrp|premium|commission|charge|charges)'
      r'\s*:?\s*(?:\$|\u20B9)?\s*$',
      caseSensitive: false,
    ).hasMatch(before)) {
      return true;
    }
    // Change amounts, not the quote ("decrease of $2.59", "rose 12.5").
    if (RegExp(
      r'(increase|decrease|change|gain|loss|rise|rose|fall|fell|drop|grew)'
      r'[a-z]*\b[^0-9]{0,16}$',
      caseSensitive: false,
    ).hasMatch(before)) {
      return true;
    }
    // Derived market stats are not the quote: day open/high/low/close,
    // the high-low range difference, averages and "days ago" narrative
    // figures all sit next to the currency with decimals on quote pages.
    if (RegExp(
      r'(open|high|low|close|difference|range|average|avg|bid|ask|spread|ago)'
      r'[a-z]*\b[^0-9]{0,24}$',
      caseSensitive: false,
    ).hasMatch(before)) {
      return true;
    }
    // Percentages ("-1.76%").
    final after = text.substring(
      pos,
      pos + raw.length + 12 > text.length ? text.length : pos + raw.length + 12,
    );
    if (after.contains('%')) return true;
    // Date/time fragments: years, "29-OCT-2026" parts, "04:55" parts.
    if (RegExp(r'^(19|20)[0-9][0-9]$').hasMatch(raw)) return true;
    final immAfter = text.substring(
      pos + raw.length,
      pos + raw.length + 1 > text.length ? text.length : pos + raw.length + 1,
    );
    if (RegExp(r'^[-/:]').hasMatch(immAfter)) return true;
    final immBefore = text.substring(pos - 1 < 0 ? 0 : pos - 1, pos);
    if (RegExp(r'[-/:]$').hasMatch(immBefore)) return true;
    // Fragment of a larger number cut by the scan window (".15", ",069").
    if (immBefore == '.' || immBefore == ',') return true;
    // HTML entity residue ("&#9660;").
    if (before.endsWith('&#') || before.endsWith('&')) return true;
    // Unit suffixes ("7D", "30D", "1Y", "24K").
    final immAfter1 = text.substring(
      pos + raw.length,
      pos + raw.length + 1 > text.length ? text.length : pos + raw.length + 1,
    );
    if (RegExp(r'^[A-Za-z]').hasMatch(immAfter1)) return true;
    // Calendar fragments ("October 29", "Oct 29") - a date is not the quote.
    if (RegExp(
      r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*$',
      caseSensitive: false,
    ).hasMatch(before)) {
      return true;
    }
    return false;
  }

  /// A live quote page shows when its quote is from. Accept a visible date
  /// of today or yesterday (page timezone may sit behind the device's).
  static bool _showsCurrentDate(
    String text,
    DateTime now, {
    int? near,
    int radius = 200,
  }) {
    final scoped = near == null
        ? text
        : text.substring(
            near - radius < 0 ? 0 : near - radius,
            near + radius > text.length ? text.length : near + radius,
          );
    const months = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];
    for (final day in [now, now.subtract(const Duration(days: 1))]) {
      final d = day.day;
      final m = months[day.month - 1];
      final y = day.year;
      final patterns = <RegExp>[
        RegExp('\\b0?$d[ -]$m[a-z]*[ -]$y\\b', caseSensitive: false),
        RegExp('\\b$m[a-z]*\\s+0?$d,?\\s+$y\\b', caseSensitive: false),
        RegExp('\\b$y-0?${day.month}-0?$d\\b'),
      ];
      if (patterns.any((rx) => rx.hasMatch(scoped))) return true;
    }
    return false;
  }

  /// A date sits near the value but none of it is current: explicit
  /// evidence the quote is stale. Stronger than any wider current date -
  /// a stale stamp next to the value rejects even when a fresher stat or
  /// timestamp appears elsewhere in the block.
  static bool _hasStaleDate(String text, DateTime now, {required int near}) {
    final scoped = text.substring(
      near - 200 < 0 ? 0 : near - 200,
      near + 200 > text.length ? text.length : near + 200,
    );
    const anyDate = [
      r'\b[0-9]{1,2}[ -](jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[ -][0-9]{4}\b',
      r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[ ]+[0-9]{1,2},?[ ]+[0-9]{4}\b',
      r'\b[0-9]{4}-[0-9]{2}-[0-9]{2}\b',
    ];
    final hasAny = anyDate.any(
      (p) => RegExp(p, caseSensitive: false).hasMatch(scoped),
    );
    if (!hasAny) return false;
    return !_showsCurrentDate(text, now, near: near);
  }

  /// A current stamp the page ties to this quote by label: an update label
  /// ("Updated:", "Last updated", "update time", "as of") or the subject
  /// itself naming its unit/update ("Gold/Ounce 29-OCT-2026", "Gold update
  /// time ...") within the 60 chars before the stamp. A bare date near the
  /// value is NOT evidence: it can belong to a neighbouring stats or
  /// performance section.
  static bool _hasLabeledCurrentStamp(
    String text,
    DiscoverySpec spec,
    DateTime now,
  ) {
    const arena = {
      'forex', 'spot', 'market', 'markets', 'live', 'today', 'trading',
      'rise', 'rises', 'fall', 'falls',
    };
    final tokens = spec.model
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(' ')
        .where((t) => t.length >= 3 && !arena.contains(t))
        .toList();
    final generic = RegExp(
      r'(last\s+)?updat(ed|e)(\s+time)?|as of',
      caseSensitive: false,
    );
    // "<subject> update time" names the quote's own refresh; a bare
    // "<subject>/<unit>" mention can be a section title (goldpricez's
    // stats stamp sits under "Performance (Gold/Ounce)"), so it is not
    // enough on its own.
    final subjectLabels = <RegExp>[
      for (final t in tokens)
        RegExp('\\b' + t + '\\s+updat', caseSensitive: false),
    ];
    bool labeledBefore(int start) {
      final a = start - 60 < 0 ? 0 : start - 60;
      final before = text.substring(a, start);
      return generic.hasMatch(before) ||
          subjectLabels.any((rx) => rx.hasMatch(before));
    }

    const months = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];
    for (final day in [now, now.subtract(const Duration(days: 1))]) {
      final d = day.day;
      final m = months[day.month - 1];
      final y = day.year;
      final patterns = <RegExp>[
        RegExp('\\b0?' + '$d' + '[ -]' + m + '[a-z]*[ -]' + '$y' + '\\b', caseSensitive: false),
        RegExp('\\b' + m + '[a-z]*\\s+0?' + '$d' + ',?\\s+' + '$y' + '\\b', caseSensitive: false),
        RegExp('\\b' + '$y' + '-0?' + '${day.month}' + '-0?' + '$d' + '\\b'),
      ];
      for (final rx in patterns) {
        for (final match in rx.allMatches(text)) {
          if (labeledBefore(match.start)) return true;
        }
      }
    }
    return false;
  }

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
      final label = 'Offer ${i + 1}';
      if (offer is! Map) {
        blockers.add('$label: unsupported offer structure.');
        continue;
      }
      final offerType = offer['@type']?.toString();
      if (offerType != 'Offer' && offerType != 'AggregateOffer') {
        blockers.add('$label: unsupported offer structure.');
        continue;
      }
      // Aggregate offers bundle sellers/variants. They are read for an honest
      // report but can never be the one exact verified offer.
      final isAggregate = offerType == 'AggregateOffer';
      if (isAggregate) {
        blockers.add(
          '$label: the page aggregates seller offers instead of naming one exact offer.',
        );
      }
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
      final price = double.tryParse(
        (offer['price'] ?? offer['lowPrice'])?.toString() ?? '',
      );
      if (price == null || !price.isFinite || price <= 0) {
        blockers.add('$label: no valid price.');
      }
      if (offer['priceCurrency'] != spec.currency) {
        blockers.add('$label: currency does not match ${spec.currency}.');
      }
      // Affirmative out-of-stock is reported as such; anything that is not an
      // explicitly verified in-stock value stays unverified. The schema URL
      // is matched case-insensitively for the out-of-stock report only -
      // retailers emit it with inconsistent casing ("OutofStock").
      final stockRaw = offer['availability']?.toString() ?? '';
      final stockNorm = stockRaw
          .replaceFirst(RegExp(r'^https?://schema\.org/'), '')
          .toLowerCase();
      final offerCount = int.tryParse(offer['offerCount']?.toString() ?? '');
      if (stockNorm == 'outofstock' || (isAggregate && offerCount == 0)) {
        blockers.add('$label: the page reports this offer out of stock.');
      } else if (![
        'https://schema.org/InStock',
        'http://schema.org/InStock',
        'InStock',
      ].contains(stockRaw)) {
        blockers.add('$label: in-stock availability is not verified.');
      }
      final condition = offer['itemCondition']?.toString();
      if (condition != null &&
          !condition.endsWith('/NewCondition') &&
          condition != 'NewCondition') {
        blockers.add('$label: not a verified new-condition offer.');
      }
      // Report exactly what is present, not a selected/current price or
      // variant. Exactly one product with exactly one offer: the offer is
      // unambiguously for that product, so its label is the product name.
      // Anything more ambiguous stays "variant not specified".
      final variant =
          offer['name']?.toString() ??
          (offers.length == 1 ? name : null) ??
          'variant not specified';
      reports.add(
        '$label: $variant; '
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
      final fresh = selected.readableQuote
          ? SourceCandidateValidator.validateReadableQuote(
              spec,
              page,
              now: time,
            )
          : selected.marketQuote
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
          final quote = SourceCandidateValidator.validateReadableQuote(
            spec,
            page,
          );
          if (quote != null && !hits.any((h) => h.url == quote.url)) {
            hits.add(quote);
          } else if (quote == null) {
            final lead = SourceCandidateValidator.reviewOnly(spec, page);
            if (lead != null && !review.any((h) => h.url == lead.url)) {
              review.add(lead);
            }
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
          // Gold quotes: the verified ounce page for the watched currency.
          const goldpricezCountry = {
            'USD': 'us',
            'INR': 'in',
            'EUR': 'eu',
            'GBP': 'uk',
            'AED': 'ae',
            'AUD': 'au',
            'CAD': 'ca',
          };
          final country = goldpricezCountry[spec.currency];
          if (country != null &&
              RegExp(r'\bgold\b', caseSensitive: false).hasMatch(
                spec.model,
              )) {
            leads.add(
              Uri.parse('https://goldpricez.com/$country/ounce'),
            );
          }
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
            final match =
                SourceCandidateValidator.validateQuote(spec, page) ??
                SourceCandidateValidator.validateReadableQuote(spec, page);
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
                  : spec.storageGb == 0
                  ? 'No page with a provable current price for this exact subject and currency was verified. Try again later or use an optional manual URL. No watch was started.'
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
    var current = url;
    // Follow redirects hop by hop, re-validating each address; silent drops
    // of 3xx pages made reachable sources look unreadable.
    for (var hop = 0; hop < 6; hop++) {
      final page = await _readOnce(current);
      if (page.status >= 300 && page.status < 400 && page.location != null) {
        current = current.resolveUri(Uri.parse(page.location!));
        continue;
      }
      return ProductPage(current, page.status, page.body);
    }
    return ProductPage(current, 0, '');
  }

  Future<_RawPage> _readOnce(Uri url) async {
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
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.statusCode != 200 || type != 'text/html') {
        return _RawPage(response.statusCode, '', location);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000) {
          throw const DiscoveryUnavailable('Source page is too large.');
        }
      }
      return _RawPage(
        response.statusCode,
        utf8.decode(bytes, allowMalformed: true),
        location,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class _RawPage {
  final int status;
  final String body;
  final String? location;
  const _RawPage(this.status, this.body, this.location);
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
    marketQuote: candidate.marketQuote,
    readableQuote: candidate.readableQuote,
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
      // The readable tier returns null whenever a stricter validation passes,
      // so this order never relaxes a page; the fallback chain covers sources
      // saved before the routing flags were persisted.
      var value = spec.readableQuote
          ? SourceCandidateValidator.validateReadableQuote(spec, page)
          : spec.marketQuote
          ? SourceCandidateValidator.validateQuote(spec, page)
          : SourceCandidateValidator.validate(spec, page);
      value ??= SourceCandidateValidator.validate(spec, page) ??
          SourceCandidateValidator.validateQuote(spec, page) ??
          SourceCandidateValidator.validateReadableQuote(spec, page);
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
