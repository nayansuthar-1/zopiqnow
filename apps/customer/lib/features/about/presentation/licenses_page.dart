import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Credits for the third-party assets zopiqnow ships.
///
/// Not optional decoration: the bundled assets (Fluent Emoji under MIT, Figtree
/// under the OFL) ship with notices that belong in the distributed app. This
/// screen is what surfaces them. See ATTRIBUTIONS.md.
class LicensesPage extends StatelessWidget {
  const LicensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Licenses & credits')),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.lg),
        children: <Widget>[
          Text(
            'zopiqnow is built on the work of others. Thank you.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.xl),
          const _Credit(
            title: 'Dish artwork (3D)',
            author: 'Microsoft Fluent Emoji',
            license: 'MIT License',
            detail:
                "Microsoft's open-source 3D emoji set. Used unmodified as "
                'category artwork.',
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          const _Credit(
            title: 'Figtree typeface',
            author: 'Erik Kennedy',
            license: 'SIL Open Font License 1.1',
            detail: 'The typeface used throughout this app.',
          ),
          const SizedBox(height: ZopiqSpacing.xl),
          Divider(color: zc.divider),
          const SizedBox(height: ZopiqSpacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Open-source packages', style: t.titleSmall),
            subtitle: Text(
              'Full licenses for every bundled dependency',
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: zc.textMuted),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'zopiqnow'),
          ),
        ],
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit({
    required this.title,
    required this.author,
    required this.license,
    required this.detail,
  });

  final String title;
  final String author;
  final String license;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: t.titleSmall?.copyWith(color: zc.textMuted)),
          const SizedBox(height: ZopiqSpacing.xxs),
          Text(author, style: t.titleMedium),
          const SizedBox(height: ZopiqSpacing.sm),
          Text(detail, style: t.bodySmall?.copyWith(color: zc.textMuted)),
          const SizedBox(height: ZopiqSpacing.sm),
          Text(license, style: t.labelMedium?.copyWith(color: zc.primary)),
        ],
      ),
    );
  }
}
