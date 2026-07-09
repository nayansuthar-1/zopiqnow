import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

/// A named group of menu items (e.g. "Recommended", "Biryanis").
@immutable
class MenuCategory {
  const MenuCategory({required this.title, required this.items});

  final String title;
  final List<MenuItem> items;
}
