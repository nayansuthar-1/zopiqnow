/// The languages the customer app speaks.
///
/// English is the base and Hindi is the secondary. Adding a third is a new
/// enum entry, a new [AppStrings] subclass, and nothing else — the settings
/// dropdown and the persisted preference both read this list rather than a
/// hardcoded pair.
enum AppLanguage {
  /// The base language. Every string in [AppStrings] is written in it, so a
  /// key that no translation has reached still renders something readable.
  english('en', 'English'),

  /// Devanagari, in the register people in Falna, Ranakpur and Sadri actually
  /// use — common English loanwords kept as loanwords (कार्ट, ऑर्डर, डिलीवरी)
  /// rather than replaced with shuddh Hindi nobody says out loud.
  hindi('hi', 'हिन्दी');

  const AppLanguage(this.code, this.nativeName);

  /// Stored in `SharedPreferences`, so it must stay stable across releases.
  final String code;

  /// Shown in the language picker. Deliberately the *endonym* — somebody
  /// looking for Hindi is looking for "हिन्दी", not for the word "Hindi"
  /// written in an alphabet the setting is meant to move them away from.
  final String nativeName;

  /// The persisted code back to a language, tolerating anything unexpected.
  /// A preference file can outlive the language it names — a build that drops
  /// a locale must not fail to start because somebody had it selected.
  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (AppLanguage language) => language.code == code,
    orElse: () => AppLanguage.english,
  );
}
