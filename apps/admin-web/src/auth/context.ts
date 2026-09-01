import { createContext, useContext } from 'react'
import type { Session } from '@supabase/supabase-js'

/// Being signed in and being an admin are two different facts, and the console
/// needs both. Supabase issues a session to anyone whose email and password
/// match — that is identity, not authority. Authority is `platform_admins`,
/// which the server answers through `is_admin()` (migration 0026).
///
/// The check here is a *courtesy*: it decides what to render. It is not what
/// keeps a non-admin out — every admin RPC re-asks the same question server-side,
/// where the answer cannot be edited in a browser.
export type AdminSession = {
  session: Session | null
  email: string | null
  isAdmin: boolean
  /// True until the stored session has been restored and checked. Rendering the
  /// sign-in screen before this settles would flash it at an admin who is
  /// already signed in.
  loading: boolean
  signOut: () => Promise<void>
}

/// Separate from `session.tsx` so that file exports nothing but its component.
/// A module that exports both a component and something else loses fast refresh
/// for the whole module — every edit to the provider would reload the app rather
/// than the component, and the console's dev loop is the one place that costs.
export const SessionContext = createContext<AdminSession | null>(null)

export function useSession(): AdminSession {
  const value = useContext(SessionContext)
  if (!value) throw new Error('useSession must be used inside <SessionProvider>')
  return value
}
