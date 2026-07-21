import { useSession } from './auth/session'
import { NotAdminPage, SignInPage } from './auth/SignInPage'
import { Card } from './ui/primitives'

export default function App() {
  const { loading, session, isAdmin, email, signOut } = useSession()

  if (loading) {
    return (
      <div className="flex min-h-full items-center justify-center">
        <p className="text-sm text-ink-muted">Loading…</p>
      </div>
    )
  }

  if (!session) return <SignInPage />
  if (!isAdmin) return <NotAdminPage email={email} onSignOut={() => void signOut()} />

  // Phase 2 replaces this with the console shell and the restaurant list.
  return (
    <div className="mx-auto max-w-3xl p-6">
      <Card>
        <h1 className="text-xl font-bold text-ink">Zopiqnow Console</h1>
        <p className="mt-1 text-sm text-ink-muted">Signed in as {email}.</p>
        <button
          className="mt-4 text-sm font-semibold text-brand hover:text-brand-deep"
          onClick={() => void signOut()}
        >
          Sign out
        </button>
      </Card>
    </div>
  )
}
