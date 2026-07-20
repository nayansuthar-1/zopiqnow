import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';

/// A single gift in the browse grid: a square photo, the name, and the price.
///
/// Display-only for now — there is no ADD button because gifts do not go into a
/// cart yet (that is a later task). Tapping opens the detail sheet.
class GiftItemCard extends StatelessWidget {
  const GiftItemCard({required this.item, this.onTap, super.key});

  final GiftItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: ZopiqRadii.rLg,
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: ZopiqRadii.rLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(ZopiqRadii.lg),
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GiftImage(url: item.imageUrl, seed: item.id),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(ZopiqSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.xs),
                    Text(
                      item.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),
                    Text(
                      '₹${item.price}',
                      style: t.titleSmall?.copyWith(
                        color: zc.textStrong,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
