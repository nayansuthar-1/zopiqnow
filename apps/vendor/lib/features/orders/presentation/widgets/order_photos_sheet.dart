import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';
import 'package:zopiq_uploads/zopiq_uploads.dart';

import 'package:zopiq_vendor/core/images/image_uploader.dart';

/// The two photographs the kitchen takes as an order leaves it.
typedef KitchenPhotos = ({String cookedUrl, String packedUrl});

/// Marking an order ready is the moment the food stops being the kitchen's
/// problem, and it is the last moment anyone at the restaurant can be asked
/// anything. So it is where both photographs are taken: the dish as it came off
/// the pass, and the sealed bag that goes to the rider.
///
/// Returns both URLs, or null if the cook backs out — in which case the order
/// stays in `preparing` and nothing is written.
Future<KitchenPhotos?> showKitchenPhotos(BuildContext context, String orderId) {
  return showModalBottomSheet<KitchenPhotos>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // The two uploads take as long as they take, and a cook who swipes the sheet
    // away mid-upload loses a photo they have already taken. Backing out is the
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
  String _cooked = '';
  String _packed = '';

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final ImageUploader uploader = ref.watch(imageUploaderProvider);
    final bool complete = _cooked.isNotEmpty && _packed.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ZopiqSpacing.pageGutter,
          0,
          ZopiqSpacing.pageGutter,
          // Above the keyboard-free bottom inset, and above the sheet's own
          // padding — the two tiles make this the tallest sheet in the app.
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
                'Two photos before this goes to a rider. They are how a '
                'complaint about the wrong or missing food gets settled.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.lg),

              ProofPhotoField(
                uploader: uploader,
                label: 'Food cooked',
                imageUrl: _cooked,
                onChanged: (String url) => setState(() => _cooked = url),
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
                      // The gate. Disabled until both uploads have returned a
                      // URL — the database will accept the move without them
                      // (0094 §"the gate is deliberately in the apps"), and this
                      // is the pressure that stops it happening.
                      onPressed: complete
                          ? () => Navigator.of(context).pop((
                              cookedUrl: _cooked,
                              packedUrl: _packed,
                            ))
                          : null,
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
