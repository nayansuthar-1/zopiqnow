import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_cart.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/repositories/gift_repository.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_cart_providers.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_status_views.dart';

/// One gift, on a page of its own.
///
/// **It used to be a bottom sheet**, and a sheet was the wrong container for it:
/// it carries a photo gallery, a price block, two callouts and a description,
/// which is a screenful — so the sheet ran to 94% of the display and was a page
/// in everything but its navigation. What it lacked was the navigation. There
/// was no back arrow, no route, no link anyone could be sent, and nothing in the
/// history: the only way out was a swipe or a tap on the four percent of the
/// screen still showing the grid behind it.
///
/// Now it is a route (`/gifts/item/:id`) with a real app bar, a real Back, and
/// the bag bar every other gift screen docks — so leaving a gift lands where you
/// came from and the bag is reachable from the page that fills it.
class GiftItemPage extends ConsumerWidget {
  const GiftItemPage({required this.itemId, super.key});

  final String itemId;

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GiftItem> item = ref.watch(giftItemByIdProvider(itemId));
    final Color surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          item.valueOrNull?.name ?? 'Gift',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      body: item.when(
        loading: () => const Center(child: ZopiqLoader()),
        error: (Object error, _) => GiftErrorView(
          message: error is GiftItemNotFound
              ? error.message
              : error is GiftLoadFailure
              ? error.message
              : 'Please check your connection and try again.',
          onRetry: () => ref.invalidate(giftItemByIdProvider(itemId)),
        ),
        data: (GiftItem gift) => _GiftItemBody(item: gift),
      ),
      // The action bar, docked. Outside the scroll view on purpose: on a gift
      // with a real description "Add to bag" would otherwise be the one thing
      // you had to scroll to the very bottom to reach.
      bottomNavigationBar: item.hasValue
          ? _AddToBagBar(item: item.requireValue)
          : null,
    );
  }
}

class _GiftItemBody extends StatelessWidget {
  const _GiftItemBody({required this.item});

  final GiftItem item;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final int originalMrp = (item.price * 1.25).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        0,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xl,
      ),
      children: <Widget>[
        ClipRRect(
          borderRadius: ZopiqRadii.rXl,
          child: AspectRatio(aspectRatio: 4 / 3, child: _Gallery(item: item)),
        ),
        const SizedBox(height: ZopiqSpacing.lg),

        // Category and the curated tag, on one line above the name.
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                item.category.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(
                  color: GiftItemPage._blinkitGreen,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            const _CuratedTag(),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.sm),

        Text(
          item.name,
          style: t.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: ZopiqSpacing.md),

        // Price, what it was, and the cut — baseline-aligned so the three sit on
        // one line rather than floating at three different heights.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              '₹${item.price}',
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Text(
              '₹$originalMrp',
              style: t.titleSmall?.copyWith(
                color: zc.textMuted,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.sm,
                vertical: ZopiqSpacing.xxs,
              ),
              decoration: const BoxDecoration(
                color: GiftItemPage._blinkitGreen,
                borderRadius: ZopiqRadii.rXs,
              ),
              child: Text(
                '20% OFF',
                style: t.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.lg),

        const _Callout(
          icon: Icons.card_giftcard_rounded,
          title: 'Complimentary gift box',
          body: 'Ribbons, a personalised card and packaging that survives the '
              'ride — included, not an add-on.',
        ),
        const SizedBox(height: ZopiqSpacing.md),
        const _Callout(
          icon: Icons.auto_awesome_rounded,
          title: 'Premium packaging & greeting card',
          body: 'Write the message at checkout and we will put it in the box.',
        ),

        if (item.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: ZopiqSpacing.xl),
          Text(
            'ABOUT THIS GIFT',
            style: t.labelMedium?.copyWith(
              color: zc.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          Text(
            item.description,
            style: t.bodyMedium?.copyWith(
              color: isDark ? Colors.white70 : zc.textMuted,
              height: 1.55,
            ),
          ),
        ],
      ],
    );
  }
}

/// The "Curated Gift" pill. Its own widget only so the row above stays readable.
class _CuratedTag extends StatelessWidget {
  const _CuratedTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: GiftItemPage._blinkitGreen.withValues(alpha: 0.1),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.card_giftcard_rounded,
            size: 12,
            color: GiftItemPage._blinkitGreen,
          ),
          const SizedBox(width: ZopiqSpacing.xs),
          Text(
            'Curated Gift',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: GiftItemPage._blinkitGreen,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon, a heading and a sentence, in a bordered block. Two of these carry
/// what the sheet used to say in two differently-shaped boxes.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: ZopiqRadii.rLg,
        border: Border.all(color: zc.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: GiftItemPage._blinkitGreen.withValues(alpha: 0.1),
              borderRadius: ZopiqRadii.rSm,
            ),
            child: Icon(icon, color: GiftItemPage._blinkitGreen, size: 22),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  body,
                  style: t.bodySmall?.copyWith(
                    color: zc.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The price and the button that commits to it, docked at the bottom.
class _AddToBagBar extends ConsumerWidget {
  const _AddToBagBar({required this.item});

  final GiftItem item;

  /// Puts it in the bag, asking first if that means abandoning another shop's.
  ///
  /// The same shape as the food cart's "Start new cart?" and for the same
  /// reason: an order is placed against one seller, so a bag spanning two is a
  /// bag that cannot be checked out. Asking is the only honest option —
  /// silently clearing somebody's bag is worse than refusing.
  Future<void> _addToBag(BuildContext context, WidgetRef ref) async {
    final GiftCartNotifier bag = ref.read(giftCartProvider.notifier);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    if (bag.add(item) == AddToGiftBagResult.differentShop) {
      final String holding = ref.read(giftCartProvider).shopName;
      final bool? replace = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Start a new bag?'),
          content: Text(
            'Your bag has gifts from '
            '${holding.isEmpty ? 'another shop' : holding}. A gift order goes '
            'to one shop, so adding this one starts a new bag.',
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

    // No `pop` any more. The sheet closed itself on adding because there was
    // nothing else it could do; a page stays, so somebody adding a second gift
    // from the same shop can go back to the shelf they were on.
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
    final GiftCart bag = ref.watch(giftCartProvider);
    final int inBag = bag.quantityOf(item.id);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: zc.divider)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.md,
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            // The price again, and deliberately: at the moment of committing,
            // the number being committed to should be beside the button rather
            // than scrolled off the top of the page.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '₹${item.price}',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  'incl. gift packaging',
                  style: t.labelSmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
            const SizedBox(width: ZopiqSpacing.lg),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GiftItemPage._blinkitGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(
                      borderRadius: ZopiqRadii.rMd,
                    ),
                  ),
                  onPressed: () => _addToBag(context, ref),
                  child: Text(
                    // Says what a second press does, because the page now stays
                    // open long enough for there to be one.
                    inBag == 0 ? 'Add to bag' : 'Add another · $inBag in bag',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
            bottom: ZopiqSpacing.md,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < images.length; i++)
                  AnimatedContainer(
                    duration: ZopiqDurations.base,
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
