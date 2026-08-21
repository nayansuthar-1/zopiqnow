import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/restaurant_offer.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';

/// The restaurant page's chrome: a plain bar that searches the menu, then the
/// vitals block, then the offers.
///
/// **The photograph is gone from the top, deliberately.** It was a 220pt
/// collapsing hero, which is a lot of screen spent on a picture the customer has
/// already seen — they tapped it on Home to get here. What they came for is the
/// menu, and everything that decides whether they order from this kitchen
/// (rating, distance, how long it takes, what the offer is) was pushed below the
/// fold behind it. The vitals are now the first thing on the page and the menu
/// starts about a screen earlier.

/// Back, a menu search, and the kitchen's name once the vitals scroll away.
class MenuTopBar extends ConsumerStatefulWidget {
  const MenuTopBar({required this.restaurant, super.key});

  final Restaurant restaurant;

  @override
  ConsumerState<MenuTopBar> createState() => _MenuTopBarState();
}

class _MenuTopBarState extends ConsumerState<MenuTopBar> {
  /// Whether the pill has become a field. It starts as a pill because a keyboard
  /// that opens itself on arrival covers the menu the customer came to read.
  bool _searching = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    _controller.clear();
    ref.read(menuSearchProvider.notifier).state = '';
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Color surface = Theme.of(context).colorScheme.surface;

    return SliverAppBar(
      pinned: true,
      backgroundColor: surface,
      surfaceTintColor: surface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleSpacing: 0,
      leading: _CircleIconButton(
        icon: Icons.arrow_back_rounded,
        onPressed: () =>
            _searching ? _close() : Navigator.of(context).maybePop(),
      ),
      title: _searching
          ? TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (String v) =>
                  ref.read(menuSearchProvider.notifier).state = v,
              style: t.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search ${widget.restaurant.name}',
                hintStyle: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
            )
          : GestureDetector(
              onTap: () => setState(() => _searching = true),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.lg,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: zc.divider),
                  borderRadius: BorderRadius.circular(ZopiqRadii.pill),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.search_rounded, size: 20, color: zc.textMuted),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Text(
                      'Search',
                      style: t.bodyMedium?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ),
              ),
            ),
      actions: <Widget>[
        if (_searching)
          _CircleIconButton(icon: Icons.close_rounded, onPressed: _close)
        else
          // A kebab with nothing behind it reads as a broken menu. The one thing
          // this bar genuinely has to offer is the search that is already here,
          // so the slot holds spacing rather than a promise.
          const SizedBox(width: ZopiqSpacing.lg),
        const SizedBox(width: ZopiqSpacing.sm),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    return Center(
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: zc.divider),
          ),
          child: Icon(icon, size: 20, color: zc.textStrong),
        ),
      ),
    );
  }
}

/// Name, rating, distance and time — everything that decides whether to order
/// here, above the menu rather than under a photograph.
class MenuVitals extends StatelessWidget {
  const MenuVitals({required this.restaurant, super.key});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
        ZopiqSpacing.pageGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (restaurant.isVeg) ...<Widget>[
            _PureVegBadge(color: zc.veg),
            const SizedBox(height: ZopiqSpacing.md),
          ],

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  restaurant.name,
                  style: t.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: ZopiqSpacing.md),
              // Only when somebody has actually rated it. A 0.0 in a green box
              // is not a low score, it is an empty one, and it reads as the
              // former to every customer who sees it.
              if (restaurant.ratingCount > 0)
                _RatingBadge(
                  rating: restaurant.rating,
                  count: restaurant.ratingCount,
                ),
            ],
          ),
          const SizedBox(height: ZopiqSpacing.md),

          _VitalRow(
            icon: Icons.location_on_outlined,
            // Cuisines where a delivery app usually puts a locality: we do not
            // hold an area name, and "Indian, Chinese" is at least true.
            //
            // The distance drops out of the line when it is unknown, leaving
            // just the cuisines, rather than heading the row with "0.0 km".
            text: <String>[
              if (restaurant.distanceKm != null)
                '${restaurant.distanceKm!.toStringAsFixed(1)} km',
              if (restaurant.cuisines.isNotEmpty) restaurant.cuisines.join(', '),
            ].join(' • '),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          _VitalRow(
            icon: Icons.timer_outlined,
            // A range now, and the spread is not invented: the ride in it is a
            // straight-line distance through an assumed speed, so a band is
            // exactly the precision we have. Falls back to a single figure when
            // there is no distance to be uncertain about — see DeliveryEta.
            text: '${restaurant.deliveryEta.label} delivery',
          ),
        ],
      ),
    );
  }
}

class _PureVegBadge extends StatelessWidget {
  const _PureVegBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZopiqRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.eco_rounded, size: 16, color: color),
          const SizedBox(width: ZopiqSpacing.xs),
          Text(
            'Pure Veg',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating, required this.count});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.sm,
            vertical: ZopiqSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: zc.veg,
            borderRadius: BorderRadius.circular(ZopiqRadii.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                rating.toStringAsFixed(1),
                style: t.titleMedium?.copyWith(
                  color: ZopiqPalette.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: ZopiqSpacing.xxs),
              const Icon(
                Icons.star_rounded,
                size: 16,
                color: ZopiqPalette.white,
              ),
            ],
          ),
        ),
        const SizedBox(height: ZopiqSpacing.xxs),
        Text(
          '$count ratings',
          style: t.labelSmall?.copyWith(color: zc.textMuted),
        ),
      ],
    );
  }
}

class _VitalRow extends StatelessWidget {
  const _VitalRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: zc.textMuted),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: zc.textStrong),
          ),
        ),
      ],
    );
  }
}

/// What this kitchen is running today (migration 0064).
///
/// The codes are shown, not applied — a coupon is typed at checkout, where the
/// order service is the thing that decides whether it holds. Renders nothing at
/// all when there are no offers, rather than an empty strip saying so.
class MenuOffersStrip extends ConsumerWidget {
  const MenuOffersStrip({required this.restaurantId, super.key});

  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RestaurantOffer> offers =
        ref.watch(restaurantOffersProvider(restaurantId)).valueOrNull ??
        const <RestaurantOffer>[];
    if (offers.isEmpty) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: ZopiqSpacing.lg),
      child: SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.pageGutter,
          ),
          itemCount: offers.length,
          separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.sm),
          itemBuilder: (BuildContext context, int i) {
            final RestaurantOffer o = offers[i];
            return Container(
              width: 240,
              padding: const EdgeInsets.all(ZopiqSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: zc.divider),
                borderRadius: ZopiqRadii.rMd,
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.local_offer_rounded, size: 20, color: zc.primary),
                  const SizedBox(width: ZopiqSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          o.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: ZopiqSpacing.xxs),
                        Text(
                          'Use ${o.code}'
                          '${o.minSubtotal > 0 ? ' above ₹${o.minSubtotal}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelSmall?.copyWith(color: zc.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
