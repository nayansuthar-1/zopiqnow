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
}
