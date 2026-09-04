import type { IconName } from './icons'

/// The console's twenty screens, as a table.
///
/// Its own module rather than a corner of AppShell.tsx, because two files need
/// it now: the sidebar draws it, and App's route fallback asks it which screen
/// a pending chunk belongs to. A file that exports both components and plain
/// functions also breaks fast refresh, which is the lint rule that noticed.

/// Grouped since B7, because twenty links in a row is a list nobody reads. The
/// headings are desktop-only — on a narrow window the nav is a horizontal
/// scroller and a heading in it would just be a chip that does nothing.
export const groups: {
  heading: string
  links: { to: string; label: string; end: boolean; icon: IconName }[]
}[] = [
  {
    heading: 'Today',
    links: [
      { to: '/', label: 'Live orders', end: true, icon: 'cookingPot' },
      { to: '/orders', label: 'All orders', end: false, icon: 'receipt' },
      // Under Today, not under Money: a complaint is worked the day it lands,
      // and it is the only screen here with somebody waiting on the other end.
      { to: '/support', label: 'Support', end: false, icon: 'chat' },
      // Beside Support for the same reason Support is here: both are a person
      // reading something that went wrong. The difference is who noticed —
      // a customer complained, or the platform did (migration 0130).
      { to: '/alerts', label: 'Alerts', end: false, icon: 'warning' },
      // Beside the food queues: a gift order has nobody but this page to move
      // it, so it belongs where somebody looks every day.
      { to: '/gift-orders', label: 'Gift orders', end: false, icon: 'gift' },
      { to: '/analytics', label: 'Platform', end: false, icon: 'trendUp' },
    ],
  },
  {
    heading: 'Catalogue',
    links: [
      { to: '/restaurants', label: 'Restaurants', end: true, icon: 'storefront' },
      { to: '/restaurants/new', label: 'Add restaurant', end: false, icon: 'plus' },
      { to: '/riders', label: 'Riders', end: false, icon: 'moped' },
      { to: '/users', label: 'People', end: false, icon: 'user' },
      // Under Catalogue and not beside Gift orders, because that is what it is:
      // the second marketplace's products, edited the way restaurants are.
      // Read-only from 0022 until 0118.
      { to: '/gifts', label: 'Gift catalogue', end: false, icon: 'sparkle' },
    ],
  },
  {
    heading: 'Reach',
    links: [
      { to: '/hero', label: 'Home hero', end: false, icon: 'star' },
      { to: '/map-ads', label: 'Map ads', end: false, icon: 'mapPin' },
      { to: '/coupons', label: 'Coupons', end: false, icon: 'tag' },
      { to: '/broadcast', label: 'Send a notification', end: false, icon: 'bellRinging' },
    ],
  },
  {
    heading: 'Money',
    links: [
      { to: '/refunds', label: 'Refunds', end: false, icon: 'refresh' },
      {
        to: '/settlements',
        label: 'Restaurant settlements',
        end: false,
        icon: 'forkKnife',
      },
      { to: '/payouts', label: 'Rider payouts', end: false, icon: 'wallet' },
      { to: '/cash', label: 'Rider cash', end: false, icon: 'checkCircle' },
    ],
  },
  {
    heading: 'Console',
    links: [{ to: '/settings', label: 'Settings', end: false, icon: 'sliders' }],
  },
]


/// Which link the current path belongs to. The longest matching prefix wins,
/// so /restaurants/new does not read as /restaurants. Exported because App's
/// route fallback names the screen it is waiting for, and this is already the
/// answer to that question.
export function currentLink(pathname: string) {
  return groups
    .flatMap((g) => g.links)
    .filter((l) => (l.end ? pathname === l.to : pathname.startsWith(l.to)))
    .sort((a, b) => b.to.length - a.to.length)[0]
}
