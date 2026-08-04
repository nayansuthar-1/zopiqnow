import { useEffect } from 'react'
import type { ReactNode } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import { useSession } from '../auth/session'

/// The frame every signed-in screen sits in. A fixed sidebar on desktop, a row
/// of tabs under the header on narrow windows — this is an ops tool used at a
/// desk, so the desktop layout is the one that gets the room.

/// Grouped since B7, because eleven links in a row is a list nobody reads. The
/// headings are desktop-only — on a narrow window the nav is a horizontal
/// scroller and a heading in it would just be a chip that does nothing.
const groups: {
  heading: string
  links: { to: string; label: string; end: boolean }[]
}[] = [
  {
    heading: 'Today',
    links: [
      { to: '/', label: 'Live orders', end: true },
      { to: '/orders', label: 'All orders', end: false },
      // Under Today, not under Money: a complaint is worked the day it lands,
      // and it is the only screen here with somebody waiting on the other end.
      { to: '/support', label: 'Support', end: false },
      { to: '/analytics', label: 'Platform', end: false },
    ],
  },
  {
    heading: 'Catalogue',
    links: [
      { to: '/restaurants', label: 'Restaurants', end: true },
      { to: '/restaurants/new', label: 'Add restaurant', end: false },
      { to: '/riders', label: 'Riders', end: false },
      { to: '/users', label: 'People', end: false },
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
      { to: '/refunds', label: 'Refunds', end: false },
      { to: '/settlements', label: 'Restaurant settlements', end: false },
      { to: '/payouts', label: 'Rider payouts', end: false },
      { to: '/cash', label: 'Rider cash', end: false },
    ],
  },
  {
    heading: 'Console',
    links: [{ to: '/settings', label: 'Settings', end: false }],
  },
]

const linkClass = ({ isActive }: { isActive: boolean }) =>
  `block whitespace-nowrap rounded-[8px] px-3 py-2 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2 focus-visible:ring-offset-white ${
    isActive
      ? 'bg-brand-soft text-brand-deep'
      : 'text-ink-muted hover:bg-canvas hover:text-ink'
  }`

export function AppShell({ children }: { children: ReactNode }) {
  const { email, signOut } = useSession()
  const { pathname } = useLocation()

  // The browser tab says which screen this is. With eleven of them and no tab
  // title, three console windows open side by side are three identical tabs.
  useEffect(() => {
    const here = groups
      .flatMap((g) => g.links)
      .filter((l) => (l.end ? pathname === l.to : pathname.startsWith(l.to)))
      // The longest matching prefix wins, so /restaurants/new does not read as
      // /restaurants.
      .sort((a, b) => b.to.length - a.to.length)[0]
    document.title = here ? `${here.label} · Zopiqnow Console` : 'Zopiqnow Console'
  }, [pathname])

  return (
    <div className="flex min-h-full flex-col md:flex-row">
      {/* Straight to the content, for anybody who does not want to tab through
          eleven nav links on every page. The first thing in the DOM, visible
          only once it has focus. */}
      <a
        href="#main"
        className="sr-only rounded-[8px] bg-brand px-4 py-2 text-sm font-semibold text-white focus:not-sr-only focus:absolute focus:top-3 focus:left-3 focus:z-50"
      >
        Skip to content
      </a>

      <aside className="shrink-0 border-b border-line bg-white md:sticky md:top-0 md:flex md:h-screen md:w-60 md:flex-col md:border-r md:border-b-0">
        <div className="flex items-center justify-between gap-3 px-5 py-4">
          <div>
            <span className="text-base font-bold text-ink">Zopiqnow</span>
            <span className="ml-1.5 text-base font-medium text-brand">
              Console
            </span>
          </div>
          {/* The mobile sign-out. Until now the only one lived in a block marked
              `hidden md:block`, so on a phone or a narrow window there was no
              way to sign out of the console at all. */}
          <button
            className="rounded-[8px] px-2 py-1 text-xs font-semibold text-brand hover:text-brand-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand md:hidden"
            onClick={() => void signOut()}
          >
            Sign out
          </button>
        </div>

        <nav
          aria-label="Console sections"
          className="flex gap-1 overflow-x-auto px-3 pb-3 md:min-h-0 md:flex-1 md:flex-col md:gap-0 md:overflow-y-auto md:pb-4"
        >
          {groups.map((g) => (
            <div key={g.heading} className="contents md:mt-3 md:block md:first:mt-0">
              <p className="hidden px-3 pt-2 pb-1 text-xs font-semibold tracking-wide text-ink-muted uppercase md:block">
                {g.heading}
              </p>
              {g.links.map((l) => (
                <NavLink key={l.to} to={l.to} end={l.end} className={linkClass}>
                  {l.label}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>

        <div className="hidden shrink-0 border-t border-line px-5 py-4 md:block">
          <p className="truncate text-xs text-ink-muted" title={email ?? undefined}>
            {email}
          </p>
          <button
            className="mt-1 rounded-[4px] text-xs font-semibold text-brand hover:text-brand-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2"
            onClick={() => void signOut()}
          >
            Sign out
          </button>
        </div>
      </aside>

      <main id="main" className="min-w-0 flex-1">
        {children}
      </main>
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
    // Sticky, because every list in this console is longer than the window and
    // the actions that belong to the page were scrolling away from it.
    <div className="sticky top-0 z-20 flex flex-wrap items-start justify-between gap-4 border-b border-line bg-white px-6 py-5">
      <div className="min-w-0">
        <h1 className="text-lg font-bold text-ink">{title}</h1>
        {subtitle && <p className="mt-0.5 text-sm text-ink-muted">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}
