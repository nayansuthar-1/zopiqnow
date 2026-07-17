import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/menu/presentation/providers/menu_providers.dart';

/// The menu's sections, to arrange rather than to fill.
///
/// The [MenuPage] is for the dishes; this is for the shelves they sit on —
/// dragging a whole section up the menu, renaming one, or taking one down for
/// the day. It is deliberately a separate screen: reordering is a mode, and a
/// list that is sometimes draggable and sometimes tappable is a list that is
/// hard to trust.
///
/// The list is optimistic. A drag, a rename, a switch all change what is on the
/// screen the instant they happen, and the database is told after; if it refuses,
/// the change is put back and the vendor is told why. The alternative — waiting
/// for a round trip before the row moves — makes a reorder feel broken.
class ManageCategoriesPage extends ConsumerStatefulWidget {
  const ManageCategoriesPage({super.key});

  @override
  ConsumerState<ManageCategoriesPage> createState() =>
      _ManageCategoriesPageState();
}

class _ManageCategoriesPageState extends ConsumerState<ManageCategoriesPage> {
  /// The working copy, seeded once from the menu and the source of truth after.
  /// Null until the first load lands; every edit mutates this and then persists.
  List<_Category>? _categories;

  @override
  Widget build(BuildContext context) {
    // Before the first load, lean on the provider for its loading and error
    // states. After it, render from the local copy so our own writes — which
    // invalidate the provider and briefly return it to loading — never blink the
    // list back to a spinner.
    if (_categories == null) {
      final AsyncValue<List<VendorMenuSection>> menu = ref.watch(menuProvider);
      return Scaffold(
        appBar: AppBar(title: const Text('Sections')),
        body: menu.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object _, StackTrace _) => _ErrorBody(
            onRetry: () => ref.invalidate(menuProvider),
          ),
          data: (List<VendorMenuSection> sections) {
            _categories = <_Category>[
              for (final VendorMenuSection s in sections)
                _Category(
                  title: s.title,
                  dishCount: s.dishes.length,
                  isAvailable: s.isAvailable,
                ),
            ];
            return _body();
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sections')),
      body: _body(),
    );
  }

  Widget _body() {
    final List<_Category> categories = _categories!;
    if (categories.isEmpty) {
      return const _EmptyBody();
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
      itemCount: categories.length,
      onReorderItem: _reorder,
      itemBuilder: (BuildContext context, int i) {
        final _Category c = categories[i];
        return _CategoryTile(
          key: ValueKey<String>(c.title),
          index: i,
          category: c,
          onRename: () => _rename(c),
          onToggle: (bool on) => _toggle(c, on),
        );
      },
    );
  }

  /// A deep copy of the current sections, for putting the screen back when a
  /// write is refused — the tiles mutate their `_Category` in place, so a shallow
  /// list copy would share the very object the optimistic edit just changed.
  List<_Category> _snapshot() => <_Category>[
    for (final _Category c in _categories!)
      _Category(
        title: c.title,
        dishCount: c.dishCount,
        isAvailable: c.isAvailable,
      ),
  ];

  /// Persist whatever is currently on screen, and put it back if the database
  /// refuses. Every edit below runs through here.
  Future<void> _persist(
    Future<String?> Function() write,
    List<_Category> before,
  ) async {
    final String? failure = await write();
    if (!mounted) return;
    if (failure != null) {
      setState(() => _categories = before);
      _say(failure);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final List<_Category> before = _snapshot();
    setState(() {
      // `onReorderItem` hands back a `newIndex` already adjusted for the row
      // lifted out at `oldIndex`, so the move is a plain remove-then-insert.
      final List<_Category> cats = _categories!;
      cats.insert(newIndex, cats.removeAt(oldIndex));
    });
    await _persist(
      () => ref
          .read(menuControllerProvider.notifier)
          .reorderCategories(<String>[
            for (final _Category c in _categories!) c.title,
          ]),
      before,
    );
  }

  Future<void> _toggle(_Category category, bool isAvailable) async {
    final List<_Category> before = _snapshot();
    setState(() => category.isAvailable = isAvailable);
    await _persist(
      () => ref
          .read(menuControllerProvider.notifier)
          .setCategoryAvailability(
            category: category.title,
            isAvailable: isAvailable,
          ),
      before,
    );
  }

  Future<void> _rename(_Category category) async {
    final String? to = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _RenameDialog(
        current: category.title,
        // Every other section's name, so the dialog can refuse a duplicate
        // before it becomes a silent merge of two sections.
        taken: <String>{
          for (final _Category c in _categories!)
            if (c.title != category.title) c.title.toLowerCase(),
        },
      ),
    );
    if (to == null || to == category.title) return;

    final String from = category.title;
    final List<_Category> before = _snapshot();
    setState(() => category.title = to);
    await _persist(
      () => ref
          .read(menuControllerProvider.notifier)
          .renameCategory(from: from, to: to),
      before,
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// One section's mutable working state. Mutable on purpose: the tiles hold a
/// reference to it, and an optimistic edit changes the field in place before the
/// database is asked to agree.
class _Category {
  _Category({
    required this.title,
    required this.dishCount,
    required this.isAvailable,
  });

  String title;
  final int dishCount;
  bool isAvailable;
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.index,
    required this.category,
    required this.onRename,
    required this.onToggle,
    super.key,
  });

  final int index;
  final _Category category;
  final VoidCallback onRename;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool off = !category.isAvailable;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xs,
      ),
      child: ZopiqCard(
        child: Row(
          children: <Widget>[
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: ZopiqSpacing.sm),
                child: Icon(Icons.drag_indicator_rounded, color: zc.textMuted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    category.title,
                    style: t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: off ? zc.textMuted : zc.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    off
                        ? 'Off the menu'
                        : '${category.dishCount} '
                              '${category.dishCount == 1 ? 'dish' : 'dishes'}',
                    style: t.bodySmall?.copyWith(
                      color: off ? zc.nonVeg : zc.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              color: zc.textMuted,
              tooltip: 'Rename',
              onPressed: onRename,
            ),
            Switch(value: category.isAvailable, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current, required this.taken});

  final String current;
  final Set<String> taken;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the section a name.');
      return;
    }
    if (widget.taken.contains(name.toLowerCase())) {
      setState(() => _error = 'There is already a section with that name.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename section'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: 'Section name', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Rename')),
      ],
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

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
            Icon(Icons.category_outlined, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text('No sections yet', style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              'Sections appear here once you add a dish under one.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

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
            Icon(Icons.cloud_off_rounded, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text('We couldn\'t load your menu', style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              'Check the internet and try again.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(label: 'Retry', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
