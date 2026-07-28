import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/app/env.dart';

/// Where the map pictures come from, and what lets us ask for one.
///
/// The Ola key is not here and never will be — it is referer-restricted, which
/// protects nothing inside an APK, so it stays in the `ola-static` Edge Function
/// (see `supabase/functions/ola-static/index.ts`). What the app holds is the URL
/// of that function and the caller's own access token.
///
/// Null when nobody is signed in. The function is behind the platform's JWT
/// check, so a map cannot be fetched without a session — and there is no screen
/// that shows one without a session either.
final Provider<String> mapEndpointProvider = Provider<String>(
  (Ref ref) => '${Env.supabaseUrl}/functions/v1/ola-static',
);

/// The access token to send with a map request.
///
/// Read at build time rather than cached: a session refresh replaces the token,
/// and a map fetched with the previous one comes back 401.
final Provider<String?> mapAuthTokenProvider = Provider<String?>(
  (Ref ref) => Supabase.instance.client.auth.currentSession?.accessToken,
);
