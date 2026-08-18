import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zopiqnow/core/l10n/app_language.dart';
import 'package:zopiqnow/core/l10n/strings.dart';
import 'package:zopiqnow/core/l10n/strings_hi.dart';

/// The chosen app language, persisted across launches.
///
/// Deliberately the same shape as `ThemeModeNotifier` next door: a synchronous
/// default, an async read that corrects it a frame later, and a `set` that
/// writes through. The first frame is therefore English even for a Hindi
/// customer — for one frame, which is cheaper than blocking `runApp` on a disk
/// read to avoid it.
class AppLanguageNotifier extends Notifier<AppLanguage> {
  static const String _key = 'app_language';

  @override
  AppLanguage build() {
    _load();
    return AppLanguage.english;
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    state = AppLanguage.fromCode(prefs.getString(_key));
  }

  Future<void> set(AppLanguage language) async {
    state = language;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, language.code);
  }
}

final NotifierProvider<AppLanguageNotifier, AppLanguage> appLanguageProvider =
    NotifierProvider<AppLanguageNotifier, AppLanguage>(AppLanguageNotifier.new);

/// The string table for the chosen language.
///
/// Widgets read copy through `context.l10n`, not through this — the provider
/// exists to feed the one `AppStringsScope` at the root. Reading it directly
/// inside a screen works but rebuilds the whole screen on a language change
/// rather than letting the inherited widget do it.
final Provider<AppStrings> appStringsProvider = Provider<AppStrings>((
  Ref ref,
) {
  return switch (ref.watch(appLanguageProvider)) {
    AppLanguage.english => const AppStrings(),
    AppLanguage.hindi => const AppStringsHi(),
  };
});
