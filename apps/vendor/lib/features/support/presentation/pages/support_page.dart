import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// Where a kitchen goes when something is wrong.
///
/// Two things, in the order a restaurant needs them. First the answers it can
/// find itself — the handful of questions support actually gets — so the common
/// case never becomes an email. Then the way to reach a person, with the one
/// thing that person will ask for (the restaurant's id) already on screen.
class SupportPage extends ConsumerWidget {
  const SupportPage({super.key});

  static const String _supportEmail = 'partners@zopiqnow.com';
  static const String _supportPhone = '+91 80 4718 0000';

  static const List<({String q, String a})> _faqs = <({String q, String a})>[
    (
      q: 'When do I get paid?',
      a: 'Delivered orders are rolled up every Monday into a weekly '
          'settlement — food value less commission. Open Payments to see each '
          'payout and the orders inside it.',
    ),
    (
      q: 'How do I turn orders off for a while?',
      a: 'Use the accepting-orders switch on Home or the queue to pause. For a '
          'standing weekly schedule — closed Mondays, breakfast only — set your '
          'Opening hours instead. Customers can only order while you\'re open.',
    ),
    (
      q: 'Can I decline an order?',
      a: 'Yes. A new order can be rejected with a reason before you accept it. '
          'Once the rider is on the way it can no longer be cancelled.',
    ),
    (
      q: 'Why is a dish not showing to customers?',
      a: 'A dish is hidden if it\'s marked unavailable, or if its whole section '
          'is switched off. Check both in Menu.',
    ),
    (
      q: 'A payout looks wrong. What do I do?',
      a: 'Open the settlement in Payments to see every order in it. If a figure '
          'still looks off, email us with the settlement week and we\'ll check.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vendor? vendor = ref.watch(vendorProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
        children: <Widget>[
          Text(
            'Common questions',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          ZopiqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < _faqs.length; i++) ...<Widget>[
                  _FaqTile(question: _faqs[i].q, answer: _faqs[i].a),
                  if (i < _faqs.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xl),
          Text(
            'Still need help?',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          ZopiqCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _ContactLine(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: _supportEmail,
                ),
                const SizedBox(height: ZopiqSpacing.md),
                const _ContactLine(
                  icon: Icons.call_outlined,
                  label: 'Phone',
                  value: _supportPhone,
                ),
                if (vendor != null) ...<Widget>[
                  const SizedBox(height: ZopiqSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: ZopiqSpacing.md),
                  Text(
                    'Your restaurant ID',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  SelectableText(
                    vendor.restaurantId,
                    style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: zc.textStrong,
                    ),
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    'Quote this when you write to us — it\'s the fastest way for '
                    'support to find your kitchen.',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One question, tap to open its answer.
class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Theme(
      // The card supplies the divider; the tile should not draw its own.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.md,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          ZopiqSpacing.md,
          0,
          ZopiqSpacing.md,
          ZopiqSpacing.md,
        ),
        iconColor: zc.textMuted,
        collapsedIconColor: zc.textMuted,
        title: Text(
          question,
          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: t.bodyMedium?.copyWith(color: zc.textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Icon(icon, color: zc.primary, size: 22),
        const SizedBox(width: ZopiqSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: t.bodySmall?.copyWith(color: zc.textMuted)),
            const SizedBox(height: ZopiqSpacing.xxs),
            SelectableText(
              value,
              style: t.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: zc.textStrong,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
