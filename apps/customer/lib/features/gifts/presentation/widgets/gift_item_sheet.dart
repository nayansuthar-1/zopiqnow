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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: zc.divider,
                borderRadius: ZopiqRadii.rPill,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: ZopiqRadii.rLg,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: GiftImage(
                      url: item.imageUrl,
                      seed: item.id,
                      iconSize: 56,
                    ),
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.lg),
                Text(
                  item.category.toUpperCase(),
                  style: t.labelSmall?.copyWith(
                    color: zc.primaryDeep,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                Text(
                  item.name,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: ZopiqSpacing.sm),
                Text(
                  '₹${item.price}',
                  style: t.titleMedium?.copyWith(
                    color: zc.textStrong,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: ZopiqSpacing.lg),
                  Text(
                    item.description,
                    style: t.bodyMedium?.copyWith(
                      color: zc.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
