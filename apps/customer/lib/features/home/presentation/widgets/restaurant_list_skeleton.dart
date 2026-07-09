import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Shimmer placeholder shown while the Home feed loads (Rule 2.5). Mirrors the
/// shape of [RestaurantCard] so the transition to real content is seamless.
class RestaurantListSkeleton extends StatelessWidget {
  const RestaurantListSkeleton({this.itemCount = 4, super.key});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ZopiqShimmer(
      child: Column(
        children: List<Widget>.generate(
          itemCount,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: ZopiqSpacing.lg),
            child: _SkeletonCard(),
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const ZopiqCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ZopiqSkeletonBox(
              height: double.infinity,
              borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.lg)),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(ZopiqSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ZopiqSkeletonBox(height: 16, width: 180),
                SizedBox(height: ZopiqSpacing.sm),
                ZopiqSkeletonBox(height: 12, width: 220),
                SizedBox(height: ZopiqSpacing.sm),
                ZopiqSkeletonBox(height: 12, width: 140),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
