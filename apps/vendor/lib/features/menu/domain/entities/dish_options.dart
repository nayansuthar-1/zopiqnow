import 'package:flutter/foundation.dart';

/// One answer a customer can pick — "Full", "Extra cheese" — and what it adds to
/// the dish's base price. Mirrors a `menu_options` row (migration 0048).
@immutable
class DishOption {
  const DishOption({
    required this.name,
    this.priceDelta = 0,
    this.isAvailable = true,
  });

  final String name;

  /// Whole rupees added to the dish's base price. Never negative — the base
  /// price is the cheapest configuration.
  final int priceDelta;

  final bool isAvailable;

  DishOption copyWith({String? name, int? priceDelta, bool? isAvailable}) =>
      DishOption(
        name: name ?? this.name,
        priceDelta: priceDelta ?? this.priceDelta,
        isAvailable: isAvailable ?? this.isAvailable,
      );

  factory DishOption.fromJson(Map<String, dynamic> json) => DishOption(
    name: json['name'] as String,
    priceDelta: (json['price_delta'] as num?)?.toInt() ?? 0,
    isAvailable: json['is_available'] as bool? ?? true,
  );

  /// The shape `set_menu_item_options` expects for an option.
  Map<String, dynamic> toRpcJson(int rank) => <String, dynamic>{
    'name': name,
    'price_delta': priceDelta,
    'is_available': isAvailable,
    'rank': rank,
  };
}

/// A question a dish asks — a named group of [options] with a rule for how many
/// may be chosen. Mirrors a `menu_option_groups` row (0048).
///
/// The rule *is* the kind: a required single choice ([isVariant], min 1/max 1)
/// is a variant like Half/Full; anything else is an add-on group. There is no
/// separate type — the app reads the min/max, exactly as the database does.
@immutable
class DishOptionGroup {
  const DishOptionGroup({
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    this.options = const <DishOption>[],
  });

  /// A required single-choice group — a variant.
  const DishOptionGroup.variant({
    required this.name,
    this.options = const <DishOption>[],
  }) : minSelect = 1,
       maxSelect = 1;

  /// An optional multi-choice group — add-ons — capped at [max].
  const DishOptionGroup.addon({
    required this.name,
    required int max,
    this.options = const <DishOption>[],
  }) : minSelect = 0,
       maxSelect = max;

  final String name;
  final int minSelect;
  final int maxSelect;
  final List<DishOption> options;

  bool get isVariant => minSelect == 1 && maxSelect == 1;

  DishOptionGroup copyWith({
    String? name,
    int? minSelect,
    int? maxSelect,
    List<DishOption>? options,
  }) => DishOptionGroup(
    name: name ?? this.name,
    minSelect: minSelect ?? this.minSelect,
    maxSelect: maxSelect ?? this.maxSelect,
    options: options ?? this.options,
  );

  factory DishOptionGroup.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw =
        (json['menu_options'] as List<dynamic>? ?? const <dynamic>[]);
    final List<Map<String, dynamic>> rows = raw
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            ((a['rank'] as num?)?.toInt() ?? 0)
                .compareTo((b['rank'] as num?)?.toInt() ?? 0),
      );
    return DishOptionGroup(
      name: json['name'] as String,
      minSelect: (json['min_select'] as num?)?.toInt() ?? 0,
      maxSelect: (json['max_select'] as num?)?.toInt() ?? 1,
      options: rows.map(DishOption.fromJson).toList(growable: false),
    );
  }

  /// The shape `set_menu_item_options` expects for a group.
  Map<String, dynamic> toRpcJson(int rank) => <String, dynamic>{
    'name': name,
    'min_select': minSelect,
    // An add-on group with no explicit cap can take all of its options.
    'max_select': maxSelect,
    'rank': rank,
    'options': <Map<String, dynamic>>[
      for (int i = 0; i < options.length; i++) options[i].toRpcJson(i),
    ],
  };
}
