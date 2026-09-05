import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import type { SearchHit, SearchKind } from '../lib/api'
import { groups } from './nav'
import { Icon, Spinner } from './primitives'
import type { IconName } from './icons'

/// One box that finds anything, on Ctrl-K (0157).
///
/// The console has four search boxes and had no search. Each one answers "is it
/// on this page", which is only useful to somebody who already knows which page
/// it is on. A phone number ringing in belongs to a customer, or to the rider
/// carrying their order, or to the restaurant that has not accepted it, and the
/// person answering does not know which until they have looked — so the four
/// boxes cost three wrong turns before the first useful one.
///
/// This asks the database instead, and the database asks every arm at once.
///
/// **It is also how you get around.** With the box empty it lists the twenty-two
/// screens; typing narrows them alongside the search results. Two things in one
/// dialog because they are one intent — "take me to the thing I am thinking
/// about" — and because a palette that only navigates is a menu with extra
/// steps.
///
/// Not built on `Modal`. That primitive focuses its panel rather than its first
/// control, deliberately, because its dialogs ask questions the reader did not.
/// This one is a text box the reader asked for, and it has to be typing into it
/// the instant it opens.

/// How long to sit on a keystroke before asking the database. Long enough that
/// typing an order id is one query rather than eight, short enough that it still
/// feels like the list is following along.
const DEBOUNCE_MS = 180

/// Where each kind of hit lives.
///
/// A rider and a person go to a list with the search already applied rather than
/// to a page of their own, because neither has one. That is the honest hand-off:
/// the roster filtered to one row is the closest thing to a rider's page that
/// exists today, and pretending otherwise would mean inventing a route with
/// nothing behind it.
function hrefFor(hit: SearchHit): string {
  switch (hit.kind) {
    case 'order':
      return `/orders/${hit.id}`
    case 'restaurant':
      return `/restaurants/${hit.id}`
    case 'rider':
      return `/riders?q=${encodeURIComponent(hit.id)}`
    case 'customer':
      return `/users?q=${encodeURIComponent(hit.id)}`
  }
}

const kindLabel: Record<SearchKind, string> = {
  order: 'Order',
  restaurant: 'Restaurant',
  rider: 'Rider',
  customer: 'Person',
}

const kindIcon: Record<SearchKind, IconName> = {
  order: 'receipt',
  restaurant: 'storefront',
  rider: 'moped',
  customer: 'user',
}

/// A row in the list, whichever half it came from. Flattened to one array so the
/// arrow keys do not have to know there are two halves.
type Row = {
  key: string
  href: string
  icon: IconName
  label: string
  hint: string
  detail: string
  group: string
}

