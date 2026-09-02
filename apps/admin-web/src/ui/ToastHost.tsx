import { useCallback, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { ToastContext } from './toast'
import type { Notify, ToastTone } from './toast'

type Toast = { id: number; tone: ToastTone; message: string }

/// How long a confirmation stays up. Long enough to read a sentence with an
/// order id in it, and no longer — a stack of stale confirmations covers the
/// corner of the screen the next action needs.
const SUCCESS_MS = 6000

export function ToastHost({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const next = useRef(1)

  const dismiss = useCallback((id: number) => {
    setToasts((t) => t.filter((x) => x.id !== id))
  }, [])

  const notify = useCallback<Notify>(
    (message, tone = 'success') => {
      const id = next.current++
      setToasts((t) => [...t, { id, tone, message }])
      // Only a confirmation goes away by itself. A failure that vanished on a
      // timer is a failure somebody did not read, and a failure nobody read is
      // indistinguishable from a success.
      if (tone === 'success') {
        window.setTimeout(() => dismiss(id), SUCCESS_MS)
      }
    },
    [dismiss],
  )

  // `notify` is stable, so this never re-renders the whole console.
  const value = useMemo(() => notify, [notify])

  return (
    <ToastContext.Provider value={value}>
      {children}
      {/* Above the modal layer, not beside it: an action confirmed from inside a
          dialog that stays open still has to be visible. */}
      <div
        className="pointer-events-none fixed right-4 bottom-4 z-[60] flex w-[min(24rem,calc(100vw-2rem))] flex-col gap-2"
        // The region is polite and the error tone carries its own assertive
        // role below, so a confirmation never interrupts what is being read and
        // a refusal always does.
        aria-live="polite"
      >
        {toasts.map((t) => (
          <div
            key={t.id}
            role={t.tone === 'error' ? 'alert' : 'status'}
            className={`pointer-events-auto flex items-start justify-between gap-3 rounded-card px-4 py-3 text-sm shadow-card ${
              t.tone === 'error'
                ? 'bg-non-veg-soft text-non-veg-ink'
                : 'bg-veg-soft text-veg'
            }`}
          >
            <p className="min-w-0">{t.message}</p>
            <button
              type="button"
              onClick={() => dismiss(t.id)}
              aria-label="Dismiss"
              className="shrink-0 rounded-xs font-semibold opacity-70 hover:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-ink"
            >
              ×
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  )
}
