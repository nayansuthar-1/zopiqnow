import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/location_disclosure.dart';

/// Asked once at startup: where are we delivering?
///
/// **Why this is a screen and not a prompt on Home.** Every number Home shows is
/// a function of where the customer is — the distance on each card, the delivery
/// fee, the ETA, and whether a kitchen appears at all (0098 draws a radius). Home
/// without an address is not Home with one field missing; it is a list sorted by
/// nothing, and a customer reading it has no way to know that. Asking first is
/// the honest order.
///
/// **Skippable, deliberately.** A hard gate strands anyone who denies the OS
/// permission and has no saved address — and denying is a decision the
/// disclosure explicitly offers ("You can skip this and type your address
/// instead"), so refusing to let them past would be an argument with an answer
/// we asked for. Skipping lands on Home in exactly the state it has always had:
/// "Set delivery location" in the header, and nothing pretending to be accurate.
///
/// It asks again on the next cold start, because it is one tap to dismiss and a
/// customer who skipped it once has not said "never".
class LocationGatePage extends ConsumerStatefulWidget {
  const LocationGatePage({super.key});

  @override
  ConsumerState<LocationGatePage> createState() => _LocationGatePageState();
}

class _LocationGatePageState extends ConsumerState<LocationGatePage> {
  bool _detecting = false;
  String? _error;

  Future<void> _useCurrentLocation() async {
    final DeviceLocationService service = ref.read(
      deviceLocationServiceProvider,
    );

    // Play's User Data policy: the in-app disclosure comes before the system
    // dialog, and only when the system dialog would actually appear. Showing it
    // to somebody who has already decided is a second sheet in front of an
    // answer they have given.
    if (await service.needsPermissionPrompt()) {
      if (!mounted) return;
      final bool accepted = await showLocationDisclosure(context);
      // Declining is an answer, not a failure. Say nothing and stop — an error
      // message here would be arguing with it.
      if (!accepted) return;
    }

    if (!mounted) return;
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      await ref.read(selectedAddressProvider.notifier).useCurrentLocation();
      if (mounted) _done();
    } on LocationFailure catch (e) {
      // The service's own sentence — "Location is switched off", "Permission
      // denied" — because each of those has a different next step and the
      // generic one has none.
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// Onward to Home. `go` rather than `pop`: the gate is a redirect target with
  /// nothing beneath it on the stack.
  void _done() {
    ref.read(locationGateProvider.notifier).state = true;
    if (mounted) context.go('/');
  }

  Future<void> _enterManually() async {
    ref.read(locationGateProvider.notifier).state = true;
    if (!mounted) return;
    // The address book, which owns adding one and selecting it. Coming back with
    // an address selected leaves Home correct; coming back without one leaves it
    // exactly as skipping would.
    await context.pushNamed(Routes.addresses);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          child: Column(
            children: <Widget>[
              const SizedBox(height: ZopiqSpacing.xxl),

              // Centred, and the only text on the screen. The paragraph that
              // used to sit under it explained *why* we were asking, which is a
              // reasonable thing to say and the wrong moment to say it: there is
              // one decision here and two buttons that make it.
              Text(
                'Set your location to start exploring\nrestaurants near you',
                textAlign: TextAlign.center,
                style: t.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),

              // Takes whatever is left between the heading and the buttons, so
              // the art shrinks on a short screen rather than pushing the
              // buttons off it.
              const Expanded(child: Center(child: _LocationArt())),

              if (_error != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(ZopiqSpacing.md),
                  decoration: BoxDecoration(
                    color: zc.nonVeg.withValues(alpha: 0.10),
                    borderRadius: ZopiqRadii.rMd,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.error_outline_rounded,
                        size: 20,
                        color: zc.nonVeg,
                      ),
                      const SizedBox(width: ZopiqSpacing.sm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: t.bodySmall?.copyWith(color: zc.nonVeg),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.lg),
              ],

              ZopiqButton(
                label: _detecting ? 'Finding you…' : 'Enable Device Location',
                variant: ZopiqButtonVariant.cta,
                onPressed: _detecting ? null : _useCurrentLocation,
              ),
              const SizedBox(height: ZopiqSpacing.sm),
              ZopiqButton(
                label: 'Enter Your Location Manually',
                variant: ZopiqButtonVariant.outline,
                onPressed: _detecting ? null : _enterManually,
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              // Kept, though the reference has no equivalent. Someone who denies
              // the OS permission and has no saved address would otherwise be
              // held on this screen with no way past it — and denying is an
              // answer the disclosure explicitly invites. Muted and last, so it
              // is available without competing with the two real choices.
              TextButton(
                onPressed: _detecting ? null : _done,
                child: Text(
                  'Skip for now',
                  style: t.labelLarge?.copyWith(color: zc.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The illustration between the heading and the buttons.
///
/// Drawn rather than shipped: there is no artwork in `assets/` for this, and a
/// flat icon on its own read as an empty state rather than an invitation. The
/// pieces are a soft tinted field, the pin, and two dishes lifted from the
/// category art already in the bundle — so it says "restaurants near you" with
/// nothing new to download and nothing to keep in sync.
class _LocationArt extends StatelessWidget {
  const _LocationArt();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double side = constraints.biggest.shortestSide;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: side * 0.82,
                height: side * 0.82,
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: side * 0.56,
                height: side * 0.56,
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
              Icon(
                Icons.location_on_rounded,
                size: side * 0.30,
                color: zc.primary,
              ),
              Positioned(
                left: side * 0.04,
                top: side * 0.30,
                child: _Dish(asset: 'assets/categories/burger.png', size: side * 0.20),
              ),
              Positioned(
                right: side * 0.04,
                top: side * 0.22,
                child: _Dish(asset: 'assets/categories/pizza.png', size: side * 0.20),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Dish extends StatelessWidget {
  const _Dish({required this.asset, required this.size});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: context.zc.divider),
      ),
      // A missing category file must not take the whole gate down with it.
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Whether the gate has had its answer this run.
///
/// In memory rather than on disk, and that is the whole design: a customer who
/// skipped is asked again next cold start, but is not asked again the moment
/// they navigate Home → restaurant → back. Persisting it would turn one dismissal
/// into a permanent one, and the alternative — never remembering — would put the
/// gate in front of every single navigation.
final StateProvider<bool> locationGateProvider = StateProvider<bool>(
  (Ref ref) => false,
);
