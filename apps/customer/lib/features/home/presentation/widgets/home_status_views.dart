import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Full-bleed error state with a retry action (Rule 2.5 — no blank screens).
class HomeErrorView extends StatelessWidget {
  const HomeErrorView({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Icon(Icons.wifi_off_rounded, size: 56, color: zc.textMuted),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(
          'Something went wrong',
          style: t.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          message,
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xl),
        ZopiqButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          expand: false,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

/// Empty state — serviceable area returned no restaurants.
class HomeEmptyView extends StatelessWidget {
  const HomeEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Icon(Icons.storefront_outlined, size: 56, color: zc.textMuted),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(
          'No restaurants nearby',
          style: t.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          'Try a different location — we\'re expanding fast.',
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// No delivery address, so no town, so no catalogue (migration 0126).
///
/// Distinct from [HomeEmptyView], which says "there is nothing here" — a claim
/// we are not entitled to make until we know where "here" is. The kitchens exist;
/// we just cannot tell which of them are the customer's until they say. So this
/// asks, and gives them the button rather than describing one.
///
/// Reachable in one way in practice: the location gate at startup is skippable,
/// and this is what skipping it looks like on the feed.
class HomeNoLocationView extends StatelessWidget {
  const HomeNoLocationView({required this.onSetLocation, super.key});

  final VoidCallback onSetLocation;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Icon(Icons.location_off_outlined, size: 56, color: zc.textMuted),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(
          'Where are we delivering?',
          style: t.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          'We deliver within your town, so set your address and we\'ll show '
          'you the kitchens that can reach you.',
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xl),
        ZopiqButton(
          label: 'Set delivery location',
          icon: Icons.my_location_rounded,
          expand: false,
          onPressed: onSetLocation,
        ),
      ],
    );
  }
}

/// An address is set, and it is outside every town we serve.
///
/// Distinct from [HomeNoLocationView]: the customer has answered "where", and
/// the honest reply is "not there yet", naming the towns we are in. Before this
/// view existed an out-of-town pin fell through to "Where are we delivering?",
/// which reads as the app having lost the address it was just given — the
/// App Store reviewer, pinning Cupertino, filed it as a bug (2.1, build 31).
class HomeOutOfAreaView extends StatelessWidget {
  const HomeOutOfAreaView({
    required this.headline,
    required this.detail,
    required this.onChangeLocation,
    super.key,
  });

  /// Both from `delivery_area_check`, which names the live towns itself.
  final String headline;
  final String detail;
  final VoidCallback onChangeLocation;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Icon(Icons.map_outlined, size: 56, color: zc.textMuted),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(headline, style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          detail,
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xl),
        ZopiqButton(
          label: 'Change location',
          icon: Icons.edit_location_alt_outlined,
          expand: false,
          onPressed: onChangeLocation,
        ),
      ],
    );
  }
}

/// The feed had restaurants, but the active filter chips excluded all of them.
/// Distinct from [HomeEmptyView]: the fix here is the user's, not ours.
class HomeNoMatchesView extends StatelessWidget {
  const HomeNoMatchesView({this.message, super.key});

  /// Overrides the second line. A category page reaches this state for a
  /// different reason than Home does — nothing nearby serves that dish, which no
  /// amount of removing filters will fix — and telling someone to drop a filter
  /// they never set is advice that cannot work.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return _CenteredState(
      children: <Widget>[
        Icon(Icons.filter_alt_off_rounded, size: 56, color: zc.textMuted),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(
          'No matching restaurants',
          style: t.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          message ?? 'Try removing a filter to see more results.',
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
