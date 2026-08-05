import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart' show CupertinoTimerPicker, CupertinoTimerPickerMode;
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

  /// Whether [_selected] came from the wheel rather than a chip. Only used to
  /// keep the Custom chip lit when the chosen value happens to also be one of
  /// the presets — 30 minutes picked on the wheel is still a considered answer,
  /// and un-highlighting the control the cook just used reads as a rejection.
  bool _isCustom = false;

  /// The wheel. `CupertinoTimerPicker` in `hm` mode is the alarm-setting
  /// gesture — a scrolling drum, not a keyboard — which is what was asked for
  /// and is also the right input for a cook holding a tablet with wet hands.
  ///
  /// Hours as well as minutes because the ceiling has to be somewhere and a
  /// kitchen quoting "an hour and a half" for a party order is a real answer.
  /// Clamped to at least a minute on the way out: a zero-minute promise would
  /// put an order on the counter before anybody has read the ticket.
  Future<void> _pickCustom() async {
    Duration draft = Duration(minutes: _selected);

    final int? minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) {
        final ZopiqColors zc = sheet.zc;
        final TextTheme t = Theme.of(sheet).textTheme;
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
                  'How long do you need?',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                Text(
                  'The customer sees this as their ETA, so quote the time you '
                  'can actually keep.',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
                const SizedBox(height: ZopiqSpacing.md),
                SizedBox(
                  height: 180,
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hm,
                    initialTimerDuration: draft,
                    // One minute, not the default five: the difference between
                    // 12 and 15 minutes is the difference between a rider
                    // waiting and a rider arriving.
                    minuteInterval: 1,
                    onTimerDurationChanged: (Duration d) => draft = d,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.md),
                ZopiqButton(
                  label: 'Use this time',
                  variant: ZopiqButtonVariant.cta,
                  onPressed: () => Navigator.pop(
                    sheet,
                    draft.inMinutes < 1 ? 1 : draft.inMinutes,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (minutes != null && mounted) {
      setState(() {
        _selected = minutes;
        _isCustom = true;
      });
    }
  }

  /// "45 min", "1 h", "1 h 20 min" — a quote long enough to need hours should
  /// not be read as a three-digit pile of minutes on a busy counter.
  static String _spell(int minutes) {
    if (minutes < 60) return '$minutes min';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

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
                    label: '$minutes min',
                    selected: !_isCustom && minutes == _selected,
                    onTap: () => setState(() {
                      _selected = minutes;
                      _isCustom = false;
                    }),
                  ),
                // The escape hatch from five fixed answers. The presets stay
                // first because they are one tap and cover most services; this
                // is for the order that is not most services.
                _MinuteChip(
                  label: _isCustom ? _spell(_selected) : 'Custom…',
                  selected: _isCustom,
                  icon: Icons.schedule_rounded,
                  onTap: () => unawaited(_pickCustom()),
                ),
              ],
            ),

            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: 'Accept · ready in ${_spell(_selected)}',
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
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  /// Already spelled by the caller. The chip renders a quote; it does not decide
  /// how a quote is worded, or the presets and the custom one would disagree
  /// about what 90 minutes is called.
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Only the custom chip has one — it is what distinguishes "pick a time" from
  /// the five answers beside it that *are* times.
  final IconData? icon;

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : zc.textStrong,
                ),
                const SizedBox(width: ZopiqSpacing.xs),
              ],
              Text(
                label,
                style: t.titleSmall?.copyWith(
                  color: selected ? Colors.white : zc.textStrong,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
