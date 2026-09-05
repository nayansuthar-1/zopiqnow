import { lazy, Suspense } from 'react'
import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { useSession } from './auth/context'
import { NotAdminPage, SignInPage } from './auth/SignInPage'
import { AppShell, PageHeader } from './ui/AppShell'
import { currentLink } from './ui/nav'
import { CardSkeleton, PageBody } from './ui/primitives'
import { RouteBoundary } from './ui/RouteBoundary'
import { ToastHost } from './ui/ToastHost'

/// The live board is the landing screen, so it is not a chunk. Everything the
/// console needs to draw `/` — the shell, the primitives, the board — is in the
/// first download; anything else is fetched when somebody asks for it.
import { LiveOrdersPage } from './orders/LiveOrdersPage'

/// The other twenty screens, one chunk each.
///
/// The console shipped as a single 706 kB file, which meant an admin opening
/// the live board to see whether an order had been picked up also downloaded
/// the onboarding wizard, the menu importer, the image adjuster and the map
/// picker — none of which that person is going to touch today. Route-level, not
/// component-level, because the route is the only boundary here that matches
/// how the app is actually used: nobody visits half a screen.
///
/// `lazy` wants a default export and every screen here is a named one, so each
/// line maps the name across. Written out rather than folded into a helper: a
/// generic one would have to type the whole module as components-only, which
/// is false the moment a screen also exports a constant, and `import()` calls
/// have to be statically visible for the bundler to make a chunk out of them.

const AllOrdersPage = lazy(() =>
  import('./orders/AllOrdersPage').then((m) => ({ default: m.AllOrdersPage })),
)
const OrderDetailPage = lazy(() =>
  import('./orders/OrderDetailPage').then((m) => ({ default: m.OrderDetailPage })),
)
const RestaurantsPage = lazy(() =>
  import('./restaurants/RestaurantsPage').then((m) => ({ default: m.RestaurantsPage })),
)
const WizardPage = lazy(() =>
  import('./restaurants/WizardPage').then((m) => ({ default: m.WizardPage })),
)
const RidersPage = lazy(() =>
  import('./riders/RidersPage').then((m) => ({ default: m.RidersPage })),
)
const UsersPage = lazy(() =>
  import('./users/UsersPage').then((m) => ({ default: m.UsersPage })),
)
const HeroSlidesPage = lazy(() =>
  import('./content/HeroSlidesPage').then((m) => ({ default: m.HeroSlidesPage })),
)
const OrderAdsPage = lazy(() =>
  import('./content/OrderAdsPage').then((m) => ({ default: m.OrderAdsPage })),
)
const CouponsPage = lazy(() =>
  import('./coupons/CouponsPage').then((m) => ({ default: m.CouponsPage })),
)
const BroadcastPage = lazy(() =>
  import('./broadcast/BroadcastPage').then((m) => ({ default: m.BroadcastPage })),
)
const AnalyticsPage = lazy(() =>
  import('./analytics/AnalyticsPage').then((m) => ({ default: m.AnalyticsPage })),
)
const SettlementsPage = lazy(() =>
  import('./settlements/SettlementsPage').then((m) => ({ default: m.SettlementsPage })),
)
const PayoutsPage = lazy(() =>
  import('./payouts/PayoutsPage').then((m) => ({ default: m.PayoutsPage })),
)
const CashPage = lazy(() =>
  import('./payouts/CashPage').then((m) => ({ default: m.CashPage })),
)
const RefundsPage = lazy(() =>
  import('./payouts/RefundsPage').then((m) => ({ default: m.RefundsPage })),
)
const SupportPage = lazy(() =>
  import('./support/SupportPage').then((m) => ({ default: m.SupportPage })),
)
const AlertsPage = lazy(() =>
  import('./alerts/AlertsPage').then((m) => ({ default: m.AlertsPage })),
)
const GiftOrdersPage = lazy(() =>
  import('./gifts/GiftOrdersPage').then((m) => ({ default: m.GiftOrdersPage })),
)
const GiftCataloguePage = lazy(() =>
  import('./gifts/GiftCataloguePage').then((m) => ({ default: m.GiftCataloguePage })),
)
const SettingsPage = lazy(() =>
  import('./settings/SettingsPage').then((m) => ({ default: m.SettingsPage })),
)
const ServiceAreasPage = lazy(() =>
  import('./settings/ServiceAreasPage').then((m) => ({
    default: m.ServiceAreasPage,
  })),
)
const PlatformSettingsPage = lazy(() =>
  import('./settings/PlatformSettingsPage').then((m) => ({
    default: m.PlatformSettingsPage,
  })),
)

