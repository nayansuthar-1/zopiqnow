import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Full-bleed error state with a retry action (Rule 2.5 — no blank screens).
class GiftErrorView extends StatelessWidget {
  const GiftErrorView({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Icon(Icons.wifi_off_rounded, size: 56, color: zc.textMuted),
        const SizedBox(height: ZopiqSpacing.lg),
        Text('Something went wrong', style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          message,
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xl),
        ZopiqButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          expand: false,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

/// Empty state — the catalog returned no gifts.
class GiftEmptyView extends StatelessWidget {
  const GiftEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Icon(Icons.card_giftcard_rounded, size: 56, color: zc.textMuted),
        const SizedBox(height: ZopiqSpacing.lg),
        Text('No gifts yet', style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          'Our makers are stocking the shelves — check back soon.',
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A simple shimmer grid stand-in while the gifts load.
class GiftGridSkeleton extends StatelessWidget {
  const GiftGridSkeleton({this.itemCount = 6, super.key});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: ZopiqSpacing.lg,
        crossAxisSpacing: ZopiqSpacing.lg,
        childAspectRatio: 0.68,
      ),
      itemCount: itemCount,
      itemBuilder: (_, _) => const ZopiqShimmer(
        child: ZopiqSkeletonBox(
          width: double.infinity,
          height: double.infinity,
          borderRadius: ZopiqRadii.rLg,
        ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
