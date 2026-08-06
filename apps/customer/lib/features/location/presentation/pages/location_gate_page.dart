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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),

              Container(
                padding: const EdgeInsets.all(ZopiqSpacing.lg),
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 40,
                  color: zc.primary,
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xl),

              Text(
                'Where should we deliver?',
                style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ZopiqSpacing.sm),
              Text(
                'Restaurants, delivery times and fees all depend on where you '
                'are. Set it once and the whole app follows.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),

              if (_error != null) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.lg),
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
              ],

              const Spacer(),

              ZopiqButton(
                label: _detecting ? 'Finding you…' : 'Use my current location',
                icon: Icons.my_location_rounded,
                variant: ZopiqButtonVariant.cta,
                onPressed: _detecting ? null : _useCurrentLocation,
              ),
              const SizedBox(height: ZopiqSpacing.sm),
              ZopiqButton(
                label: 'Enter address manually',
                variant: ZopiqButtonVariant.outline,
                onPressed: _detecting ? null : _enterManually,
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Center(
                child: TextButton(
                  onPressed: _detecting ? null : _done,
                  child: Text(
                    'Skip for now',
                    style: t.labelLarge?.copyWith(color: zc.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
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
