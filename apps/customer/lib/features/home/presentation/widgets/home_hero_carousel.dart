import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/hero_slide.dart';

/// The Home hero — a swipeable carousel of campaign slides under the header.
///
/// It continues the header's brand colour into a full-bleed panel (Zomato's
/// home), and now holds several offers the user can swipe between, with page
/// dots and a gentle auto-advance. Each slide's text animates: it lifts and
/// fades in on first build (entrance) and drifts with a parallax as you swipe.
///
/// **Two kinds of slide, and which one you see.** [slides] is what an admin
/// published in the console (migration 0053): artwork, copy and a destination,
/// editable without a build. When it is empty — no campaign running, or the
/// fetch failed, or the phone is offline — the carousel renders the in-app
/// composition below instead (gradient + rotating ray bursts + a sheen), which
/// is what shipped before any of this was content. That fallback is the empty
/// state on purpose: zero rows must look like the app, not like a blank band.
///
/// Motion budget (DEVELOPMENT_PLAN — Motion & performance standard): every loop
/// is a transform or a one-shot opacity behind a [RepaintBoundary]; nothing
/// animates layout. All loops and the auto-advance stop under OS reduce-motion.
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({
    required this.headerInset,
    required this.promoHeight,
    this.slides = const <HeroSlide>[],
    this.onTapCta,
    this.onOpenTarget,
    super.key,
  });

  /// The published campaign slides. Empty renders the in-app fallback art.
  final List<HeroSlide> slides;

  /// Opens a slide's `cta_target`. Only called for a slide that names one; a
  /// slide with no target falls back to [onTapCta], which is what the hero's
  /// button has always done.
  final ValueChanged<String>? onOpenTarget;

  /// Blank space reserved at the top of every slide so the location + search
  /// header (which the app bar floats over the carousel) never sits on the
  /// promo copy. The gradient still fills behind it, so the header reads as
  /// floating on the hero.
  final double headerInset;

  /// Height of the visible promo area *below* [headerInset] — where the
  /// headline and CTA live. Total carousel height is the sum of the two.
  final double promoHeight;

  /// "Order now". Home passes a scroll-to-the-restaurants callback.
  final VoidCallback? onTapCta;

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  final PageController _page = PageController(initialPage: 12000);
  Timer? _auto;
  DateTime _lastInteract = DateTime.fromMillisecondsSinceEpoch(0);
  bool _reduceMotion = false;

  /// How many distinct slides the carousel is paging through — published ones
  /// if there are any, otherwise the in-app fallback set.
  int get _count =>
      widget.slides.isEmpty ? _slides.length : widget.slides.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAuto();
  }

  @override
  void didUpdateWidget(HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only on a change of *count*, never on an ordinary rebuild. The app bar
    // rebuilds this widget on every pixel of its collapse, and restarting the
    // timer each time would reset the five seconds forever — the carousel would
    // never advance on its own.
    if (oldWidget.slides.length != widget.slides.length) _syncAuto();
  }

  void _syncAuto() {
    // Auto-advance is a nicety, not the way to see slides — off when the OS
    // asks for reduced motion. Swiping still works.
    //
    // Also off for a single slide, which an admin publishing one campaign will
    // produce: there is nowhere to advance *to*, so the timer would slide the
    // same artwork out and back in every five seconds.
    if (_reduceMotion || _count < 2) {
      _auto?.cancel();
      _auto = null;
    } else {
      _startAuto();
    }
  }

  void _startAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_page.hasClients) return;
      // Yield to the user: don't yank the page while they're browsing slides.
      if (DateTime.now().difference(_lastInteract) < const Duration(seconds: 6)) {
        return;
      }
      _page.animateToPage(
        (_page.page ?? 12000.0).round() + 1,
        duration: ZopiqDurations.slow,
        curve: ZopiqCurves.emphasized,
      );
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double height = widget.headerInset + widget.promoHeight;
        final double headlineSize = (width * 0.108).clamp(30.0, 44.0);

        return SizedBox(
          height: height,
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              if (n is UserScrollNotification) _lastInteract = DateTime.now();
              return false;
            },
            child: Stack(
              children: <Widget>[
                // One PageView for both kinds of slide, so the published ones
                // arriving mid-session only swap the *children*. Rebuilding the
                // view itself would mean a second widget briefly attached to the
                // same PageController, which Flutter refuses outright. The
                // incoming slide's own entrance fade covers the swap.
                PageView.builder(
                  controller: _page,
                  itemBuilder: (BuildContext context, int i) =>
                      widget.slides.isEmpty
                      ? _HeroSlideView(
                          slide: _slides[i % _slides.length],
                          index: i,
                          page: _page,
                          headlineSize: headlineSize,
                          topInset: widget.headerInset,
                          reduceMotion: _reduceMotion,
                          onTapCta: widget.onTapCta,
                        )
                      : _PublishedSlideView(
                          slide: widget.slides[i % widget.slides.length],
                          index: i,
                          page: _page,
                          headlineSize: headlineSize,
                          topInset: widget.headerInset,
                          reduceMotion: _reduceMotion,
                          onTapCta: widget.onTapCta,
                          onOpenTarget: widget.onOpenTarget,
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: ZopiqSpacing.md,
                  child: _Dots(count: _count, pageController: _page),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The page-position indicator. Only 5 dots visible at a time.
/// As the user swipes, the dots infinitely slide left/right.
///
/// Two shapes, because [count] stopped being a constant the day slides became
/// content. Up to five, the row shows exactly that many dots and lights the
/// current one — anything else would claim the carousel holds slides it does
/// not. Above five it is the sliding window this was written as, since a row of
/// twelve dots is not a page indicator any more.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.pageController});

  final int count;
  final PageController pageController;

  @override
  Widget build(BuildContext context) {
    // One slide has no position to indicate.
    if (count < 2) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: pageController,
      builder: (BuildContext context, Widget? child) {
        final double page = pageController.hasClients && pageController.position.haveDimensions
            ? (pageController.page ?? 12000.0)
            : 12000.0;

        if (count <= 5) {
          final int active = page.round() % count;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 0; i < count; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: ZopiqPalette.white.withValues(
                      alpha: i == active ? 1.0 : 0.5,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          );
        }

        final int basePage = page.floor();
        final double f = page - basePage;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 65, // 5 dots * 13 width
              height: 7,
              child: ClipRect(
                child: Stack(
                  children: List<Widget>.generate(6, (int index) {
                    final int i = index - 2; // Renders relative positions -2 to 3
                    final double d = (basePage + i - page).abs();
                    final double opacity = 0.5 + 0.5 * (1 - d.clamp(0.0, 1.0));
                    
                    double scale = 1.0;
                    if (i == -2) scale = 1.0 - f;
                    if (i == 3) scale = f;

                    return Positioned(
                      left: (i + 2) * 13.0 - f * 13.0,
                      top: 0,
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: ZopiqPalette.white.withValues(alpha: opacity),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One campaign slide: gradient body, ambient decoration, and the animated copy.
class _HeroSlideView extends StatefulWidget {
  const _HeroSlideView({
    required this.slide,
    required this.index,
    required this.page,
    required this.headlineSize,
    required this.topInset,
    required this.reduceMotion,
    this.onTapCta,
  });

  final _HeroSlide slide;
  final int index;
  final PageController page;
  final double headlineSize;
  final double topInset;
  final bool reduceMotion;
  final VoidCallback? onTapCta;

  @override
  State<_HeroSlideView> createState() => _HeroSlideViewState();
}

class _HeroSlideViewState extends State<_HeroSlideView>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: ZopiqDurations.ambient,
  );
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: ZopiqDurations.breath,
  );
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: ZopiqDurations.slow,
  );

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _entrance.value = 1;
    } else {
      _spin.repeat();
      _sheen.repeat();
      _pulse.repeat(reverse: true);
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _sheen.dispose();
    _pulse.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final _HeroSlide s = widget.slide;
    final bool hasDealCards = s.dealCards != null && s.dealCards!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: s.gradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            right: -90,
            top: -70,
            child: RepaintBoundary(
              child: RotationTransition(
                turns: _spin,
                child: const _RayBurst(radius: 190, alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            left: -60,
            bottom: -110,
            child: RepaintBoundary(
              child: RotationTransition(
                turns: ReverseAnimation(_spin),
                child: const _RayBurst(radius: 130, alpha: 0.07),
              ),
            ),
          ),
          const Positioned.fill(child: _CenterGlow()),
          Positioned(
            left: 0,
            top: 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: _Sheen(animation: _sheen, width: 400, height: 300),
              ),
            ),
          ),
          // The copy: entrance (fade + lift, once) wrapped around a parallax
          // drift driven by the page position, so text slides as you swipe.
          FadeTransition(
            opacity: CurvedAnimation(parent: _entrance, curve: ZopiqCurves.enter),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.14),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: _entrance, curve: ZopiqCurves.emphasized),
              ),
              child: AnimatedBuilder(
                animation: widget.page,
                builder: (BuildContext context, Widget? child) {
                  final double page =
                      widget.page.hasClients &&
                          widget.page.position.haveDimensions
                      ? (widget.page.page ?? widget.index.toDouble())
                      : widget.index.toDouble();
                  final double delta = page - widget.index;
                  return Transform.translate(
                    offset: Offset(delta * -30, 0),
                    child: child,
                  );
                },
                child: hasDealCards
                    ? _DealCardsSlideContent(
                        slide: s,
                        topInset: widget.topInset,
                        headlineSize: widget.headlineSize,
                        pulse: _pulse,
                        onTapCta: widget.onTapCta,
                      )
                    : Padding(
                        padding: EdgeInsets.fromLTRB(
                          ZopiqSpacing.pageGutter,
                          widget.topInset,
                          ZopiqSpacing.pageGutter,
                          ZopiqSpacing.lg,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            _EyebrowPill(icon: s.eyebrowIcon, label: s.eyebrow),
                            const SizedBox(height: ZopiqSpacing.sm),
                            Text(
                              s.headline,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.displayLarge?.copyWith(
                                color: ZopiqPalette.white,
                                fontSize: widget.headlineSize,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                fontVariations: const <FontVariation>[
                                  FontVariation('wght', 800),
                                ],
                                shadows: const <Shadow>[
                                  Shadow(
                                    color: Color(0x33000000),
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: ZopiqSpacing.xs),
                            Text(
                              s.subline,
                              textAlign: TextAlign.center,
                              style: t.bodyMedium?.copyWith(
                                color: ZopiqPalette.white.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(height: ZopiqSpacing.md),
                            _PulsingCta(pulse: _pulse, onTap: widget.onTapCta),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One admin-published slide: the uploaded artwork, a scrim, and the copy.
///
/// Deliberately *not* the composition above. The gradient, the rotating ray
/// bursts and the sheen exist because there was no artwork; put them over a real
/// photograph and they fight it. What is kept is the copy's motion — the same
/// entrance lift and swipe parallax — so the two kinds of slide move alike even
/// though they look nothing alike.
///
/// The scrim is the one thing here that is not decoration. Artwork is uploaded
/// by a person who cannot know what the headline will sit on, so white text over
/// an unknown photograph needs a floor under it or a pale sky makes the headline
/// vanish. A bottom-weighted gradient, no blur, no glow.
class _PublishedSlideView extends StatefulWidget {
  const _PublishedSlideView({
    required this.slide,
    required this.index,
    required this.page,
    required this.headlineSize,
    required this.topInset,
    required this.reduceMotion,
    this.onTapCta,
    this.onOpenTarget,
  });

  final HeroSlide slide;
  final int index;
  final PageController page;
  final double headlineSize;
  final double topInset;
  final bool reduceMotion;
  final VoidCallback? onTapCta;
  final ValueChanged<String>? onOpenTarget;

  @override
  State<_PublishedSlideView> createState() => _PublishedSlideViewState();
}

class _PublishedSlideViewState extends State<_PublishedSlideView>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: ZopiqDurations.breath,
  );
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: ZopiqDurations.slow,
  );

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _entrance.value = 1;
    } else {
      // Only if there is a button to breathe. Since 0067 a slide can have none,
      // and a repeating controller with no listener is a ticker firing sixty
      // times a second to move nothing — the kind of cost that only shows up on
      // the Android 10 floor, and with a carousel that keeps several pages
      // alive it would be several of them.
      if (widget.slide.ctaLabel.isNotEmpty) _pulse.repeat(reverse: true);
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _entrance.dispose();
    super.dispose();
  }

  void _onTap() {
    final String? target = widget.slide.ctaTarget;
    if (target == null) {
      widget.onTapCta?.call();
    } else {
      widget.onOpenTarget?.call(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final HeroSlide s = widget.slide;
    // Read once into a local so the null check below promotes it — `s.motionUrl`
    // is a field and would need a `!` at the use site.
    final String? motion = s.motionUrl;

    final Widget slide = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // The brand gradient is the fallback, not a backdrop: a slide whose
        // artwork fails to load still reads as the app, with its copy intact.
        //
        // `fill` and not the package default of `cover`, which is the one place
        // this widget disagrees with every other image in the app. Everywhere
        // else the picture is *of* something — a dish, a shopfront — and cover
        // crops the edges to protect the subject. A hero slide is a composed
        // banner: cropping it cuts off the corner the designer put the price
        // in. Stretching costs almost nothing here because the hero is
        // 393 × 396 at the reference phone — square to within one percent — so
        // the "roughly square" upload the console asks for arrives at
        // essentially its own aspect ratio. On a wider or taller phone the
        // stretch is a few percent, which is invisible on a banner and visible
        // as a missing price if it were cropped instead.
        ZopiqNetworkImage(
          url: s.imageUrl,
          fit: BoxFit.fill,
          fallback: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  ZopiqPalette.primary,
                  ZopiqPalette.primaryDeep,
                ],
              ),
            ),
          ),
        ),

        // The loop, over the still and under the scrim.
        //
        // Not mounted at all under reduce-motion, and that is a deliberate
        // choice over the cheaper one. Flutter *does* pause multi-frame images
        // when animations are disabled (`image.dart`), but a paused animation
        // is frozen on its own first frame — an arbitrary video still, not the
        // artwork an admin chose and composed the headline against. Rule 1 says
        // every failure path lands on the still, so this one does too.
        if (motion != null && !widget.reduceMotion)
          Positioned.fill(
            child: _SlideMotion(
              url: motion,
              page: widget.page,
              index: widget.index,
            ),
          ),

        // The scrim, and only when there is copy for it to be a floor under.
        //
        // It was never decoration: artwork is uploaded by somebody who cannot
        // know what the headline will sit on, so white text over an unknown
        // photograph needs something beneath it or a pale sky swallows it. That
        // argument is entirely about the text. On a slide that is nothing but
        // artwork (0067) it darkens the bottom half of a picture for the sake of
        // words that are not there — which is the thing the change exists to
        // stop, arriving by a different door.
        if (s.title.isNotEmpty ||
            s.subtitle.isNotEmpty ||
            s.ctaLabel.isNotEmpty)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x33000000), Color(0x99000000)],
                    stops: <double>[0.35, 1],
                  ),
                ),
              ),
            ),
          ),
        FadeTransition(
          opacity: CurvedAnimation(parent: _entrance, curve: ZopiqCurves.enter),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.14),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: _entrance, curve: ZopiqCurves.emphasized),
            ),
            child: AnimatedBuilder(
              animation: widget.page,
              builder: (BuildContext context, Widget? child) {
                final double page =
                    widget.page.hasClients &&
                        widget.page.position.haveDimensions
                    ? (widget.page.page ?? widget.index.toDouble())
                    : widget.index.toDouble();
                final double delta = page - widget.index;
                return Transform.translate(
                  offset: Offset(delta * -30, 0),
                  child: child,
                );
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  ZopiqSpacing.pageGutter,
                  widget.topInset,
                  ZopiqSpacing.pageGutter,
                  ZopiqSpacing.lg,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    // Every one of these three is optional since 0067, and each
                    // costs no vertical space when it is absent rather than
                    // leaving a gap where it would have been. A slide with none
                    // of them is the artwork and nothing else, which is the
                    // whole point of the change: a designed banner already says
                    // what it says, and a headline drawn over it is the same
                    // words twice.
                    if (s.title.isNotEmpty)
                      Text(
                        s.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.displayLarge?.copyWith(
                          color: ZopiqPalette.white,
                          fontSize: widget.headlineSize,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          fontVariations: const <FontVariation>[
                            FontVariation('wght', 800),
                          ],
                          shadows: const <Shadow>[
                            Shadow(
                              color: Color(0x66000000),
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    if (s.subtitle.isNotEmpty) ...<Widget>[
                      if (s.title.isNotEmpty)
                        const SizedBox(height: ZopiqSpacing.xs),
                      Text(
                        s.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(
                          color: ZopiqPalette.white.withValues(alpha: 0.92),
                          shadows: const <Shadow>[
                            Shadow(color: Color(0x66000000), blurRadius: 4),
                          ],
                        ),
                      ),
                    ],
                    if (s.ctaLabel.isNotEmpty) ...<Widget>[
                      if (s.title.isNotEmpty || s.subtitle.isNotEmpty)
                        const SizedBox(height: ZopiqSpacing.md),
                      _PulsingCta(
                        pulse: _pulse,
                        label: s.ctaLabel,
                        // The arrow says where the tap goes. Down for the slide
                        // that scrolls the feed, forward for one that leaves it.
                        icon: s.ctaTarget == null
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_forward_rounded,
                        onTap: _onTap,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    // With a button, the button is the tap target and the artwork around it is
    // not — that is how it has worked since 0053 and how a hero normally works.
    //
    // With no button (0067) the tap has to live somewhere, or a designed banner
    // that names a `cta_target` would be a link with nothing to click. So the
    // whole slide becomes the target. `HitTestBehavior.opaque` is needed
    // because most of a slide is a picture with transparent regions above it,
    // and without it a tap on the artwork would fall through to nothing.
    //
    // This does not fight the carousel: `PageView` claims the horizontal drag
    // gesture in the arena and a tap is only recognised once no drag has been.
    // Swiping past a slide never opens it.
    if (s.ctaLabel.isNotEmpty) return slide;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Semantics(
        button: true,
        // The artwork carries the words, and the words are pixels — so the only
        // thing a screen reader has to go on is what the slide *does*.
        label: s.title.isNotEmpty ? s.title : 'Offer banner',
        child: slide,
      ),
    );
  }
}

/// A slide's looping animation, drawn over its still.
///
/// **There is no video player here and that is the point.** The admin uploads an
/// MP4 and Cloudinary delivers it as an animated WebP, which [Image] decodes and
/// loops natively — so a moving hero costs no new dependency and nothing in
/// `pubspec.yaml` moves. As far as this widget is concerned it is loading a
/// picture that happens to have more than one frame.
///
/// **Only the slide in front of the customer animates.** An off-screen loop is
/// battery and CPU spent on something nobody is looking at, and the carousel
/// keeps several pages alive at once. [TickerMode] is what stops it: Flutter
/// pauses multi-frame images when the ticker mode is disabled, which parks the
/// animation *without* tearing the widget down — so swiping back to a slide
/// resumes it rather than paying to decode it again.
///
/// The `< 0.5` test means exactly one loop runs at any moment (rule 3). The
/// consequence, and it is deliberate: a slide swiping into view stays on its
/// first frame until it passes the halfway point and takes over.
class _SlideMotion extends StatefulWidget {
  const _SlideMotion({
    required this.url,
    required this.page,
    required this.index,
  });

  final String url;
  final PageController page;
  final int index;

  @override
  State<_SlideMotion> createState() => _SlideMotionState();
}

class _SlideMotionState extends State<_SlideMotion> {
  bool _current = false;

  @override
  void initState() {
    super.initState();
    widget.page.addListener(_sync);
    // Not read here: the controller has no dimensions until the PageView has
    // laid out, so on this frame every slide would look like page zero.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.page.removeListener(_sync);
    super.dispose();
  }

  /// Deliberately a listener with its own `setState` rather than an
  /// [AnimatedBuilder] over the controller. The parallax above rebuilds on
  /// every pixel of a swipe because it has a new offset on every pixel; this
  /// has a new answer perhaps twice per swipe, and rebuilding an [Image]
  /// subtree sixty times a second to arrive at the same boolean is the kind of
  /// cost that only shows up on the Android 10 floor.
  void _sync() {
    if (!mounted) return;
    final double page =
        widget.page.hasClients && widget.page.position.haveDimensions
        ? (widget.page.page ?? widget.index.toDouble())
        : widget.index.toDouble();
    final bool current = (page - widget.index).abs() < 0.5;
    if (current != _current) setState(() => _current = current);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TickerMode(
        enabled: _current,
        child: Image.network(
          widget.url,
          // Matches the still underneath it (0067). Two different fits on two
          // layers of the same slide would make the loop jump out of register
          // with the artwork it is supposed to be animating.
          fit: BoxFit.fill,
          // No `cacheWidth`, unlike every still in the app. The loop is already
          // delivered at 720px by the Cloudinary transformation that built it,
          // which is the memory bound; asking for the phone's own width on top
          // of that would be asking to *upscale*, and `ResizeImage` asserts on
          // exactly that in debug.
          //
          // Frames are decoded one at a time as the animation plays, so what
          // sits in memory is the current frame and the encoded bytes — not the
          // whole loop.
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
          frameBuilder:
              (
                BuildContext context,
                Widget child,
                int? frame,
                bool wasSynchronouslyLoaded,
              ) {
                // Rule 1, restated as a fade: the still is already painted
                // underneath, so the loop appears over it rather than replacing
                // it, and there is never a blank frame between the two.
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: ZopiqDurations.base,
                  curve: ZopiqCurves.emphasized,
                  child: child,
                );
              },
        ),
      ),
    );
  }
}

/// A translucent badge for the slide's kicker line.
class _EyebrowPill extends StatelessWidget {
  const _EyebrowPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: ZopiqPalette.white.withValues(alpha: 0.18),
        borderRadius: ZopiqRadii.rPill,
        border: Border.all(color: ZopiqPalette.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: ZopiqPalette.white),
          const SizedBox(width: ZopiqSpacing.xxs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ZopiqPalette.white,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterGlow extends StatelessWidget {
  const _CenterGlow();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 0.95,
          colors: <Color>[Color(0x24FFFFFF), Color(0x00FFFFFF)],
        ),
      ),
    );
  }
}

/// A diagonal light band sweeping across the panel, then resting off-screen.
class _Sheen extends StatelessWidget {
  const _Sheen({
    required this.animation,
    required this.width,
    required this.height,
  });

  final Animation<double> animation;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final double bandWidth = width * 0.22;
    final double bandHeight = height * 1.6;

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double p = const Interval(
          0.0,
          0.5,
          curve: Curves.easeInOut,
        ).transform(animation.value);
        final double dx = -bandWidth + (width + bandWidth) * p;
        return Transform.translate(
          offset: Offset(dx, -(bandHeight - height) / 2),
          child: child,
        );
      },
      child: Transform.rotate(
        angle: 0.35,
        child: SizedBox(
          width: bandWidth,
          height: bandHeight,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Color(0x00FFFFFF),
                  Color(0x22FFFFFF),
                  Color(0x00FFFFFF),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White CTA pill with a slow scale breath.
class _PulsingCta extends StatelessWidget {
  const _PulsingCta({
    required this.pulse,
    this.label = 'Order now',
    this.icon = Icons.arrow_downward_rounded,
    this.onTap,
  });

  final Animation<double> pulse;

  /// The published slide's `cta_label`. Defaults to what the in-app slides say.
  final String label;

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 1,
          end: 1.05,
        ).chain(CurveTween(curve: ZopiqCurves.standard)).animate(pulse),
        child: ZopiqPressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.xl,
              vertical: ZopiqSpacing.md,
            ),
            decoration: const BoxDecoration(
              color: ZopiqPalette.white,
              borderRadius: ZopiqRadii.rPill,
              boxShadow: <BoxShadow>[
                BoxShadow(color: Color(0x40000000), blurRadius: 12),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: ZopiqPalette.primaryDeep,
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.xs),
                Icon(icon, size: 16, color: ZopiqPalette.primaryDeep),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Deal-cards slide layout ─────────────────────────────────────────────────

/// Special content layout for a hero slide that contains deal cards.
///
/// Compact headline + "ORDER NOW" at the top, "BIG BRANDS, BIGGEST LOOT!"
/// tagline in the middle, then a horizontally scrollable row of green cards.
class _DealCardsSlideContent extends StatelessWidget {
  const _DealCardsSlideContent({
    required this.slide,
    required this.topInset,
    required this.headlineSize,
    required this.pulse,
    this.onTapCta,
  });

  final _HeroSlide slide;
  final double topInset;
  final double headlineSize;
  final Animation<double> pulse;
  final VoidCallback? onTapCta;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(top: topInset, bottom: ZopiqSpacing.xl),
      child: Column(
        children: <Widget>[
          // ── Headline area ──
          Text(
            slide.headline,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.displayLarge?.copyWith(
              color: ZopiqPalette.white,
              fontSize: headlineSize * 0.72,
              height: 1.05,
              fontWeight: FontWeight.w900,
              fontVariations: const <FontVariation>[
                FontVariation('wght', 900),
              ],
              shadows: const <Shadow>[
                Shadow(color: Color(0x44000000), offset: Offset(0, 2)),
              ],
            ),
          ),
          const SizedBox(height: ZopiqSpacing.md),

          // ── Tagline ──
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.md,
              vertical: ZopiqSpacing.xxs,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: ZopiqPalette.white.withValues(alpha: 0.2),
                ),
                bottom: BorderSide(
                  color: ZopiqPalette.white.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Text(
              'BIG BRANDS, BIGGEST LOOT!',
              style: t.labelSmall?.copyWith(
                color: ZopiqPalette.white.withValues(alpha: 0.85),
                letterSpacing: 2.0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.md),

          // ── Three deal cards filling the width ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.pageGutter,
              ),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < slide.dealCards!.length; i++) ...[
                    if (i > 0) const SizedBox(width: ZopiqSpacing.sm),
                    Expanded(
                      child: RepaintBoundary(
                        child: _MiniDealCard(deal: slide.dealCards![i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact deal card rendered inside the hero carousel slide.
class _MiniDealCard extends StatelessWidget {
  const _MiniDealCard({required this.deal});

  final _DealCardData deal;

  @override
  Widget build(BuildContext context) {
    return ZopiqPressable(
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          borderRadius: ZopiqRadii.rLg,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: deal.gradient,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: ZopiqRadii.rLg,
          child: Stack(
            children: <Widget>[
              // Title at the top
              Positioned(
                left: ZopiqSpacing.sm,
                top: ZopiqSpacing.sm,
                right: ZopiqSpacing.sm,
                child: Text(
                  deal.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              // Bold headline at the bottom-left
              Positioned(
                left: ZopiqSpacing.sm,
                bottom: ZopiqSpacing.sm,
                child: Text(
                  deal.headline,
                  style: const TextStyle(
                    color: Color(0xFFFFEB3B),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: -0.3,
                    shadows: <Shadow>[
                      Shadow(
                        color: Color(0x66000000),
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
              // Art illustration at bottom-right
              Positioned(
                right: 0,
                bottom: 0,
                width: 56,
                height: 56,
                child: _DealArtWidget(artType: deal.artType),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Routes to the correct custom-painted illustration.
class _DealArtWidget extends StatelessWidget {
  const _DealArtWidget({required this.artType});

  final _DealArt artType;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: switch (artType) {
        _DealArt.priceDrop => _PriceDropPainter(),
        _DealArt.dealFeast => _DealFeastPainter(),
        _DealArt.topBrands => _TopBrandsPainter(),
        _DealArt.freeDelivery => _FreeDeliveryPainter(),
      },
    );
  }
}

// ─── Custom-painted deal card art ────────────────────────────────────────────

/// Price tag with a downward arrow.
class _PriceDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    final Path tag = Path()
      ..moveTo(cx - 8, cy - 18)
      ..lineTo(cx + 14, cy - 18)
      ..lineTo(cx + 14, cy + 8)
      ..lineTo(cx + 3, cy + 20)
      ..lineTo(cx - 8, cy + 8)
      ..close();
    canvas.drawPath(tag, Paint()..color = const Color(0xFFFDD835));

    final Paint arrow = Paint()
      ..color = const Color(0xFF1B5E20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx + 3, cy - 10), Offset(cx + 3, cy + 6), arrow);
    canvas.drawLine(Offset(cx - 3, cy - 1), Offset(cx + 3, cy + 6), arrow);
    canvas.drawLine(Offset(cx + 9, cy - 1), Offset(cx + 3, cy + 6), arrow);

    canvas.drawCircle(
      Offset(cx - 2, cy - 11),
      2.5,
      Paint()..color = const Color(0xFF2E8B57),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Starburst badge with "%".
class _DealFeastPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    final Path burst = Path();
    const int points = 12;
    const double outerR = 22;
    const double innerR = 16;
    for (int i = 0; i < points * 2; i++) {
      final double angle = (i * math.pi) / points - math.pi / 2;
      final double r = i.isEven ? outerR : innerR;
      final double x = cx + r * math.cos(angle);
      final double y = cy + r * math.sin(angle);
      if (i == 0) {
        burst.moveTo(x, y);
      } else {
        burst.lineTo(x, y);
      }
    }
    burst.close();
    canvas.drawPath(
      burst,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFFFF6D00), Color(0xFFE53935)],
        ).createShader(
          Rect.fromCenter(center: Offset(cx, cy), width: 44, height: 44),
        ),
    );

    final TextPainter tp = TextPainter(
      text: const TextSpan(
        text: '%',
        style: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Food bowls with ₹ symbol.
class _TopBrandsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    _drawBowl(canvas, Offset(cx - 5, cy - 1), 14, const Color(0xFFFFB74D));
    _drawBowl(canvas, Offset(cx + 6, cy + 5), 12, const Color(0xFFFF8A65));

    final TextPainter tp = TextPainter(
      text: const TextSpan(
        text: '₹',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2 + 1, cy - tp.height / 2 - 8));
  }

  void _drawBowl(Canvas canvas, Offset c, double r, Color color) {
    final Path bowl = Path()
      ..addArc(Rect.fromCircle(center: c, radius: r), 0, math.pi)
      ..close();
    canvas.drawPath(bowl, Paint()..color = color);
    canvas.drawLine(
      Offset(c.dx - r, c.dy),
      Offset(c.dx + r, c.dy),
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(c.dx - 4, c.dy - 3),
      3.5,
      Paint()..color = const Color(0xFFEF5350),
    );
    canvas.drawCircle(
      Offset(c.dx + 3, c.dy - 2),
      3,
      Paint()..color = const Color(0xFF66BB6A),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Delivery bag with wheels.
class _FreeDeliveryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    final RRect bag = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy - 5), width: 22, height: 18),
      const Radius.circular(3),
    );
    canvas.drawRRect(bag, Paint()..color = const Color(0xFFFFB300));
    canvas.drawLine(
      Offset(cx - 11, cy - 10),
      Offset(cx + 11, cy - 10),
      Paint()
        ..color = const Color(0xFFFF8F00)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    final Paint wheel = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(cx - 8, cy + 11), 5.5, wheel);
    canvas.drawCircle(Offset(cx + 9, cy + 11), 5.5, wheel);
    canvas.drawCircle(Offset(cx - 8, cy + 11), 1.5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx + 9, cy + 11), 1.5, Paint()..color = Colors.white);

    final Paint line = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 20, cy - 1), Offset(cx - 14, cy - 1), line);
    canvas.drawLine(Offset(cx - 22, cy + 4), Offset(cx - 14, cy + 4), line);
    canvas.drawLine(Offset(cx - 18, cy + 9), Offset(cx - 14, cy + 9), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A starburst of triangular rays.

class _RayBurst extends StatelessWidget {
  const _RayBurst({required this.radius, required this.alpha});

  final double radius;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(radius * 2),
      painter: _RayBurstPainter(
        color: ZopiqPalette.white.withValues(alpha: alpha),
      ),
    );
  }
}

class _RayBurstPainter extends CustomPainter {
  const _RayBurstPainter({required this.color});

  final Color color;

  static const int _rays = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;
    final Paint paint = Paint()..color = color;
    final Path path = Path();
    const double step = 2 * math.pi / _rays;
    for (int i = 0; i < _rays; i++) {
      final double mid = i * step;
      path
        ..moveTo(c.dx, c.dy)
        ..lineTo(
          c.dx + r * math.cos(mid - step / 4),
          c.dy + r * math.sin(mid - step / 4),
        )
        ..lineTo(
          c.dx + r * math.cos(mid + step / 4),
          c.dy + r * math.sin(mid + step / 4),
        )
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RayBurstPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// One hero slide's content + colours.
@immutable
class _HeroSlide {
  const _HeroSlide({
    required this.eyebrow,
    required this.eyebrowIcon,
    required this.headline,
    required this.subline,
    required this.gradient,
    this.dealCards,
  });

  final String eyebrow;
  final IconData eyebrowIcon;
  final String headline;
  final String subline;
  final List<Color> gradient;

  /// When non-null, this slide renders as a "deals" slide: compact headline
  /// at the top with a horizontally scrolling row of deal cards below it.
  final List<_DealCardData>? dealCards;
}

/// Data for one deal card inside a hero slide.
@immutable
class _DealCardData {
  const _DealCardData({
    required this.title,
    required this.headline,
    required this.gradient,
    required this.artType,
  });

  final String title;
  final String headline;
  final List<Color> gradient;
  final _DealArt artType;
}

/// Which illustration art to paint on a deal card.
enum _DealArt { priceDrop, dealFeast, topBrands, freeDelivery }

/// The empty state — what the hero shows when no campaign is published, and not
/// a placeholder waiting to be deleted. The first slide stays on the brand
/// orange; the rest carry the offers that used to live in the removed cards,
/// plus a teaser for the upcoming Dining feature.
///
/// Real artwork arrives as rows now (migration 0053), which is why this list is
/// no longer the thing to edit when copy changes.
const List<_HeroSlide> _slides = <_HeroSlide>[
  _HeroSlide(
    eyebrow: 'BIG BRANDS · BIGGEST LOOT',
    eyebrowIcon: Icons.local_fire_department_rounded,
    headline: 'BIG BRAND\nHEIST',
    subline: 'Mega deals from your favourite brands!',
    gradient: <Color>[Color(0xFF4A148C), Color(0xFF1A0033)],
    dealCards: <_DealCardData>[
      _DealCardData(
        title: 'Dishes Starting\nAt ₹29',
        headline: 'PRICE\nDROP',
        gradient: <Color>[Color(0xFF9CCC65), Color(0xFF558B2F)], // Lime
        artType: _DealArt.priceDrop,
      ),
      _DealCardData(
        title: 'Deal\nFeast',
        headline: 'GET 70%\nOFF',
        gradient: <Color>[Color(0xFFFF9800), Color(0xFFBF360C)], // Orange
        artType: _DealArt.dealFeast,
      ),
      _DealCardData(
        title: 'Top Brands,\nTop Deals',
        headline: 'FLAT\n₹100 OFF',
        gradient: <Color>[Color(0xFF2E7D32), Color(0xFF1B5E20)], // Dark Green
        artType: _DealArt.topBrands,
      ),
    ],
  ),
  _HeroSlide(
    eyebrow: 'LAUNCH WEEK',
    eyebrowIcon: Icons.bolt_rounded,
    headline: 'ITEMS AT 50% OFF',
    subline: 'Free delivery on your first order',
    gradient: <Color>[ZopiqPalette.primary, ZopiqPalette.primaryDeep],
  ),
  _HeroSlide(
    eyebrow: 'USE TRYNEW',
    eyebrowIcon: Icons.local_offer_rounded,
    headline: '60% OFF',
    subline: 'Up to ₹120 on your first order',
    gradient: <Color>[Color(0xFFFF4E8B), Color(0xFFC31432)],
  ),
  _HeroSlide(
    eyebrow: 'USE ZOPIQ150',
    eyebrowIcon: Icons.local_offer_rounded,
    headline: 'FLAT ₹150 OFF',
    subline: 'On orders above ₹399',
    gradient: <Color>[Color(0xFF7C4DFF), Color(0xFF5B2A9D)],
  ),
  _HeroSlide(
    eyebrow: 'NEW · DINING',
    eyebrowIcon: Icons.restaurant_rounded,
    headline: 'BOOK A TABLE',
    subline: 'Reserve at top spots near you',
    gradient: <Color>[Color(0xFF00B894), Color(0xFF007E63)],
  ),
  _HeroSlide(
    eyebrow: 'USE SAVE30',
    eyebrowIcon: Icons.local_offer_rounded,
    headline: '30% OFF',
    subline: 'Up to ₹75, all weekend',
    gradient: <Color>[Color(0xFF2E86FF), Color(0xFF1C4FD8)],
  ),
];
