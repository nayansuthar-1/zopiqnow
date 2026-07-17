import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Accepting an order is also a promise about when. This asks the one question
/// the kitchen answers at that moment — how long until it's ready — and hands
/// back the chosen minutes, or null if the cook backs out.
///
/// A default is pre-selected so the common case is a single tap: glance, accept.
Future<int?> showPrepTime(BuildContext context, String orderId) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _PrepSheet(orderId: orderId),
  );
}

class _PrepSheet extends StatefulWidget {
  const _PrepSheet({required this.orderId});

  final String orderId;

  @override
  State<_PrepSheet> createState() => _PrepSheetState();
}

class _PrepSheetState extends State<_PrepSheet> {
  // The minutes a kitchen actually quotes. 20 is the sensible default.
  static const List<int> _options = <int>[10, 15, 20, 30, 45];
  int _selected = 20;

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
              'Accept order ${widget.orderId}?',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              'How long until it\'s ready? The ticket will count down to it.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.lg),

            Wrap(
              spacing: ZopiqSpacing.sm,
              runSpacing: ZopiqSpacing.sm,
              children: <Widget>[
                for (final int minutes in _options)
                  _MinuteChip(
                    minutes: minutes,
                    selected: minutes == _selected,
                    onTap: () => setState(() => _selected = minutes),
                  ),
              ],
            ),

            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: 'Accept · ready in $_selected min',
              variant: ZopiqButtonVariant.cta,
              onPressed: () => Navigator.pop(context, _selected),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinuteChip extends StatelessWidget {
  const _MinuteChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Material(
      color: selected ? zc.primary : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: ZopiqRadii.rMd,
        side: BorderSide(color: selected ? zc.primary : zc.divider),
      ),
      child: InkWell(
        borderRadius: ZopiqRadii.rMd,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.lg,
            vertical: ZopiqSpacing.md,
          ),
          child: Text(
            '$minutes min',
            style: t.titleSmall?.copyWith(
              color: selected ? Colors.white : zc.textStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
