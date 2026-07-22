import type { ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import { useSession } from '../auth/session'

/// The frame every signed-in screen sits in. A fixed sidebar on desktop, a row of
/// tabs under the header on narrow windows — this is an ops tool used at a desk,
/// so the desktop layout is the one that gets the room.

const links = [
  { to: '/', label: 'Restaurants', end: true },
  { to: '/restaurants/new', label: 'Add restaurant', end: false },
  { to: '/riders', label: 'Riders', end: false },
  { to: '/settings', label: 'Settings', end: false },
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

        <nav className="flex gap-1 overflow-x-auto px-3 pb-3 md:flex-col md:pb-0">
          {links.map((l) => (
            <NavLink
              key={l.to}
              to={l.to}
              end={l.end}
              className={({ isActive }) =>
                `whitespace-nowrap rounded-[8px] px-3 py-2 text-sm font-medium transition-colors ${
                  isActive
                    ? 'bg-brand-soft text-brand-deep'
                    : 'text-ink-muted hover:bg-canvas hover:text-ink'
                }`
              }
            >
              {l.label}
            </NavLink>
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
