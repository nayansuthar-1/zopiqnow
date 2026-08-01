import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/account/domain/legal_documents.dart';

/// The privacy policy and the terms, rendered in the app.
///
/// In the app and not a link to a website, deliberately. A policy behind a
/// browser hand-off is a policy that is unreadable on a bad connection, breaks
/// when a URL moves, and cannot be found at all by somebody on a train. The web
/// copies still exist — Play requires one that works without installing
/// anything — and they are generated from the same text this screen reads, so
/// there is no second version to keep in step.
class LegalPage extends StatelessWidget {
  const LegalPage({required this.document, super.key});

  /// `privacy` or `terms`.
  final String document;

  @override
  Widget build(BuildContext context) {
    final LegalDocument doc = legalDocuments[document] ?? privacyPolicy;
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
        children: <Widget>[
          Text(
            doc.preamble,
            style: t.bodyMedium?.copyWith(color: zc.textMuted, height: 1.5),
          ),
          const SizedBox(height: ZopiqSpacing.xl),
          for (final LegalSection section in doc.sections) ...<Widget>[
            Text(
              section.heading,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            for (final String paragraph in section.paragraphs) ...<Widget>[
              Text(
                paragraph,
                style: t.bodyMedium?.copyWith(color: zc.textMuted, height: 1.5),
              ),
              const SizedBox(height: ZopiqSpacing.sm),
            ],
            for (final String bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
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
                        bullet,
                        style: t.bodyMedium?.copyWith(
                          color: zc.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: ZopiqSpacing.lg),
          ],
          const SizedBox(height: ZopiqSpacing.xl),
        ],
      ),
    );
  }
}
