import { useCallback } from 'react'
import { useSearchParams } from 'react-router-dom'

/// Filter state that lives in the address bar.
///
/// Every list in this console kept its filters, its search term and its page
/// number in component state, which had three costs and one of them mattered:
///
///   * A refresh lost your place. Nine screens deep into a settlement run, F5
///     put you back on page one of "pending".
///   * The back button walked out of the screen rather than out of the filter.
///   * **A view could not be handed to anybody.** "The stalled refunds for
///     Sadri" was a sentence you had to say out loud, not a link you could send,
///     and an ops team that cannot send each other links describes screens to
///     each other instead.
///
/// The third is the reason this exists. The other two came free.
///
/// ## The rules these follow
///
/// **A default is absent, not written.** `/orders` and `/orders?status=any` are
/// the same screen, so only one of them is ever in the address bar. Without this
/// the URL fills with restatements of the obvious and stops being readable, and
/// "is this link filtered?" stops being answerable at a glance.
///
/// **A change replaces rather than pushes.** Choosing four filters in a row
/// would otherwise put four entries in history and the back button would walk
/// them one at a time. The screen you came from is one press away, which is what
/// somebody means by back.
///
/// **The URL is not trusted.** A hand-typed `?status=nonsense` would otherwise
/// reach an RPC as an order status, so anything with a fixed set of values is
/// checked against it and falls back when it does not match.

/// One named value in the query string.
///
/// `allowed` is optional but wanted wherever the value has a fixed set — it is
/// the difference between a bad URL showing the default and a bad URL reaching
/// the database.
/// `NoInfer` on the fallback, so `useUrlState('q', '')` is a hook over `string`
/// and not one over the literal type `''` — which is what plain inference makes
/// of it, and which then refuses every value anybody tries to set. Where the
/// value does have a fixed set, `allowed` supplies the type instead.
export function useUrlState<T extends string = string>(
  key: string,
  fallback: NoInfer<T>,
  allowed?: readonly T[],
): readonly [T, (next: T) => void] {
  const [params, setParams] = useSearchParams()

  const raw = params.get(key) as T | null
  const value = raw === null || (allowed && !allowed.includes(raw)) ? fallback : raw

  const set = useCallback(
    (next: T) => {
      // The functional form, not a fresh `URLSearchParams(params)`: a handler
      // that sets two of these — "filter changed, so go back to page one" is
      // most of them — would otherwise have the second write land on the state
      // the first one read, and silently undo it.
      setParams(
        (prev) => {
          const p = new URLSearchParams(prev)
          if (next === fallback) p.delete(key)
          else p.set(key, next)
          return p
        },
        { replace: true },
      )
    },
    [key, fallback, setParams],
  )

  return [value, set] as const
}

/// A page number in the query string, held as the 1-based number a person reads
/// and returned as the 0-based one the RPCs take.
///
/// The offset by one is the whole reason this is not `useUrlState`. `?page=2` in
/// the address bar has to mean the second page — that is what the pager says and
/// what somebody typing it expects — while `admin_all_orders` counts from zero.
/// Doing that conversion in each page instead would be five chances to be off by
/// one in the direction that silently skips fifty orders.
export function useUrlPage(): readonly [number, (next: number) => void] {
  const [raw, setRaw] = useUrlState('page', '1')
  const parsed = Number.parseInt(raw, 10)
  const page = Number.isFinite(parsed) && parsed > 0 ? parsed - 1 : 0
  const set = useCallback((next: number) => setRaw(String(next + 1)), [setRaw])
  return [page, set] as const
}
