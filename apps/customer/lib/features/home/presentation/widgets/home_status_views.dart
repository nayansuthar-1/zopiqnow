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

/// The feed had restaurants, but the active filter chips excluded all of them.
/// Distinct from [HomeEmptyView]: the fix here is the user's, not ours.
class HomeNoMatchesView extends StatelessWidget {
  const HomeNoMatchesView({super.key});

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
          'Try removing a filter to see more results.',
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
