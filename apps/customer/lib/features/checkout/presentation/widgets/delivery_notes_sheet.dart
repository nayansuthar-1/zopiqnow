import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';

/// What the rider should know about this door, for this order.
///
/// Prefilled from the selected address's saved note, and saved back only to
/// *this* order — "the lift is out today" is not a fact about where you live, so
/// it does not rewrite the address book. Editing the saved note is the address
/// form's job, and the sheet says where to find it.
Future<void> showDeliveryNotesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.xl)),
    ),
    builder: (_) => const DeliveryNotesSheet(),
  );
}

class DeliveryNotesSheet extends ConsumerStatefulWidget {
  const DeliveryNotesSheet({super.key});

  @override
  ConsumerState<DeliveryNotesSheet> createState() => _DeliveryNotesSheetState();
}

class _DeliveryNotesSheetState extends ConsumerState<DeliveryNotesSheet> {
  late final TextEditingController _controller;

  /// The cap the column carries (0061). Enforced here as a counter rather than
  /// a refusal — a note that runs long is trimmed by the server, and being told
  /// so while typing beats discovering it afterwards.
  static const int _maxLength = 160;

  @override
  void initState() {
    super.initState();
    // `read`, not `watch`: this is the field's starting text, and rebinding it
    // under the cursor because something upstream moved would be maddening.
    _controller = TextEditingController(
      text: ref.read(deliveryNotesProvider) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(deliveryNotesProvider.notifier).set(_controller.text);
    Navigator.of(context).pop();
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
          Text('Note for the rider', style: t.titleLarge),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            'Gate number, landmark, which floor — anything that saves them a '
            'phone call.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: _maxLength,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Gate 2, blue building. Ring the bell twice.',
              border: OutlineInputBorder(borderRadius: ZopiqRadii.rMd),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            'This applies to this order. To keep it for every order to this '
            'address, edit the address in your address book.',
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          // Always enabled: clearing the field and saving is how a note is
          // removed, and a button that refuses an empty box would trap it.
          ZopiqButton(
            label: 'Save',
            variant: ZopiqButtonVariant.cta,
            expand: true,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
