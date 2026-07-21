import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { useSession } from './auth/session'
import { NotAdminPage, SignInPage } from './auth/SignInPage'
import { AppShell, PageHeader } from './ui/AppShell'
import { RestaurantsPage } from './restaurants/RestaurantsPage'
import { WizardPage } from './restaurants/WizardPage'

/// Filled in by Phase 3 (the wizard) and Phase 7 (settings). Routed now so the
/// sidebar links and the list's Edit buttons are real from the start.
function Placeholder({ what }: { what: string }) {
  return (
    <>
      <PageHeader title={what} subtitle="Coming in the next phase." />
      <div className="p-6 text-sm text-ink-muted">Not built yet.</div>
    </>
  )
}

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

  return (
    <BrowserRouter>
      <AppShell>
        <Routes>
          <Route path="/" element={<RestaurantsPage />} />
          {/* Keyed so switching from an existing restaurant to /new remounts the
              wizard — otherwise React keeps the old form state and the new draft
              starts life pre-filled with someone else's restaurant. */}
          <Route path="/restaurants/new" element={<WizardPage key="new" />} />
          <Route path="/restaurants/:id" element={<WizardPage key="edit" />} />
          <Route path="/settings" element={<Placeholder what="Settings" />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </AppShell>
    </BrowserRouter>
  )
}
