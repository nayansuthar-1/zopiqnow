import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/menu/domain/entities/dish_options.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/menu/presentation/providers/dish_options_providers.dart';

/// The customisation editor for one dish: its variant and add-on groups.
///
/// A dish must already exist (have an id) before it can carry options, so this is
/// reached only from the *edit* sheet, never the add sheet. It loads the dish's
/// current groups once, edits a working copy, and writes the whole thing back
/// through `set_menu_item_options` — a wholesale swap, the way the vendor thinks
/// of it ("this is how this dish is customised now").
class DishCustomizationPage extends ConsumerStatefulWidget {
  const DishCustomizationPage({required this.dish, super.key});

  final VendorDish dish;

  @override
  ConsumerState<DishCustomizationPage> createState() =>
      _DishCustomizationPageState();
}

class _DishCustomizationPageState extends ConsumerState<DishCustomizationPage> {
  List<DishOptionGroup>? _groups;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final List<DishOptionGroup> groups = await ref
          .read(dishOptionsDataSourceProvider)
          .fetch(widget.dish.id);
      if (!mounted) return;
      setState(() {
        _groups = List<DishOptionGroup>.of(groups);
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'We couldn\'t load this dish\'s options.';
      });
    }
  }

  Future<void> _save() async {
    final List<DishOptionGroup> groups = _groups ?? const <DishOptionGroup>[];

    // A group with no options is a question with no answers — refuse it here
    // rather than store an empty group the customer can never satisfy.
    if (groups.any((DishOptionGroup g) => g.options.isEmpty)) {
      setState(() => _saveError = 'Every group needs at least one option.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });
    final String? failure = await ref
        .read(dishOptionsControllerProvider.notifier)
        .save(widget.dish.id, groups);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _saveError = failure;
      });
    }
  }

  void _replaceGroup(int i, DishOptionGroup group) =>
      setState(() => _groups![i] = group);

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customisation'),
        actions: <Widget>[
          if (!_loading && _loadError == null)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _CenteredMessage(
                icon: Icons.cloud_off_rounded,
                title: _loadError!,
                actionLabel: 'Retry',
                onAction: _load,
              )
            : ListView(
                padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
                children: <Widget>[
                  Text(
                    widget.dish.name,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    'Base price ₹${widget.dish.price}. Variants and add-ons add to it.',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                  const SizedBox(height: ZopiqSpacing.lg),

                  if (_groups!.isEmpty)
                    const _CenteredMessage(
                      icon: Icons.tune_rounded,
                      title: 'No customisation yet',
                      body:
                          'Add a variant (like Half/Full) or add-ons (like extra cheese).',
                    )
                  else
                    for (int i = 0; i < _groups!.length; i++) ...<Widget>[
                      _GroupCard(
                        group: _groups![i],
                        onChanged: (DishOptionGroup g) => _replaceGroup(i, g),
                        onRemove: () =>
                            setState(() => _groups!.removeAt(i)),
                      ),
                      const SizedBox(height: ZopiqSpacing.md),
                    ],

                  const SizedBox(height: ZopiqSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _addGroup,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a group'),
                  ),

                  if (_saveError != null) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.md),
                    Text(
                      _saveError!,
                      style: t.bodySmall?.copyWith(color: zc.nonVeg),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _addGroup() async {
    final DishOptionGroup? group = await showModalBottomSheet<DishOptionGroup>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _GroupForm(),
    );
    if (group != null) setState(() => _groups!.add(group));
  }
}

/// One group and its options, with edit/remove for the group and each option.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.onChanged,
    required this.onRemove,
  });

  final DishOptionGroup group;
  final ValueChanged<DishOptionGroup> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      padding: const EdgeInsets.all(ZopiqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      group.name,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      group.isVariant
                          ? 'Variant · pick one'
                          : 'Add-ons · pick up to ${group.maxSelect}',
                      style: t.labelSmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit group',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _editGroup(context),
              ),
              IconButton(
                tooltip: 'Remove group',
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: zc.nonVeg),
                onPressed: onRemove,
              ),
            ],
          ),
          const Divider(height: ZopiqSpacing.md),

          for (int i = 0; i < group.options.length; i++)
            _OptionRow(
              option: group.options[i],
              onChanged: (DishOption o) {
                final List<DishOption> next = List<DishOption>.of(group.options);
                next[i] = o;
                onChanged(group.copyWith(options: next));
              },
              onEdit: () => _editOption(context, i),
              onRemove: () {
                final List<DishOption> next = List<DishOption>.of(group.options)
                  ..removeAt(i);
                onChanged(group.copyWith(options: next));
              },
            ),

          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addOption(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add option'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editGroup(BuildContext context) async {
    final DishOptionGroup? edited = await showModalBottomSheet<DishOptionGroup>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GroupForm(existing: group),
    );
    // Editing keeps the group's options; only its name/kind/max change.
    if (edited != null) onChanged(edited.copyWith(options: group.options));
  }

  Future<void> _addOption(BuildContext context) async {
    final DishOption? option = await showModalBottomSheet<DishOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _OptionForm(),
    );
    if (option != null) {
      onChanged(group.copyWith(options: <DishOption>[...group.options, option]));
    }
  }

  Future<void> _editOption(BuildContext context, int i) async {
    final DishOption? edited = await showModalBottomSheet<DishOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OptionForm(existing: group.options[i]),
    );
    // Editing keeps the option's availability; only its name/price change.
    if (edited != null) {
      final List<DishOption> next = List<DishOption>.of(group.options);
      next[i] = edited.copyWith(isAvailable: group.options[i].isAvailable);
      onChanged(group.copyWith(options: next));
    }
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.onChanged,
    required this.onEdit,
    required this.onRemove,
  });

  final DishOption option;
  final ValueChanged<DishOption> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.xxs),
      child: Row(
        children: <Widget>[
          // Tap the name/price to fix a typo or change the amount.
          Expanded(
            child: InkWell(
              onTap: onEdit,
              borderRadius: ZopiqRadii.rSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.xs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        option.name,
                        style: t.bodyMedium?.copyWith(
                          color: option.isAvailable
                              ? zc.textStrong
                              : zc.textMuted,
                          decoration: option.isAvailable
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    Text(
                      option.priceDelta == 0 ? 'Free' : '+₹${option.priceDelta}',
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // A single option can sell out without deleting it.
          Switch(
            value: option.isAvailable,
            onChanged: (bool v) => onChanged(option.copyWith(isAvailable: v)),
          ),
          IconButton(
            tooltip: 'Remove option',
            icon: Icon(Icons.close_rounded, size: 18, color: zc.textMuted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Add or edit a group: a name, whether it is a variant or add-ons, and — for
/// add-ons — how many may be chosen.
class _GroupForm extends StatefulWidget {
  const _GroupForm({this.existing});

  final DishOptionGroup? existing;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  late final TextEditingController _name;
  late final TextEditingController _max;
  late bool _isVariant;
  String? _error;

  @override
  void initState() {
    super.initState();
    final DishOptionGroup? g = widget.existing;
    _name = TextEditingController(text: g?.name ?? '');
    _isVariant = g?.isVariant ?? true;
    _max = TextEditingController(
      text: g != null && !g.isVariant ? '${g.maxSelect}' : '1',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _max.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name, e.g. "Size" or "Toppings".');
      return;
    }
    final DishOptionGroup group;
    if (_isVariant) {
      group = DishOptionGroup.variant(name: name);
    } else {
      final int max = int.tryParse(_max.text.trim()) ?? 0;
      if (max < 1) {
        setState(() => _error = 'How many add-ons can they pick? Enter 1 or more.');
        return;
      }
      group = DishOptionGroup.addon(name: name, max: max);
    }
    Navigator.of(context).pop(group);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: EdgeInsets.only(
        left: ZopiqSpacing.pageGutter,
        right: ZopiqSpacing.pageGutter,
        top: ZopiqSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + ZopiqSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.existing == null ? 'Add a group' : 'Edit group',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: true, label: Text('Variant (pick one)')),
              ButtonSegment<bool>(value: false, label: Text('Add-ons')),
            ],
            selected: <bool>{_isVariant},
            onSelectionChanged: (Set<bool> s) =>
                setState(() => _isVariant = s.first),
          ),
          if (!_isVariant) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.md),
            TextField(
              controller: _max,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Max choices',
                helperText: 'How many add-ons a customer can pick from this group.',
              ),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.sm),
            Text(_error!, style: t.bodySmall?.copyWith(color: zc.nonVeg)),
          ],
          const SizedBox(height: ZopiqSpacing.lg),
          ZopiqButton(
            label: widget.existing == null ? 'Add group' : 'Save group',
            variant: ZopiqButtonVariant.cta,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// Add or edit an option: a name and what it adds to the price.
class _OptionForm extends StatefulWidget {
  const _OptionForm({this.existing});

  final DishOption? existing;

  @override
  State<_OptionForm> createState() => _OptionFormState();
}

class _OptionFormState extends State<_OptionForm> {
  late final TextEditingController _name;
  late final TextEditingController _delta;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _delta = TextEditingController(
      text: widget.existing != null ? '${widget.existing!.priceDelta}' : '0',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _delta.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the option a name, e.g. "Full" or "Extra cheese".');
      return;
    }
    final int delta = int.tryParse(_delta.text.trim()) ?? 0;
    Navigator.of(context).pop(
      DishOption(name: name, priceDelta: delta),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: EdgeInsets.only(
        left: ZopiqSpacing.pageGutter,
        right: ZopiqSpacing.pageGutter,
        top: ZopiqSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + ZopiqSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.existing == null ? 'Add an option' : 'Edit option',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Option name'),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          TextField(
            controller: _delta,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'Adds to price',
              prefixText: '+₹ ',
              helperText: 'Leave 0 for a free choice like "Half".',
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.sm),
            Text(_error!, style: t.bodySmall?.copyWith(color: zc.nonVeg)),
          ],
          const SizedBox(height: ZopiqSpacing.lg),
          ZopiqButton(
            label: widget.existing == null ? 'Add option' : 'Save option',
            variant: ZopiqButtonVariant.cta,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(ZopiqSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 44, color: zc.textMuted),
          const SizedBox(height: ZopiqSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: t.titleSmall?.copyWith(color: zc.textStrong),
          ),
          if (body != null) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
          ],
          if (onAction != null) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.md),
            TextButton(onPressed: onAction, child: Text(actionLabel ?? 'Retry')),
          ],
        ],
      ),
    );
  }
}
