import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Home header as a sliver: delivery location + profile, with the search entry
/// docked beneath.
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
    final ZopiqColors zc = context.zc;

    return SliverAppBar(
      floating: true,
      snap: true,
      primary: false,
      toolbarHeight: 60,
      titleSpacing: ZopiqSpacing.pageGutter,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: _LocationTitle(address: address, onTap: onTapLocation),
      actions: <Widget>[
        ?trailing,
        _ProfileButton(onTap: onTapProfile, color: zc.primary),
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
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rSm,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.location_on_rounded, color: zc.primary, size: 22),
          const SizedBox(width: ZopiqSpacing.xs),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Delivering to',
                  style: t.labelSmall?.copyWith(color: zc.textMuted),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: zc.textStrong,
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
  const _ProfileButton({required this.onTap, required this.color});

  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(Icons.person_rounded, color: color, size: 20),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rMd,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.md),
        decoration: BoxDecoration(
          color: isDark
              ? ZopiqPalette.surfaceDarkElevated
              : ZopiqPalette.surfaceLight,
          borderRadius: ZopiqRadii.rMd,
          border: Border.all(color: zc.divider),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Search for restaurants or dishes',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
            ),
            Icon(Icons.search_rounded, color: zc.primary, size: 22),
          ],
        ),
      ),
    );
  }
}
