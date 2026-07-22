import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';

/// Opens the detail sheet for a gift. A modal sheet rather than a full route:
/// browsing is a light, dip-in-and-out act, and gifts have nothing to configure
/// (no size, no cart) yet — so the sheet shows the photo, the name, the price,
/// and the description, and that is the whole of it.
Future<void> showGiftItemSheet(BuildContext context, GiftItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.xl)),
    ),
    builder: (BuildContext context) => _GiftItemSheet(item: item),
  );
}

class _GiftItemSheet extends StatelessWidget {
  const _GiftItemSheet({required this.item});

  final GiftItem item;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Grab handle.
            Center(
              child: Container(
                margin: const EdgeInsets.only(
                  top: ZopiqSpacing.md,
                  bottom: ZopiqSpacing.sm,
                ),
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: zc.divider,
                  borderRadius: ZopiqRadii.rPill,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ZopiqSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: ZopiqRadii.rLg,
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: _Gallery(item: item),
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          item.category.toUpperCase(),
                          style: t.labelSmall?.copyWith(
                            color: zc.primaryDeep,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZopiqSpacing.sm,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: zc.primaryDeep.withValues(alpha: 0.1),
                            borderRadius: ZopiqRadii.rPill,
                          ),
                          child: Text(
                            'Curated Gift',
                            style: t.labelSmall?.copyWith(
                              color: zc.primaryDeep,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZopiqSpacing.xs),
                    Text(
                      item.name,
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),
                    Text(
                      '₹${item.price}',
                      style: t.headlineSmall?.copyWith(
                        color: zc.textStrong,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.md),
                    // Gift highlights bar
                    Container(
                      padding: const EdgeInsets.all(ZopiqSpacing.md),
                      decoration: BoxDecoration(
                        color: zc.primaryDeep.withValues(alpha: 0.05),
                        borderRadius: ZopiqRadii.rMd,
                        border: Border.all(
                          color: zc.primaryDeep.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.card_giftcard_rounded,
                            color: zc.primaryDeep,
                            size: 24,
                          ),
                          const SizedBox(width: ZopiqSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Complimentary Gift Box',
                                  style: t.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Includes ribbons, personalized card & safe packaging.',
                                  style: t.bodySmall?.copyWith(
                                    color: zc.textMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.description.isNotEmpty) ...<Widget>[
                      const SizedBox(height: ZopiqSpacing.lg),
                      Text(
                        'ABOUT THIS GIFT',
                        style: t.labelMedium?.copyWith(
                          color: zc.textMuted,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: ZopiqSpacing.xs),
                      Text(
                        item.description,
                        style: t.bodyMedium?.copyWith(
                          color: zc.textMuted,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: ZopiqSpacing.xl),
                    ZopiqButton(
                      label: 'Close',
                      expand: true,
                      onPressed: () => Navigator.of(context).pop(),
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

/// A swipeable gallery of a gift's photos, with a dot per page. Falls back to
/// the single [GiftItem.imageUrl] when a product has no gallery, so a one-photo
/// item still renders (with no dots).
class _Gallery extends StatefulWidget {
  const _Gallery({required this.item});

  final GiftItem item;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final PageController _controller = PageController();
  int _page = 0;

  List<String> get _images => widget.item.imageUrls.isNotEmpty
      ? widget.item.imageUrls
      : <String>[widget.item.imageUrl];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> images = _images;

    return Stack(
      children: <Widget>[
        PageView.builder(
          controller: _controller,
          itemCount: images.length,
          onPageChanged: (int i) => setState(() => _page = i),
          itemBuilder: (BuildContext context, int i) => GiftImage(
            url: images[i],
            // Seed per page so a fallback placeholder still varies per photo.
            seed: '${widget.item.id}-$i',
            iconSize: 56,
          ),
        ),
        // Dots — only worth drawing when there is more than one photo.
        if (images.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: ZopiqSpacing.sm,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < images.length; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(
                      horizontal: ZopiqSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
