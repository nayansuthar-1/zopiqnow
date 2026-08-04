import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_uploads/src/image_uploader.dart';

/// One photograph that has to be taken before something can happen: the food
/// off the pass, the sealed bag, the handover at the door.
///
/// Deliberately not [PhotoField]'s sibling in the vendor app. That one edits a
/// dish's picture — an optional field on a form the vendor saves as a whole, and
/// a gallery pick is exactly right for it. This one is evidence: it is taken at
/// a moment, it gates a button, and it asks where the picture came from rather
/// than assuming.
///
/// Takes an [ImageUploader] rather than reading a provider, so the package stays
/// free of Riverpod and each app wires its own.
class ProofPhotoField extends StatefulWidget {
  const ProofPhotoField({
    required this.uploader,
    required this.label,
    required this.imageUrl,
    required this.onChanged,
    this.height = 150,
    super.key,
  });

  final ImageUploader uploader;

  /// What this photograph is of — "Food cooked", "Bag packed", "Handover".
  final String label;

  /// The URL already uploaded, or empty.
  final String imageUrl;

  /// Fired with the new URL once the upload lands. Never fired with an empty
  /// string: a failed or abandoned pick leaves whatever was there.
  final ValueChanged<String> onChanged;

  final double height;

  @override
  State<ProofPhotoField> createState() => _ProofPhotoFieldState();
}

class _ProofPhotoFieldState extends State<ProofPhotoField> {
  bool _uploading = false;

  Future<void> _start() async {
    if (_uploading) return;

    final PhotoSource? source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Camera first, and it is the one that belongs here — a photograph
            // taken now is the only kind that proves anything. The gallery stays
            // because a refused camera permission must not be a dead end, and
            // because a phone that has just crashed out of the camera still has
            // the shot in its roll.
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final String? url = await widget.uploader.pickAndUpload(source: source);
      if (url != null) widget.onChanged(url);
    } on ImageUploadFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool hasImage = widget.imageUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // A tick that fills in is the whole status report: the button below
            // is waiting on these, and this says which one is still missing
            // without a sentence about it.
            Icon(
              hasImage
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: hasImage ? zc.veg : zc.textMuted,
            ),
            const SizedBox(width: ZopiqSpacing.xs),
            Text(
              widget.label,
              style: t.labelLarge?.copyWith(
                color: hasImage ? zc.textStrong : zc.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        InkWell(
          borderRadius: ZopiqRadii.rMd,
          onTap: _start,
          child: Container(
            height: widget.height,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: zc.shimmerBase,
              borderRadius: ZopiqRadii.rMd,
              border: Border.all(
                color: hasImage ? zc.veg : zc.divider,
                width: hasImage ? 1.5 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (hasImage)
                  ZopiqNetworkImage(
                    url: widget.imageUrl,
                    fallback: _Prompt(
                      zc: zc,
                      t: t,
                      label: 'Photo unavailable — tap to retake',
                    ),
                  )
                else
                  _Prompt(zc: zc, t: t, label: 'Tap to add'),

                if (_uploading)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Center(child: ZopiqLoader(color: Colors.white)),
                  )
                else if (hasImage)
                  Positioned(
                    right: ZopiqSpacing.sm,
                    bottom: ZopiqSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZopiqSpacing.md,
                        vertical: ZopiqSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: ZopiqRadii.rPill,
                      ),
                      child: Text(
                        'Retake',
                        style: t.labelMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.zc, required this.t, required this.label});

  final ZopiqColors zc;
  final TextTheme t;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.add_a_photo_rounded, size: 28, color: zc.textMuted),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(label, style: t.bodySmall?.copyWith(color: zc.textMuted)),
        ],
      ),
    );
  }
}
