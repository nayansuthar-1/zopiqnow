/// Backend configuration, supplied at build time.
///
/// The same Supabase project as the customer app — one database, two clients.
/// The URL and *publishable* key are not secrets: they are designed to ship
/// inside a client, and row-level security is what actually protects the data.
/// What makes this app a vendor app is not a key, it is a row in
/// `restaurant_staff` (migration 0009).
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
}
