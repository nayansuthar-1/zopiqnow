import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// A shimmering stack of card-shaped placeholders — the loading state for a list
/// of tickets or dishes. Replaces the bare [CircularProgressIndicator] the pages
/// used to spin, so a load reads as "your cards are coming", not "something is
/// happening somewhere".
///
/// One shimmer animation drives the whole column (the sweep is a shader mask over
/// all descendants), so a longer list is not a heavier one.
class VendorSkeletonList extends StatelessWidget {
  const VendorSkeletonList({this.count = 5, this.itemHeight = 132, super.key});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return ZopiqShimmer(
      child: ListView.builder(
        // The skeleton stands in for content that isn't scrollable yet.
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.pageGutter,
          vertical: ZopiqSpacing.sm,
        ),
        itemCount: count,
        itemBuilder: (BuildContext context, int _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.xs),
          child: ZopiqSkeletonBox(
            height: itemHeight,
            borderRadius: ZopiqRadii.rLg,
          ),
        ),
      ),
    );
  }
}
