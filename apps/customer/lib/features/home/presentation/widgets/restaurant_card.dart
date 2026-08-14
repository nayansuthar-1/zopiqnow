import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/favourites/presentation/widgets/favourite_button.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart';

/// Hero tag shared by a restaurant's Home list card and its menu header, so the
/// image flies between the two screens.
///
/// Lives here, next to the card that owns the source Hero, so the menu feature
/// depends on home rather than the reverse.
String restaurantImageHeroTag(String restaurantId) =>
    'restaurant-image-$restaurantId';

/// Dark green used for rating pill and veg indicators — matches the reference
/// design (Swiggy-style deep green, not the lighter token).
const Color _darkGreen = Color(0xFF267335);

/// Discovery card for a single [Restaurant]. Pure presentation — all spacing
/// and radius come from zopiq_ui tokens.
///
/// Redesigned to match the Swiggy-style reference:
/// - Thin border with low opacity
/// - Cuisine · price overlay badge (top-left of image)
/// - Favourite heart (top-right of image) — a live control now. It was a
///   decorative bookmark glyph: an icon that looked tappable, was not, and did
///   nothing, which is the worst thing a control can be.
/// - "FREE delivery" badge (bottom-left of image)
/// - Dot indicator (bottom-right of image)
/// - Name + dark-green rating pill
/// - ETA | distance row
/// - Offer text
/// - Dashed divider + "Pure Veg restaurant" footer
class RestaurantCard extends StatelessWidget {
  const RestaurantCard({
    required this.restaurant,
    this.onTap,
    this.heroic = true,
    this.photos = const <String>[],
    super.key,
  });

  final Restaurant restaurant;
  final VoidCallback? onTap;

  /// Dish photographs from this restaurant's menu (0119), shown after its cover
  /// in the card's photo strip.
  ///
  /// Optional, and every call site that cannot cheaply supply them leaves it
  /// empty rather than fetching: with none the card draws exactly what it drew
  /// before — one photo and no dots. The strip is an enrichment of the card, not
  /// a part of it that can be missing.
  final List<String> photos;

