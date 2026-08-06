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

  /// Cloudinary, for the photograph of the handover (0094).
  ///
  /// The same cloud and the same *unsigned* preset the vendor app uploads dish
  /// photos through, and the same reasoning: the cloud name is public — it is in
  /// every delivery URL — and an unsigned preset carries no secret, so the app
  /// can upload with just these two and never sees the API key or secret. Those
  /// live only in `.env`, server-side, and exist to create and lock down the
  /// preset. A mobile binary is decompilable, so a secret compiled into it is a
  /// public secret; that is why neither is here.
  static const String cloudinaryCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'w69i7qes',
  );

  static const String cloudinaryUploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'zopiqnow_unsigned',
  );

  /// The **web** OAuth client, shared with the customer and vendor apps.
  ///
  /// Shared deliberately, and it is not a shortcut: this is the audience the id
  /// token is minted for and the value Supabase checks it against, so all three
  /// apps must present the same one. What is *not* shared is the Android client
  /// — Google reserves the pair (package name, signing certificate) globally to
  /// one client, so `com.siteonlab.zopiq_rider` needs its own registration with
  /// this app's own fingerprints. Getting that wrong fails on the device with
  /// `Invalid key value: <sha1>:com.siteonlab.zopiq_rider` and nowhere else.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '789936942272-82up4pgu8v6in4vmvnogqhiqa8legtl5.apps.googleusercontent.com',
  );
}

// The Maps key is deliberately absent from this file. Google's Maps SDK reads
// it from a manifest meta-data element, not from Dart, so it never becomes a
// `String.fromEnvironment` and never needs a `--dart-define`. Gradle substitutes
// it from `android/local.properties`, which is gitignored. See
// `android/app/build.gradle.kts`.
