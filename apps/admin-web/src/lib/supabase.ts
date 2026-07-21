import { createClient } from '@supabase/supabase-js'

// The anon key, and only ever the anon key. The service-role key bypasses RLS
// and every `is_admin()` check behind it, so it does not belong in a bundle a
// browser downloads. Authority in this console comes from the signed-in admin's
// own JWT, exactly as it does in the three Flutter apps.
const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  throw new Error(
    'Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Copy .env.example to .env.local.',
  )
}

export const supabase = createClient(url, anonKey)

/// Supabase surfaces a raised `P0001` as a message string. Our RPCs raise
/// sentences meant to be read by a person, so they are shown as-is; anything
/// else gets a generic line rather than a Postgres error code.
export function messageFor(error: unknown): string {
  if (error && typeof error === 'object' && 'message' in error) {
    const message = String((error as { message: unknown }).message)
    if (message.trim().length > 0) return message
  }
  return 'Something went wrong. Please try again.'
}
