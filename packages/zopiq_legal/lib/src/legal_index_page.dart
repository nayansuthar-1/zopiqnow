import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_legal/src/legal_document.dart';
import 'package:zopiq_legal/src/registry.dart';

/// Every document that applies to this app's user, grouped.
///
/// Twenty-one rows in one flat list is a filing cabinet, and somebody looking
/// for the refund policy would have to read nineteen titles to find it. So they
/// are bucketed the way somebody actually arrives at them: what they agreed to,
/// what happens to their money, how people are expected to behave, what is done
/// with their data, and where to complain.
///
/// [audience] is what makes one screen serve three apps: a rider does not see
/// the Merchant SLA, and a customer does not see the Delivery Partner
/// Verification Policy.
class LegalIndexPage extends StatelessWidget {
  const LegalIndexPage({
    required this.audience,
    required this.onOpenDocument,
    super.key,
  });

  final LegalAudience audience;

  /// Called with a slug. The app decides what opening a document means, because
  /// the three of them do not all navigate the same way.
  final void Function(String slug) onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final List<({String group, String title, List<LegalDocument> documents})>
    groups = legalIndexFor(audience);

    return Scaffold(
      appBar: AppBar(title: const Text('Legal & policies')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.md,
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.xxl,
        ),
        children: <Widget>[
          for (final (
                group: String _,
                title: String title,
                documents: List<LegalDocument> documents,
              )
              in groups) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(
                top: ZopiqSpacing.lg,
                bottom: ZopiqSpacing.sm,
              ),
              child: Text(
                title,
                style: t.labelLarge?.copyWith(
                  color: zc.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            for (final LegalDocument doc in documents)
              _DocumentRow(doc: doc, onTap: () => onOpenDocument(doc.slug)),
          ],
          const SizedBox(height: ZopiqSpacing.xl),
          Text(
            'All documents are Version 1.0, effective '
            '${allLegalDocuments.first.effectiveDate}. Zopiq is operated by '
            'Hybrid Monks LLP, Sadri, Rajasthan.',
            style: t.bodySmall?.copyWith(color: zc.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.doc, required this.onTap});

  final LegalDocument doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    // The two main documents carry the brand in their title —
                    // "Zopiq Privacy Policy" — which is redundant inside the
                    // Zopiq app and makes both of them sort under Z in a
                    // reader's eye.
                    doc.title.replaceFirst('Zopiq ', ''),
                    style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (doc.subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      doc.subtitle!,
                      style: t.bodySmall?.copyWith(
                        color: zc.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Icon(Icons.chevron_right_rounded, color: zc.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
