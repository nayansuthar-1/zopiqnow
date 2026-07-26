import { useState } from 'react'
import { supabase, messageFor } from '../lib/supabase'
import { Button, Card, Field } from '../ui/primitives'

/// Email and password. Not the email OTP the vendor and rider apps use, and the
/// difference is deliberate in one way worth naming.
///
/// The OTP door called `signInWithOtp({ shouldCreateUser: true })`, which minted
/// an auth account for **any** address that asked for a code. That was safe —
/// authority is `platform_admins` (0026), and a session without a row there can
/// read nothing and call nothing — but it meant the console's front door created
/// users as a side effect of someone typing into it. This screen cannot create
/// anything: an admin exists because somebody made them one, or they do not.
///
/// There is no sign-up and no password reset here on purpose. Both would be a
/// way into an ops console that does not begin with an existing admin, which is
/// the same reason `platform_admins` has no self-service path.
export function SignInPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function signIn() {
    setBusy(true)
    setError(null)
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
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

  return (
    <div className="flex min-h-full items-center justify-center p-6">
      <Card className="w-full max-w-md">
        <h1 className="text-xl font-bold text-ink">Zopiqnow Console</h1>
        <p className="mt-1 text-sm text-ink-muted">
          Sign in with your Zopiqnow staff email.
        </p>

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

          {error && <p className="text-sm text-non-veg">{error}</p>}

          <Button type="submit" loading={busy} className="w-full">
            Sign in
          </Button>
        </form>
      </Card>
    </div>
  )
}

/// Signed in, but not an admin. Deliberately a dead end with one way out — the
/// console does not explain what `platform_admins` is to someone who is not in it.
export function NotAdminPage({ email, onSignOut }: { email: string | null; onSignOut: () => void }) {
  return (
    <div className="flex min-h-full items-center justify-center p-6">
      <Card className="w-full max-w-md text-center">
        <h1 className="text-xl font-bold text-ink">This console is for Zopiqnow staff</h1>
        <p className="mt-2 text-sm text-ink-muted">
          {email ?? 'This account'} doesn&apos;t have access. If you run a restaurant on
          Zopiqnow, use the Zopiqnow Partner app instead.
        </p>
        <Button variant="secondary" className="mt-6 w-full" onClick={onSignOut}>
          Sign out
        </Button>
      </Card>
    </div>
  )
}
