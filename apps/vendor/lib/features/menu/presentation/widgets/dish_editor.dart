import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/images/photo_field.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/menu/presentation/pages/dish_customization_page.dart';
import 'package:zopiq_vendor/features/menu/presentation/providers/menu_providers.dart';

/// Opens the add / edit sheet. Pass a [dish] to edit it, or nothing to add one.
Future<void> showDishEditor(
  BuildContext context, {
  VendorDish? dish,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (BuildContext sheetContext) => _DishEditor(dish: dish),
);

/// One form for two jobs — adding a dish and editing one — because they are the
/// same fields and the only difference is whether the row already has an id.
class _DishEditor extends ConsumerStatefulWidget {
  const _DishEditor({this.dish});

  final VendorDish? dish;

  @override
  ConsumerState<_DishEditor> createState() => _DishEditorState();
}

class _DishEditorState extends ConsumerState<_DishEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _originalPrice;
  late final TextEditingController _prepMinutes;
  late final TextEditingController _category;
  late bool _isVeg;
  late bool _isBestseller;
  late String _imageUrl;

  /// The serving window, as minutes since midnight. Both null — no window, sold
  /// all day — is the state every dish starts in and most stay in.
  int? _serveFrom;
  int? _serveTo;

  bool _busy = false;
  String? _error;

  VendorDish? get _original => widget.dish;
  bool get _isEditing => _original != null;

  @override
  void initState() {
    super.initState();
    final VendorDish? d = _original;
    _name = TextEditingController(text: d?.name ?? '');
    _description = TextEditingController(text: d?.description ?? '');
    // A new dish shows an empty price field, not "0" — a placeholder zero is a
    // number the vendor has to notice and clear.
    _price = TextEditingController(text: d != null ? '${d.price}' : '');
    _originalPrice = TextEditingController(
      text: d?.originalPrice != null ? '${d!.originalPrice}' : '',
    );
    _prepMinutes = TextEditingController(
      text: d?.prepMinutes != null ? '${d!.prepMinutes}' : '',
    );
    _category = TextEditingController(text: d?.category ?? '');
    _isVeg = d?.isVeg ?? true;
    _isBestseller = d?.isBestseller ?? false;
    _imageUrl = d?.imageUrl ?? '';
    _serveFrom = d?.serveFromMinutes;
    _serveTo = d?.serveToMinutes;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _originalPrice.dispose();
    _prepMinutes.dispose();
    _category.dispose();
    super.dispose();
  }

  bool get _hasWindow => _serveFrom != null && _serveTo != null;

  /// Switching the window on seeds a breakfast — 8 AM to 11 AM — because a pair
  /// of pickers starting at "now" would need two edits before it meant anything.
  /// Switching it off clears both ends, which is what the column pair means by
  /// "all day" and what the check constraint requires.
  void _toggleWindow() => setState(() {
    _error = null;
    if (_hasWindow) {
      _serveFrom = null;
      _serveTo = null;
    } else {
      _serveFrom = 8 * 60;
      _serveTo = 11 * 60;
    }
  });

  Future<void> _pickWindow({required bool opening}) async {
    final int current = (opening ? _serveFrom : _serveTo) ?? 0;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    setState(() {
      _error = null;
      final int minutes = picked.hour * 60 + picked.minute;
      if (opening) {
        _serveFrom = minutes;
      } else {
        _serveTo = minutes;
      }
    });
  }

  /// Rendered through [TimeOfDay.format] so it follows the device's 12/24-hour
  /// setting, the same way the hours editor's chips do.
  static String _formatMinutes(BuildContext context, int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

  Future<void> _save() async {
    final String name = _name.text.trim();
    final String category = _category.text.trim();
    final int price = int.tryParse(_price.text.trim()) ?? 0;
    final int? originalPrice = int.tryParse(_originalPrice.text.trim());
    final int? prepMinutes = int.tryParse(_prepMinutes.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Give the dish a name.');
      return;
    }
    if (price <= 0) {
      setState(() => _error = 'Enter a price in rupees.');
      return;
    }
    if (category.isEmpty) {
      setState(() => _error = 'Which section does it go under? e.g. Biryanis.');
      return;
    }
    // Said here as well as in the check constraint, so the vendor reads a
    // sentence instead of a Postgres violation. The constraint is still the
    // guard — a check the client can read is a check, not a guard.
    if (originalPrice != null && originalPrice <= price) {
      setState(
        () => _error = 'The struck-through price has to be above ₹$price.',
      );
      return;
    }
    if (prepMinutes != null && (prepMinutes <= 0 || prepMinutes > 240)) {
      setState(() => _error = 'Prep time should be between 1 and 240 minutes.');
      return;
    }
    if (_serveFrom != null && _serveTo != null && _serveFrom == _serveTo) {
      setState(() => _error = 'The serving window starts and ends at the '
          'same time.');
      return;
    }

    // For an edit, start from the real row so the id and availability ride
    // along; for a new dish, a draft the database will give an id.
    final VendorDish dish = (_original ?? const VendorDish.draft()).copyWith(
      name: name,
      description: _description.text.trim(),
      price: price,
      isVeg: _isVeg,
      isBestseller: _isBestseller,
      category: category,
      imageUrl: _imageUrl,
      originalPrice: originalPrice,
      clearOriginalPrice: originalPrice == null,
      prepMinutes: prepMinutes,
      clearPrepMinutes: prepMinutes == null,
      serveFromMinutes: _serveFrom,
      serveToMinutes: _serveTo,
      clearServingWindow: _serveFrom == null || _serveTo == null,
    );

    setState(() {
      _busy = true;
      _error = null;
    });
    final String? failure = await ref
        .read(menuControllerProvider.notifier)
        .save(dish);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = failure;
      });
    }
  }

  Future<void> _delete() async {
    final VendorDish? d = _original;
    if (d == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Remove this dish?'),
        content: Text(
          '${d.name} will be taken off the menu. If it has never been ordered '
          'it is deleted for good.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final String? failure = await ref
        .read(menuControllerProvider.notifier)
        .delete(d.id);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      // Lift the sheet above the keyboard so the field being typed into is not
      // hidden behind it.
      padding: EdgeInsets.only(
        left: ZopiqSpacing.pageGutter,
        right: ZopiqSpacing.pageGutter,
        top: ZopiqSpacing.sm,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + ZopiqSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _isEditing ? 'Edit dish' : 'Add a dish',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ZopiqSpacing.lg),

            PhotoField(
              imageUrl: _imageUrl,
              height: 150,
              onChanged: (String url) => setState(() => _imageUrl = url),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Dish name'),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    // Repaints the "customers are charged ₹X" line below, so
                    // the promise under the field is never one edit stale.
                    onChanged: (String _) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefixText: '₹ ',
                    ),
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _originalPrice,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Was (optional)',
                      prefixText: '₹ ',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            // Said plainly, at the field, because this is the one number on the
            // screen that does not charge anybody — and because a "was" price
            // the kitchen never actually charged is a misleading price claim
            // that lands on them, not on us.
            Text(
              'Shown struck through beside the price. Customers are charged '
              '₹${_price.text.trim().isEmpty ? '—' : _price.text.trim()}. '
              'Only use a price you really charged.',
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _category,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Section'),
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _prepMinutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Prep (optional)',
                      suffixText: 'min',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.md),

            // Veg / non-veg, with the same mark the customer sees on the dish, so
            // the person setting it is looking at exactly what the diner will.
            InkWell(
              borderRadius: ZopiqRadii.rMd,
              onTap: () => setState(() => _isVeg = !_isVeg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: ZopiqSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    ZopiqVegIndicator(isVeg: _isVeg, size: 20),
                    const SizedBox(width: ZopiqSpacing.md),
                    Expanded(
                      child: Text(
                        _isVeg ? 'Vegetarian' : 'Non-vegetarian',
                        style: t.bodyLarge,
                      ),
                    ),
                    Switch(
                      value: _isVeg,
                      activeTrackColor: zc.veg,
                      onChanged: (bool v) => setState(() => _isVeg = v),
                    ),
                  ],
                ),
              ),
            ),

            // Bestseller — the vendor's own claim, shown to customers as a badge.
            // The star carries the meaning the way the veg mark does above it.
            InkWell(
              borderRadius: ZopiqRadii.rMd,
              onTap: () => setState(() => _isBestseller = !_isBestseller),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _isBestseller
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 20,
                      color: _isBestseller ? zc.rating : zc.textMuted,
                    ),
                    const SizedBox(width: ZopiqSpacing.md),
                    Expanded(
                      child: Text('Bestseller', style: t.bodyLarge),
                    ),
                    Switch(
                      value: _isBestseller,
                      activeTrackColor: zc.rating,
                      onChanged: (bool v) => setState(() => _isBestseller = v),
                    ),
                  ],
                ),
              ),
            ),

            // When this dish is sold. Off for almost every dish, so it collapses
            // to a single row until the kitchen says otherwise — a breakfast
            // menu is a real need and an uncommon one, and the editor should
            // cost nothing to the dishes that are sold all day.
            InkWell(
              borderRadius: ZopiqRadii.rMd,
              onTap: _toggleWindow,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.schedule_rounded,
                      size: 20,
                      color: _hasWindow ? zc.primary : zc.textMuted,
                    ),
                    const SizedBox(width: ZopiqSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Served at set hours', style: t.bodyLarge),
                          Text(
                            _hasWindow
                                ? 'Hidden from the menu outside these hours.'
                                : 'Available all day.',
                            style: t.bodySmall?.copyWith(color: zc.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _hasWindow,
                      activeTrackColor: zc.primary,
                      onChanged: (bool _) => _toggleWindow(),
                    ),
                  ],
                ),
              ),
            ),
            if (_hasWindow) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xs),
              Row(
                children: <Widget>[
                  _TimeChip(
                    label: _formatMinutes(context, _serveFrom!),
                    onTap: () => _pickWindow(opening: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZopiqSpacing.sm,
                    ),
                    child: Text('–', style: t.bodyMedium),
                  ),
                  _TimeChip(
                    label: _formatMinutes(context, _serveTo!),
                    onTap: () => _pickWindow(opening: false),
                  ),
                  // A window that ends before it starts runs past midnight —
                  // legal, and worth naming, exactly as the hours editor does.
                  if (_serveTo! < _serveFrom!)
                    Padding(
                      padding: const EdgeInsets.only(left: ZopiqSpacing.sm),
                      child: Text(
                        'next day',
                        style: t.labelSmall?.copyWith(color: zc.textMuted),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: ZopiqSpacing.sm),
            ],

            // Variants & add-ons live behind their own screen — a dish must be
            // saved (have an id) before options can attach to it, so this shows
            // only when editing, never while adding.
            if (_isEditing) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xs),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Customisation'),
                subtitle: const Text('Variants (Half/Full) and add-ons'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DishCustomizationPage(dish: _original!),
                  ),
                ),
              ),
            ],

            if (_error != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.md),
              Text(
                _error!,
                style: t.bodySmall?.copyWith(color: zc.nonVeg),
              ),
            ],

            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: _isEditing ? 'Save changes' : 'Add dish',
              variant: ZopiqButtonVariant.cta,
              isLoading: _busy,
              onPressed: _save,
            ),
            if (_isEditing) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.sm),
              TextButton(
                onPressed: _busy ? null : _delete,
                child: Text(
                  'Remove from menu',
                  style: TextStyle(color: zc.nonVeg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tappable time, styled like the hours editor's so the two screens that pick
/// a time on this app look like the same app.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    return InkWell(
      borderRadius: ZopiqRadii.rSm,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.md,
          vertical: ZopiqSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: zc.primary.withValues(alpha: 0.10),
          borderRadius: ZopiqRadii.rSm,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: zc.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
