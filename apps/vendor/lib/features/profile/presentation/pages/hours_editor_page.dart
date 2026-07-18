import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/vendor_message.dart';
import 'package:zopiq_vendor/features/profile/domain/entities/opening_hours.dart';
import 'package:zopiq_vendor/features/profile/presentation/providers/hours_providers.dart';

/// When the kitchen is open, one row a day.
///
/// A schedule, not the live pause — that switch lives on Home and the queue. This
/// is the standing week: a day toggled off is closed, a day on has an opening and
/// a closing time. An empty week is "always open", which is exactly what every
/// restaurant that never opens this screen already is.
class HoursEditorPage extends ConsumerStatefulWidget {
  const HoursEditorPage({super.key});

  @override
  ConsumerState<HoursEditorPage> createState() => _HoursEditorPageState();
}

class _HoursEditorPageState extends ConsumerState<HoursEditorPage> {
  static const List<String> _dayNames = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  /// The default a day gets the moment it is switched on: 9 AM to 11 PM.
  static const TimeOfDay _defaultOpen = TimeOfDay(hour: 9, minute: 0);
  static const TimeOfDay _defaultClose = TimeOfDay(hour: 23, minute: 0);

  /// One editable row per weekday, indexed 0 (Monday) … 6 (Sunday).
  final List<_DayDraft> _days = <_DayDraft>[
    for (int i = 0; i < 7; i++)
      const _DayDraft(open: false, opens: _defaultOpen, closes: _defaultClose),
  ];

  bool _seeded = false;
  bool _saving = false;
  String? _error;

  void _seed(List<OpeningHours> hours) {
    for (final OpeningHours h in hours) {
      final int i = h.weekday - 1;
      if (i < 0 || i > 6) continue;
      _days[i] = _DayDraft(
        open: true,
        opens: _toTime(h.opensMinutes),
        closes: _toTime(h.closesMinutes),
      );
    }
    _seeded = true;
  }

  Future<void> _pick(int index, {required bool opening}) async {
    final _DayDraft day = _days[index];
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: opening ? day.opens : day.closes,
    );
    if (picked == null) return;
    setState(() {
      _days[index] = opening ? day.copyWith(opens: picked) : day.copyWith(closes: picked);
      _error = null;
    });
  }

  Future<void> _save() async {
    // Every open day must close after it opens — the same rule the database's
    // `closes > opens` check enforces, said here as a sentence.
    for (int i = 0; i < 7; i++) {
      final _DayDraft d = _days[i];
      if (d.open && _minutes(d.closes) <= _minutes(d.opens)) {
        setState(() => _error = '${_dayNames[i]} closes before it opens.');
        return;
      }
    }

    final List<OpeningHours> hours = <OpeningHours>[
      for (int i = 0; i < 7; i++)
        if (_days[i].open)
          OpeningHours(
            weekday: i + 1,
            opensMinutes: _minutes(_days[i].opens),
            closesMinutes: _minutes(_days[i].closes),
          ),
    ];

    setState(() {
      _saving = true;
      _error = null;
    });
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final String? failure = await ref
        .read(hoursControllerProvider.notifier)
        .save(hours);
    if (!mounted) return;
    if (failure == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Hours saved.')));
      navigator.pop();
    } else {
      setState(() {
        _saving = false;
        _error = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<OpeningHours>> hours = ref.watch(
      restaurantHoursProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Opening hours')),
      body: hours.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace _) => VendorMessage(
          icon: Icons.cloud_off_rounded,
          title: 'We couldn\'t load your hours',
          body: 'Check the internet and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(restaurantHoursProvider),
        ),
        data: (List<OpeningHours> data) {
          if (!_seeded) _seed(data);
          return _Editor(
            days: _days,
            dayNames: _dayNames,
            saving: _saving,
            error: _error,
            onToggle: (int i, bool open) =>
                setState(() => _days[i] = _days[i].copyWith(open: open)),
            onPickOpen: (int i) => _pick(i, opening: true),
            onPickClose: (int i) => _pick(i, opening: false),
            onSave: _save,
          );
        },
      ),
    );
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;
  static TimeOfDay _toTime(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.days,
    required this.dayNames,
    required this.saving,
    required this.error,
    required this.onToggle,
    required this.onPickOpen,
    required this.onPickClose,
    required this.onSave,
  });

  final List<_DayDraft> days;
  final List<String> dayNames;
  final bool saving;
  final String? error;
  final void Function(int, bool) onToggle;
  final void Function(int) onPickOpen;
  final void Function(int) onPickClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
      children: <Widget>[
        Text(
          'Customers can only order while you\'re open. Leave a day off to stay '
          'closed all day; an empty week means always open.',
          style: t.bodySmall?.copyWith(color: zc.textMuted),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        for (int i = 0; i < 7; i++) ...<Widget>[
          _DayRow(
            name: dayNames[i],
            day: days[i],
            onToggle: (bool v) => onToggle(i, v),
            onPickOpen: () => onPickOpen(i),
            onPickClose: () => onPickClose(i),
          ),
          if (i < 6) const Divider(height: 1),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: ZopiqSpacing.md),
          Text(error!, style: t.bodySmall?.copyWith(color: zc.nonVeg)),
        ],
        const SizedBox(height: ZopiqSpacing.xl),
        ZopiqButton(
          label: 'Save hours',
          variant: ZopiqButtonVariant.cta,
          isLoading: saving,
          onPressed: onSave,
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.name,
    required this.day,
    required this.onToggle,
    required this.onPickOpen,
    required this.onPickClose,
  });

  final String name;
  final _DayDraft day;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              name,
              style: t.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: day.open ? zc.textStrong : zc.textMuted,
              ),
            ),
          ),
          Expanded(
            child: day.open
                ? Row(
                    children: <Widget>[
                      _TimeChip(label: day.opens.format(context), onTap: onPickOpen),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZopiqSpacing.sm,
                        ),
                        child: Text('–', style: t.bodyMedium),
                      ),
                      _TimeChip(label: day.closes.format(context), onTap: onPickClose),
                    ],
                  )
                : Text(
                    'Closed',
                    style: t.bodyMedium?.copyWith(color: zc.textMuted),
                  ),
          ),
          Switch(
            value: day.open,
            activeTrackColor: zc.veg,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    return InkWell(
      borderRadius: ZopiqRadii.rSm,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.md,
          vertical: ZopiqSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: zc.primary.withValues(alpha: 0.10),
          borderRadius: ZopiqRadii.rSm,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: zc.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One weekday's editable state. A closed day keeps its last-used times so
/// switching it back on doesn't wipe them.
@immutable
class _DayDraft {
  const _DayDraft({
    required this.open,
    required this.opens,
    required this.closes,
  });

  final bool open;
  final TimeOfDay opens;
  final TimeOfDay closes;

  _DayDraft copyWith({bool? open, TimeOfDay? opens, TimeOfDay? closes}) =>
      _DayDraft(
        open: open ?? this.open,
        opens: opens ?? this.opens,
        closes: closes ?? this.closes,
      );
}
