import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Why the customer is calling the order off — asked as a bottom sheet with the
/// four reasons people actually give, plus a confirm.
///
/// Returns the chosen reason, `''` when confirmed with no reason, or **null**
/// when the sheet is dismissed — which the caller reads as "changed my mind,
/// leave the order alone". The distinction matters: `''` is a cancellation, and
/// null is not.
///
/// The reason is optional on purpose. Making it mandatory would buy the platform
/// a tidier report and cost the customer a form standing between them and a
/// mistake they are trying to undo; anyone in a hurry picks the first option in
/// the list, and the report is then tidy and wrong.
///
/// Every reason here is written third-person, because `status_reason` has one
/// column and two readers: the customer sees it on their own receipt, and the
/// kitchen sees it on its history ticket.
Future<String?> showCancelOrderSheet(BuildContext context, String orderId) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _CancelOrderSheet(orderId: orderId),
  );
}

class _CancelOrderSheet extends StatefulWidget {
  const _CancelOrderSheet({required this.orderId});

  final String orderId;

  static const List<String> _reasons = <String>[
    'Ordered by mistake',
    'Changed my mind',
    'Wrong delivery address',
    'It\'s taking too long',
  ];

  @override
  State<_CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends State<_CancelOrderSheet> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZopiqSpacing.pageGutter,
          0,
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Cancel order ${widget.orderId}?',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              'The restaurant will be told. This can\'t be undone — you\'d have '
              'to place the order again.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.lg),

            for (final String reason in _CancelOrderSheet._reasons)
              _ReasonRow(
                label: reason,
                selected: _selected == reason,
                onTap: () => setState(
                  () => _selected = _selected == reason ? null : reason,
                ),
              ),

            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: 'Cancel order',
              variant: ZopiqButtonVariant.primary,
              onPressed: () => Navigator.pop(context, _selected ?? ''),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep my order'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable reason: a tappable row with a check when chosen.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: Material(
        color: selected
            ? zc.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: ZopiqRadii.rMd,
          side: BorderSide(color: selected ? zc.primary : zc.divider),
        ),
        child: InkWell(
          borderRadius: ZopiqRadii.rMd,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.md,
              vertical: ZopiqSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: t.bodyLarge?.copyWith(
                      color: selected ? zc.textStrong : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 22,
                  color: selected ? zc.primary : zc.divider,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
