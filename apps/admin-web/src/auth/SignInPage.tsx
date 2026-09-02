import { useState } from 'react'
import { supabase, messageFor } from '../lib/supabase'
import { Button, Card, Field } from '../ui/primitives'

/// Two doors: email and password, or a six-digit code mailed to an address
/// already on the roster. Both end in the same place — a Supabase session that
/// `is_admin()` then has the final word on.
///
/// **The code door is not the old code door.** The console's first sign-in
/// screen called `signInWithOtp({ shouldCreateUser: true })`, which minted an
/// `auth.users` row for *any* address that typed itself in. Authority is the
/// `platform_admins` row and never the account, so that was survivable — but
/// the front door of an ops console created users as a side effect of being
/// looked at, and 0153 replaced the whole thing with a password.
///
/// What comes back here is narrower in the two ways that matter. The console
/// never asks GoTrue for anything: it asks the `console-otp` function, which
/// holds the service-role key, checks `platform_admins` — a table RLS closes to
/// every other reader (0026) — and only then asks for a code, with
/// `shouldCreateUser: false`. An address that is not an admin gets no mail, and
/// an address with no account gets no account.
///
/// **The screen says the same thing either way**, which is the point: naming
/// the addresses that are admins would be handing a stranger the list worth
/// attacking. It cannot say "there is no such admin", so it says "if that
/// address can open this console".
///
/// There is still no sign-up and no password reset. Both would be a way in that
/// does not begin with an existing admin, which is the same reason
/// `platform_admins` has no self-service path. The code door does begin with
/// one: the roster is the gate, and it is checked on the server.

type Door = 'password' | 'code'

export function SignInPage() {
  const [door, setDoor] = useState<Door>('password')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [code, setCode] = useState('')
  /// Whether the code has been asked for. Not "whether it was sent" — this
  /// screen is never told that, and a name that claimed otherwise would invite
  /// somebody to render it.
  const [asked, setAsked] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const address = email.trim().toLowerCase()

  function switchTo(next: Door) {
    setDoor(next)
    setError(null)
    setCode('')
    setAsked(false)
  }

  async function signIn() {
    setBusy(true)
    setError(null)
    const { error } = await supabase.auth.signInWithPassword({
      email: address,
      password,
    })
    setBusy(false)
    if (error) {
      // Supabase answers a wrong password and an unknown address with the same
      // "Invalid login credentials", and that is the right behaviour — telling
      // a stranger which addresses exist is telling them who to go after. One
      // sentence for both, so nothing here narrows it down either.
      setError(
        error.message === 'Invalid login credentials'
          ? "That email and password don't match."
          : messageFor(error),
      )
      return
    }
    // On success there is nothing to do here: SessionProvider is listening to
    // the auth state change, and it decides — via is_admin() — what comes next.
  }

  async function askForCode() {
    setBusy(true)
    setError(null)
    const { error } = await supabase.functions.invoke('console-otp', {
      body: { email: address },
    })
    setBusy(false)
    if (error) {
      setError(await invokeMessage(error))
      return
    }
    setAsked(true)
  }

  async function signInWithCode() {
    setBusy(true)
    setError(null)
    const { error } = await supabase.auth.verifyOtp({
      email: address,
      token: code.trim(),
      // `email`, not `magiclink`: the mail carries a six-digit code because the
      // template renders `{{ .Token }}`, which is the same dashboard decision
      // the three Flutter apps' sign-in depends on.
      type: 'email',
    })
    setBusy(false)
    if (error) {
      setError(
        error.message.toLowerCase().includes('expired') ||
          error.message.toLowerCase().includes('invalid')
          ? 'That code is wrong or has expired. Ask for another one.'
          : messageFor(error),
      )
      return
    }
    // Same as the password door: SessionProvider takes it from here.
  }

  return (
    <div className="flex min-h-full items-center justify-center p-6">
      <Card className="w-full max-w-md">
        <h1 className="text-xl font-bold text-ink">Zopiqnow Console</h1>
        <p className="mt-1 text-sm text-ink-muted">
          {door === 'password'
            ? 'Sign in with your Zopiqnow staff email.'
            : 'A code, to a staff email that can already open this console.'}
        </p>

        {door === 'password' ? (
          <form
            className="mt-6 space-y-4"
            onSubmit={(e) => {
              e.preventDefault()
              void signIn()
            }}
          >
            <Field
              label="Email"
              type="email"
              required
              autoFocus
              autoComplete="username"
              placeholder="you@siteonlab.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />

            <Field
              label="Password"
              type="password"
              required
              // Named so the browser's password manager offers to save and fill
              // it. Without this an ops password gets retyped, and a retyped
              // password gets written on something.
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />

            {error && <p className="text-sm text-non-veg-ink">{error}</p>}

            <Button type="submit" loading={busy} className="w-full">
              Sign in
            </Button>
          </form>
        ) : !asked ? (
          <form
            className="mt-6 space-y-4"
            onSubmit={(e) => {
              e.preventDefault()
              void askForCode()
            }}
          >
            <Field
              label="Email"
              type="email"
              required
              autoFocus
              autoComplete="username"
              placeholder="you@siteonlab.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />

            {error && <p className="text-sm text-non-veg-ink">{error}</p>}

            <Button type="submit" loading={busy} className="w-full">
              Email me a code
            </Button>
          </form>
        ) : (
          <form
            className="mt-6 space-y-4"
            onSubmit={(e) => {
              e.preventDefault()
              void signInWithCode()
            }}
          >
            {/* Says nothing about whether that address is an admin, because the
                function it just called said nothing either. */}
            <p className="rounded-field border border-line bg-canvas p-3 text-sm text-ink-muted">
              If <span className="text-ink">{address}</span> can open this
              console, a six-digit code is on its way. It can take a minute, and
              asking again straight away will not make it faster.
            </p>

            <Field
              label="Code"
              required
              autoFocus
              inputMode="numeric"
              maxLength={6}
              placeholder="123456"
              // The one autocomplete iOS and Android both act on: it puts the
              // code from the notification on the keyboard instead of making
              // somebody memorise six digits from another app.
              autoComplete="one-time-code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
            />

            {error && <p className="text-sm text-non-veg-ink">{error}</p>}

            <Button
              type="submit"
              loading={busy}
              disabled={code.trim().length < 6}
              className="w-full"
            >
              Sign in
            </Button>

            <Button
              type="button"
              variant="ghost"
              className="w-full"
              disabled={busy}
              onClick={() => {
                setAsked(false)
                setCode('')
                setError(null)
              }}
            >
              Use a different address
            </Button>
          </form>
        )}

        <Button
          variant="ghost"
          className="mt-2 w-full"
          disabled={busy}
          onClick={() => switchTo(door === 'password' ? 'code' : 'password')}
        >
          {door === 'password'
            ? 'Sign in with a code instead'
            : 'Sign in with a password instead'}
        </Button>
      </Card>
    </div>
  )
}

