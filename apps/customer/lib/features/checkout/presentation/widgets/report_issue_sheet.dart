import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';

/// Files one complaint. Throws [OrderIssueFailure] with the service's own
/// sentence, which is what the sheet renders in place.
typedef IssueSubmit =
    Future<void> Function(IssueCategory category, String? body);

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
///
/// **Two kinds of order share this sheet**, which is why [submit] and
/// [categories] are arguments rather than things it reaches for itself. A food
/// order goes to `raise_order_issue` and may name the rider; a gift goes to
/// `raise_gift_issue` and may not (0114). Everything a complaint *looks* like —
/// the chips, the optional note, the mandatory category, the refusal in place —
/// is the same for both, and a second copy of this file would be two screens
/// that drift the first time one of them is reworded.
Future<bool?> showReportIssueSheet(
  BuildContext context, {
  required String orderId,
  required IssueSubmit submit,
  List<IssueCategory> categories = IssueCategory.forFood,
  String hint = 'The biryani was missing, only the raita arrived.',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _ReportIssueSheet(
      orderId: orderId,
      submit: submit,
      categories: categories,
      hint: hint,
    ),
  );
}

class _ReportIssueSheet extends ConsumerStatefulWidget {
  const _ReportIssueSheet({
    required this.orderId,
    required this.submit,
    required this.categories,
    required this.hint,
  });

  final String orderId;
  final IssueSubmit submit;
  final List<IssueCategory> categories;
  final String hint;

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
      // The caller owns both the call and the invalidation that follows it: the
      // receipt behind this sheet reads its own provider, and only the caller
      // knows which one that is.
      await widget.submit(
        category,
        _body.text.trim().isEmpty ? null : _body.text.trim(),
      );
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
                  for (final IssueCategory c in widget.categories)
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
                decoration: InputDecoration(
                  labelText: 'Anything else? (optional)',
                  hintText: widget.hint,
                  border: const OutlineInputBorder(),
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
