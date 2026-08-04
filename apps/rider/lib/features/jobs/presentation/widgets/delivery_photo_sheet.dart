import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/images/image_uploader.dart';
import 'package:zopiq_rider/core/widgets/rider_animations.dart';

/// The photograph of the handover, taken before the customer reads their code.
///
/// A separate sheet rather than another field on [DeliverySheet], because that
/// sheet's code entry is shared verbatim with the pickup one — a photo tile
/// bolted onto it would appear at the restaurant counter too, where there is
/// nothing to photograph and a rider mid-collection to slow down.
///
/// Returns the uploaded URL, or null if the rider backs out. Backing out costs
/// nothing: the delivery is not written until the code goes in after this.
Future<String?> showDeliveryPhoto(BuildContext context, String deliverTo) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // A swipe-away mid-upload would throw away a photo the rider has already
    // stood there and taken. "Not now" is the way out, and it says so.
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _DeliveryPhotoSheet(deliverTo: deliverTo),
  );
}

class _DeliveryPhotoSheet extends ConsumerStatefulWidget {
  const _DeliveryPhotoSheet({required this.deliverTo});

  final String deliverTo;

  @override
  ConsumerState<_DeliveryPhotoSheet> createState() =>
      _DeliveryPhotoSheetState();
}

class _DeliveryPhotoSheetState extends ConsumerState<_DeliveryPhotoSheet> {
  String _photo = '';

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZopiqRadii.xl),
        ),
      ),
      padding: EdgeInsets.only(
        left: ZopiqSpacing.xl,
        right: ZopiqSpacing.xl,
        top: ZopiqSpacing.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + ZopiqSpacing.xl,
      ),
      child: RiderFadeSlide(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Photo of the handover',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                widget.deliverTo,
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.md),
              Text(
                'The bag at the door, or in the customer\'s hands. This is what '
                'settles a "it never arrived" a week from now.',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.lg),

              ProofPhotoField(
                uploader: ref.watch(imageUploaderProvider),
                label: 'Handover',
                imageUrl: _photo,
                onChanged: (String url) => setState(() => _photo = url),
              ),
              const SizedBox(height: ZopiqSpacing.xl),

              ZopiqButton(
                label: 'Next — customer\'s code',
                variant: ZopiqButtonVariant.cta,
                // The gate. `confirm_delivered` accepts a null photo (0094), so
                // this button is the only thing insisting on one.
                onPressed: _photo.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_photo),
              ),
              const SizedBox(height: ZopiqSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
