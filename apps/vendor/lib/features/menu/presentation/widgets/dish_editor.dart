import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/images/photo_field.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
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
  late final TextEditingController _category;
  late bool _isVeg;
  late String _imageUrl;

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
    _category = TextEditingController(text: d?.category ?? '');
    _isVeg = d?.isVeg ?? true;
    _imageUrl = d?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    final String category = _category.text.trim();
    final int price = int.tryParse(_price.text.trim()) ?? 0;

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

    // For an edit, start from the real row so the id and availability ride
    // along; for a new dish, a draft the database will give an id.
    final VendorDish dish = (_original ?? const VendorDish.draft()).copyWith(
      name: name,
      description: _description.text.trim(),
      price: price,
      isVeg: _isVeg,
      category: category,
      imageUrl: _imageUrl,
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
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefixText: '₹ ',
                    ),
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _category,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Section'),
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
