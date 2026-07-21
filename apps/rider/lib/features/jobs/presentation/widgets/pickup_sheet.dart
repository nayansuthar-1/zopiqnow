import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Four digits, read aloud across a counter.
///
/// The direction matters and is worth restating where somebody will read it: the
/// *restaurant* is shown the code and the *rider* types it. A rider who can
/// produce these digits is standing in that shop. The other way round would
/// prove only that the rider can read their own screen.
///
/// Pops the code, or null if the rider backs out. It does not verify anything —
/// `confirm_pickup` in Postgres is the only thing that knows the right answer,
/// and it is the only thing that should.
class PickupSheet extends StatefulWidget {
  const PickupSheet({required this.restaurantName, super.key});

  final String restaurantName;

  @override
  State<PickupSheet> createState() => _PickupSheetState();
}

class _PickupSheetState extends State<PickupSheet> {
  final TextEditingController _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final String code = _code.text.trim();
    if (code.length != 4) {
      setState(() => _error = 'The code is 4 digits.');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      // Clears the keyboard, which on this sheet is always up.
      padding: EdgeInsets.only(
        left: ZopiqSpacing.xl,
        right: ZopiqSpacing.xl,
        top: ZopiqSpacing.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + ZopiqSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Pickup code', style: t.titleLarge),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            'Ask ${widget.restaurantName} for the 4-digit code on their screen.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            style: t.headlineSmall?.copyWith(letterSpacing: 8),
            decoration: InputDecoration(
              hintText: '0000',
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          ZopiqButton(
            label: 'Confirm pickup',
            variant: ZopiqButtonVariant.cta,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
