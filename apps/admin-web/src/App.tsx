import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { useSession } from './auth/session'
import { NotAdminPage, SignInPage } from './auth/SignInPage'
import { AppShell } from './ui/AppShell'
import { RestaurantsPage } from './restaurants/RestaurantsPage'
import { WizardPage } from './restaurants/WizardPage'
import { RidersPage } from './riders/RidersPage'
import { UsersPage } from './users/UsersPage'
import { HeroSlidesPage } from './content/HeroSlidesPage'
import { PayoutsPage } from './payouts/PayoutsPage'
import { CashPage } from './payouts/CashPage'
import { RefundsPage } from './payouts/RefundsPage'
import { GiftOrdersPage } from './gifts/GiftOrdersPage'
import { SupportPage } from './support/SupportPage'
import { SettingsPage } from './settings/SettingsPage'
import { AllOrdersPage } from './orders/AllOrdersPage'
import { LiveOrdersPage } from './orders/LiveOrdersPage'
import { AnalyticsPage } from './analytics/AnalyticsPage'
import { CouponsPage } from './coupons/CouponsPage'
import { BroadcastPage } from './broadcast/BroadcastPage'
import { SettlementsPage } from './settlements/SettlementsPage'

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
          {/* The floor, not the filing cabinet. Onboarding a restaurant is a
              thing somebody does once; an order going wrong is happening now,
              so B7 moved the landing screen to the live board and left
              Restaurants where it was, one click away. */}
          <Route path="/" element={<LiveOrdersPage />} />
          <Route path="/orders" element={<AllOrdersPage />} />
          <Route path="/restaurants" element={<RestaurantsPage />} />
          {/* Keyed so switching from an existing restaurant to /new remounts the
              wizard — otherwise React keeps the old form state and the new draft
              starts life pre-filled with someone else's restaurant. */}
          <Route path="/restaurants/new" element={<WizardPage key="new" />} />
          <Route path="/restaurants/:id" element={<WizardPage key="edit" />} />
          <Route path="/riders" element={<RidersPage />} />
          <Route path="/users" element={<UsersPage />} />
          <Route path="/hero" element={<HeroSlidesPage />} />
          <Route path="/coupons" element={<CouponsPage />} />
          <Route path="/broadcast" element={<BroadcastPage />} />
          <Route path="/analytics" element={<AnalyticsPage />} />
          <Route path="/settlements" element={<SettlementsPage />} />
          <Route path="/payouts" element={<PayoutsPage />} />
          <Route path="/cash" element={<CashPage />} />
          <Route path="/refunds" element={<RefundsPage />} />
          <Route path="/support" element={<SupportPage />} />
          <Route path="/gift-orders" element={<GiftOrdersPage />} />
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </AppShell>
    </BrowserRouter>
  )
}
