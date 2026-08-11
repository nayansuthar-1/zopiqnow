import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/bottom_nav_provider.dart';
import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/location_prompt.dart';

/// The sheet that comes up on app open when location is unavailable.
///
/// It is not a warning. Every route to an address is on it — switch location on,
/// pick a saved one, or type a place — so a customer who has location off is
/// never told off about it, they are handed the three ways forward and can
/// dismiss all of them.
///
/// Separate from `showAddressPicker`, which is the same list without the
/// permission card, because that one is opened deliberately by tapping the
/// header. This one arrives uninvited, which is why it leads with the reason it
/// is here and carries a close button big enough to find.
/// Whether the sheet has already had its turn this run.
///
/// In memory, like [locationGateProvider] and for the same reason: "every time
/// the app opens" means once per launch, not once per navigation. Persisting it
/// would turn one dismissal into a permanent one; not having it at all would put
/// the sheet in front of every rebuild of the shell.
final StateProvider<bool> locationSheetShownProvider = StateProvider<bool>(
  (Ref ref) => false,
);

Future<void> showLocationOffSheet(BuildContext context, WidgetRef ref) {
  return withBottomNavHidden(
    ref,
    () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Transparent, so the round close button can float clear of the sheet
      // rather than sit inside it taking a row of its own.
      backgroundColor: Colors.transparent,
      builder: (_) => const LocationOffSheet(),
    ),
  );
}

class LocationOffSheet extends ConsumerStatefulWidget {
  const LocationOffSheet({super.key});

  @override
  ConsumerState<LocationOffSheet> createState() => _LocationOffSheetState();
}

class _LocationOffSheetState extends ConsumerState<LocationOffSheet> {
  final TextEditingController _search = TextEditingController();

  /// The in-flight search, cancelled on every keystroke — see [_onQueryChanged].
  Timer? _debounce;

  List<Address> _results = const <Address>[];
  bool _searching = false;
  bool _searched = false;
  bool _enabling = false;

  /// Why location is unavailable, so the card can name it. Read once when the
  /// sheet opens and again after "Enable", because that is the only thing that
  /// changes it while the sheet is up.
  LocationReadiness? _readiness;

  static const Duration _searchDebounce = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    unawaited(_refreshReadiness());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refreshReadiness() async {
    final LocationReadiness state = await ref
        .read(deviceLocationServiceProvider)
        .readiness();
    if (mounted) setState(() => _readiness = state);
  }

