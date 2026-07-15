import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDishEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add dish'),
      ),
      body: menu.when(
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
                  child: entry.isHeader
                      ? _SectionHeader(title: entry.title!)
                      : DishRow(
                          key: ValueKey<String>(entry.dish!.id),
                          dish: entry.dish!,
                        ),
                );
              },
            ),
          );
        },
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
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