export function CommandPalette() {
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [hits, setHits] = useState<SearchHit[]>([])
  const [searching, setSearching] = useState(false)
  const [cursor, setCursor] = useState(0)
  const input = useRef<HTMLInputElement>(null)
  const listId = useId()

  // Ctrl-K, or Cmd-K on a Mac. Captured on the document so it works wherever the
  // keyboard happens to be — including inside another screen's search box, which
  // is exactly where somebody realises they are on the wrong screen.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setOpen((was) => !was)
      }
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [])

  // Reset on open rather than on close, so the dialog never animates its own
  // contents away as it goes.
  useEffect(() => {
    if (!open) return
    setQuery('')
    setHits([])
    setCursor(0)
    input.current?.focus()
    const { overflow } = document.body.style
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = overflow
    }
  }, [open])

  useEffect(() => {
    const q = query.trim()
    // The database returns nothing under two characters; asking anyway would be
    // a round trip to be told so.
    if (q.length < 2) {
      setHits([])
      setSearching(false)
      return
    }
    setSearching(true)
    let cancelled = false
    const timer = setTimeout(() => {
      api
        .search(q)
        .then((found) => {
          if (cancelled) return
          setHits(found)
          setCursor(0)
        })
        // A failed search is an empty one. There is no room in a palette for an
        // error banner, and the screens themselves all report their own.
        .catch(() => {
          if (!cancelled) setHits([])
        })
        .finally(() => {
          if (!cancelled) setSearching(false)
        })
    }, DEBOUNCE_MS)
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [query])

  const rows = useMemo<Row[]>(() => {
    const q = query.trim().toLowerCase()

    const found: Row[] = hits.map((h) => ({
      key: `${h.kind}:${h.id}`,
      href: hrefFor(h),
      icon: kindIcon[h.kind],
      label: h.title,
      hint: h.subtitle ?? '',
      detail: h.detail ?? '',
      group: kindLabel[h.kind],
    }))

    const screens: Row[] = groups
      .flatMap((g) => g.links.map((l) => ({ ...l, heading: g.heading })))
      .filter((l) => q === '' || l.label.toLowerCase().includes(q))
      .map((l) => ({
        key: `screen:${l.to}`,
        href: l.to,
        icon: l.icon,
        label: l.label,
        hint: '',
        detail: l.heading,
        group: 'Go to',
      }))

    return [...found, ...screens]
  }, [hits, query])

  // The list shrinks as the query narrows, and the highlight has to come back
  // inside it. Without this, typing one character too many leaves the cursor
  // past the end and Enter opens nothing at all.
  useEffect(() => {
    setCursor((c) => Math.min(c, Math.max(0, rows.length - 1)))
  }, [rows.length])

  const go = useCallback(
    (row: Row | undefined) => {
      if (!row) return
      setOpen(false)
      navigate(row.href)
    },
    [navigate],
  )

  if (!open) return null

  // Grouped for the eye, flat for the keyboard: the headings are drawn as the
  // list is walked, so the index the arrow keys move through is the index the
  // rows are rendered in.
  let lastGroup = ''

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center bg-ink/40 p-4 pt-[10vh]"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) setOpen(false)
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Search Zopiqnow"
        className="w-full max-w-xl overflow-hidden rounded-card bg-white shadow-modal"
      >
        <div className="flex items-center gap-3 border-b border-line px-4">
          <Icon name="search" className="size-5 shrink-0 text-ink-muted" />
          <input
            ref={input}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Escape') {
                e.preventDefault()
                setOpen(false)
              } else if (e.key === 'ArrowDown') {
                e.preventDefault()
                setCursor((c) => Math.min(c + 1, rows.length - 1))
              } else if (e.key === 'ArrowUp') {
                e.preventDefault()
                setCursor((c) => Math.max(c - 1, 0))
              } else if (e.key === 'Enter') {
                e.preventDefault()
                go(rows[cursor])
              }
            }}
            role="combobox"
            aria-expanded
            aria-controls={listId}
            aria-autocomplete="list"
            aria-activedescendant={
              rows[cursor] ? `${listId}-${cursor}` : undefined
            }
            placeholder="Order id, phone, email, name — or a screen"
            aria-label="Search Zopiqnow"
            className="h-14 flex-1 bg-transparent text-base text-ink outline-none placeholder:text-ink-muted"
          />
          {searching && <Spinner className="shrink-0 text-ink-muted" />}
        </div>

        <ul id={listId} role="listbox" className="max-h-[50vh] overflow-y-auto py-2">
          {rows.length === 0 ? (
            <li className="px-4 py-6 text-center text-sm text-ink-muted">
              {query.trim().length < 2
                ? 'Type at least two characters.'
                : searching
                  ? 'Looking…'
                  : 'Nothing matches that.'}
            </li>
          ) : (
            rows.map((row, i) => {
              const heading = row.group !== lastGroup ? row.group : null
              lastGroup = row.group
              return (
                <li key={row.key}>
                  {heading && (
                    <p className="px-4 pt-3 pb-1 text-xs font-semibold tracking-wide text-ink-muted uppercase">
                      {heading}
                    </p>
                  )}
                  <button
                    type="button"
                    id={`${listId}-${i}`}
                    role="option"
                    aria-selected={i === cursor}
                    // Pointer, not click: the row under the cursor and the row
                    // the arrow keys are on have to be the same row, or Enter
                    // opens something other than what is highlighted.
                    onMouseMove={() => setCursor(i)}
                    onClick={() => go(row)}
                    className={`flex w-full items-center gap-3 px-4 py-2.5 text-left ${
                      i === cursor ? 'bg-brand-soft' : ''
                    }`}
                  >
                    <Icon
                      name={row.icon}
                      className={`size-5 shrink-0 ${i === cursor ? 'text-brand-ink' : 'text-ink-muted'}`}
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium text-ink">
                        {row.label}
                      </span>
                      {row.hint && (
                        <span className="block truncate text-xs text-ink-muted">
                          {row.hint}
                        </span>
                      )}
                    </span>
                    {row.detail && (
                      <span className="shrink-0 text-xs text-ink-muted">
                        {row.detail}
                      </span>
                    )}
                  </button>
                </li>
              )
            })
          )}
        </ul>
      </div>
    </div>
  )
}
