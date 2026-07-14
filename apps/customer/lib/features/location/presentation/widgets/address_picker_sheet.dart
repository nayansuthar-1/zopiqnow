import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';

/// Bottom sheet for choosing the delivery address: detect via GPS, or pick a
/// saved one.
Future<void> showAddressPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.xl)),
    ),
    builder: (_) => const AddressPickerSheet(),
  );
}

class AddressPickerSheet extends ConsumerStatefulWidget {
  const AddressPickerSheet({super.key});

  @override
  ConsumerState<AddressPickerSheet> createState() => _AddressPickerSheetState();
}

class _AddressPickerSheetState extends ConsumerState<AddressPickerSheet> {
  bool _detecting = false;
  String? _error;

  Future<void> _useCurrentLocation() async {
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      await ref.read(selectedAddressProvider.notifier).useCurrentLocation();
      if (mounted) Navigator.of(context).pop();
    } on LocationFailure catch (failure) {
      // The previously selected address stays selected — a failed detect must
      // not blank the Home header.
      if (mounted) {
        setState(() {
          _error = failure.message;
          _detecting = false;
        });
      }
    }
  }

  Future<void> _select(Address address) async {
    await ref.read(selectedAddressProvider.notifier).select(address);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final AsyncValue<List<Address>> saved = ref.watch(savedAddressesProvider);
    final Address? selected = ref.watch(selectedAddressProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZopiqSpacing.pageGutter,
          0,
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Select delivery location', style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: 'Use my current location',
              icon: Icons.my_location_rounded,
              isLoading: _detecting,
              expand: true,
              onPressed: _useCurrentLocation,
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.sm),
              Text(_error!, style: t.bodySmall?.copyWith(color: zc.nonVeg)),
            ],
            const SizedBox(height: ZopiqSpacing.lg),
            Text(
              'SAVED ADDRESSES',
              style: t.labelSmall?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            // The list is the account's now, so it arrives over the network. A
            // failure here is not fatal to the sheet: GPS above still works, and
            // that is the path a signed-out user takes anyway.
            saved.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object _, StackTrace _) => Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: ZopiqSpacing.md,
                ),
                child: Text(
                  'We couldn\'t load your saved addresses.',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ),
              data: (List<Address> addresses) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (addresses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: ZopiqSpacing.sm,
                      ),
                      child: Text(
                        'Nothing saved yet.',
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ),
                  ...addresses.map(
                    (Address address) => _AddressTile(
                      address: address,
                      isSelected: selected?.id == address.id,
                      onTap: () => _select(address),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.add_rounded, color: zc.primary),
                    title: Text(
                      'Add a new address',
                      style: t.titleSmall?.copyWith(color: zc.primary),
                    ),
                    // The route is auth-guarded: a signed-out tap lands on login
                    // and comes back. The sheet closes first — leaving a modal
                    // over the login screen is how you get a dead-looking app.
                    onTap: () {
                      Navigator.of(context).pop();
                      context.pushNamed(Routes.addressNew);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.address,
    required this.isSelected,
    required this.onTap,
  });

  final Address address;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        address.label == 'Work'
            ? Icons.work_outline_rounded
            : Icons.home_outlined,
        color: zc.primary,
      ),
      title: Text(address.label ?? address.line1),
      subtitle: Text(
        address.shortDisplay,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle_rounded, color: zc.primary)
          : null,
      onTap: onTap,
    );
  }
}
