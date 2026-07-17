import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/images/image_uploader.dart';

/// A tappable photo well: shows the current image, or a prompt to add one, and
/// runs the pick-and-upload when tapped. Reports the new URL up through
/// [onChanged] — it does not save anything itself, because the photo is one field
/// of a form the vendor saves as a whole.
///
/// Shared by the dish editor and the restaurant profile: the only difference is
/// the shape, so that is the only thing the caller sets.
class PhotoField extends ConsumerStatefulWidget {
  const PhotoField({
    required this.imageUrl,
    required this.onChanged,
    this.height = 160,
    super.key,
  });

  final String imageUrl;
  final ValueChanged<String> onChanged;
  final double height;

  @override
  ConsumerState<PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends ConsumerState<PhotoField> {
  bool _uploading = false;

  Future<void> _pick() async {
    if (_uploading) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final String? url = await ref.read(imageUploaderProvider).pickAndUpload();
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

    return InkWell(
      borderRadius: ZopiqRadii.rMd,
      onTap: _pick,
      child: Container(
        height: widget.height,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: zc.shimmerBase,
          borderRadius: ZopiqRadii.rMd,
          border: Border.all(color: zc.divider),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasImage)
              ZopiqNetworkImage(
                url: widget.imageUrl,
                fallback: _Placeholder(zc: zc, t: t, label: 'Photo unavailable'),
              )
            else
              _Placeholder(zc: zc, t: t, label: 'Add a photo'),

            // The "change" affordance over an existing image, and the busy state
            // over either.
            if (_uploading)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.photo_camera_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: ZopiqSpacing.xs),
                      Text(
                        'Change',
                        style: t.labelMedium?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.zc, required this.t, required this.label});

  final ZopiqColors zc;
  final TextTheme t;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.add_a_photo_rounded, size: 32, color: zc.textMuted),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(label, style: t.bodySmall?.copyWith(color: zc.textMuted)),
        ],
      ),
    );
  }
}
