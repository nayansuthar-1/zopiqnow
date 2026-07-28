/// Backend configuration, supplied at build time.
///
/// The Supabase URL and *publishable* key are not secrets — they are designed
/// to ship inside the client, and row-level security is what actually protects
/// the data. They live here so a staging build is a `--dart-define` away rather
/// than an edit:
///
///   flutter run --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
///
/// The **service-role** key is a different animal entirely: it bypasses RLS. It
/// never appears in this app, in this repo, or in any build — only in Edge
/// Functions, from Supabase's own secret store.
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ofjjuzrxnksbyglzwaah.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_FV-_vP7cmhm_4GY11-wPwQ_NsC87Sbb',
  );

  /// The **Web** OAuth client id, not the Android one — and that is not a typo.
  ///
  /// Native Google sign-in asks Android for an id token *addressed to a backend*,
  /// and the backend here is Supabase, which is configured with this same web
  /// client. Pass the Android client id instead and the token comes back with the
  /// wrong `aud`, which Supabase rejects. The Android client still has to exist
  /// (it is what ties the signing certificate to the app), but it is never named
  /// in code.
  ///
  /// Public by design, like every OAuth client id: it identifies the app, it does
  /// not authenticate it. The client *secret* lives only in Supabase.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '824878750768-thl7npqn43prt1ku2n8ts6ign9ejgdd9.apps.googleusercontent.com',
  );

  /// Ola's tile key, for the delivery map.
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
