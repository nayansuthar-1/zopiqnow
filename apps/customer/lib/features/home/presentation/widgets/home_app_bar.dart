import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_filters.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_hero_carousel.dart';
import 'package:zopiqnow/features/notifications/presentation/widgets/notification_bell.dart';

/// Home header as a Zomato-style collapsing sliver, built *around* the hero
/// carousel.
///
/// **At the top** there is no chrome at all: the swipeable carousel is
/// full-bleed from the very top of the screen (behind the status bar), and the
/// delivery location + profile and the search pill + "Veg" toggle simply float
/// over it. The app bar is effectively transparent.
///
/// **On scroll** the carousel slides up and out, the location row fades away,
/// and the search + veg row rises into a solid `primary` strip that pins under
/// the status bar — Zomato's sticky search. The search row is one widget whose
/// top is interpolated by the collapse fraction, so it *travels* into the bar
/// rather than being duplicated.
///
/// `primary: false`: this bar owns the status-bar area itself (Home no longer
/// wraps the scroll view in a SafeArea), and the header content is inset by the
/// real `MediaQuery` top padding so the carousel can bleed behind the clock.
class HomeSliverAppBar extends StatelessWidget {
  const HomeSliverAppBar({
    required this.address,
    this.onTapLocation,
    this.onTapSearch,
    this.onTapProfile,
    this.onTapCta,
    super.key,
  });

  final String address;
  final VoidCallback? onTapLocation;
  final VoidCallback? onTapSearch;
  final VoidCallback? onTapProfile;

  /// Forwarded to the carousel's "Order now" CTA.
  final VoidCallback? onTapCta;

  // Header metrics (below the status-bar inset).
  static const double _topPad = ZopiqSpacing.pageGutter; // 16
  static const double _rowHeight = 44; // address row & search pill
  static const double _rowGap = ZopiqSpacing.sm + ZopiqSpacing.xxs; // 10
  static const double _belowSearch = ZopiqSpacing.sm; // 8

  /// Header content height, status-bar inset excluded.
  static const double _headerBody =
      _topPad + _rowHeight + _rowGap + _rowHeight; // 106

  @override
  Widget build(BuildContext context) {
    final double inset = MediaQuery.paddingOf(context).top;
    final double width = MediaQuery.sizeOf(context).width;

    // The visible promo area under the header; the carousel is the sum. Sized
    // for the tallest slide (a two-line headline + subline + CTA) so nothing
    // clips.
    final double promoHeight = (width * 0.58).clamp(238.0, 262.0);
    final double headerInset = inset + _headerBody + _belowSearch;
    final double expanded = headerInset + promoHeight;
    // The pinned strip: status inset + a padded search pill.
    final double collapsed = inset + _topPad + _rowHeight + _topPad;

    final double searchTopExpanded = inset + _topPad + _rowHeight + _rowGap;
    final double searchTopCollapsed = inset + _topPad;

    return SliverAppBar(
      pinned: true,
      primary: false,
      automaticallyImplyLeading: false,
      expandedHeight: expanded,
      collapsedHeight: collapsed,
      toolbarHeight: collapsed,
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double h = constraints.maxHeight;
          final double shrink = expanded - h;
          final double t = (shrink / (expanded - collapsed)).clamp(0.0, 1.0);

          // The location row leaves quickly, well before it could touch the
          // rising search pill.
          final double locationOpacity = (1 - t * 2.2).clamp(0.0, 1.0);
          // The solid strip only takes over near the end, so the carousel stays
          // clear (not veiled) through most of the scroll.
          final double solidAlpha = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
          // The search pill rises from just under the location row to the top.
          final double searchTop =
              searchTopExpanded +
              (searchTopCollapsed - searchTopExpanded) * t;

          final SystemUiOverlayStyle overlayStyle = t > 0.5 
              ? (Theme.of(context).brightness == Brightness.dark 
                  ? SystemUiOverlayStyle.light 
                  : SystemUiOverlayStyle.dark)
              : SystemUiOverlayStyle.light;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: ClipRect(
              child: Stack(
              children: <Widget>[
                // The carousel, full height, translated up as the bar collapses
                // so it scrolls away naturally (no squish).
                Positioned(
                  top: -shrink,
                  left: 0,
                  right: 0,
                  height: expanded,
                  child: IgnorePointer(
                    ignoring: t > 0.5,
                    child: HomeHeroCarousel(
                      headerInset: headerInset,
                      promoHeight: promoHeight,
                      onTapCta: onTapCta,
                    ),
                  ),
                ),

                // Solid brand fill that fades in to become the pinned bar.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: solidAlpha),
                      ),
                    ),
                  ),
                ),

                // Location + profile — fades and lifts away on collapse.
                Positioned(
                  left: ZopiqSpacing.pageGutter,
                  right: ZopiqSpacing.pageGutter,
                  top: inset + _topPad,
                  height: _rowHeight,
                  child: IgnorePointer(
                    ignoring: locationOpacity < 0.1,
                    child: Opacity(
                      opacity: locationOpacity,
                      child: Transform.translate(
                        offset: Offset(0, -10 * t),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: _LocationTitle(
                                address: address,
                                onTap: onTapLocation,
                              ),
                            ),
                            const SizedBox(width: ZopiqSpacing.sm),
                            const NotificationBell(),
                            const SizedBox(width: ZopiqSpacing.sm),
                            _ProfileButton(onTap: onTapProfile),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Search + veg — travels up into the pinned strip.
                Positioned(
                  left: ZopiqSpacing.pageGutter,
                  right: ZopiqSpacing.pageGutter,
                  top: searchTop,
                  height: _rowHeight,
                  child: Row(
                    children: <Widget>[
                      Expanded(child: _SearchField(onTap: onTapSearch)),
                      const SizedBox(width: ZopiqSpacing.sm),
                      const _VegToggle(),
                    ],
                  ),
                ),

              ],
            ),
          ),
          );
        },
      ),
    );
  }
}

