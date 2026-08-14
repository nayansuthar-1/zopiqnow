import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_ad.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/order_ad_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/corner_puck.dart';

/// The advertiser's puck over a map, and the one place a view is counted.
///
/// Both maps show this — the glance on the order screen and the full-screen one
/// — so the "is there an ad, and has this order seen it" question is answered
/// once, here, rather than twice in two screens that would drift.
///
/// **Nothing when no campaign is live.** Not a placeholder, not a greyed circle:
/// the corner of the map goes back to being map, which is what it was before
/// 0125 and what it should be again the day the last campaign ends.
///
/// The view is recorded once per mount and the server keeps only the first per
/// order (0125), so a customer watching a scooter for ten minutes is one
/// impression however many times the map rebuilt underneath it.
class ExplorePuck extends ConsumerStatefulWidget {
  const ExplorePuck({required this.orderId, required this.onOpen, super.key});

  final String orderId;

  final void Function(OrderAd ad) onOpen;

  @override
  ConsumerState<ExplorePuck> createState() => _ExplorePuckState();
}

class _ExplorePuckState extends ConsumerState<ExplorePuck> {
  /// The ad this mount has already counted. Held rather than a plain bool so a
  /// campaign swapped in mid-session is counted as the new impression it is.
  String? _counted;

  void _countOnce(OrderAd ad) {
    if (_counted == ad.id) return;
    _counted = ad.id;
    unawaited(
      ref
          .read(orderAdDataSourceProvider)
          .record(adId: ad.id, kind: 'view', orderId: widget.orderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final OrderAd? ad = ref.watch(liveOrderAdProvider).valueOrNull;
    if (ad == null) return const SizedBox.shrink();

    // Recorded from build because that is the moment it is on screen, and it is
    // guarded above so a rebuild is not a second impression.
    _countOnce(ad);

    return CornerPuck(
      label: 'EXPLORE',
      imageUrl: ad.logoUrl,
      onTap: () => widget.onOpen(ad),
    );
  }
}
