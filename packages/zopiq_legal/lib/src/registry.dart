/// Ways of asking the corpus a question.
///
/// The list itself is generated — see `documents/all.dart`, which
/// `tool/import_legal.mjs` writes. This file is hand-written and holds only
/// the lookups, so regenerating the corpus never overwrites logic.
library;

import 'package:zopiq_legal/src/documents/all.dart';
import 'package:zopiq_legal/src/legal_document.dart';

export 'package:zopiq_legal/src/documents/all.dart'
    show allLegalDocuments, legalConsentVersion;

/// One document by slug, or null if the slug is a typo or a stale deep link.
LegalDocument? legalDocumentBySlug(String slug) {
  for (final LegalDocument doc in allLegalDocuments) {
    if (doc.slug == slug) return doc;
  }
  return null;
}

/// The documents addressed to one kind of user, in filing order.
List<LegalDocument> legalDocumentsFor(LegalAudience audience) =>
    allLegalDocuments
        .where((LegalDocument d) => d.audiences.contains(audience))
        .toList(growable: false);

/// The documents somebody must agree to before they can sign in — the terms
/// and the privacy policy, and deliberately nothing else.
///
/// Gating a sign-in on all twenty-one would not be consent. It would be a wall
/// nobody reads, which is the thing consent law exists to prevent, dressed up
/// as compliance. The other nineteen are one tap away from the account screen
/// and named inside these two.
final List<LegalDocument> consentDocuments = allLegalDocuments
    .where((LegalDocument d) => d.requiresConsent)
    .toList(growable: false);

/// The documents for one audience, bucketed under [legalGroupTitles] and in
/// [legalGroupOrder]. Empty groups are dropped — a rider has no reason to see
/// an empty "Partner operations" heading with nothing under it.
List<({String group, String title, List<LegalDocument> documents})>
legalIndexFor(LegalAudience audience) {
  final List<LegalDocument> mine = legalDocumentsFor(audience);
  final List<({String group, String title, List<LegalDocument> documents})>
  out = <({String group, String title, List<LegalDocument> documents})>[];

  for (final String group in legalGroupOrder) {
    final List<LegalDocument> inGroup = mine
        .where((LegalDocument d) => d.group == group)
        .toList(growable: false);
    if (inGroup.isEmpty) continue;
    out.add((
      group: group,
      title: legalGroupTitles[group]!,
      documents: inGroup,
    ));
  }
  return out;
}