  /// Whether this card's image is the Hero source for the menu header.
  ///
  /// Exactly one mounted card per restaurant may claim it. Home and Search both
  /// live in the shell's `IndexedStack` — both mounted, one Navigator — so a
  /// restaurant showing in both would register two Heroes under one tag and
  /// crash the next route transition. Search therefore opts out; it loses the
  /// image flight, not the navigation.
  final bool heroic;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: ZopiqRadii.rXl,
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: ZopiqRadii.rXl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CardImage(
                restaurant: restaurant,
                heroic: heroic,
                photos: photos,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.lg,
                  vertical: ZopiqSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // ─── Name + rating ───
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            restaurant.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: ZopiqSpacing.sm),
                        _RatingPill(rating: restaurant.rating),
                      ],
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),

                    // ─── ETA | distance ───
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.schedule_outlined,
                          size: 16,
                          color: zc.textMuted,
                        ),
                        const SizedBox(width: ZopiqSpacing.xs),
                        Text(
                          '${restaurant.etaMinutes} min',
                          style: t.bodyMedium?.copyWith(color: zc.textMuted),
                        ),
                        // Omitted entirely when we cannot measure it, rather
                        // than shown as 0.0 km — see Restaurant.distanceKm.
                        if (restaurant.distanceKm != null) ...<Widget>[
                          _Separator(color: zc.textMuted),
                          Text(
                            '${restaurant.distanceKm!.toStringAsFixed(1)} km',
                            style: t.bodyMedium?.copyWith(color: zc.textMuted),
                          ),
                        ],
                      ],
                    ),

                    // ─── Offer text ───
                    if (restaurant.promoText != null) ...<Widget>[
                      const SizedBox(height: ZopiqSpacing.sm),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.local_offer_rounded,
                            size: 16,
                            color: Color(0xFF5B8DF5),
                          ),
                          const SizedBox(width: ZopiqSpacing.xs),
                          Flexible(
                            child: Text(
                              restaurant.promoText!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(
                                color: zc.textStrong,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ─── Pure Veg footer (only if veg) ───
              if (restaurant.isVeg) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.lg,
                  ),
                  child: _DashedDivider(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.08),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: ZopiqSpacing.lg,
                    right: ZopiqSpacing.lg,
                    top: ZopiqSpacing.sm,
                    bottom: ZopiqSpacing.md,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZopiqSpacing.md,
                      vertical: ZopiqSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF5F5F5),
                      borderRadius: ZopiqRadii.rPill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Leaf-style veg icon
                        const Icon(
                          Icons.eco_rounded,
                          size: 16,
                          color: _darkGreen,
                        ),
                        const SizedBox(width: ZopiqSpacing.xs),
                        Text(
                          'Pure Veg restaurant',
                          style: t.labelMedium?.copyWith(
                            color: zc.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The most pages the strip will draw, and the most dots it will draw.
///
/// Six pages because that is the ceiling `restaurant_card_photos` clamps to
/// (0119) plus nothing — the cover is one of the six, not a seventh.
///
/// Five dots because a row of dots stops being readable at a glance somewhere
/// around six, and because the strip is a hint that there is more to see rather
/// than a page counter. With six photos the dots window: the active one is kept
/// inside the row and the row slides under it, the way a phone keyboard's page
/// dots do.
const int _maxPages = 6;
const int _maxDots = 5;

/// Where an infinite [PageView] starts.
///
/// A looping strip is a `PageView` with no `itemCount` and the real page read
/// out with `%`. It has to start a long way from zero so that the *first* swipe
/// can go backwards as well as forwards; starting at 0 gives a strip that loops
/// one way and hits a wall the other, which is worse than not looping at all.
///
/// **The photo index is measured from here, not from zero** — `index % length`
/// would open the card on whichever photo the origin happened to land on, and
/// the page count is not known when the controller is built. 100000 % 6 is 4, so
/// every restaurant with a full strip would have opened on its fifth photograph
/// and flown the wrong Hero. Subtracting first makes the origin arbitrary again,
/// which is what it was meant to be; Dart's `%` returns a non-negative result
/// for a positive divisor, so swiping back past the origin still lands on a real
/// photo rather than a negative index.
const int _loopOrigin = 100000;

class _CardImage extends StatefulWidget {
  const _CardImage({
    required this.restaurant,
    required this.heroic,
    required this.photos,
  });

  final Restaurant restaurant;
  final bool heroic;
  final List<String> photos;

  @override
  State<_CardImage> createState() => _CardImageState();
}

class _CardImageState extends State<_CardImage> {
  late final PageController _controller = PageController(
    initialPage: _loopOrigin,
  );

  /// Which photo is showing, already reduced modulo the page count.
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The cover first, then the dishes.
  ///
  /// The cover leads because it is the one photograph the restaurant chose, and
  /// because it is the Hero source for the menu screen — a strip that opened on
  /// a dish would fly the wrong picture. Duplicates are dropped: a vendor whose
  /// cover *is* one of their dish photos would otherwise get the same image
  /// twice with a dot for each.
  List<String> get _pages {
    final List<String> urls = <String>[];
    if (widget.restaurant.imageUrl.isNotEmpty) {
      urls.add(widget.restaurant.imageUrl);
    }
    for (final String url in widget.photos) {
      if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
      if (urls.length == _maxPages) break;
    }
    return urls;
  }

  /// The first page: the restaurant's own cover, and the Hero source.
  ///
  /// **Only page zero is ever wrapped in a [Hero].** A tag may be claimed by one
  /// mounted widget at a time, and a `PageView` keeps its neighbours alive — so
  /// tagging every page would register three Heroes under one tag and crash the
  /// next route transition, which is the same trap the [RestaurantCard.heroic]
  /// flag exists for between Home and Search.
  ///
  /// A consequence worth naming: swipe to a dish and tap, and page zero may no
  /// longer be mounted, so there is no Hero to fly and the menu opens with an
  /// ordinary push. That is the right way for this to degrade — the alternative
  /// is a cover photo flying out of a card that is showing a biryani.
  Widget _page0(BuildContext context, String url) {
    final Widget image = url.isEmpty || url == widget.restaurant.imageUrl
        ? RestaurantImage(restaurant: widget.restaurant)
        : _photo(url, widget.restaurant.id);
    return widget.heroic
        ? Hero(tag: restaurantImageHeroTag(widget.restaurant.id), child: image)
        : image;
  }

  /// A dish photograph. The gradient behind it is seeded with the restaurant's
  /// id rather than the dish's, so a strip that fails to load reads as one
  /// coherent card instead of five different colours.
  Widget _photo(String url, String seed) => ZopiqNetworkImage(
    url: url,
    fallback: GradientImagePlaceholder(
      seed: seed,
      icon: Icons.restaurant_rounded,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final List<String> pages = _pages;

    // Nothing to swipe through: one photo, or none at all. Drawn as a plain
    // image with no controller attached and — the point of the exercise — no
    // dots. Five dots under a single photograph is what this card did before
    // and it was never true.
    final Widget strip = pages.length < 2
        ? _page0(context, pages.isEmpty ? '' : pages.first)
        : PageView.builder(
            controller: _controller,
            // No `itemCount`, which is what makes it endless in both
            // directions. The page index is unbounded; `%` turns it back into a
            // photograph.
            itemBuilder: (BuildContext context, int index) {
              final int at = (index - _loopOrigin) % pages.length;
              return at == 0
                  ? _page0(context, pages[0])
                  : _photo(pages[at], widget.restaurant.id);
            },
            onPageChanged: (int index) {
              final int at = (index - _loopOrigin) % pages.length;
              if (at != _page) setState(() => _page = at);
            },
          );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(ZopiqRadii.xl),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            strip,

            // ─── Favourite heart (top-right) ───
            // Outside the card's InkWell hit area in intent, though not in the
            // tree: it takes its own tap, so hearting a restaurant does not also
            // open its menu.
            Positioned(
              right: ZopiqSpacing.md,
              top: ZopiqSpacing.md,
              child: FavouriteButton(restaurant: widget.restaurant),
            ),

            // ─── Cuisine · Price overlay (top-left) ───
            Positioned(
              left: ZopiqSpacing.md,
              top: ZopiqSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.sm + 2,
                  vertical: ZopiqSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: ZopiqRadii.rSm,
                ),
                child: Text(
                  // Cuisine alone since 0101. "₹400 for one" was a number an
                  // admin invented once during onboarding, and it is no longer
                  // asked for — printing it would be printing a zero.
                  widget.restaurant.cuisines.take(1).join(),
                  style: t.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // The "FREE delivery" badge that used to sit here is gone with
            // migration 0123, which withdrew the ₹500 threshold — but it was
            // never conditional on anything in the first place. It was a
            // hardcoded green flag on *every* card in the feed, so it promised
            // free delivery on restaurants that charged for it and on baskets
            // nowhere near the threshold. The same class of thing as the five
            // dots before 0119 and the two dead nav tabs: a control that looks
            // like information and is a constant.

            // ─── Dot indicator strip (bottom-right) ───
            // Only when there is more than one photograph. A single dot says
            // nothing, and five dots over one photo is what this card used to
            // claim before there was a strip behind them.
            if (pages.length > 1)
              Positioned(
                right: ZopiqSpacing.md,
                bottom: ZopiqSpacing.md,
                child: _Dots(count: pages.length, active: _page),
              ),

            // ─── "Closed for now" scrim ───
            // Over everything, because "closed" is the first thing to read about
            // this restaurant. The card stays tappable — a closed kitchen's menu
            // is still worth browsing — and the scrim only paints; it absorbs no
            // taps, so the heart beneath it still hearts.
            if (!widget.restaurant.acceptingOrders)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZopiqSpacing.md,
                            vertical: ZopiqSpacing.xs + 2,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: ZopiqRadii.rPill,
                          ),
                          child: Text(
                            'Closed for now',
                            style: t.labelLarge?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        // The kitchen's own reason, under the pill rather than
                        // inside it: the pill is the fact and has to stay one
                        // glance wide, the reason is the detail and may not fit.
                        if (widget.restaurant.pauseReason.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              ZopiqSpacing.lg,
                              ZopiqSpacing.xs,
                              ZopiqSpacing.lg,
                              0,
                            ),
                            child: Text(
                              widget.restaurant.pauseReason,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The photo strip's position indicator: at most [_maxDots] dots, whatever the
/// page count.
///
/// With five photos or fewer this is one dot per photo and nothing clever
/// happens. With six — the ceiling — the row becomes a window onto the dots: the
/// active one is kept away from the ends where possible and the row slides under
/// it, so the strip stays five dots wide and still says where you are. The dots
/// entering and leaving the window are drawn smaller, which is what stops the
/// slide reading as the dots changing meaning.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final int shown = count < _maxDots ? count : _maxDots;

    // Where the window starts. Clamped so it never runs off either end — with
    // `count <= _maxDots` this is always 0 and every dot is its own photo.
    final int start = count <= _maxDots
        ? 0
        : (active - _maxDots ~/ 2).clamp(0, count - _maxDots);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(shown, (int i) {
        final int at = start + i;
        final bool isActive = at == active;
        // An edge dot only shrinks when there is actually something past it.
        final bool isEdge =
            (i == 0 && start > 0) ||
            (i == shown - 1 && start + shown < count);
        final double size = isActive
            ? 6
            : isEdge
            ? 4
            : 5;

        return AnimatedContainer(
          duration: ZopiqDurations.fast,
          curve: ZopiqCurves.emphasized,
          width: size,
          height: size,
          margin: EdgeInsets.only(left: i == 0 ? 0 : ZopiqSpacing.xs),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.45),
          ),
        );
      }),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _darkGreen,
        borderRadius: ZopiqRadii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            rating.toStringAsFixed(1),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: ZopiqSpacing.xxs),
          const Icon(Icons.star_rounded, size: 14, color: Colors.white),
        ],
      ),
    );
  }
}

/// Vertical pipe separator between inline metadata items.
class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.sm),
      child: Container(
        width: 1,
        height: 14,
        color: color.withValues(alpha: 0.35),
      ),
    );
  }
}

/// A dashed horizontal divider drawn with a [CustomPainter].
class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: _DashPainter(color: color),
        size: const Size(double.infinity, 1),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const double dashWidth = 5;
    const double dashSpace = 3;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => color != oldDelegate.color;
}
