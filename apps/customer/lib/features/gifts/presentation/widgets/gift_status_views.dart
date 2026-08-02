import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Full-bleed error state with a retry action in Blinkit theme.
class GiftErrorView extends StatelessWidget {
  const GiftErrorView({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: _blinkitGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.wifi_off_rounded,
            size: 40,
            color: _blinkitGreen,
          ),
        ),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(
          'Something went wrong',
          style: t.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          message,
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xl),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _blinkitGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(
            'Try again',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          onPressed: onRetry,
        ),
      ],
    );
  }
}

/// Empty state — the catalog returned no gifts.
class GiftEmptyView extends StatelessWidget {
  const GiftEmptyView({super.key});

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: _blinkitGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.card_giftcard_rounded,
            size: 40,
            color: _blinkitGreen,
          ),
        ),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(
          'No gifts found',
          style: t.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          'Our makers are stocking the shelves — check back soon or try another category.',
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A responsive shimmer grid stand-in while gifts load.
class GiftGridSkeleton extends StatelessWidget {
  const GiftGridSkeleton({this.itemCount = 6, super.key});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int crossAxisCount = width > 900 ? 4 : (width > 550 ? 3 : 2);
        final double childAspectRatio = width < 400 ? 0.62 : 0.65;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(ZopiqSpacing.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: ZopiqSpacing.lg,
            crossAxisSpacing: ZopiqSpacing.lg,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: itemCount,
          itemBuilder: (_, _) => ZopiqShimmer(
            child: ZopiqSkeletonBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
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

