import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

class ProfileDetailsPage extends ConsumerWidget {
  const ProfileDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authControllerProvider);
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    final String email =
        auth is AuthSignedIn ? auth.user.email : 'Not signed in';
    const String name = 'Zopiq user';
    const String mobile = '+91 9876543210';
    const String dob = '01 Jan 1990';
    const String gender = 'Male';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile Details')),
      body: ListView(
        padding: ZopiqSpacing.pagePadding,
        children: <Widget>[
          const SizedBox(height: ZopiqSpacing.lg),
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: zc.primary.withValues(alpha: 0.12),
              child: Icon(Icons.person_rounded, color: zc.primary, size: 54),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xl),
          _DetailRow(label: 'Name', value: name),
          _DetailRow(label: 'Email', value: email),
          _DetailRow(label: 'Mobile', value: mobile),
          _DetailRow(label: 'Date of Birth', value: dob),
          _DetailRow(label: 'Gender', value: gender),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: t.labelSmall?.copyWith(color: zc.textMuted)),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(value, style: t.bodyLarge),
          const SizedBox(height: ZopiqSpacing.xs),
          Divider(height: 1, color: zc.divider),
        ],
      ),
    );
  }
}
