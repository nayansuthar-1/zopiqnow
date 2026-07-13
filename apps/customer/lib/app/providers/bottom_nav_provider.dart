import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls the visibility of the bottom navigation bar.
/// Used by HomePage to hide the bar when scrolling down.
final StateProvider<bool> bottomNavVisibilityProvider = StateProvider<bool>((Ref ref) => true);