/// What a route looks like while its chunk is in the air.
///
/// The console's own frame, with the real screen name already in it — the nav
/// knows where you clicked, so the header does not have to wait for the chunk
/// to find out. A bare spinner would blank the page between two screens that
/// both have a sticky header, and the jump back is more noticeable than the
/// wait itself. What arrives next is the screen drawing its own skeleton while
/// it queries, so this reads as one continuous load rather than two.
function RouteFallback() {
  const { pathname } = useLocation()
  return (
    <>
      <PageHeader title={currentLink(pathname)?.label ?? ''} />
      <PageBody>
        <CardSkeleton rows={3} />
      </PageBody>
    </>
  )
}

export default function App() {
  const { loading, session, isAdmin, email, signOut, checkFailed, recheck } =
    useSession()

  if (loading) {
    return (
      <div className="flex min-h-full items-center justify-center">
        <p className="text-sm text-ink-muted">Loading…</p>
      </div>
    )
  }

  if (!session) return <SignInPage />
  if (!isAdmin) {
    return (
      <NotAdminPage
        email={email}
        onSignOut={() => void signOut()}
        checkFailed={checkFailed}
        onRetry={recheck}
      />
    )
  }

  return (
    <BrowserRouter>
      {/* Outside AppShell, so a confirmation survives the screen that raised it
          unmounting — the usual shape here is "act, then navigate away". */}
      <ToastHost>
        <AppShell>
          <ConsoleRoutes />
        </AppShell>
      </ToastHost>
    </BrowserRouter>
  )
}

function ConsoleRoutes() {
  const { pathname } = useLocation()

  return (
    <RouteBoundary resetKey={pathname}>
      <Suspense fallback={<RouteFallback />}>
        <Routes>
          {/* The floor, not the filing cabinet. Onboarding a restaurant is a
              thing somebody does once; an order going wrong is happening now,
              so B7 moved the landing screen to the live board and left
              Restaurants where it was, one click away. */}
          <Route path="/" element={<LiveOrdersPage />} />
          <Route path="/orders" element={<AllOrdersPage />} />
          {/* One order, on one page (0154). */}
          <Route path="/orders/:id" element={<OrderDetailPage />} />
          <Route path="/restaurants" element={<RestaurantsPage />} />
          {/* Keyed so switching from an existing restaurant to /new remounts the
              wizard — otherwise React keeps the old form state and the new draft
              starts life pre-filled with someone else's restaurant. */}
          <Route path="/restaurants/new" element={<WizardPage key="new" />} />
          <Route path="/restaurants/:id" element={<WizardPage key="edit" />} />
          <Route path="/riders" element={<RidersPage />} />
          <Route path="/users" element={<UsersPage />} />
          <Route path="/hero" element={<HeroSlidesPage />} />
          <Route path="/map-ads" element={<OrderAdsPage />} />
          <Route path="/coupons" element={<CouponsPage />} />
          <Route path="/broadcast" element={<BroadcastPage />} />
          <Route path="/analytics" element={<AnalyticsPage />} />
          <Route path="/settlements" element={<SettlementsPage />} />
          <Route path="/payouts" element={<PayoutsPage />} />
          <Route path="/cash" element={<CashPage />} />
          <Route path="/refunds" element={<RefundsPage />} />
          <Route path="/support" element={<SupportPage />} />
          <Route path="/alerts" element={<AlertsPage />} />
          <Route path="/gift-orders" element={<GiftOrdersPage />} />
          <Route path="/gifts" element={<GiftCataloguePage />} />
          <Route path="/settings" element={<SettingsPage />} />
          {/* The knobs (0159). Under /settings so the nav's longest-prefix
              match keeps the Console group highlighted on all three. */}
          <Route path="/settings/areas" element={<ServiceAreasPage />} />
          <Route path="/settings/platform" element={<PlatformSettingsPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </RouteBoundary>
  )
}
