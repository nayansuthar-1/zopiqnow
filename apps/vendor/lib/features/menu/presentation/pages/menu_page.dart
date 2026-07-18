import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiq_vendor/features/menu/presentation/widgets/dish_editor.dart';
import 'package:zopiq_vendor/features/menu/presentation/widgets/dish_row.dart';

/// The restaurant's menu, to manage rather than to order from.
///
/// Reached from the queue, not instead of it: the queue is the tablet's home
/// because a kitchen glances at orders far more than it edits dishes. This screen
/// is where the menu is kept true — a dish sells out, a price changes, a new
/// item is added — and its one loud action is the "+" that adds a dish.
class MenuPage extends ConsumerWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<VendorMenuSection>> menu = ref.watch(menuProvider);

    // The section manager is only reachable once there is a section to manage —
    // an empty menu has nothing to reorder.
    final bool hasSections = menu.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: context.zc.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: () => showDishEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add dish',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ── Custom Header ──
            ZopiqReveal(
              index: 0,
              child: _Header(hasSections: hasSections),
            ),

            Expanded(
              child: menu.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object _, StackTrace _) => _Message(
                  icon: Icons.cloud_off_rounded,
                  title: 'We couldn\'t load your menu',
                  body: 'Check the internet and try again.',
                  onRetry: () => ref.invalidate(menuProvider),
                ),
                data: (List<VendorMenuSection> sections) {
                  if (sections.isEmpty) {
                    return const _Message(
                      icon: Icons.restaurant_menu_rounded,
                      title: 'No dishes yet',
                      body: 'Add your first dish with the button below.',
                    );
                  }

                  // Flattened so the list stays lazy: a header and its dishes are just
                  // rows, built only as they scroll into view.
                  final List<_Entry> entries = <_Entry>[
                    for (final VendorMenuSection s in sections) ...<_Entry>[
                      _Entry.header(s.title),
                      for (final VendorDish d in s.dishes) _Entry.dish(d),
                    ],
                  ];

                  return RefreshIndicator(
                    color: context.zc.primary,
                    onRefresh: () async => ref.refresh(menuProvider.future),
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: entries.length,
                      separatorBuilder: (BuildContext context, int i) {
                        // A divider only between two dishes — never above a section
                        // header, which brings its own space.
                        final bool nextIsHeader =
                            i + 1 < entries.length && entries[i + 1].isHeader;
                        if (entries[i].isHeader || nextIsHeader) {
                          return const SizedBox.shrink();
                        }
                        return Divider(height: 1, color: context.zc.divider);
                      },
                      itemBuilder: (BuildContext context, int i) {
                        final _Entry entry = entries[i];
                        return RepaintBoundary(
                          child: ZopiqReveal(
                            index: 1 + i, // Staggered entrance
                            child: entry.isHeader
                                ? _SectionHeader(title: entry.title!)
                                : DishRow(
                                    key: ValueKey<String>(entry.dish!.id),
                                    dish: entry.dish!,
                                  ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hasSections});

  final bool hasSections;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Menu Management',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  'Manage dishes, prices, and availability',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          if (hasSections)
            Container(
              decoration: BoxDecoration(
                color: zc.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.swap_vert_rounded, color: zc.primary),
                tooltip: 'Sections',
                onPressed: () => context.pushNamed(Routes.menuCategories),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row in the flattened list: a section header or a dish, never both.
class _Entry {
  const _Entry._({this.title, this.dish});

  _Entry.header(String title) : this._(title: title);
  _Entry.dish(VendorDish dish) : this._(dish: dish);

  final String? title;
  final VendorDish? dish;

  bool get isHeader => title != null;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    return Container(
      width: double.infinity,
      color: zc.primary.withValues(alpha: 0.04), // subtle tinted background for section
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: zc.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(title, style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              body,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqButton(
                label: 'Retry',
                expand: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
