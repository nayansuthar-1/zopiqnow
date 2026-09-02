import { createContext, useContext } from 'react'

/// Split from the component that provides it, the same way `auth/context.ts` is
/// split from `auth/session.tsx` — a file that exports both a hook and a
/// component defeats fast refresh and trips `react/only-export-components`.

export type ToastTone = 'success' | 'error'

/// Say something happened, where the eye already is.
///
/// The console had fifty `<Banner>`s and all of them rendered inline at the top
/// of the page body. Act on row forty of a settlements table and the sentence
/// saying it worked draws about 1,800px above the viewport: the button stops
/// spinning and nothing else observable happens. That is the whole reason this
/// exists — not decoration, but the difference between "it worked" and "I think
/// it worked, let me do it again".
export type Notify = (message: string, tone?: ToastTone) => void

export const ToastContext = createContext<Notify>(() => {
  // A no-op default rather than a throw. This is reached only if somebody
  // renders a screen outside `ToastHost`, and losing a confirmation is a much
  // smaller failure than crashing the page that was confirming something.
})

export function useToast(): Notify {
  return useContext(ToastContext)
}
