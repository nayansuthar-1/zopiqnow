import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/widgets/rider_animations.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider_kyc.dart';
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

    // Null while the first read is in flight. The badge draws a neutral
    // "Checking…" for it rather than guessing either way — a green shield that
    // turns red a second later is worse than a second of nothing.
    final RiderKyc? kyc = ref.watch(kycProvider).valueOrNull;

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

                    // The badge told every rider they were an "Active Fleet
                    // Partner" whether or not anybody had ever looked at their
                    // papers. Since 0080 that is a claim the platform can
                    // actually make or withhold, so it says which (RID-002).
                    _VerificationBadge(kyc: kyc),

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

            // Only when there is something to say. A verified rider with months
            // left on both papers does not need a card telling them so — the
            // badge above already does, and a permanent panel about documents
            // is a permanent suggestion that something is wrong.
            if (kyc != null && (!kyc.canWork || kyc.expiringSoon)) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.lg),
              RiderFadeSlide(
                delay: const Duration(milliseconds: 80),
                child: _VerificationCard(kyc: kyc),
              ),
            ],

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

/// Verified, or not, and never a shield the platform has not earned the right to
/// draw (0080, audit RID-002).
class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.kyc});

  final RiderKyc? kyc;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final (Color colour, String label) = switch (kyc) {
      null => (zc.textMuted, 'Checking…'),
      final RiderKyc k when k.canWork => (zc.veg, 'Verified Fleet Partner'),
      final RiderKyc k when k.status == 'rejected' => (
        zc.nonVeg,
        'Documents not accepted',
      ),
      _ => (zc.rating, 'Verification pending'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RiderSvgIcon(
            type: RiderSvgType.verifiedShield,
            size: 14,
            color: colour,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: t.labelSmall?.copyWith(
              color: colour,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sentence, when there is one.
///
/// The wording comes from the database — `rider_work_block` writes it, including
/// the admin's own reason for a rejection — so the rider reads the same sentence
/// the board and the Go-online button would refuse them with, rather than a
/// second app-side paraphrase that can drift out of step with it.
class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.kyc});

  final RiderKyc kyc;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final bool warning = kyc.canWork;
    final Color colour = warning ? zc.rating : zc.nonVeg;

    final String body = switch (kyc) {
      final RiderKyc k when k.expiringSoon && k.daysToExpiry! <= 0 =>
        'Your papers run out today.',
      final RiderKyc k when k.expiringSoon =>
        'Your licence or insurance runs out in ${k.daysToExpiry} '
            'day${k.daysToExpiry == 1 ? '' : 's'}. Send the renewed copy to '
            'Fleet Operations before then so you are not stopped mid-shift.',
      final RiderKyc k when k.nothingFiled =>
        'Fleet Operations has not filed your documents yet. Take your licence, '
            'insurance, ID and RC to them to start taking deliveries.',
      _ => kyc.blockedReason ?? '',
    };

    return Container(
      padding: const EdgeInsets.all(ZopiqSpacing.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: ZopiqRadii.rMd,
        border: Border.all(color: colour.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            warning ? Icons.schedule_rounded : Icons.gpp_maybe_rounded,
            size: 20,
            color: colour,
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  warning ? 'Renew soon' : 'You cannot take deliveries yet',
                  style: t.labelLarge?.copyWith(
                    color: colour,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: t.bodySmall?.copyWith(color: zc.textStrong),
                ),
              ],
            ),
          ),
        ],
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
