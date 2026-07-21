import { useState } from 'react'
import { api } from '../../lib/api'
import type { RestaurantDetail } from '../../lib/api'
import { StepFrame } from './StepFrame'

/// Seven rows, one per weekday, matching `restaurant_hours` exactly: a day the
/// kitchen is shut is the *absence* of a row, not a row with zeroes in it.
///
/// A window whose closing time is earlier than its opening time runs past
/// midnight — 18:00 to 01:00 is a kitchen serving until 1am, filed under the day
/// it opened. Legal since migration 0036, and labelled here so it does not read
/// like a mistake.

const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

type Day = { open: boolean; opens: string; closes: string }

const shut: Day = { open: false, opens: '10:00', closes: '22:00' }

function initialDays(detail: RestaurantDetail | null): Day[] {
  const days: Day[] = Array.from({ length: 7 }, () => ({ ...shut }))
  for (const h of detail?.hours ?? []) {
    // day_of_week is ISO: 1 = Monday.
    days[h.day - 1] = { open: true, opens: h.opens.slice(0, 5), closes: h.closes.slice(0, 5) }
  }
  return days
}

export function HoursStep({
  id,
  detail,
  onSaved,
  onNext,
}: {
  id: string
  detail: RestaurantDetail | null
  onSaved: () => Promise<void>
  onNext: () => void
}) {
  const [days, setDays] = useState<Day[]>(() => initialDays(detail))
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function update(index: number, patch: Partial<Day>) {
    setDays((prev) => prev.map((d, i) => (i === index ? { ...d, ...patch } : d)))
    setError(null)
  }

  function copyToAll(index: number) {
    const source = days[index]
    setDays(() => Array.from({ length: 7 }, () => ({ ...source })))
    setError(null)
  }

  async function save() {
    const zeroLength = days.findIndex((d) => d.open && d.opens === d.closes)
    if (zeroLength !== -1) {
      // The one shape the database still refuses: it would be ambiguous between
      // "closed all day" and "open all day", and only the first of those has a
      // meaning here (no row at all).
      setError(`${dayNames[zeroLength]} opens and closes at the same time.`)
      return
    }

    setBusy(true)
    setError(null)
    try {
      await api.setHours(
        id,
        days
          .map((d, i) => ({ day: i + 1, opens: d.opens, closes: d.closes, open: d.open }))
          .filter((d) => d.open)
          .map(({ day, opens, closes }) => ({ day, opens, closes })),
      )
      await onSaved()
      onNext()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const allShut = days.every((d) => !d.open)

  return (
    <StepFrame
      title="Opening hours"
      description="When the kitchen takes orders. Outside these hours the app refuses the order, whatever the cart says."
      error={error}
      busy={busy}
      onSave={() => void save()}
    >
      <div className="divide-y divide-line">
        {days.map((day, i) => (
          <div key={dayNames[i]} className="flex flex-wrap items-center gap-3 py-3">
            <label className="flex w-32 shrink-0 items-center gap-2">
              <input
                type="checkbox"
                checked={day.open}
                onChange={(e) => update(i, { open: e.target.checked })}
                className="h-4 w-4 accent-brand"
              />
              <span
                className={`text-sm font-medium ${day.open ? 'text-ink' : 'text-ink-muted'}`}
              >
                {dayNames[i]}
              </span>
            </label>

            {day.open ? (
              <div className="flex flex-wrap items-center gap-2">
                <input
                  type="time"
                  value={day.opens}
                  onChange={(e) => update(i, { opens: e.target.value })}
                  className="h-9 rounded-[8px] border border-line bg-white px-2 text-sm outline-none focus:border-brand"
                />
                <span className="text-ink-muted">–</span>
                <input
                  type="time"
                  value={day.closes}
                  onChange={(e) => update(i, { closes: e.target.value })}
                  className="h-9 rounded-[8px] border border-line bg-white px-2 text-sm outline-none focus:border-brand"
                />
                {day.closes < day.opens && (
                  <span className="rounded-full bg-brand-soft px-2 py-0.5 text-xs font-medium text-brand-deep">
                    closes next day
                  </span>
                )}
                <button
                  type="button"
                  onClick={() => copyToAll(i)}
                  className="text-xs font-semibold text-brand hover:text-brand-deep"
                >
                  Copy to all days
                </button>
              </div>
            ) : (
              <span className="text-sm text-ink-muted">Closed</span>
            )}
          </div>
        ))}
      </div>

      {allShut && (
        <p className="rounded-[8px] bg-canvas px-4 py-3 text-sm text-ink-muted">
          With no days set, the kitchen counts as always open — and publishing is
          blocked until at least one day has hours.
        </p>
      )}
    </StepFrame>
  )
}
