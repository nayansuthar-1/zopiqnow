import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import { useSession } from '../auth/context'
import { CommandPalette } from './CommandPalette'
import { currentLink, groups } from './nav'
import { Icon } from './primitives'

/// The frame every signed-in screen sits in. A fixed sidebar on desktop, a row
/// of tabs under the header on narrow windows — this is an ops tool used at a
/// desk, so the desktop layout is the one that gets the room.

const linkClass = ({ isActive }: { isActive: boolean }) =>
  `flex items-center gap-2.5 whitespace-nowrap rounded-field px-3 py-2 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-ink focus-visible:ring-offset-2 focus-visible:ring-offset-white ${
    isActive
      ? 'bg-brand-soft text-brand-ink'
      : 'text-ink-muted hover:bg-canvas hover:text-ink'
  }`

export function AppShell({ children }: { children: ReactNode }) {
  const { email, signOut } = useSession()
  const { pathname } = useLocation()
  // Closed on every navigation: below md this is a menu over the page, and a
  // menu that stays open after you have chosen from it is in the way.
  const [navOpen, setNavOpen] = useState(false)
  const here = currentLink(pathname)

  // The browser tab says which screen this is. With twenty of them and no tab
  // title, three console windows open side by side are three identical tabs.
  useEffect(() => {
    // Recomputed rather than closing over `here`, and keyed on the path: two
    // paths can share a link — every /restaurants/:id resolves to the
    // Restaurants entry — and the nav has to close on the navigation, not only
    // when the highlighted item changes.
    const link = currentLink(pathname)
    document.title = link ? `${link.label} · Zopiqnow Console` : 'Zopiqnow Console'
    setNavOpen(false)
  }, [pathname])

  return (
    <div className="flex min-h-full flex-col md:flex-row">
      {/* Ctrl-K, from anywhere in the console. Mounted here rather than per
          screen because the whole point of it is that you do not have to be on
          the right screen first. Renders nothing until it is opened. */}
      <CommandPalette />

      {/* Straight to the content, for anybody who does not want to tab through
          twenty nav links on every page. The first thing in the DOM, visible
          only once it has focus. */}
      <a
        href="#main"
        className="sr-only rounded-field bg-brand px-4 py-2 text-sm font-semibold text-ink focus:not-sr-only focus:absolute focus:top-3 focus:left-3 focus:z-50"
      >
        Skip to content
      </a>

      <aside className="shrink-0 border-b border-line bg-white md:sticky md:top-0 md:flex md:h-screen md:w-60 md:flex-col md:border-r md:border-b-0">
        <div className="flex items-center justify-between gap-3 px-5 py-4">
          <div>
            <span className="text-base font-bold text-ink">Zopiqnow</span>
            <span className="ml-1.5 text-base font-medium text-brand-ink">
              Console
            </span>
          </div>
          {/* The mobile sign-out. Until now the only one lived in a block marked
              `hidden md:block`, so on a phone or a narrow window there was no
              way to sign out of the console at all. */}
          <button
            className="rounded-field px-2 py-1 text-xs font-semibold text-brand-ink hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-ink md:hidden"
            onClick={() => void signOut()}
          >
            Sign out
          </button>
        </div>

        {/* Below md the nav was one horizontal strip of twenty links with the
            group headings hidden, so finding "Rider cash" meant scrubbing a
            scroller with no landmarks in it. As a disclosure the headings come
            back and the page starts where the page starts. */}
        <button
          type="button"
          aria-expanded={navOpen}
          aria-controls="console-nav"
          onClick={() => setNavOpen((o) => !o)}
          className="mx-3 mb-3 flex items-center justify-between rounded-field border border-line px-3 py-2 text-sm font-medium text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-ink md:hidden"
        >
          <span className="flex items-center gap-2.5">
            {here && <Icon name={here.icon} className="size-[18px]" />}
            {here?.label ?? 'Menu'}
          </span>
          <span aria-hidden="true" className="text-ink-muted">
            {navOpen ? '▲' : '▼'}
          </span>
        </button>

        <nav
          id="console-nav"
          aria-label="Console sections"
          className={`flex-col gap-0 px-3 pb-3 md:flex md:min-h-0 md:flex-1 md:overflow-y-auto md:pb-4 ${
            navOpen ? 'flex' : 'hidden'
          }`}
        >
          {groups.map((g) => (
            <div key={g.heading} className="mt-3 first:mt-0">
              <p className="px-3 pt-2 pb-1 text-xs font-semibold tracking-wide text-ink-muted uppercase">
                {g.heading}
              </p>
              {g.links.map((l) => (
                <NavLink key={l.to} to={l.to} end={l.end} className={linkClass}>
                  {/* The icon inherits the link's colour, so the active item's
                      glyph turns brand-ink with its label rather than needing a
                      second rule that could fall out of step. */}
                  <Icon name={l.icon} className="size-[18px]" />
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
            className="mt-1 rounded-xs text-xs font-semibold text-brand-ink hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-ink focus-visible:ring-offset-2"
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
  const box = useRef<HTMLDivElement>(null)
  const [lifted, setLifted] = useState(false)

  // How tall this header is, published to the document so anything sticking
  // underneath it knows where the window really begins. `DataTable` needs it to
  // cap its own height, and its height is not a constant: a header with a
  // subtitle is 87px and one without is 64px, and the subtitle on the live
  // board rewrites itself every fifteen seconds.
  useEffect(() => {
    const el = box.current
    if (!el) return
    const publish = () =>
      document.documentElement.style.setProperty(
        '--page-header-h',
        `${el.offsetHeight}px`,
      )
    publish()
    const ro = new ResizeObserver(publish)
    ro.observe(el)
    // Cleared on unmount rather than left behind, so a screen with no
    // PageHeader at all falls back to the default in the calc() rather than
    // inheriting the last screen's number.
    return () => {
      ro.disconnect()
      document.documentElement.style.removeProperty('--page-header-h')
    }
  }, [])

  // A 1px border was the only thing between this header and the page, so
  // content slid under it with nothing to say it had. The shadow appears the
  // moment anything has scrolled past, and only then — a page that fits its
  // window keeps the console flat, which is the look this app is held to.
  useEffect(() => {
    const onScroll = () => setLifted(window.scrollY > 2)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    // Sticky, because every list in this console is longer than the window and
    // the actions that belong to the page were scrolling away from it.
    <div
      ref={box}
      className={`sticky top-0 z-20 flex flex-wrap items-start justify-between gap-4 border-b border-line bg-white px-6 py-5 transition-shadow ${
        lifted ? 'shadow-card' : ''
      }`}
    >
      <div className="min-w-0">
        <h1 className="text-lg font-bold text-ink">{title}</h1>
        {subtitle && <p className="mt-0.5 text-sm text-ink-muted">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}
