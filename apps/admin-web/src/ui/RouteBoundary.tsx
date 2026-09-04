import { Component } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import { Button, Card } from './primitives'

/// The one thing route splitting can fail at.
///
/// Before Phase 6 the console was a single file: if it loaded at all, every
/// screen in it worked. Now each screen is a chunk fetched on the click, and a
/// fetch can fail — most often because the console was redeployed while an
/// admin had it open, so the tab is holding yesterday's HTML and asking for a
/// hashed filename that no longer exists. React's answer to a rejected `lazy`
/// import is to unmount the tree, which in an ops console means a white page
/// in the middle of a shift.
///
/// So: a boundary, and it offers a reload, because for a stale chunk a reload
/// genuinely is the fix — it fetches the current HTML and with it the current
/// filenames. This does not try to tell a missing chunk apart from a screen
/// that threw while rendering; both end here, and both are worth one honest
/// sentence and a way out rather than a diagnosis the admin cannot act on.
///
/// A class, because `getDerivedStateFromError` has no hook. The rest of the
/// console is function components and stays that way.
export class RouteBoundary extends Component<
  { resetKey: string; children: ReactNode },
  { failed: boolean; lastKey: string }
> {
  state = { failed: false, lastKey: this.props.resetKey }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  /// Navigating clears it. Without this, one screen whose chunk failed to
  /// arrive would hold the boundary open over every screen after it, and the
  /// console would look far more broken than it is. Done here rather than by
  /// keying the boundary from outside, so a working screen is not remounted on
  /// every navigation just to reset an error it never had.
  static getDerivedStateFromProps(
    props: { resetKey: string },
    state: { failed: boolean; lastKey: string },
  ) {
    if (props.resetKey === state.lastKey) return null
    return { failed: false, lastKey: props.resetKey }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // The console has no crash reporter of its own (the three apps have
    // Crashlytics; this does not). The browser console is where an admin on the
    // phone to us can read it out, so it goes there whole.
    console.error('Screen failed to load', error, info.componentStack)
  }

  render() {
    if (!this.state.failed) return this.props.children

    return (
      <div className="flex min-h-full items-center justify-center p-6">
        <Card className="w-full max-w-md text-center">
          <h1 className="text-lg font-bold text-ink">This screen didn’t load</h1>
          <p className="mt-2 text-sm text-ink-muted">
            Usually this means the console was updated while you had it open.
            Reloading picks up the new version. Nothing you have done is lost —
            every action in this console is saved when you press the button, not
            when you leave the page.
          </p>
          <Button className="mt-6 w-full" onClick={() => window.location.reload()}>
            Reload the console
          </Button>
        </Card>
      </div>
    )
  }
}
