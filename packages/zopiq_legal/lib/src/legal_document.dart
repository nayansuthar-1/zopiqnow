/// One legal document, as data.
///
/// The Word originals in `legal/source/` are the source of truth — they are
/// what gets reviewed and signed off. `tool/import_legal.mjs` turns them into
/// the generated files beside this one, and everything that shows a policy to
/// anybody reads those: the in-app reader in all three apps, and the HTML pages
/// Google Play links to. Nobody retypes a policy, so no two copies can disagree.
library;

/// Who a document is addressed to.
///
/// Not a filter on who *may* read one — anybody can open anything from the
/// index — but on which documents an app puts in front of somebody by default.
/// A customer should not have to scroll past the Merchant SLA to find the
/// refund policy.
enum LegalAudience { customer, restaurant, rider }

/// The pieces a document is made of. Word gives us headings, paragraphs,
/// bulleted lists and tables, and nothing else appears in these twenty-one
/// files, so this models exactly those four and no more.
sealed class LegalBlock {
  const LegalBlock();
}

/// A section heading. [level] is 1, 2 or 3, straight from the Word style.
final class LegalHeading extends LegalBlock {
  const LegalHeading(this.level, this.text);

  final int level;
  final String text;
}

final class LegalParagraph extends LegalBlock {
  const LegalParagraph(this.text);

  final String text;
}

final class LegalBullets extends LegalBlock {
  const LegalBullets(this.items);

  final List<String> items;
}

/// The retention schedules and SLA tables. Rendered as a table where there is
/// width for one and as stacked label/value pairs where there is not — a
/// three-column table on a 360dp phone is unreadable either way, but stacked
/// at least fits.
final class LegalTable extends LegalBlock {
  const LegalTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

/// A whole document.
final class LegalDocument {
  const LegalDocument({
    required this.slug,
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.group,
    required this.audiences,
    required this.requiresConsent,
    required this.blocks,
    this.subtitle,
    this.docId,
  });

  /// The url segment and the route parameter — `privacy-policy`,
  /// `refund-and-cancellation-policy`. Derived from the filename with the
  /// leading number stripped, because a number is a filing order and putting
  /// one in a URL dates it the moment a document is inserted above it.
  final String slug;

  final String title;

  /// The line under the title on the cover page, where there is one.
  final String? subtitle;

  /// `ZOPIQ-LEGAL-01`. The two main documents have none.
  final String? docId;

  final String version;
  final String effectiveDate;

  /// Which section of the index this falls under. See [legalGroupTitles].
  final String group;

  final Set<LegalAudience> audiences;

  /// Whether agreeing to this is a condition of signing in. True for exactly
  /// two documents — see [consentDocuments].
  final bool requiresConsent;

  final List<LegalBlock> blocks;
}

/// The headings the index groups documents under, in order.
const Map<String, String> legalGroupTitles = <String, String>{
  'core': 'The agreement',
  'orders': 'Orders, payments and refunds',
  'conduct': 'Conduct and safety',
  'data': 'Your data',
  'support': 'Help and access',
  'partner': 'Partner operations',
};

/// The order [legalGroupTitles] renders in. A map's insertion order is already
/// this, but relying on that is relying on nobody ever reordering the literal.
const List<String> legalGroupOrder = <String>[
  'core',
  'orders',
  'conduct',
  'data',
  'support',
  'partner',
];
