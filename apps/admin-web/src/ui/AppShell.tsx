import type { ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import { useSession } from '../auth/session'

/// The frame every signed-in screen sits in. A fixed sidebar on desktop, a row of
/// tabs under the header on narrow windows — this is an ops tool used at a desk,
/// so the desktop layout is the one that gets the room.

/// Grouped since B7, because eleven links in a row is a list nobody reads. The
/// headings are desktop-only — on a narrow window the nav is a horizontal
/// scroller and a heading in it would just be a chip that does nothing.
const groups: { heading: string; links: { to: string; label: string; end: boolean }[] }[] = [
  {
    heading: 'Today',
    links: [
      { to: '/', label: 'Live orders', end: true },
      { to: '/analytics', label: 'Platform', end: false },
    ],
  },
  {
    heading: 'Catalogue',
    links: [
      { to: '/restaurants', label: 'Restaurants', end: true },
      { to: '/restaurants/new', label: 'Add restaurant', end: false },
      { to: '/riders', label: 'Riders', end: false },
    ],
  },
  {
    heading: 'Reach',
    links: [
      { to: '/hero', label: 'Home hero', end: false },
      { to: '/coupons', label: 'Coupons', end: false },
      { to: '/broadcast', label: 'Send a notification', end: false },
    ],
  },
  {
    heading: 'Money',
    links: [
      { to: '/settlements', label: 'Restaurant settlements', end: false },
      { to: '/payouts', label: 'Rider payouts', end: false },
    ],
  },
  {
    heading: 'Console',
    links: [{ to: '/settings', label: 'Settings', end: false }],
  },
]

export function AppShell({ children }: { children: ReactNode }) {
  const { email, signOut } = useSession()

  return (
    <div className="flex min-h-full flex-col md:flex-row">
      <aside className="shrink-0 border-b border-line bg-white md:w-60 md:border-r md:border-b-0">
        <div className="flex items-center justify-between px-5 py-4 md:block">
          <div>
            <span className="text-base font-bold text-ink">Zopiqnow</span>
            <span className="ml-1.5 text-base font-medium text-brand">Console</span>
          </div>
        </div>

        <nav className="flex gap-1 overflow-x-auto px-3 pb-3 md:flex-col md:gap-0 md:pb-4">
          {groups.map((g) => (
            <div key={g.heading} className="contents md:block md:mt-3 md:first:mt-0">
              <p className="hidden px-3 pt-2 pb-1 text-xs font-semibold tracking-wide text-ink-muted uppercase md:block">
                {g.heading}
              </p>
              {g.links.map((l) => (
                <NavLink
                  key={l.to}
                  to={l.to}
                  end={l.end}
                  className={({ isActive }) =>
                    `block whitespace-nowrap rounded-[8px] px-3 py-2 text-sm font-medium transition-colors ${
                      isActive
                        ? 'bg-brand-soft text-brand-deep'
                        : 'text-ink-muted hover:bg-canvas hover:text-ink'
                    }`
                  }
                >
                  {l.label}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>

        <div className="hidden border-t border-line px-5 py-4 md:block">
          <p className="truncate text-xs text-ink-muted" title={email ?? undefined}>
            {email}
          </p>
          <button
            className="mt-1 text-xs font-semibold text-brand hover:text-brand-deep"
            onClick={() => void signOut()}
          >
            Sign out
          </button>
        </div>
      </aside>

      <main className="min-w-0 flex-1">{children}</main>
    </div>
  )
}

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string
  subtitle?: string
  action?: ReactNode
}) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-4 border-b border-line bg-white px-6 py-5">
      <div>
        <h1 className="text-lg font-bold text-ink">{title}</h1>
        {subtitle && <p className="mt-0.5 text-sm text-ink-muted">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}
