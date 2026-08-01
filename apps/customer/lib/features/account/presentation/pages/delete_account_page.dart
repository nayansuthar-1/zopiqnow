import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// Closing the account, on a screen of its own.
///
/// A screen rather than a menu row with a dialog on it, and that is a Play
/// Store requirement as much as a kindness: the deletion route has to be
/// findable and it has to say what it does before it does it. Somebody deleting
/// their account is owed the list — what goes, what stays, and why anything
/// stays at all — on the page where they decide, not in a help article.
///
/// The confirm is a second deliberate tap in a sheet, not a typed word. Typing
/// DELETE is a pattern borrowed from tools whose users are administrators
/// destroying other people's data; here the only thing at risk is the account of
/// the person holding the phone, and making them spell it out reads as a dare.
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  bool _busy = false;

  Future<void> _confirmAndDelete() async {
    final bool? go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _ConfirmSheet(),
    );
    if (go != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (!mounted) return;
      // Home, not back: every screen behind this one belongs to an account that
      // no longer exists.
      context.goNamed(Routes.home);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')),
        );
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('We couldn\'t delete your account. Please try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
        children: <Widget>[
          Text(
            'This cannot be undone',
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          Text(
            'Deleting your account is permanent. There is no waiting period and '
            'no way to get it back — signing up again with the same email '
            'creates a new, empty account.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.xl),

          _Section(
            title: 'Deleted straight away',
            icon: Icons.delete_outline_rounded,
            iconColor: zc.nonVeg,
            items: const <String>[
              'Your login, and your Google sign-in if you used one',
              'Your name, phone number and profile photo',
              'Every saved delivery address',
              'Your saved restaurants',
              'Your notifications, and the push token on this phone',
            ],
          ),
          const SizedBox(height: ZopiqSpacing.lg),

          _Section(
            title: 'Kept, with you removed from it',
            icon: Icons.receipt_long_rounded,
            iconColor: zc.textMuted,
            items: const <String>[
              'Your past orders — the amounts, the restaurant and the date. '
                  'We are required to keep these as tax records, and the '
                  'restaurants are paid from them. Your name, phone number and '
                  'delivery address are erased from every one.',
              'Your ratings, so the restaurants\' scores do not change. Anything '
                  'you wrote alongside a rating is deleted, and the review shows '
                  'no name.',
            ],
          ),
          const SizedBox(height: ZopiqSpacing.xl),

          Container(
            padding: const EdgeInsets.all(ZopiqSpacing.md),
            decoration: BoxDecoration(
              color: zc.divider.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(ZopiqRadii.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline_rounded, size: 20, color: zc.textMuted),
                const SizedBox(width: ZopiqSpacing.sm),
                Expanded(
                  child: Text(
                    'If you have an order on the way, finish or cancel it first — '
                    'a rider is using your address to reach you.',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xl),

          ZopiqButton(
            label: 'Delete my account',
            variant: ZopiqButtonVariant.outline,
            isLoading: _busy,
            onPressed: _busy ? null : _confirmAndDelete,
          ),
          const SizedBox(height: ZopiqSpacing.md),
          ZopiqButton(
            label: 'Keep my account',
            variant: ZopiqButtonVariant.primary,
            onPressed: _busy ? null : () => context.pop(),
          ),
          const SizedBox(height: ZopiqSpacing.xl),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: ZopiqSpacing.sm),
            Text(
              title,
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.sm),
        for (final String item in items)
          Padding(
            padding: const EdgeInsets.only(
              left: ZopiqSpacing.lg,
              bottom: ZopiqSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: zc.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.sm),
                Expanded(
                  child: Text(
                    item,
                    style: t.bodyMedium?.copyWith(color: zc.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        0,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xl + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Delete your account?',
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          Text(
            'This is the last step. Once you tap delete, your account is gone '
            'and cannot be restored.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.xl),
          ZopiqButton(
            label: 'Yes, delete it',
            variant: ZopiqButtonVariant.outline,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          ZopiqButton(
            label: 'Cancel',
            variant: ZopiqButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
