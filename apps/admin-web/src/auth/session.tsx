import { useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { SessionContext } from './context'
import type { AdminSession } from './context'

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true
    // Whose authority we last asked the server about. `onAuthStateChange` fires
    // on far more than a sign-in — see below — and re-asking on every one of
    // those is a network round trip that can only ever return the same answer.
    let checkedFor: string | null = null

    async function resolve(next: Session | null) {
      if (!active) return
      setSession(next)

      if (!next) {
        checkedFor = null
        setIsAdmin(false)
        setLoading(false)
        return
      }

      if (checkedFor === next.user.id) {
        setLoading(false)
        return
      }

      const { data, error } = await supabase.rpc('is_admin')
      if (!active) return
      // An error here is a network failure, not a denial. Either way the console
      // stays shut: fail closed, never open.
      checkedFor = error ? null : next.user.id
      setIsAdmin(error ? false : data === true)
      setLoading(false)
    }

    void supabase.auth.getSession().then(({ data }) => resolve(data.session))

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      // **`loading` is not set back to true here, and that is the whole fix.**
      //
      // `onAuthStateChange` does not only fire when somebody signs in or out.
      // supabase-js listens for `visibilitychange`, and every time the tab comes
      // back to the front it revalidates the stored session and emits an event —
      // usually `SIGNED_IN` or `TOKEN_REFRESHED`, with the same user as before.
      //
      // This used to raise `loading`, and `App` renders a bare "Loading…" screen
      // while that is true. Raising it unmounted `<BrowserRouter>` and the whole
      // shell under it, so alt-tabbing away and back tore down every screen and
      // built it again: filters reset, forms emptied, tables refetched, the live
      // board jumped back to the top. Indistinguishable from a page reload, and
      // reported as one.
      //
      // `loading` means "the stored session has not been checked yet". That is
      // true exactly once, before the first resolution, and `resolve` is what
      // ends it. It is not a spinner for every subsequent token refresh.
      //
      // Deferred out of the callback rather than awaited inside it: supabase-js
      // holds an internal lock while it dispatches, and calling back into the
      // client from within the handler can deadlock it. A zero timeout is the
      // documented way out.
      setTimeout(() => void resolve(next), 0)
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