/// The message inside a failed `functions.invoke`, which supabase-js hands back
/// as an unparsed `Response` on the error rather than as a message. Falls back
/// to a sentence of our own, because the alternative is "FunctionsHttpError".
async function invokeMessage(error: unknown): Promise<string> {
  const context = (error as { context?: unknown }).context
  if (context instanceof Response) {
    try {
      const body: unknown = await context.json()
      if (
        body &&
        typeof body === 'object' &&
        'error' in body &&
        typeof (body as { error: unknown }).error === 'string'
      ) {
        return (body as { error: string }).error
      }
    } catch {
      // Not JSON. Nothing to say that the fallback does not say better.
    }
  }
  return 'Could not ask for a code just now. Try again.'
}

/// Signed in, but not an admin. Deliberately a dead end with one way out — the
/// console does not explain what `platform_admins` is to someone who is not in it.
export function NotAdminPage({
  email,
  onSignOut,
  /// The check did not come back, rather than coming back "no". The console
  /// still shows nothing — it fails closed — but this is not a dead end, and a
  /// screen whose only control is Sign out reads as one.
  checkFailed,
  onRetry,
}: {
  email: string | null
  onSignOut: () => void
  checkFailed: boolean
  onRetry: () => Promise<void>
}) {
  const [busy, setBusy] = useState(false)

  return (
    <div className="flex min-h-full items-center justify-center p-6">
      <Card className="w-full max-w-md text-center">
        {checkFailed ? (
          <>
            <h1 className="text-xl font-bold text-ink">
              Could not check your access
            </h1>
            <p className="mt-2 text-sm text-ink-muted">
              The server did not answer, so the console stayed shut. That is a
              connection problem rather than a refusal — try again.
            </p>
            <Button
              className="mt-6 w-full"
              loading={busy}
              onClick={() => {
                setBusy(true)
                void onRetry().finally(() => setBusy(false))
              }}
            >
              Try again
            </Button>
            <Button
              variant="secondary"
              className="mt-2 w-full"
              onClick={onSignOut}
            >
              Sign out
            </Button>
          </>
        ) : (
          <>
            <h1 className="text-xl font-bold text-ink">
              This console is for Zopiqnow staff
            </h1>
            <p className="mt-2 text-sm text-ink-muted">
              {email ?? 'This account'} doesn&apos;t have access. If you run a
              restaurant on Zopiqnow, use the Zopiqnow Partner app instead.
            </p>
            <Button
              variant="secondary"
              className="mt-6 w-full"
              onClick={onSignOut}
            >
              Sign out
            </Button>
          </>
        )}
      </Card>
    </div>
  )
}
