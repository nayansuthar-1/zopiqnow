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

  /// Cloudinary, for dish and restaurant photos.
  ///
  /// The cloud name is **public** — it is in every delivery URL — and the upload
  /// preset is an *unsigned* one, which by design carries no secret: the app can
  /// upload with just these two and never sees the API key or secret. Those live
  /// only in `.env`, server-side, and are used to create and lock down the preset.
  /// A mobile binary is decompilable, so a secret compiled into it is a public
  /// secret; that is why neither is here.
  static const String cloudinaryCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'w69i7qes',
  );

  static const String cloudinaryUploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'zopiqnow_unsigned',
  );

  /// The **web** OAuth client, shared with the customer and rider apps.
  ///
  /// Shared deliberately, and it is not a shortcut: this is the audience the id
  /// token is minted for and the value Supabase checks it against, so all three
  /// apps must present the same one. What is *not* shared is the Android client
  /// — Google reserves the pair (package name, signing certificate) globally to
  /// one client, so `com.siteonlab.zopiq_vendor` needs its own registration with
  /// this app's own fingerprints. Getting that wrong fails on the device with
  /// `Invalid key value: <sha1>:com.siteonlab.zopiq_vendor` and nowhere else.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '789936942272-82up4pgu8v6in4vmvnogqhiqa8legtl5.apps.googleusercontent.com',
  );
}
