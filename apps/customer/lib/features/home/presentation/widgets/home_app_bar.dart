import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Home header as a sliver: delivery location + profile, with the search entry
/// docked beneath.
///
/// Styled to sit on the brand hero (Zomato's home): solid `primary` background
/// that the [HomeHeroBanner] gradient below continues, white ink, and a white
/// search pill. Because the bar itself carries the brand color, it still looks
/// right when it floats back mid-list.
///
/// `floating: true, snap: true` gives Swiggy's behaviour — the header scrolls
/// away to hand the list the full screen, and springs straight back on the first
/// upward drag rather than making the user scroll all the way to the top.
///
/// `primary: false` because Home wraps the whole scroll view in a [SafeArea].
/// Left primary, this bar would eat the status-bar inset itself, and the pinned
/// filter chips would then slide *under* the status bar once it scrolled away.
class HomeSliverAppBar extends StatelessWidget {
  const HomeSliverAppBar({
    required this.address,
    this.onTapLocation,
    this.onTapSearch,
    this.onTapProfile,
    this.trailing,
    super.key,
  });

  final String address;
  final VoidCallback? onTapLocation;
  final VoidCallback? onTapSearch;
  final VoidCallback? onTapProfile;

  /// Optional extra action (e.g. a debug entry point).
  final Widget? trailing;

  static const double _searchHeight = 60;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      floating: true,
      snap: true,
      primary: false,
      toolbarHeight: 60,
      titleSpacing: ZopiqSpacing.pageGutter,
      backgroundColor: ZopiqPalette.primary,
      // White status-bar icons over the brand hero, in both themes.
      systemOverlayStyle: SystemUiOverlayStyle.light,
      actionsIconTheme: const IconThemeData(color: ZopiqPalette.white),
      title: _LocationTitle(address: address, onTap: onTapLocation),
      actions: <Widget>[
        ?trailing,
        _ProfileButton(onTap: onTapProfile),
        const SizedBox(width: ZopiqSpacing.pageGutter),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(_searchHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZopiqSpacing.pageGutter,
            0,
            ZopiqSpacing.pageGutter,
            ZopiqSpacing.lg,
          ),
          child: _SearchField(onTap: onTapSearch),
        ),
      ),
    );
  }
}

class _LocationTitle extends StatelessWidget {
  const _LocationTitle({required this.address, required this.onTap});

  final String address;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rSm,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.location_on_rounded,
            color: ZopiqPalette.white,
            size: 22,
          ),
          const SizedBox(width: ZopiqSpacing.xs),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Delivering to',
                  style: t.labelSmall?.copyWith(
                    color: ZopiqPalette.white.withValues(alpha: 0.8),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(
                          color: ZopiqPalette.white,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: ZopiqPalette.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: CircleAvatar(
        radius: 18,
        backgroundColor: ZopiqPalette.white.withValues(alpha: 0.22),
        child: const Icon(
          Icons.person_rounded,
          color: ZopiqPalette.white,
          size: 20,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rMd,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.md),
        // Fixed light colors in both themes: this pill sits on the brand
        // hero, not on the scaffold, so it must not flip with the mode.
        decoration: const BoxDecoration(
          color: ZopiqPalette.white,
          borderRadius: ZopiqRadii.rMd,
          boxShadow: <BoxShadow>[
            BoxShadow(color: Color(0x1F000000), blurRadius: 8),
          ],
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                // Search matches restaurant names and cuisines, not dish names —
                // say so rather than promise what it does not do.
                'Search for restaurants or cuisines',
                style: t.bodyMedium?.copyWith(color: ZopiqPalette.textMuted),
              ),
            ),
            const Icon(
              Icons.search_rounded,
              color: ZopiqPalette.primaryDeep,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
