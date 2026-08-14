import { useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { MenuItemRow, OptionGroup } from '../lib/api'
import { Banner, Button, Modal, SegmentedControl, Spinner } from '../ui/primitives'

/// Every question one dish asks before it can be ordered: its sizes and add-ons.
///
/// This lives in its own dialog rather than inside the Add/Edit one, and that is
/// the whole lesson of the first attempt (0106, removed in 544cf99). The write
/// RPC **replaces all** of a dish's groups, so a dialog that also edits a dish's
/// name has to send groups on every save — and the day a read fails, or a dish is
/// added before it has an id, "no groups" and "leave the groups alone" become the
/// same payload. Here the two cannot be confused: opening this dialog is the only
/// thing that reads groups, and saving it is the only thing that writes them.
///
/// A size is not a special kind of thing (0048). It is a group whose options
/// carry a price delta, and `min_select`/`max_select` are the entire behaviour.
/// So "500 g / 1 kg" and "extra cheese" are the same editor.

/// What a group asks of the customer. The three shapes a menu actually uses,
/// each of which is just a (min, max) pair underneath.
type Kind = 'required' | 'optional' | 'addons'

type DraftOption = { key: number; name: string; delta: string; available: boolean }
type DraftGroup = {
  key: number
  name: string
  kind: Kind
  /// Only read when `kind` is 'addons'. Kept as text so a half-typed number does
  /// not collapse to 0 under the cursor.
  min: string
  max: string
  options: DraftOption[]
}

let keySeed = 0
const nextKey = () => ++keySeed

function kindOf(g: OptionGroup): Kind {
  if (g.max_select === 1) return g.min_select >= 1 ? 'required' : 'optional'
  return 'addons'
}

function toDraft(g: OptionGroup): DraftGroup {
  return {
    key: nextKey(),
    name: g.name,
    kind: kindOf(g),
    min: String(g.min_select),
    max: String(g.max_select),
    options: (g.options ?? []).map((o) => ({
      key: nextKey(),
      name: o.name,
      delta: String(o.price_delta),
      available: o.is_available ?? true,
    })),
  }
}

/// Draft → the RPC's shape. Ranks are the on-screen order, which is the only
/// order anybody has expressed.
function toGroup(g: DraftGroup, rank: number): OptionGroup {
  const min = g.kind === 'required' ? 1 : g.kind === 'optional' ? 0 : Number(g.min || 0)
  const max = g.kind === 'addons' ? Number(g.max || 1) : 1
  return {
    name: g.name.trim(),
    min_select: min,
    max_select: max,
    rank,
    options: g.options.map((o, i) => ({
      name: o.name.trim(),
      price_delta: Math.round(Number(o.delta || 0)),
      is_available: o.available,
      rank: i,
    })),
  }
}

export function OptionsDialog({
  item,
  onClose,
  onSaved,
}: {
  item: MenuItemRow
  onClose: () => void
  onSaved: () => void
}) {
  /// Null until the read lands or fails. Nothing can be saved from null, which is
  /// what keeps a failed read from being written back as "this dish has none".
  const [groups, setGroups] = useState<DraftGroup[] | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [reloads, setReloads] = useState(0)

  useEffect(() => {
    let cancelled = false
    setGroups(null)
    setLoadError(null)
    api
      .menuItemOptions(item.id)
      .then((rows) => {
        if (!cancelled) setGroups((rows ?? []).map(toDraft))
      })
      .catch((e: unknown) => {
        if (!cancelled) {
          setLoadError(e instanceof Error ? e.message : String(e))
        }
      })
    return () => {
      cancelled = true
    }
  }, [item.id, reloads])

  function patch(i: number, next: Partial<DraftGroup>) {
    setGroups((gs) => gs && gs.map((g, j) => (j === i ? { ...g, ...next } : g)))
  }

  function patchOption(i: number, j: number, next: Partial<DraftOption>) {
    setGroups(
      (gs) =>
        gs &&
        gs.map((g, gi) =>
          gi === i
            ? { ...g, options: g.options.map((o, oj) => (oj === j ? { ...o, ...next } : o)) }
            : g,
        ),
    )
  }

  async function save() {
    if (!groups) return
    for (const g of groups) {
      if (!g.name.trim()) return setSaveError('Every group needs a name.')
      if (g.options.length === 0) {
        return setSaveError(`"${g.name.trim()}" has no options — a question with no answers.`)
      }
      if (g.options.some((o) => !o.name.trim())) {
        return setSaveError(`Every option in "${g.name.trim()}" needs a name.`)
      }
      if (g.options.some((o) => !Number.isFinite(Number(o.delta)) || Number(o.delta) < 0)) {
        // The base price is the cheapest configuration, so an option can only add.
        // A cheaper size means lowering the dish's own price and charging the
        // larger one the difference.
        return setSaveError(
          `An option can only add to the price. Make the cheapest one ₹0 and lower ${item.name}'s price instead.`,
        )
      }
      if (g.kind === 'addons') {
        const min = Number(g.min || 0)
        const max = Number(g.max || 0)
        if (!Number.isInteger(min) || !Number.isInteger(max) || max < 1 || min < 0 || max < min) {
          return setSaveError(`"${g.name.trim()}" asks for an impossible number of picks.`)
        }
      }
    }

    setSaving(true)
    setSaveError(null)
    try {
      await api.setMenuItemOptions(item.id, groups.map(toGroup))
      onSaved()
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : String(e))
      setSaving(false)
    }
  }

  return (
    <Modal
      title={`Options · ${item.name}`}
      size="lg"
      busy={saving}
      onClose={onClose}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={() => void save()} loading={saving} disabled={!groups}>
            Save options
          </Button>
        </>
      }
    >
      <p className="text-sm text-ink-muted">
        This dish costs ₹{item.price}. Every option adds to that — a 500 g cake at
        ₹{item.price} with a 1 kg option at +₹{item.price} sells for ₹{item.price * 2}.
      </p>

      {saveError && (
        <Banner tone="error" className="mt-4" onDismiss={() => setSaveError(null)}>
          {saveError}
        </Banner>
      )}

      {loadError ? (
        <div className="mt-6 rounded-[8px] border border-line p-6 text-center">
          <p className="text-sm text-ink">We couldn’t read this dish’s options.</p>
          <p className="mt-1 text-sm text-ink-muted">
            Nothing has been changed. {loadError}
          </p>
          <Button
            variant="secondary"
            className="mt-4"
            onClick={() => setReloads((n) => n + 1)}
          >
            Try again
          </Button>
        </div>
      ) : !groups ? (
        <div className="mt-6 flex justify-center py-8">
          <Spinner />
        </div>
      ) : (
        <div className="mt-5 space-y-4">
          {groups.length === 0 && (
            <p className="rounded-[8px] border border-dashed border-line px-4 py-6 text-center text-sm text-ink-muted">
              This dish asks nothing before it is ordered. Add a group to give it
              sizes or add-ons.
            </p>
          )}

          {groups.map((g, i) => (
            <div key={g.key} className="rounded-[8px] border border-line p-4">
              <div className="flex items-center gap-2">
                <input
                  value={g.name}
                  placeholder="Choose a size"
                  onChange={(e) => patch(i, { name: e.target.value })}
                  className="h-10 flex-1 rounded-[8px] border border-line bg-white px-3 text-sm font-medium text-ink outline-none focus:border-brand"
                  aria-label="Group name"
                />
                <button
                  type="button"
                  onClick={() => setGroups((gs) => gs && gs.filter((_, j) => j !== i))}
                  className="shrink-0 text-sm font-medium text-ink-muted hover:text-non-veg"
                >
                  Remove group
                </button>
              </div>

              <div className="mt-3">
                <SegmentedControl<Kind>
                  label="How many the customer picks"
                  value={g.kind}
                  onChange={(kind) => patch(i, { kind })}
                  options={[
                    { value: 'required', label: 'Must pick one' },
                    { value: 'optional', label: 'May pick one' },
                    { value: 'addons', label: 'Add-ons' },
                  ]}
                />
              </div>

              {g.kind === 'addons' && (
                <div className="mt-3 flex items-center gap-2 text-sm text-ink-muted">
                  <span>Pick at least</span>
                  <input
                    value={g.min}
                    inputMode="numeric"
                    onChange={(e) => patch(i, { min: e.target.value })}
                    className="h-9 w-16 rounded-[8px] border border-line bg-white px-2 text-center text-sm text-ink outline-none focus:border-brand"
                    aria-label="Minimum picks"
                  />
                  <span>and up to</span>
                  <input
                    value={g.max}
                    inputMode="numeric"
                    onChange={(e) => patch(i, { max: e.target.value })}
                    className="h-9 w-16 rounded-[8px] border border-line bg-white px-2 text-center text-sm text-ink outline-none focus:border-brand"
                    aria-label="Maximum picks"
                  />
                </div>
              )}

              <div className="mt-3 space-y-2">
                {g.options.map((o, j) => (
                  <div key={o.key} className="flex items-center gap-2">
                    <input
                      value={o.name}
                      placeholder="500 g"
                      onChange={(e) => patchOption(i, j, { name: e.target.value })}
                      className="h-10 flex-1 rounded-[8px] border border-line bg-white px-3 text-sm text-ink outline-none focus:border-brand"
                      aria-label="Option name"
                    />
                    <span className="text-sm text-ink-muted">+₹</span>
                    <input
                      value={o.delta}
                      inputMode="numeric"
                      onChange={(e) => patchOption(i, j, { delta: e.target.value })}
                      className="h-10 w-24 rounded-[8px] border border-line bg-white px-3 text-sm tabular-nums text-ink outline-none focus:border-brand"
                      aria-label="Adds to the price"
                    />
                    <span className="w-20 shrink-0 text-right text-sm tabular-nums text-ink-muted">
                      {Number.isFinite(Number(o.delta))
                        ? `₹${item.price + Math.round(Number(o.delta || 0))}`
                        : '—'}
                    </span>
                    <button
                      type="button"
                      onClick={() =>
                        patch(i, { options: g.options.filter((_, oj) => oj !== j) })
                      }
                      className="shrink-0 px-1 text-sm text-ink-muted hover:text-non-veg"
                      aria-label={`Remove ${o.name || 'option'}`}
                    >
                      ✕
                    </button>
                  </div>
                ))}
              </div>

              <button
                type="button"
                onClick={() =>
                  patch(i, {
                    options: [
                      ...g.options,
                      { key: nextKey(), name: '', delta: '0', available: true },
                    ],
                  })
                }
                className="mt-3 text-sm font-semibold text-brand hover:text-brand-deep"
              >
                Add option
              </button>
            </div>
          ))}

          <Button
            variant="secondary"
            onClick={() =>
              setGroups((gs) => [
                ...(gs ?? []),
                {
                  key: nextKey(),
                  name: '',
                  // Optional is the safer default: making an existing one-tap dish
                  // ask a question is a change every customer feels.
                  kind: 'optional',
                  min: '0',
                  max: '1',
                  options: [{ key: nextKey(), name: '', delta: '0', available: true }],
                },
              ])
            }
          >
            Add group
          </Button>
        </div>
      )}
    </Modal>
  )
}
