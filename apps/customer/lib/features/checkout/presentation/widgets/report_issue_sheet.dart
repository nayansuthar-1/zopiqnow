import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';

/// What went wrong, asked at the one moment somebody is angry enough to say.
///
/// Returns true when a complaint was filed, so the caller can refresh the
/// receipt; null or false when they backed out.
///
/// Two deliberate shapes, both the opposite of the cancel sheet's:
///
///   • The **category is mandatory** and the text is optional. Cancelling is a
///     mistake being undone and a form in front of it is cruelty; a complaint is
///     a thing somebody wants answered, and a queue that cannot be sorted is a
///     queue nobody works. One tap is still the whole cost.
///   • It **submits from here** rather than handing a value back. The refusals
///     ("You have already reported this order.") are written for the customer
///     and belong on the screen that asked, not translated into a bool.
Future<bool?> showReportIssueSheet(BuildContext context, String orderId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _ReportIssueSheet(orderId: orderId),
  );
}

class _ReportIssueSheet extends ConsumerStatefulWidget {
  const _ReportIssueSheet({required this.orderId});

  final String orderId;

  @override
  ConsumerState<_ReportIssueSheet> createState() => _ReportIssueSheetState();
}

class _ReportIssueSheetState extends ConsumerState<_ReportIssueSheet> {
  final TextEditingController _body = TextEditingController();
  IssueCategory? _selected;
  bool _sending = false;
  String? _refusal;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final IssueCategory? category = _selected;
    if (category == null || _sending) return;

    setState(() {
      _sending = true;
      _refusal = null;
    });

    try {
      await ref
          .read(orderRepositoryProvider)
          .raiseIssue(
            orderId: widget.orderId,
            category: category,
            body: _body.text.trim().isEmpty ? null : _body.text.trim(),
          );
      // The receipt reads this to show what was reported, so it has to be stale
      // for no longer than it takes to pop.
      ref.invalidate(orderIssuesProvider(widget.orderId));
      if (mounted) Navigator.of(context).pop(true);
    } on OrderIssueFailure catch (failure) {
      if (mounted) {
        setState(() {
          _sending = false;
          _refusal = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ZopiqSpacing.pageGutter,
          0,
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'What went wrong?',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Order ${widget.orderId}. Somebody will read this and get back '
                'to you — reporting it does not cancel anything or move any '
                'money on its own.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.lg),

              Wrap(
                spacing: ZopiqSpacing.sm,
                runSpacing: ZopiqSpacing.sm,
                children: <Widget>[
                  for (final IssueCategory c in IssueCategory.values)
                    ChoiceChip(
                      label: Text(c.label),
                      selected: _selected == c,
                      onSelected: _sending
                          ? null
                          : (bool picked) =>
                                setState(() => _selected = picked ? c : null),
                    ),
                ],
              ),
              const SizedBox(height: ZopiqSpacing.lg),

              TextField(
                controller: _body,
                enabled: !_sending,
                maxLines: 3,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Anything else? (optional)',
                  hintText: 'The biryani was missing, only the raita arrived.',
                  border: OutlineInputBorder(),
                ),
              ),

              if (_refusal case final String refusal) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.sm),
                Text(
                  refusal,
                  style: t.bodyMedium?.copyWith(color: zc.nonVeg),
                ),
              ],
              const SizedBox(height: ZopiqSpacing.lg),

              ZopiqButton(
                label: 'Report this',
                variant: ZopiqButtonVariant.cta,
                isLoading: _sending,
                // A complaint with no category is not filed. The text box alone
                // would give support a paragraph and no way to sort it.
                onPressed: _selected == null ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
