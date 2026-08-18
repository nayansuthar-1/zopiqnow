import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_legal/src/legal_document.dart';
import 'package:zopiq_legal/src/registry.dart';

/// One legal document, rendered in the app.
///
/// In the app and not a link to a website, deliberately. A policy behind a
/// browser hand-off is a policy that is unreadable on a bad connection, breaks
/// when a URL moves, and cannot be found at all by somebody on a train. The web
/// copies still exist — Play requires one that works without installing
/// anything — and they are built from the same data this screen reads, so there
/// is no second version to keep in step.
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.slug, super.key});

  /// `terms-and-conditions`, `privacy-policy`, and so on.
  final String slug;

  @override
  Widget build(BuildContext context) {
    final LegalDocument? doc = legalDocumentBySlug(slug);
    if (doc == null) return _NotFound(slug: slug);

    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.md,
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.xxl,
        ),
        // One extra for the masthead at index 0. `.builder` rather than a
        // `children:` list because the terms run to 352 blocks, and building
        // every one of them to show the first screenful is 352 widgets of work
        // for a screen that shows about nine.
        itemCount: doc.blocks.length + 1,
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) return _Masthead(doc: doc);
          return _Block(block: doc.blocks[i - 1], zc: zc, t: t);
        },
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({required this.doc});

  final LegalDocument doc;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (doc.subtitle != null)
          Text(
            doc.subtitle!,
            style: t.titleSmall?.copyWith(color: zc.textMuted, height: 1.4),
          ),
        const SizedBox(height: ZopiqSpacing.sm),
        // Version and date together, because a policy whose date is not on it
        // is a policy nobody can tell they are reading an old copy of.
        Text(
          'Version ${doc.version} · Effective ${doc.effectiveDate}'
          '${doc.docId != null ? ' · ${doc.docId}' : ''}',
          style: t.bodySmall?.copyWith(color: zc.textMuted),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        Divider(color: zc.divider, height: 1),
        const SizedBox(height: ZopiqSpacing.lg),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block, required this.zc, required this.t});

  final LegalBlock block;
  final ZopiqColors zc;
  final TextTheme t;

  @override
  Widget build(BuildContext context) {
    switch (block) {
      case LegalHeading(level: final int level, text: final String text):
        return Padding(
          // A level-1 heading opens a section and needs air above it; a level-3
          // heading is a question inside one and would look detached with the
          // same gap.
          padding: EdgeInsets.only(
            top: level == 1 ? ZopiqSpacing.xl : ZopiqSpacing.lg,
            bottom: ZopiqSpacing.sm,
          ),
          child: Text(
            text,
            style: switch (level) {
              // The source shouts its top-level headings — "12. CASH ON
              // DELIVERY (COD) POLICY" — as legal documents do. Left in caps
              // and set smaller with letter-spacing it reads as a section
              // marker; set large it reads as shouting.
              1 => t.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: zc.textStrong,
              ),
              2 => t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              _ => t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            },
          ),
        );

      case LegalParagraph(text: final String text):
        return Padding(
          padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
          child: Text(
            text,
            style: t.bodyMedium?.copyWith(color: zc.textMuted, height: 1.55),
          ),
        );

      case LegalBullets(items: final List<String> items):
        return Padding(
          padding: const EdgeInsets.only(
            bottom: ZopiqSpacing.sm,
            top: ZopiqSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 9, left: 2),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: zc.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZopiqSpacing.sm),
                      Expanded(
                        child: Text(
                          item,
                          style: t.bodyMedium?.copyWith(
                            color: zc.textMuted,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

      case LegalTable(
        headers: final List<String> headers,
        rows: final List<List<String>> rows,
      ):
        return _Table(headers: headers, rows: rows, zc: zc, t: t);
    }
  }
}

/// The retention schedules and the SLA targets.
///
/// Stacked, not gridded. These tables run to four columns of prose — "Retained
/// in accordance with applicable tax and accounting laws" is a cell — and four
/// columns of prose on a 360dp phone is four words per line and a horizontal
/// scrollbar. One card per row, with the header text as the label for each
/// value, says the same thing and fits.
class _Table extends StatelessWidget {
  const _Table({
    required this.headers,
    required this.rows,
    required this.zc,
    required this.t,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final ZopiqColors zc;
  final TextTheme t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: ZopiqSpacing.xs,
        bottom: ZopiqSpacing.md,
      ),
      child: Column(
        children: <Widget>[
          for (final List<String> row in rows)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
              padding: const EdgeInsets.all(ZopiqSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: ZopiqRadii.rMd,
                border: Border.all(color: zc.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int c = 0; c < row.length; c++) ...<Widget>[
                    if (c > 0) const SizedBox(height: ZopiqSpacing.sm),
                    // The first cell is the row's subject — the data category,
                    // the metric — so it gets to be the heading rather than a
                    // labelled field like the rest.
                    if (c == 0)
                      Text(
                        row[c],
                        style: t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else ...<Widget>[
                      if (c < headers.length && headers[c].isNotEmpty)
                        Text(
                          headers[c],
                          style: t.labelSmall?.copyWith(
                            color: zc.textMuted,
                            letterSpacing: 0.3,
                          ),
                        ),
                      Text(
                        row[c],
                        style: t.bodySmall?.copyWith(
                          color: zc.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A slug that resolves to nothing — a stale deep link, or a document that was
/// withdrawn. Says so, rather than showing an empty page that looks broken.
class _NotFound extends StatelessWidget {
  const _NotFound({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          child: Text(
            'There is no document called "$slug". It may have been replaced — '
            'the current documents are listed under Legal & policies.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.zc.textMuted),
          ),
        ),
      ),
    );
  }
}
