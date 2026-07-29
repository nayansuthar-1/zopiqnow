import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/widgets/rider_animations.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';

/// Who the rider is, and the way out.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Sign Out of Partner Account?'),
            content: const Text(
              'You will stop receiving job offers until you sign back in.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.zc.nonVeg,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ) ??
        false;
    if (ok) {
      ref.read(riderAuthControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Rider? rider = ref.watch(riderProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner Profile'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          children: <Widget>[
            RiderFadeSlide(
              child: ZopiqCard(
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: ZopiqSpacing.sm),
                    // Large Avatar
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: zc.primary.withValues(alpha: 0.15),
                      child: Text(
                        rider?.name.isNotEmpty ?? false
                            ? rider!.name[0].toUpperCase()
                            : 'P',
                        style: t.headlineMedium?.copyWith(
                          color: zc.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.md),

                    Text(
                      rider?.name.isNotEmpty ?? false
                          ? rider!.name
                          : 'Delivery Partner',
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),

                    // Active Partner Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: zc.veg.withValues(alpha: 0.12),
                        borderRadius: ZopiqRadii.rPill,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          RiderSvgIcon(
                            type: RiderSvgType.verifiedShield,
                            size: 14,
                            color: zc.veg,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Active Fleet Partner',
                            style: t.labelSmall?.copyWith(
                              color: zc.veg,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: ZopiqSpacing.lg),
                    Divider(height: 1, color: zc.divider),
                    const SizedBox(height: ZopiqSpacing.md),

                    // What customers have made of the deliveries (0062). A dash
                    // until somebody has actually rated one: a new partner has
                    // no score, not the worst possible one.
                    Row(
                      children: <Widget>[
                        Icon(Icons.star_rounded, size: 20, color: zc.rating),
                        const SizedBox(width: ZopiqSpacing.sm),
                        Text(
                          rider?.isRated ?? false
                              ? rider!.rating.toStringAsFixed(1)
                              : '—',
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: ZopiqSpacing.sm),
                        Text(
                          rider?.isRated ?? false
                              ? 'from ${rider!.ratingCount} '
                                    'rating${rider.ratingCount == 1 ? '' : 's'}'
                              : 'No ratings yet',
                          style: t.bodySmall?.copyWith(color: zc.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZopiqSpacing.md),
                    Divider(height: 1, color: zc.divider),
                    const SizedBox(height: ZopiqSpacing.md),

                    _Row(
                      iconType: RiderSvgType.profile,
                      label: 'Email',
                      text: rider?.email ?? 'Not available',
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),
                    _Row(
                      iconType: RiderSvgType.phoneCall,
                      label: 'Phone',
                      text: rider?.phone.isNotEmpty ?? false
                          ? rider!.phone
                          : 'On file with Ops',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: ZopiqSpacing.lg),

            RiderFadeSlide(
              delay: const Duration(milliseconds: 100),
              child: Container(
                padding: const EdgeInsets.all(ZopiqSpacing.md),
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: 0.06),
                  borderRadius: ZopiqRadii.rMd,
                  border: Border.all(color: zc.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: <Widget>[
                    RiderSvgIcon(
                      type: RiderSvgType.verifiedShield,
                      size: 20,
                      color: zc.primary,
                    ),
                    const SizedBox(width: ZopiqSpacing.md),
                    Expanded(
                      child: Text(
                        'To update your phone number or account details, reach out to your Zopiqnow Fleet Operations admin.',
                        style: t.bodySmall?.copyWith(color: zc.textStrong),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: ZopiqSpacing.xl),

            RiderFadeSlide(
              delay: const Duration(milliseconds: 150),
              child: ZopiqButton(
                label: 'Sign Out',
                variant: ZopiqButtonVariant.outline,
                onPressed: () => _confirmSignOut(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.iconType,
    required this.label,
    required this.text,
  });

  final RiderSvgType iconType;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        RiderSvgIcon(
          type: iconType,
          size: 20,
          color: zc.primary,
        ),
        const SizedBox(width: ZopiqSpacing.sm),
        Text(
          '$label: ',
          style: t.bodyMedium?.copyWith(
            color: zc.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: t.bodyMedium?.copyWith(
              color: zc.textStrong,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
