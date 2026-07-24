import 'package:flutter/foundation.dart';

/// One choosable answer on a dish — "Full", "Extra cheese" — and what it adds to
/// the base price. Mirrors a `menu_options` row (migration 0048). The [id] is
/// what the order service is sent; the [name] and [priceDelta] are what the
/// customer sees and what the line is priced by.
@immutable
class MenuOption {
  const MenuOption({
    required this.id,
    required this.name,
    this.priceDelta = 0,
  });

  final String id;
  final String name;

  /// Whole rupees this option adds to the dish's base price (never negative).
  final int priceDelta;

  factory MenuOption.fromJson(Map<String, dynamic> json) => MenuOption(
    id: json['id'] as String,
    name: json['name'] as String,
    priceDelta: (json['price_delta'] as num?)?.toInt() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MenuOption && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// A question a dish asks — a named group of [options] with a rule for how many
/// may be chosen. Mirrors `menu_option_groups` (0048). The rule *is* the kind: a
/// required single choice ([isVariant]) is a variant like Half/Full; anything
/// else is an add-on group.
@immutable
class MenuOptionGroup {
  const MenuOptionGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.options,
  });

  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<MenuOption> options;

  /// A required single choice — radios, and one must be picked.
  bool get isVariant => minSelect == 1 && maxSelect == 1;

  /// Whether at least one option must be chosen from this group.
  bool get isRequired => minSelect >= 1;

  factory MenuOptionGroup.fromJson(Map<String, dynamic> json) {
    final List<Map<String, dynamic>> rows =
        (json['menu_options'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort(
            (Map<String, dynamic> a, Map<String, dynamic> b) =>
                ((a['rank'] as num?)?.toInt() ?? 0)
                    .compareTo((b['rank'] as num?)?.toInt() ?? 0),
          );
    return MenuOptionGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      minSelect: (json['min_select'] as num?)?.toInt() ?? 0,
      maxSelect: (json['max_select'] as num?)?.toInt() ?? 1,
      options: rows.map(MenuOption.fromJson).toList(growable: false),
    );
  }
}
