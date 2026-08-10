import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';
import 'package:zopiq_uploads/zopiq_uploads.dart';

import 'package:zopiq_vendor/core/images/image_uploader.dart';

/// Marking an order ready is the moment the food stops being the kitchen's
/// problem, and it is the last moment anyone at the restaurant can be asked
/// anything. So it is where the photograph is taken: the sealed bag that goes to
/// the rider.
///
/// **One photograph, not two.** This sheet used to ask for the dish off the pass
/// as well. The bag is the one that survives, because it is the thing that
/// actually exists at the instant a cook taps *Mark ready* — by then the food is
/// packed, and asking for a picture of it as it came off the pass is asking to
/// unseal a bag or to photograph a memory. A second tile also cost the sheet
/// twice the camera round-trips at the busiest minute in a kitchen's evening,
/// which is how a proof photo turns into a thing people learn to fake.
///
/// Returns the URL, or null if the cook backs out — in which case the order
/// stays in `preparing` and nothing is written.
Future<String?> showKitchenPhotos(BuildContext context, String orderId) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // The upload takes as long as it takes, and a cook who swipes the sheet away
    // mid-upload loses a photo they have already taken. Backing out is the
    // Cancel button, which is honest about what it does.
    isDismissible: false,
    enableDrag: false,
    builder: (BuildContext context) => _PhotosSheet(orderId: orderId),
  );
}

class _PhotosSheet extends ConsumerStatefulWidget {
  const _PhotosSheet({required this.orderId});

  final String orderId;

  @override
  ConsumerState<_PhotosSheet> createState() => _PhotosSheetState();
}

class _PhotosSheetState extends ConsumerState<_PhotosSheet> {
  String _packed = '';

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final ImageUploader uploader = ref.watch(imageUploaderProvider);

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
                'Ready for pickup — order ${widget.orderId}',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'One photo of the sealed bag before this goes to a rider. It is '
                'how a complaint about the wrong or missing food gets settled.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.lg),

              ProofPhotoField(
                uploader: uploader,
                label: 'Bag packed',
                imageUrl: _packed,
                onChanged: (String url) => setState(() => _packed = url),
              ),
              const SizedBox(height: ZopiqSpacing.xl),

              Row(
                children: <Widget>[
                  Expanded(
                    child: ZopiqButton(
                      label: 'Cancel',
                      variant: ZopiqButtonVariant.outline,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: ZopiqSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: ZopiqButton(
                      label: 'Mark ready',
                      variant: ZopiqButtonVariant.cta,
                      // The gate. Disabled until the upload has returned a URL —
                      // the database will accept the move without it (0094
                      // §"the gate is deliberately in the apps"), and this is
                      // the pressure that stops it happening.
                      onPressed: _packed.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(_packed),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
