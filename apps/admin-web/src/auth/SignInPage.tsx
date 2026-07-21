import { useState } from 'react'
import { supabase, messageFor } from '../lib/supabase'
import { Button, Card, Field } from '../ui/primitives'

/// Email OTP, the same door the vendor and rider apps use — a six-digit code to
/// an address, delivered by the SMTP sender already configured on the project.
///
/// An auth account is created on first sign-in for whoever asks, exactly as it is
/// for a vendor. It grants nothing: the console is gated on `platform_admins`,
/// and a session without a row there can read nothing and call nothing.
export function SignInPage() {
  const [email, setEmail] = useState('')
  const [code, setCode] = useState('')
  const [sent, setSent] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function sendCode() {
    setBusy(true)
    setError(null)
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim().toLowerCase(),
      options: { shouldCreateUser: true },
    })
    setBusy(false)
    if (error) {
      setError(messageFor(error))
      return
    }
    setSent(true)
  }

  async function verifyCode() {
    setBusy(true)
    setError(null)
    const { error } = await supabase.auth.verifyOtp({
      email: email.trim().toLowerCase(),
      token: code.trim(),
      type: 'email',
    })
    setBusy(false)
    if (error) {
      setError("That code didn't work. Please try again.")
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
            void (sent ? verifyCode() : sendCode())
          }}
        >
          <Field
            label="Email"
            type="email"
            required
            autoFocus={!sent}
            disabled={sent}
            placeholder="you@siteonlab.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />

          {sent && (
            <Field
              label="Six-digit code"
              inputMode="numeric"
              autoComplete="one-time-code"
              required
              autoFocus
              placeholder="123456"
              hint={`Sent to ${email.trim().toLowerCase()}.`}
              value={code}
              onChange={(e) => setCode(e.target.value)}
            />
          )}

          {error && <p className="text-sm text-non-veg">{error}</p>}

          <Button type="submit" loading={busy} className="w-full">
            {sent ? 'Verify and sign in' : 'Send code'}
          </Button>

          {sent && (
            <Button
              type="button"
              variant="ghost"
              className="w-full"
              onClick={() => {
                setSent(false)
                setCode('')
                setError(null)
              }}
            >
              Use a different email
            </Button>
          )}
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
