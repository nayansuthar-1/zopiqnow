import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Home header: delivery location (tappable, changes address later) + a search
/// entry. Implemented as a [PreferredSizeWidget] so it docks as the Scaffold's
/// app bar. Search is a stub route target for now.
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({
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

  static const double _height = 116;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZopiqSpacing.lg,
          ZopiqSpacing.sm,
          ZopiqSpacing.lg,
          ZopiqSpacing.sm,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.location_on_rounded, color: zc.primary, size: 22),
                const SizedBox(width: ZopiqSpacing.xs),
                Expanded(
                  child: InkWell(
                    onTap: onTapLocation,
                    borderRadius: ZopiqRadii.rSm,
                    child: Row(
                      children: <Widget>[
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text('Delivering to', style: t.labelSmall?.copyWith(color: zc.textMuted)),
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
                                  Icon(Icons.keyboard_arrow_down_rounded,
                                      size: 20, color: zc.textStrong),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ?trailing,
                const SizedBox(width: ZopiqSpacing.xs),
                _ProfileButton(onTap: onTapProfile, color: zc.primary),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            _SearchField(onTap: onTapSearch),
          ],
        ),
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
          color: isDark ? ZopiqPalette.surfaceDarkElevated : const Color(0xFFF1F1F3),
          borderRadius: ZopiqRadii.rMd,
          border: Border.all(color: zc.divider),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.search_rounded, color: zc.textMuted, size: 20),
            const SizedBox(width: ZopiqSpacing.sm),
            Text(
              'Search for restaurants or dishes',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
