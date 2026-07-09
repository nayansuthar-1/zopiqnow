import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/offer.dart';

/// Horizontally scrolling promo banners shown under the category rail.
class OffersCarousel extends StatelessWidget {
  const OffersCarousel({required this.offers, this.onTapOffer, super.key});

  final List<Offer> offers;
  final ValueChanged<Offer>? onTapOffer;

  static const double _cardWidth = 280;
  static const double _cardHeight = 128;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: ZopiqSpacing.pagePadding,
        physics: const BouncingScrollPhysics(),
        itemCount: offers.length,
        separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.md),
        itemBuilder: (BuildContext context, int i) => RepaintBoundary(
          child: _OfferCard(
            offer: offers[i],
            onTap: onTapOffer == null ? null : () => onTapOffer!(offers[i]),
          ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, this.onTap});

  final Offer offer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqPressable(
      onTap: onTap,
      child: Container(
        width: OffersCarousel._cardWidth,
        padding: const EdgeInsets.all(ZopiqSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: ZopiqRadii.rLg,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[zc.primary, zc.primaryDeep],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  offer.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineMedium?.copyWith(color: ZopiqPalette.white),
                ),
                Text(
                  offer.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(
                    color: ZopiqPalette.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            _CodeChip(code: offer.code),
          ],
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: ZopiqPalette.white.withValues(alpha: 0.18),
        borderRadius: ZopiqRadii.rXs,
        border: Border.all(color: ZopiqPalette.white.withValues(alpha: 0.4)),
      ),
      child: Text(
        'USE $code',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: ZopiqPalette.white),
      ),
    );
  }
}
