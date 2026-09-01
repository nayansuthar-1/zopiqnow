import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { SessionContext } from './context'
import type { AdminSession } from './context'

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [loading, setLoading] = useState(true)
  const [checkFailed, setCheckFailed] = useState(false)

  // Whose authority we last asked the server about. `onAuthStateChange` fires
  // on far more than a sign-in — see below — and re-asking on every one of
  // those is a network round trip that can only ever return the same answer.
  //
  // A ref rather than a variable inside the effect, because `resolve` is now
  // reachable from outside it: the retry has to be able to ask again without
  // tearing down and re-establishing the auth subscription.
  const checkedFor = useRef<string | null>(null)
  const alive = useRef(true)

  const resolve = useCallback(async (next: Session | null) => {
    if (!alive.current) return
    setSession(next)

    if (!next) {
      checkedFor.current = null
      setIsAdmin(false)
      setCheckFailed(false)
      setLoading(false)
      return
    }

    if (checkedFor.current === next.user.id) {
      setLoading(false)
      return
    }

    const { data, error } = await supabase.rpc('is_admin')
    if (!alive.current) return
    // An error here is a network failure, not a denial. Either way the console
    // stays shut: fail closed, never open.
    //
    // But they are not the same screen. "You are not staff" is a sentence about
    // the person and a dead end on purpose; "we could not ask" is a sentence
    // about the connection and has a way out. `checkFailed` is the difference,
    // and `checkedFor` staying null after a failure is what lets the next ask
    // actually reach the server.
    checkedFor.current = error ? null : next.user.id
    setIsAdmin(error ? false : data === true)
    setCheckFailed(Boolean(error))
    setLoading(false)
  }, [])

  useEffect(() => {
    alive.current = true

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
      alive.current = false
      sub.subscription.unsubscribe()
    }
  }, [resolve])

  const value = useMemo<AdminSession>(
    () => ({
      session,
      email: session?.user.email ?? null,
      isAdmin,
      loading,
      checkFailed,
      recheck: () => resolve(session),
      signOut: async () => {
        await supabase.auth.signOut()
      },
    }),
    [session, isAdmin, loading, checkFailed, resolve],
  )

  return <SessionContext value={value}>{children}</SessionContext>
}
