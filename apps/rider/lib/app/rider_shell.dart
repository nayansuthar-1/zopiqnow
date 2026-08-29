import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/battery_optimisation.dart';
import 'package:zopiq_rider/core/storage/secure_store.dart';
import 'package:zopiq_rider/core/widgets/rider_animations.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/auth/presentation/pages/profile_page.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/pages/earnings_page.dart';
import 'package:zopiq_rider/features/jobs/presentation/pages/home_page.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';
import 'package:zopiq_rider/features/jobs/presentation/widgets/offer_sheet.dart';
import 'package:zopiq_rider/features/notifications/offer_ring.dart';

/// Three main tabs for the Rider partner experience using custom vector SVG icons.
class RiderShell extends ConsumerStatefulWidget {
  const RiderShell({super.key});

  @override
  ConsumerState<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends ConsumerState<RiderShell> {
  int _index = 0;

  /// The order whose sheet is currently up, so a rebuild does not open a second
  /// one over the first. Cleared when the sheet closes for any reason —
  /// accepted, declined, or run out.
  String? _showing;

  /// Set the first time the battery question is considered, so a rider whose
  /// carrying state flickers is not asked twice in one shift.
  bool _batteryConsidered = false;

  /// One key, one answer, kept forever: a rider who has been shown this once has
  /// been shown it. Nagging somebody about a system setting every time they pick
  /// up a bag is how an app gets uninstalled.
  static const String _batteryAskedKey = 'battery_prompt_shown';

  @override
  void initState() {
    super.initState();
    // The ring is answered outside the widget tree — from the tray, and for a
    // killed app from a different isolate entirely — so it arrives as a
    // [ValueNotifier] rather than a provider. See `OfferRing.answered`.
    OfferRing.answered.addListener(_onRingAnswered);
  }

  @override
  void dispose() {
    OfferRing.answered.removeListener(_onRingAnswered);
    super.dispose();
  }

  /// The rider tapped the ring. Put them where the job is.
  ///
  /// Deliberately **not** "open the offer sheet". Fifteen seconds is not long
  /// enough to unlock a phone, so by the time this runs the window has usually
  /// passed to the next partner — and since 0148 that no longer means the job is
  /// gone: it is on the Jobs tab, marked as offered to somebody else, still
  /// takeable. So this switches to that tab and refreshes it. If the countdown
  /// did survive, [currentOfferProvider] raises the sheet over the top on its
  /// own, exactly as it does for an offer that arrived while the app was open.
  void _onRingAnswered() {
    final String? orderId = OfferRing.answered.value;
    if (orderId == null || !mounted) return;
    OfferRing.answered.value = null;
    setState(() => _index = 0);
    ref
      ..invalidate(offersProvider)
      ..invalidate(boardProvider);
  }

  /// Puts the sheet up and keeps [_showing] honest for as long as it is there.
  ///
  /// `isDismissible: false` and `enableDrag: false` on purpose, and it is the
  /// one modal in this app that refuses a swipe-away: the two answers are
  /// Accept and Decline, and a third exit that silently means "let it time out"
  /// costs the customer fifteen seconds the rider had already decided against.
  /// Declining is one tap and re-offers the job immediately.
  Future<void> _raise(DeliveryOffer offer) async {
    _showing = offer.orderId;
    // The rider is looking at the offer, so the phone has done its job and can
    // stop ringing. Safe when nothing is ringing — see `OfferRing.stop`.
    unawaited(OfferRing.stop());
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => OfferSheet(offer: offer),
      );
    } finally {
      // In a `finally` so a sheet torn down by a route change — a sign-out, a
      // deep link — does not leave this pinned at an order id that will never
      // come round again, which would make the *next* offer silently not open.
      if (mounted) _showing = null;
    }
  }

  /// Asks the rider to take this app off the battery optimiser's list, once,
  /// the first time they are actually carrying something (audit RID-001).
  ///
  /// **Why here and why then.** The foreground service the reporter now runs is
  /// what stock Android honours, and on Xiaomi, Oppo, Vivo, Realme and Samsung
  /// it is not enough on its own — those builds stop an unexempted service
  /// anyway, screen off, mid-ride. Asked at the moment the rider picks up a bag
  /// the request explains itself; asked at launch it is one more dialog between
  /// somebody and their first job.
  ///
  /// Skipped outright when the phone already exempts us, which is most stock
  /// Android and every rider who has already done this once.
  Future<void> _maybeAskAboutBattery() async {
    if (_batteryConsidered) return;
    _batteryConsidered = true;

    final BatteryOptimisation battery = ref.read(batteryOptimisationProvider);
    if (await battery.isExempt()) return;

    final SecureStore store = ref.read(secureStoreProvider);
    if (await store.read(_batteryAskedKey) != null) return;
    if (!mounted) return;

    final bool open =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Keep your location running'),
            content: const Text(
              "This phone's battery saver can stop Zopiq while you ride, and "
              'the customer stops seeing where you are. Find Zopiq Rider in '
              "the list and set it to Don't optimise.",
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Not now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Open settings'),
              ),
            ],
          ),
        ) ??
        false;

    // Written after the answer, not before it: a rider who was interrupted
    // before they could answer has not been asked, and should be next time.
    await store.write(_batteryAskedKey, 'y');
    if (open) await battery.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final List<Job> run = ref.watch(activeJobsProvider);
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;

    // The rider's position, on while they are carrying (0057). Watched here
    // rather than on the jobs screen because it must keep running while they
    // are looking at their earnings or their profile — a map that blanks
    // because the rider switched tabs is a map nobody trusts.
    ref.watch(locationReportingProvider);

    // The battery question rides on the same edge as the tracking above: the
    // first time this rider is genuinely carrying, and never on a launch.
    ref.listen<bool>(carryingProvider, (bool? _, bool carrying) {
      if (carrying) unawaited(_maybeAskAboutBattery());
    });

    // An offer is a question with a deadline, so it is raised from the shell
    // and not from a screen: whichever tab the rider is on, the sheet comes up.
    ref.listen<DeliveryOffer?>(currentOfferProvider, (
      DeliveryOffer? _,
      DeliveryOffer? offer,
    ) {
      if (offer == null || offer.orderId == _showing) return;
      if (offer.isExpired(DateTime.now())) return;
      unawaited(_raise(offer));
    });

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          HomePage(),
          EarningsPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: zc.textStrong.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: zc.primary.withValues(alpha: 0.14),
          onDestinationSelected: (int i) => setState(() => _index = i),
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: run.isEmpty
                  ? RiderSvgIcon(
                      type: RiderSvgType.deliveryBike,
                      color: zc.textMuted,
                    )
                  : RiderPulseBadge(
                      glowColor: zc.primary,
                      enabled: true,
                      child: Badge(
                        backgroundColor: zc.primary,
                        label: run.length > 1 ? Text('${run.length}') : null,
                        child: RiderSvgIcon(
                          type: RiderSvgType.deliveryBike,
                          color: zc.primary,
                        ),
                      ),
                    ),
              selectedIcon: RiderSvgIcon(
                type: RiderSvgType.deliveryBike,
                color: zc.primary,
              ),
              label: 'Jobs',
            ),
            NavigationDestination(
              icon: RiderSvgIcon(
                type: RiderSvgType.wallet,
                color: zc.textMuted,
              ),
              selectedIcon: RiderSvgIcon(
                type: RiderSvgType.wallet,
                color: zc.primary,
              ),
              label: 'Earnings',
            ),
            NavigationDestination(
              icon: RiderSvgIcon(
                type: RiderSvgType.profile,
                color: zc.textMuted,
              ),
              selectedIcon: RiderSvgIcon(
                type: RiderSvgType.profile,
                color: zc.primary,
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
