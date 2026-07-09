import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/theme_mode_provider.dart';

/// Foundation milestone deliverable: a living showcase of the zopiq_ui design
/// system. It exercises every token and core component in one place so the
/// theme (light + dark) can be verified visually on an Android 10 device.
///
/// This screen is throwaway scaffolding — it will be replaced by the real
/// customer Home once feature work begins.
class DesignShowcasePage extends ConsumerWidget {
  const DesignShowcasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('zopiq_ui'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Theme: ${mode.name}',
            onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
            icon: Icon(switch (mode) {
              ThemeMode.system => Icons.brightness_auto_outlined,
              ThemeMode.light => Icons.light_mode_outlined,
              ThemeMode.dark => Icons.dark_mode_outlined,
            }),
          ),
          const SizedBox(width: ZopiqSpacing.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.lg),
        children: const <Widget>[
          _Section(title: 'Brand palette', child: _PaletteRow()),
          _Section(title: 'Typography', child: _TypographySample()),
          _Section(title: 'Buttons', child: _ButtonsSample()),
          _Section(title: 'Card & food type', child: _CardSample()),
          _Section(title: 'Loading skeleton', child: _ShimmerSample()),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ZopiqSpacing.md),
        child,
        const SizedBox(height: ZopiqSpacing.xl),
      ],
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final List<(String, Color)> swatches = <(String, Color)>[
      ('primary', zc.primary),
      ('cta', zc.primaryDeep),
      ('veg', zc.veg),
      ('nonVeg', zc.nonVeg),
      ('rating', zc.rating),
    ];

    return Wrap(
      spacing: ZopiqSpacing.md,
      runSpacing: ZopiqSpacing.md,
      children: <Widget>[
        for (final (String name, Color color) in swatches)
          Column(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: ZopiqRadii.rMd,
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: zc.cardShadow, blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(name, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}

class _TypographySample extends StatelessWidget {
  const _TypographySample();

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Delicious, delivered fast', style: t.headlineMedium),
        const SizedBox(height: ZopiqSpacing.xs),
        Text('Order from the best restaurants near you.', style: t.bodyMedium),
      ],
    );
  }
}

class _ButtonsSample extends StatelessWidget {
  const _ButtonsSample();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ZopiqButton(
          label: 'Order now',
          icon: Icons.shopping_bag_outlined,
          variant: ZopiqButtonVariant.cta,
          onPressed: () {},
        ),
        const SizedBox(height: ZopiqSpacing.md),
        ZopiqButton(label: 'Add to cart', onPressed: () {}),
        const SizedBox(height: ZopiqSpacing.md),
        Row(
          children: <Widget>[
            const Expanded(
              child: ZopiqButton(
                label: 'Loading',
                isLoading: true,
                onPressed: null,
              ),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: ZopiqButton(
                label: 'Track',
                variant: ZopiqButtonVariant.outline,
                onPressed: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CardSample extends StatelessWidget {
  const _CardSample();

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return ZopiqCard(
      onTap: () {},
      child: Row(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.12),
              borderRadius: ZopiqRadii.rMd,
            ),
            child: Icon(Icons.ramen_dining_outlined, color: zc.primary),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const ZopiqVegIndicator(isVeg: true),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Expanded(
                      child: Text('Paradise Biryani', style: t.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                Text('Biryani • Hyderabadi • 30 min', style: t.bodySmall),
                const SizedBox(height: ZopiqSpacing.sm),
                _RatingPill(rating: 4.4, color: zc.rating),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating, required this.color});

  final double rating;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(color: color, borderRadius: ZopiqRadii.rXs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star_rounded, size: 14, color: Colors.white),
          const SizedBox(width: ZopiqSpacing.xxs),
          Text(
            rating.toStringAsFixed(1),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ShimmerSample extends StatelessWidget {
  const _ShimmerSample();

  @override
  Widget build(BuildContext context) {
    return const ZopiqShimmer(
      child: Row(
        children: <Widget>[
          ZopiqSkeletonBox(width: 64, height: 64, borderRadius: ZopiqRadii.rMd),
          SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ZopiqSkeletonBox(height: 16),
                SizedBox(height: ZopiqSpacing.sm),
                ZopiqSkeletonBox(height: 12, width: 180),
                SizedBox(height: ZopiqSpacing.sm),
                ZopiqSkeletonBox(height: 12, width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
