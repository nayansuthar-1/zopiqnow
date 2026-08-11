import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/bottom_nav_provider.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_cart_providers.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';

/// Opens the detail sheet for a gift item:
/// Features Blinkit-style express 10-min delivery banner, complimentary gift box callout,
/// pricing breakdown, image gallery carousel, and product description.
/// The shell's pills slide away for as long as the sheet is up: this one is
/// tall, and the Cart pill floating over its "Add to bag" row was a tap target
/// sitting on top of another tap target.
Future<void> showGiftItemSheet(
  BuildContext context,
  WidgetRef ref,
  GiftItem item,
) {
  return withBottomNavHidden(
    ref,
    () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) => _GiftItemSheet(item: item),
    ),
  );
}

class _GiftItemSheet extends ConsumerWidget {
  const _GiftItemSheet({required this.item});

  final GiftItem item;

  static const Color _blinkitGreen = Color(0xFF0C831F);
  static const Color _blinkitYellow = Color(0xFFF7C400);

  /// Puts it in the bag, asking first if that means abandoning another shop's.
  ///
  /// The same shape as the food cart's "Start new cart?" and for the same
  /// reason: an order is placed against one seller, so a bag spanning two is a
  /// bag that cannot be checked out. Asking is the only honest option — silently
  /// clearing somebody's bag is worse than refusing.
  Future<void> _addToBag(BuildContext context, WidgetRef ref) async {
    final GiftCartNotifier bag = ref.read(giftCartProvider.notifier);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    if (bag.add(item) == AddToGiftBagResult.differentShop) {
      final String holding = ref.read(giftCartProvider).shopName;
      final bool? replace = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Start a new bag?'),
          content: Text(
            'Your bag has gifts from ${holding.isEmpty ? 'another shop' : holding}. '
            'A gift order goes to one shop, so adding this one starts a new bag.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep my bag'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start new bag'),
            ),
          ],
        ),
      );
      if (!(replace ?? false)) return;
      bag.startNewBagWith(item);
    }

    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${item.name} added to your gift bag'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final int originalMrp = (item.price * 1.25).round();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Grab handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(
                  top: 12,
                  bottom: 8,
                ),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Gallery
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: _Gallery(item: item),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Express Delivery Bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            _blinkitGreen.withValues(alpha: isDark ? 0.25 : 0.08),
                            _blinkitGreen.withValues(alpha: isDark ? 0.1 : 0.02),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _blinkitGreen.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: _blinkitGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.card_giftcard_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Premium gift packaging & custom greeting card included',
                              style: t.labelSmall?.copyWith(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Category & Tag Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          item.category.toUpperCase(),
                          style: t.labelSmall?.copyWith(
                            color: _blinkitGreen,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _blinkitGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.card_giftcard_rounded,
                                size: 12,
                                color: _blinkitGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Curated Gift',
                                style: t.labelSmall?.copyWith(
                                  color: _blinkitGreen,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Item Name
                    Text(
                      item.name,
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Price Block
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          '₹${item.price}',
                          style: t.headlineSmall?.copyWith(
                            color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₹$originalMrp',
                          style: t.titleSmall?.copyWith(
                            color: zc.textMuted,
                            decoration: TextDecoration.lineThrough,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _blinkitGreen,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '20% OFF',
                            style: t.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Gift Packaging Feature Box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _blinkitGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.card_giftcard_rounded,
                              color: _blinkitGreen,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Complimentary Gift Box',
                                  style: t.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Includes ribbons, personalized card & safe packaging.',
                                  style: t.bodySmall?.copyWith(
                                    color: zc.textMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (item.description.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 20),
                      Text(
                        'ABOUT THIS GIFT',
                        style: t.labelMedium?.copyWith(
                          color: zc.textMuted,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.description,
                        style: t.bodyMedium?.copyWith(
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // The button that used to say "Close" and close. A
                    // catalogue with no way to buy anything was the whole of
                    // the Gifts tab until 0096.
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blinkitGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _addToBag(context, ref),
                        child: Text(
                          'Add to bag · ₹${item.price}',
                          style: t.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A swipeable gallery of a gift's photos, with pagination dots.
class _Gallery extends StatefulWidget {
  const _Gallery({required this.item});

  final GiftItem item;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final PageController _controller = PageController();
  int _page = 0;

  List<String> get _images => widget.item.imageUrls.isNotEmpty
      ? widget.item.imageUrls
      : <String>[widget.item.imageUrl];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> images = _images;

    return Stack(
      children: <Widget>[
        PageView.builder(
          controller: _controller,
          itemCount: images.length,
          onPageChanged: (int i) => setState(() => _page = i),
          itemBuilder: (BuildContext context, int i) => GiftImage(
            url: images[i],
            seed: '${widget.item.id}-$i',
            iconSize: 56,
          ),
        ),
        if (images.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < images.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _page ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: i == _page
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

