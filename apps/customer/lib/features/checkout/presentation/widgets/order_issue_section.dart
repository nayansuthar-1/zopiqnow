import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';

/// What the customer already told us about this order (migrations 0095, 0114).
///
/// It exists for one reason: somebody who has complained wants to know the
/// complaint landed. Without this the report sheet takes a tap, closes, and
/// leaves the receipt looking exactly as it did — which reads as "nothing
/// happened" and produces a second complaint about the first one.
///
/// Renders nothing when there is none, which is almost every order, and nothing
/// while the read is in flight, so a receipt does not jump. There is nothing to
/// tap: raising one is the "Get help" button's job, and answering one is not the
/// customer's.
///
/// **Takes the list rather than fetching it**, because a food order and a gift
/// order read two different functions (`my_order_issues`, `my_gift_order_issues`)
/// and a complaint looks identical either way. The caller watches its own
/// provider; this draws whatever it is handed.
class OrderIssueSection extends StatelessWidget {
  const OrderIssueSection({required this.issues, super.key});

  final List<OrderIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();

    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          issues.length == 1 ? 'REPORTED' : 'REPORTED ISSUES',
          style: t.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.8,
            color: isDark ? Colors.white54 : const Color(0xFF888888),
          ),
        ),
        const SizedBox(height: 12),
        for (final OrderIssue issue in issues) ...<Widget>[
          _IssueRow(issue: issue),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        Divider(
          height: 1,
          thickness: 1,
          color: isDark ? Colors.white12 : const Color(0xFFEEEEEE),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});

  final OrderIssue issue;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          issue.isResolved
              ? Icons.check_circle_rounded
              : Icons.schedule_rounded,
          size: 18,
          color: issue.isResolved ? zc.veg : zc.textMuted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                issue.category.label,
                style: t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF111111),
                ),
              ),
              if (issue.body.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  issue.body,
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                issue.isResolved
                    ? 'Closed'
                    : 'We\'re looking at this',
                style: t.labelSmall?.copyWith(
                  color: issue.isResolved ? zc.veg : zc.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // The answer, when there is one. Shown in full rather than
              // truncated: a reply somebody had to write is the whole reason
              // this section exists, and a customer who has to tap to read it
              // will assume nobody replied.
              if (issue.adminNote case final String note) ...<Widget>[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(ZopiqSpacing.sm),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white10
                        : const Color(0xFFF6F6F6),
                    borderRadius: ZopiqRadii.rSm,
                  ),
                  child: Text(
                    note,
                    style: t.bodySmall?.copyWith(
                      color: isDark ? Colors.white70 : const Color(0xFF444444),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
