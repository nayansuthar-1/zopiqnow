import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// Converts what the user typed into E.164. India-only today, which is why the
/// prefix is a fixed label and not a country picker.
String toE164(String national) => '+91${national.trim()}';

/// Asks for the number the rider will call.
///
/// Sign-in is by email now, so an account can exist without a phone number — but
/// an order cannot be delivered without one. This is the one place that gap is
/// closed, and checkout is where it surfaces, because that is where it matters.
Future<void> showDeliveryPhoneSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.xl)),
    ),
    builder: (_) => const DeliveryPhoneSheet(),
  );
}

class DeliveryPhoneSheet extends ConsumerStatefulWidget {
  const DeliveryPhoneSheet({super.key});

  @override
  ConsumerState<DeliveryPhoneSheet> createState() => _DeliveryPhoneSheetState();
}

class _DeliveryPhoneSheetState extends ConsumerState<DeliveryPhoneSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Ten digits **starting 6–9**, which is what an Indian mobile is (0151).
  ///
  /// The length check alone let `1918739985` through, and there is an order in
  /// the live table carrying exactly that — a number the rider can never reach.
  /// `place_order` now refuses the same shape server-side; this is here so the
  /// customer is told at the sheet, where they can still fix it, rather than at
  /// checkout with a full cart behind them.
  static final RegExp _mobile = RegExp(r'^[6-9]\d{9}$');

  bool get _isValid => _mobile.hasMatch(_controller.text.trim());

  Future<void> _save() async {
    if (!_isValid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .setPhone(toE164(_controller.text));
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'We couldn\'t save that. Try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: ZopiqSpacing.pageGutter,
        right: ZopiqSpacing.pageGutter,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom + ZopiqSpacing.pageGutter,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Add a delivery number', style: t.titleLarge),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            'Your rider calls this if they can\'t find you.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            autofillHints: const <String>[AutofillHints.telephoneNumber],
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              prefixText: '+91  ',
              hintText: '98765 43210',
              counterText: '',
              errorText: _error,
              border: const OutlineInputBorder(borderRadius: ZopiqRadii.rMd),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          ZopiqButton(
            label: 'Save',
            variant: ZopiqButtonVariant.cta,
            isLoading: _saving,
            expand: true,
            onPressed: _isValid ? _save : null,
          ),
        ],
      ),
    );
  }
}
