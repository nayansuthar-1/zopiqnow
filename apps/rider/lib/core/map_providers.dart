import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_rider/app/env.dart';

/// Where the map pictures come from, and what lets us ask for one.
///
/// The Ola key is not here and never will be — it is referer-restricted, which
/// protects nothing inside an APK, so it stays in the `ola-static` Edge Function
/// (see `supabase/functions/ola-static/index.ts`). What the app holds is the URL
/// of that function and the rider's own access token.
final Provider<String> mapEndpointProvider = Provider<String>(
  (Ref ref) => '${Env.supabaseUrl}/functions/v1/ola-static',
);

/// The access token to send with a map request. Read at build time rather than
/// cached: a session refresh replaces the token, and a map fetched with the
/// previous one comes back 401.
final Provider<String?> mapAuthTokenProvider = Provider<String?>(
  (Ref ref) => Supabase.instance.client.auth.currentSession?.accessToken,
);
