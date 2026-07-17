import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Why an order is being turned away — asked as a bottom sheet with a short list
/// of the reasons a kitchen actually gives, plus a confirm.
///
/// Returns the chosen reason on confirm, `''` when confirmed with no reason
/// (only reachable when [reasonRequired] is false), or **null** when the sheet is
/// dismissed — which the caller reads as "changed my mind, do nothing".

/// Declining a *new* order. A reason is required — the customer is owed one, and
/// the restaurant's own reporting later depends on it.
Future<String?> showRejectReason(BuildContext context, String orderId) {
  return _show(
    context,
    title: 'Reject order $orderId?',
    body: 'The customer will be told their order wasn\'t accepted. This can\'t '
        'be undone.',
    confirmLabel: 'Reject order',
    reasons: const <String>[
      'Too many orders right now',
      'Items unavailable',
      'Kitchen closed',
      'Other',
    ],
    reasonRequired: true,
  );
}

/// Calling off an order already accepted. A reason helps but is not forced — the
/// kitchen may just need it gone.
Future<String?> showCancelReason(BuildContext context, String orderId) {
  return _show(
    context,
    title: 'Cancel order $orderId?',
    body: 'The customer will be told and, for a paid order, refunded. This '
        'can\'t be undone.',
    confirmLabel: 'Cancel order',
    reasons: const <String>[
      'Items ran out',
      'Kitchen issue',
      'Customer requested',
      'Other',
    ],
    reasonRequired: false,
  );
}

Future<String?> _show(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required List<String> reasons,
  required bool reasonRequired,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _ReasonSheet(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      reasons: reasons,
      reasonRequired: reasonRequired,
    ),
  );
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.reasons,
    required this.reasonRequired,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final List<String> reasons;
  final bool reasonRequired;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool canConfirm = !widget.reasonRequired || _selected != null;

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
              widget.title,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(widget.body, style: t.bodyMedium?.copyWith(color: zc.textMuted)),
            const SizedBox(height: ZopiqSpacing.lg),

            for (final String reason in widget.reasons)
              _ReasonRow(
                label: reason,
                selected: _selected == reason,
                onTap: () => setState(
                  () => _selected = _selected == reason ? null : reason,
                ),
              ),

            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: widget.confirmLabel,
              variant: ZopiqButtonVariant.primary,
              onPressed: canConfirm
                  ? () => Navigator.pop(context, _selected ?? '')
                  : null,
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep it'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable reason: a tappable row with a check when chosen. A tinted
/// border, not a filled block — the sheet stays calm.
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
        color: selected ? zc.primary.withValues(alpha: 0.06) : Colors.transparent,
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
