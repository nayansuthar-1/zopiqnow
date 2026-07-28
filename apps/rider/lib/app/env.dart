/// Backend configuration, supplied at build time.
///
/// The same Supabase project as the other two apps — one database, three
/// clients. The URL and *publishable* key are not secrets: they are designed to
/// ship inside a client, and row-level security is what actually protects the
/// data. What makes this a rider app is not a key, it is a row in
/// `delivery_partners` (migration 0025).
///
/// The **service-role** key bypasses RLS and never appears in this app, in this
/// repo, or in any build.
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ofjjuzrxnksbyglzwaah.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_FV-_vP7cmhm_4GY11-wPwQ_NsC87Sbb',
  );

  /// Ola's tile key, for the job map.
  ///
  /// **No default, deliberately.** A vector map fetches its own tiles, so this
  /// key must reach the device and does ship inside the APK — but that is not a
  /// reason to also commit it. It is billable, and this repo has already had one
  /// live key reach a commit. So it is passed at build time and lives in
  /// `dart_defines.json`, which is gitignored:
  ///
  ///   flutter run --dart-define-from-file=../../dart_defines.json
  ///
  /// Empty here means the map shows its "no key" state rather than a grey void,
  /// which is the difference between a build mistake you can read and one you
  /// have to guess at.
  static const String olaMapsApiKey = String.fromEnvironment(
    'OLA_MAPS_API_KEY',
  );
}
