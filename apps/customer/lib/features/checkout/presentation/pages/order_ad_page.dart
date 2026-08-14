import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_ad.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/order_ad_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/corner_puck.dart';

/// The ad, full screen, with the map shrunk to the puck in its corner.
///
/// The mirror of the tracking map: there, the map fills the slot and the ad is
/// the puck; here it is the other way round. The puck pops rather than pushing a
/// map, so the two screens are one stack entry apart however the customer got
/// here and there is only ever one map alive.
///
/// **It says "Ad".** Small, over the artwork, always. A full-bleed picture
/// inside a food app otherwise reads as the food app's own offer, and this one
/// is somebody else's.
class OrderAdPage extends ConsumerStatefulWidget {
  const OrderAdPage({required this.ad, required this.orderId, super.key});

  final OrderAd ad;

  /// Which order was on screen. Carried only so the view counts once per order
  /// rather than once per rebuild (0125).
  final String? orderId;

  @override
  ConsumerState<OrderAdPage> createState() => _OrderAdPageState();
}

class _OrderAdPageState extends ConsumerState<OrderAdPage> {
  @override
  void initState() {
    super.initState();
    // Opening the ad *is* the click on the puck; the view is recorded by the map
    // that offered it. Recorded here rather than in the tap handler so it counts
    // once the screen actually exists.
    unawaited(
      ref
          .read(orderAdDataSourceProvider)
          .record(
            adId: widget.ad.id,
            kind: 'click',
            orderId: widget.orderId,
          ),
    );
  }

  Future<void> _openTarget() async {
    final OrderAd ad = widget.ad;
    await ref
        .read(orderAdDataSourceProvider)
        .record(adId: ad.id, kind: 'click', orderId: widget.orderId);
    if (!mounted) return;

    if (ad.opensExternally) {
      // externalApplication, not the in-app webview: the advertiser's site is
      // plainly not ours, and a browser with its own address bar is the clearest
      // way to say so.
      await launchUrl(
        Uri.parse(ad.ctaTarget),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    // An in-app target. Same rule the home hero follows: a restaurant is pushed
    // so it keeps a back arrow, everything else is a tab and is gone to.
    if (!mounted) return;
    if (ad.ctaTarget.startsWith('/restaurant/')) {
      // Its Future completes when that screen is popped, which is not something
      // this page waits for.
      unawaited(context.push(ad.ctaTarget));
    } else {
      context.go(ad.ctaTarget);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OrderAd ad = widget.ad;
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The artwork is the screen. `contain`, not `cover`: a banner is a
          // composed thing and cropping it cuts off the corner the designer put
          // the offer in — the same call the home hero made for the same reason.
          ZopiqNetworkImage(
            url: ad.imageUrl,
            fit: BoxFit.contain,
            fallback: Center(
              child: Icon(Icons.image_not_supported_rounded, color: zc.textMuted),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(ZopiqSpacing.sm),
                child: Row(
                  children: <Widget>[
                    _Scrim(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                        tooltip: 'Back to your order',
                      ),
                    ),
                    const Spacer(),
                    _Scrim(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZopiqSpacing.sm,
                          vertical: ZopiqSpacing.xxs,
                        ),
                        child: Text(
                          'Ad',
                          style: t.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(ZopiqSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (ad.headline.isNotEmpty)
                            _Scrim(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ZopiqSpacing.sm,
                                  vertical: ZopiqSpacing.xs,
                                ),
                                child: Text(
                                  ad.headline,
                                  style: t.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          if (ad.hasCta) ...<Widget>[
                            const SizedBox(height: ZopiqSpacing.sm),
                            ZopiqButton(
                              label: ad.ctaLabel,
                              onPressed: () => unawaited(_openTarget()),
                              // The glyph is the warning: a button that leaves
                              // the app should look like one before it is
                              // pressed, not after.
                              icon: ad.opensExternally
                                  ? Icons.open_in_new_rounded
                                  : Icons.chevron_right_rounded,
                              expand: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: ZopiqSpacing.md),
                    // Back to the map. Pops, never pushes — see the class note.
                    CornerPuck(
                      label: 'MAP',
                      icon: Icons.map_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dark rounded ground for white text over unknown artwork. The ad's own
/// picture decides what is behind these, so nothing may rely on it being pale.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: ZopiqRadii.rSm,
    ),
    child: child,
  );
}
