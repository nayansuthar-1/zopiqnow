import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/repositories/address_repository.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';

/// The customer's saved addresses: add, edit, delete.
///
/// Auth-guarded by the router (`/addresses` is a protected prefix) — an address
/// book belongs to an account, and until now the app had neither, handing every
/// user the same two hardcoded Hyderabad addresses.
class AddressBookPage extends ConsumerWidget {
  const AddressBookPage({super.key});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Address address,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete this address?'),
        content: Text(
          '${address.shortDisplay} will be removed from your saved addresses. '
          'Orders you have already placed are not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    try {
      await ref.read(addressBookControllerProvider.notifier).delete(address.id);
    } on AddressBookFailure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final AsyncValue<List<Address>> saved = ref.watch(savedAddressesProvider);
    final Address? selected = ref.watch(selectedAddressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Address book')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed(Routes.addressNew),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add address'),
        backgroundColor: zc.primary,
        foregroundColor: Colors.white,
      ),
      body: saved.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.cloud_off_rounded, size: 56, color: zc.textMuted),
                const SizedBox(height: ZopiqSpacing.lg),
                Text(
                  error is AddressBookFailure
                      ? error.message
                      : 'We couldn\'t load your addresses.',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: ZopiqSpacing.xl),
                ZopiqButton(
                  label: 'Retry',
                  expand: false,
                  onPressed: () => ref.invalidate(savedAddressesProvider),
                ),
              ],
            ),
          ),
        ),
        data: (List<Address> addresses) {
          if (addresses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(ZopiqSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.location_off_rounded,
                      size: 56,
                      color: zc.textMuted,
                    ),
                    const SizedBox(height: ZopiqSpacing.lg),
                    Text('No saved addresses', style: t.titleMedium),
                    const SizedBox(height: ZopiqSpacing.xs),
                    Text(
                      'Save an address and it will be one tap away at checkout.',
                      style: t.bodyMedium?.copyWith(color: zc.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(
              top: ZopiqSpacing.sm,
              // Clear of the FAB, which would otherwise sit on the last row.
              bottom: 96,
            ),
            itemCount: addresses.length,
            itemBuilder: (BuildContext context, int i) {
              final Address address = addresses[i];
              return _AddressRow(
                address: address,
                isSelected: selected?.id == address.id,
                onEdit: () => context.pushNamed(
                  Routes.addressEdit,
                  pathParameters: <String, String>{'id': address.id},
                  extra: address,
                ),
                onDelete: () => _delete(context, ref, address),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.address,
    required this.isSelected,
    required this.onEdit,
    required this.onDelete,
  });

  final Address address;

  /// The address this device is currently delivering to. Worth marking: it is
  /// the one whose deletion will clear the Home header.
  final bool isSelected;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xs,
      ),
      child: ZopiqCard(
        onTap: onEdit,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              address.label == 'Work'
                  ? Icons.work_outline_rounded
                  : Icons.home_outlined,
              color: zc.primary,
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          address.label ?? address.line1,
                          style: t.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected) ...<Widget>[
                        const SizedBox(width: ZopiqSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZopiqSpacing.sm,
                            vertical: ZopiqSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: zc.primary.withValues(alpha: 0.12),
                            borderRadius: ZopiqRadii.rPill,
                          ),
                          child: Text(
                            'Delivering here',
                            style: t.labelSmall?.copyWith(color: zc.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    address.shortDisplay,
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              color: zc.textMuted,
              tooltip: 'Delete address',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
