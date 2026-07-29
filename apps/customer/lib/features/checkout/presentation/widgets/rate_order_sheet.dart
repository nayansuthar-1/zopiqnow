import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_review.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';

/// Rates a delivered order: the food, and — when somebody actually carried it —
/// the rider, separately.
///
/// **Two rows of stars, not one.** Food and delivery are two different people's
/// work, and a single score blames a kitchen for a slow bike or a rider for a
/// cold curry. The rider row is absent entirely when [state] says nobody carried
/// the order, rather than shown greyed: a disabled control asks a question it
/// then refuses to hear the answer to.
///
/// **The rider's row is optional even when it is shown.** A customer who wants
/// to rate the food and leave the person alone can. Null is a real answer and
/// migration 0062 stores it as one — it is not a zero, which would drag a
/// rider's average down for an opinion nobody offered.
///
/// [initialFood] is the star the customer tapped on the receipt to get here, so
/// the commonest rating costs one tap and a confirm rather than three taps and
/// a hunt. It is ignored when [existing] is present — an edit opens on what was
/// actually said.
Future<void> showRateOrderSheet(
  BuildContext context, {
  required String orderId,
  required OrderReviewState state,
  OrderReview? existing,
  int initialFood = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) => _RateOrderSheet(
      orderId: orderId,
      state: state,
      existing: existing,
      initialFood: initialFood,
    ),
  );
}

class _RateOrderSheet extends ConsumerStatefulWidget {
  const _RateOrderSheet({
    required this.orderId,
    required this.state,
    required this.initialFood,
    this.existing,
  });

  final String orderId;
  final OrderReviewState state;
  final OrderReview? existing;
  final int initialFood;

  @override
  ConsumerState<_RateOrderSheet> createState() => _RateOrderSheetState();
}

class _RateOrderSheetState extends ConsumerState<_RateOrderSheet> {
  late int _food = widget.existing?.foodRating ?? widget.initialFood;
  late int? _rider = widget.existing?.riderRating;
  late final TextEditingController _comment = TextEditingController(
    text: widget.existing?.comment ?? '',
  );

  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // The one check worth making on the phone, because it is about the form and
    // not about the rules: there is nothing to send yet. Everything else — the
    // window, the ownership, the range — is answered by the database, and its
    // sentence is what lands in [_error].
    if (_food == 0) {
      setState(() => _error = 'Tap a star to rate your food.');
      return;
    }

    final String? failure = await ref
        .read(orderReviewControllerProvider.notifier)
        .submit(
          orderId: widget.orderId,
          foodRating: _food,
          riderRating: _rider,
          comment: _comment.text,
        );

    if (!mounted) return;
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Thanks for the rating.')));
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isSaving = ref.watch(orderReviewControllerProvider);
    final bool isEdit = widget.existing != null;

    return Padding(
      // The keyboard, when the comment field has focus.
      padding: EdgeInsets.only(
        left: ZopiqSpacing.lg,
        right: ZopiqSpacing.lg,
        top: ZopiqSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + ZopiqSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: zc.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(
              isEdit ? 'Change your rating' : 'How was your order?',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              isEdit
                  ? 'You can change this for an hour after you first rate it.'
                  : 'Your rating is what the next customer sees on this restaurant.',
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.lg),

            _StarRow(
              label: 'The food',
              value: _food,
              onChanged: (int v) => setState(() {
                _food = v;
                _error = null;
              }),
            ),

            if (widget.state.hasRider) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.md),
              _StarRow(
                label: widget.state.riderName == null
                    ? 'The delivery'
                    : 'Delivery by ${widget.state.riderName}',
                value: _rider ?? 0,
                // Tapping the star you already gave clears it. That is how a
                // customer takes back an opinion about a person without having
                // to leave a lower one.
                onChanged: (int v) =>
                    setState(() => _rider = _rider == v ? null : v),
              ),
            ],

            const SizedBox(height: ZopiqSpacing.lg),
            TextField(
              controller: _comment,
              maxLength: 500,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Anything you want to say? (optional)',
                isDense: true,
              ),
            ),

            if (_error case final String message) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.sm),
              Text(
                message,
                style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: ZopiqSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: isSaving ? null : _save,
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isEdit ? 'Save changes' : 'Submit rating'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Five stars and a label. [value] of 0 means unrated, which is why the row
/// renders outlines rather than an empty gap — a customer has to be able to see
/// where to tap.
class _StarRow extends StatelessWidget {
  const _StarRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Row(
          children: <Widget>[
            for (int star = 1; star <= 5; star++)
              IconButton(
                onPressed: () => onChanged(star),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                constraints: const BoxConstraints(),
                tooltip: '$star',
                icon: Icon(
                  star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 34,
                  color: star <= value ? zc.rating : zc.textMuted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