  /// "Enable" — the whole ladder, in one tap.
  ///
  /// [ensureLocationReady] turns location services on in place, shows the Play
  /// disclosure, or sends a blocked customer to settings, whichever this device
  /// actually needs. Only when it says yes do we touch the GPS.
  Future<void> _enable() async {
    setState(() => _enabling = true);
    try {
      if (!await ensureLocationReady(context, ref)) {
        // Declining is an answer. Re-read the state — they may have turned
        // services on and then refused the permission — and say nothing.
        await _refreshReadiness();
        return;
      }
      await ref.read(selectedAddressProvider.notifier).useCurrentLocation();
      if (mounted) Navigator.of(context).pop();
    } on LocationFailure {
      // Everything recoverable was already offered above, so a failure here is
      // the geocoder coming up empty or the fix not having taken. The saved
      // addresses and the search box are still on screen and still work.
      await _refreshReadiness();
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

  /// Debounced, so typing "Ramdev Chouraha" costs one geocode rather than
  /// fifteen. Each keystroke cancels the pending one.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final String query = value.trim();

    if (query.length < 3) {
      // Under three characters the geocoder matches half the country. Clear
      // rather than search, so the list does not sit there showing results for
      // a word the customer has since deleted.
      setState(() {
        _results = const <Address>[];
        _searching = false;
        _searched = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(_searchDebounce, () => unawaited(_runSearch(query)));
  }

  Future<void> _runSearch(String query) async {
    final List<Address> found = await ref
        .read(deviceLocationServiceProvider)
        .searchPlaces(query);

    // The field may have moved on — or been emptied — while the geocoder was
    // working. Dropping a stale answer is cheaper than showing the wrong one.
    if (!mounted || _search.text.trim() != query) return;
    setState(() {
      _results = found;
      _searching = false;
      _searched = true;
    });
  }

  Future<void> _select(Address address) async {
    await ref.read(selectedAddressProvider.notifier).select(address);
    if (mounted) Navigator.of(context).pop();
  }

  void _seeAll() {
    // Closes first: leaving a modal over a pushed screen is how you get an app
    // that looks dead. The same call `showAddressPicker` makes.
    Navigator.of(context).pop();
    context.pushNamed(Routes.addresses);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Address>> saved = ref.watch(savedAddressesProvider);

    return Padding(
      // Lifts the whole sheet above the keyboard when the search field has
      // focus, rather than letting it type behind one.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _CloseButton(),
          const SizedBox(height: ZopiqSpacing.md),
          Flexible(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(ZopiqRadii.xl),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    ZopiqSpacing.pageGutter,
                    ZopiqSpacing.lg,
                    ZopiqSpacing.pageGutter,
                    ZopiqSpacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _PermissionCard(
                        readiness: _readiness,
                        busy: _enabling,
                        onEnable: _enabling ? null : _enable,
                      ),
                      const SizedBox(height: ZopiqSpacing.xl),
                      _SectionRow(onSeeAll: _seeAll),
                      const SizedBox(height: ZopiqSpacing.md),
                      _SavedAddresses(saved: saved, onSelect: _select),
                      const SizedBox(height: ZopiqSpacing.md),
                      _SearchField(
                        controller: _search,
                        onChanged: _onQueryChanged,
                      ),
                      _SearchResults(
                        results: _results,
                        searching: _searching,
                        searched: _searched,
                        onSelect: _select,
                      ),
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

/// The round dismiss button that floats above the sheet.
///
/// Above rather than inside, because the sheet is a suggestion and the way out
/// of it should not have to compete for space with three ways further in.
class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    // Inverted per theme rather than a fixed dark circle: this floats over the
    // dimmed page, not over the sheet, so it takes its contrast from the
    // backdrop. A `textStrong` circle would be a near-white disc carrying a
    // white glyph in dark mode — an invisible close button on a sheet that
    // arrived uninvited.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color background = isDark ? ZopiqPalette.white : ZopiqPalette.black;
    final Color foreground = isDark ? ZopiqPalette.black : ZopiqPalette.white;

    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).pop(),
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.md),
          child: Icon(Icons.close_rounded, color: foreground, size: 22),
        ),
      ),
    );
  }
}

/// The reason the sheet is here, and the one tap that fixes it.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.readiness,
    required this.busy,
    required this.onEnable,
  });

  final LocationReadiness? readiness;
  final bool busy;
  final VoidCallback? onEnable;

  /// Says the true thing for this device rather than one sentence for every
  /// case: "allow location access" is the wrong instruction when the problem is
  /// that GPS is switched off, and vice versa.
  ({String title, String detail}) get _copy => switch (readiness) {
    LocationReadiness.serviceOff => (
      title: 'Location is switched off',
      detail: 'Turn on location to see restaurants that deliver to you.',
    ),
    LocationReadiness.permissionBlocked => (
      title: 'Location is blocked for Zopiq',
      detail: 'Turn it back on in app settings, or pick an address below.',
    ),
    _ => (
      title: 'Location permission is off',
      detail: 'Enable your location permission for a better experience.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final ({String title, String detail}) copy = _copy;

    return Container(
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: ZopiqRadii.rLg,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.location_off_rounded,
            size: 34,
            color: locationOffColor(context),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  copy.title,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  copy.detail,
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          ZopiqButton(
            label: 'Enable',
            expand: false,
            isLoading: busy,
            onPressed: onEnable,
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          'Select a saved address',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        GestureDetector(
          onTap: onSeeAll,
          child: Text(
            'See all',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: context.zc.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The account's addresses, as cards.
///
/// A failure here is not fatal to the sheet: the Enable button above and the
/// search box below are both still routes to an address, and one of them is the
/// path a signed-out customer takes anyway.
class _SavedAddresses extends StatelessWidget {
  const _SavedAddresses({required this.saved, required this.onSelect});

  final AsyncValue<List<Address>> saved;
  final ValueChanged<Address> onSelect;

  @override
  Widget build(BuildContext context) {
    return saved.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
        child: Center(child: ZopiqLoader()),
      ),
      error: (Object _, StackTrace _) => const _Note(
        text: 'We couldn\'t load your saved addresses.',
      ),
      data: (List<Address> addresses) {
        if (addresses.isEmpty) {
          return const _Note(text: 'No saved addresses yet.');
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final Address address in addresses)
              Padding(
                padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
                child: _AddressCard(
                  address: address,
                  onTap: () => onSelect(address),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.onTap});

  final Address address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: ZopiqRadii.rLg,
      child: InkWell(
        borderRadius: ZopiqRadii.rLg,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.lg),
          child: Row(
            children: <Widget>[
              Icon(
                address.label == 'Work'
                    ? Icons.work_outline_rounded
                    : Icons.home_outlined,
                color: zc.textStrong,
                size: 24,
              ),
              const SizedBox(width: ZopiqSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      address.label ?? address.line1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.xxs),
                    Text(
                      address.shortDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: ZopiqRadii.rLg,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search location manually',
          hintStyle: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: zc.textMuted),
          prefixIcon: Icon(Icons.search_rounded, color: zc.primary, size: 22),
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: ZopiqSpacing.lg,
            horizontal: ZopiqSpacing.md,
          ),
        ),
      ),
    );
  }
}

/// What the geocoder found, under the field it was typed into.
///
/// Nothing at all until a search has actually run: an empty list before that is
/// "you have not typed anything", which needs no words on screen.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.results,
    required this.searching,
    required this.searched,
    required this.onSelect,
  });

  final List<Address> results;
  final bool searching;
  final bool searched;
  final ValueChanged<Address> onSelect;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: ZopiqSpacing.lg),
        child: Center(child: ZopiqLoader()),
      );
    }
    if (results.isEmpty) {
      if (!searched) return const SizedBox.shrink();
      return const _Note(
        text: 'No places matched that. Try a landmark or an area name.',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: ZopiqSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final Address place in results)
            Padding(
              padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
              child: _AddressCard(
                address: place,
                onTap: () => onSelect(place),
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.zc.textMuted),
      ),
    );
  }
}