class _LocationTitle extends StatelessWidget {
  const _LocationTitle({required this.address, required this.onTap});

  final String address;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rSm,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.location_on_rounded,
            color: ZopiqPalette.white,
            size: 22,
          ),
          const SizedBox(width: ZopiqSpacing.xs),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Delivering to',
                  style: t.labelSmall?.copyWith(
                    color: ZopiqPalette.white.withValues(alpha: 0.8),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(color: ZopiqPalette.white),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: ZopiqPalette.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: CircleAvatar(
        radius: 18,
        backgroundColor: ZopiqPalette.white.withValues(alpha: 0.22),
        child: const Icon(
          Icons.person_rounded,
          color: ZopiqPalette.white,
          size: 20,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rMd,
      child: Container(
        height: HomeSliverAppBar._rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.md),
        // Fixed light colors in both themes: this pill sits on the brand
        // hero, not on the scaffold, so it must not flip with the mode.
        decoration: const BoxDecoration(
          color: ZopiqPalette.white,
          borderRadius: ZopiqRadii.rMd,
          boxShadow: <BoxShadow>[
            BoxShadow(color: Color(0x1F000000), blurRadius: 8),
          ],
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.search_rounded,
              color: ZopiqPalette.primaryDeep,
              size: 22,
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Expanded(
              child: Text(
                'Search "Biryani"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(color: ZopiqPalette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zomato's "Veg Mode": a white pill with a mini switch that filters the whole
/// feed to pure-veg restaurants. It shares the `pureVeg` filter, so flipping it
/// also lights the "Pure Veg" chip below (and vice-versa) — one source of truth.
class _VegToggle extends ConsumerWidget {
  const _VegToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool on = ref.watch(
      homeFiltersProvider.select((HomeFilters f) => f.pureVeg),
    );
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Semantics(
      button: true,
      toggled: on,
      label: 'Veg mode',
      child: GestureDetector(
        onTap: ref.read(homeFiltersProvider.notifier).togglePureVeg,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: HomeSliverAppBar._rowHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'VEG\nMODE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: 0.5,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              _MiniToggle(on: on),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact on/off track with a sliding knob — small enough to sit inside the
/// veg pill without a Material [Switch]'s bulk.
class _MiniToggle extends StatelessWidget {
  const _MiniToggle({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return AnimatedContainer(
      duration: ZopiqDurations.fast,
      curve: ZopiqCurves.standard,
      width: 32,
      height: 18,
      decoration: BoxDecoration(
        color: on ? zc.veg : ZopiqPalette.textMuted.withValues(alpha: 0.5),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: AnimatedAlign(
        duration: ZopiqDurations.fast,
        curve: ZopiqCurves.standard,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(
            color: ZopiqPalette.white,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(color: Color(0x33000000), blurRadius: 2),
            ],
          ),
        ),
      ),
    );
  }
}
