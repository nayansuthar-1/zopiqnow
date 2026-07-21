import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'

/// Being signed in and being an admin are two different facts, and the console
/// needs both. Supabase issues a session to anyone who can receive an OTP —
/// that is identity, not authority. Authority is `platform_admins`, which the
/// server answers through `is_admin()` (migration 0026).
///
/// The check here is a *courtesy*: it decides what to render. It is not what
/// keeps a non-admin out — every admin RPC re-asks the same question server-side,
/// where the answer cannot be edited in a browser.
type AdminSession = {
  session: Session | null
  email: string | null
  isAdmin: boolean
  /// True until the stored session has been restored and checked. Rendering the
  /// sign-in screen before this settles would flash it at an admin who is
  /// already signed in.
  loading: boolean
  signOut: () => Promise<void>
}

const SessionContext = createContext<AdminSession | null>(null)

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true

    async function resolve(next: Session | null) {
      if (!active) return
      setSession(next)

      if (!next) {
        setIsAdmin(false)
        setLoading(false)
        return
      }

      const { data, error } = await supabase.rpc('is_admin')
      if (!active) return
      // An error here is a network failure, not a denial. Either way the console
      // stays shut: fail closed, never open.
      setIsAdmin(error ? false : data === true)
      setLoading(false)
    }

    supabase.auth.getSession().then(({ data }) => resolve(data.session))

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setLoading(true)
      void resolve(next)
    })

    return () => {
      active = false
      sub.subscription.unsubscribe()
    }
  }, [])

  const value = useMemo<AdminSession>(
    () => ({
      session,
      email: session?.user.email ?? null,
      isAdmin,
      loading,
      signOut: async () => {
        await supabase.auth.signOut()
      },
    }),
    [session, isAdmin, loading],
  )

  return <SessionContext value={value}>{children}</SessionContext>
}

export function useSession(): AdminSession {
  const value = useContext(SessionContext)
  if (!value) throw new Error('useSession must be used inside <SessionProvider>')
  return value
}
