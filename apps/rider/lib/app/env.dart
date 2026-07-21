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
}
