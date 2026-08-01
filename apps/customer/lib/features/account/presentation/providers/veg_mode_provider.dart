import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "100% Veg Mode" — a standing preference, not a screen's local state.
///
/// It was a `bool` inside a `StatefulWidget` on the Account page until
/// 2026-07-30: it forgot itself when the page was popped, and it filtered
/// nothing. It is on the device rather than in the user's metadata deliberately
/// — it is a way of using this phone, it should apply before anybody signs in,
/// and it should not cost a round trip on a cold start. That is the same
/// reasoning, and the same store, as the theme mode beside it.
class VegModeNotifier extends Notifier<bool> {
  static const String _key = 'veg_mode';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool? saved = prefs.getBool(_key);
    if (saved != null) state = saved;
  }

  Future<void> set(bool value) async {
    // Optimistic: the switch moves under the thumb, then the write lands. A
    // preference that waits on disk before it animates feels broken.
    state = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final NotifierProvider<VegModeNotifier, bool> vegModeProvider =
    NotifierProvider<VegModeNotifier, bool>(VegModeNotifier.new);
