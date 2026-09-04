import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { api } from '../lib/api'
import type { MenuItemRow } from '../lib/api'
import { Banner, Button, Card, ConfirmDialog, Pill } from '../ui/primitives'
import { inr } from '../lib/money'
import { ItemDialog } from './ItemDialog'
import { ImportDialog } from './ImportDialog'
import { OptionsDialog } from './OptionsDialog'

/// The menu builder.
///
/// The thing that shapes this whole screen: **a section is not a row anywhere.**
/// `menu_items.category` is a string on each dish, and a section is the set of
/// dishes that happen to share it (0002). Nothing in the database keeps two dishes
/// in "Starters" agreeing on their `category_rank`, and nothing stops a typo
/// creating a second section called "Startes" with one dish in it.
///
/// So this screen owns that consistency. Sections are derived from the items on
/// every render, renaming goes through one RPC that rewrites every row in the
/// section, and reordering sends the menu's entire running order rather than the
/// rows that moved.

type Section = { name: string; rank: number; items: MenuItemRow[]; available: boolean }

function sectionsOf(items: MenuItemRow[]): Section[] {
  const byName = new Map<string, Section>()
  for (const item of items) {
    const existing = byName.get(item.category)
    if (existing) {
      existing.items.push(item)
    } else {
      byName.set(item.category, {
        name: item.category,
        rank: item.category_rank,
        items: [item],
        // `category_available` lives on every row of the section. They should
        // always agree — `admin_set_category_available` writes them together — so
        // the first row is the answer.
        available: item.category_available,
      })
    }
  }
  return [...byName.values()]
    .sort((a, b) => a.rank - b.rank)
    .map((s) => ({ ...s, items: s.items.sort((x, y) => x.item_rank - y.item_rank) }))
}

/// Flattens sections back into the payload `admin_reorder_menu` wants: every dish,
/// with the rank it should now have.
function orderPayload(sections: Section[]) {
  return sections.flatMap((section, sectionIndex) =>
    section.items.map((item, itemIndex) => ({
      id: item.id,
      category: section.name,
      category_rank: sectionIndex,
      item_rank: itemIndex,
    })),
  )
}

export function MenuStep({
  id,
  onNext,
  /// Every load of this list, handed to whoever is holding the wizard. The step
  /// bar needs to know whether there is a sellable dish, and this component has
  /// already asked — a second fetch on the same rows would be a second answer
  /// that can disagree with the first.
  onLoaded,
}: {
  id: string
  onNext: () => void
  onLoaded?: (items: MenuItemRow[]) => void
}) {
  const [items, setItems] = useState<MenuItemRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const [editing, setEditing] = useState<MenuItemRow | null>(null)
  const [adding, setAdding] = useState(false)
  const [importing, setImporting] = useState(false)
  const [deleting, setDeleting] = useState<MenuItemRow | null>(null)
  const [optioning, setOptioning] = useState<MenuItemRow | null>(null)
  const [deletingSection, setDeletingSection] = useState<Section | null>(null)
  const [clearing, setClearing] = useState(false)
  const [renaming, setRenaming] = useState<{ from: string; to: string } | null>(null)
  const [dragging, setDragging] = useState<{ section: number; item: number } | null>(null)

  // Held in a ref, so `load` still depends on `id` and nothing else. As a plain
  // dependency it would rebuild `load` whenever the caller passed a fresh arrow,
  // and the effect below runs on `load` — which is a fetch loop, not a re-render.
  const onLoadedRef = useRef(onLoaded)
  useEffect(() => {
    onLoadedRef.current = onLoaded
  })

  const load = useCallback(async () => {
    try {
      const rows = await api.listMenu(id)
      setItems(rows)
      onLoadedRef.current?.(rows)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [id])

  useEffect(() => {
    void load()
  }, [load])

  const sections = useMemo(() => sectionsOf(items ?? []), [items])
  const categories = sections.map((s) => s.name)

  async function run(action: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await action()
      await load()
      return true
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      return false
    } finally {
      setBusy(false)
    }
  }

  /// Applies a reordering optimistically and persists the whole running order.
  async function reorder(next: Section[]) {
    setItems(
      next.flatMap((s, si) =>
        s.items.map((item, ii) => ({
          ...item,
          category: s.name,
          category_rank: si,
          item_rank: ii,
        })),
      ),
    )
    await run(() => api.reorderMenu(id, orderPayload(next)))
  }

  function moveSection(from: number, direction: -1 | 1) {
    const to = from + direction
    if (to < 0 || to >= sections.length) return
    const next = [...sections]
    ;[next[from], next[to]] = [next[to], next[from]]
    void reorder(next)
  }

  function dropItem(sectionIndex: number, itemIndex: number) {
    if (!dragging) return
    // Dragging between sections would change a dish's category as well as its
    // rank, which is a different operation with different consequences (the
    // section might not exist, the ranks of two sections shift). The dialog's
    // Section field is where a dish changes section.
    if (dragging.section !== sectionIndex) {
      setDragging(null)
      return
    }
    const next = sections.map((s) => ({ ...s, items: [...s.items] }))
    const [moved] = next[sectionIndex].items.splice(dragging.item, 1)
    next[sectionIndex].items.splice(itemIndex, 0, moved)
    setDragging(null)
    void reorder(next)
  }

  const total = items?.length ?? 0
  const unavailable = (items ?? []).filter((i) => !i.is_available).length
  const noPhoto = (items ?? []).filter((i) => !i.image_url).length

  return (
    <Card>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-base font-bold text-ink">Menu</h2>
          <p className="mt-1 text-sm text-ink-muted">
            {total === 0
              ? 'Nothing on the menu yet. Publishing needs at least one dish.'
              : `${total} dishes in ${sections.length} ${
                  sections.length === 1 ? 'section' : 'sections'
                }` +
                (unavailable ? ` · ${unavailable} unavailable` : '') +
                (noPhoto ? ` · ${noPhoto} without a photo` : '')}
          </p>
        </div>
        <div className="flex gap-2">
          {total > 0 && (
            <Button variant="ghost" disabled={busy} onClick={() => setClearing(true)}>
              Delete menu
            </Button>
          )}
          <Button variant="secondary" onClick={() => setImporting(true)}>
            Import CSV
          </Button>
          <Button onClick={() => setAdding(true)}>Add dish</Button>
        </div>
      </div>

      {error && (
        <Banner tone="error" className="mt-4" onDismiss={() => setError(null)}>{error}</Banner>
      )}

      <div className="mt-5 space-y-5">
        {sections.map((section, si) => (
          <div key={section.name} className="rounded-field border border-line">
            <div className="flex flex-wrap items-center gap-2 border-b border-line bg-canvas px-4 py-2.5">
              {renaming?.from === section.name ? (
                <form
                  className="flex flex-1 items-center gap-2"
                  onSubmit={(e) => {
                    e.preventDefault()
                    const to = renaming.to.trim()
                    if (!to || to === section.name) return setRenaming(null)
                    void run(() => api.renameCategory(id, section.name, to)).then(
                      (ok) => ok && setRenaming(null),
                    )
                  }}
                >
                  <input
                    autoFocus
                    value={renaming.to}
                    onChange={(e) => setRenaming({ ...renaming, to: e.target.value })}
                    className="h-9 flex-1 rounded-field border border-field bg-white px-3 text-sm outline-none focus:border-brand-ink"
                  />
                  <Button type="submit" className="h-9 px-3" loading={busy}>
                    Rename
                  </Button>
                  <Button
                    type="button"
                    variant="ghost"
                    className="h-9 px-3"
                    onClick={() => setRenaming(null)}
                  >
                    Cancel
                  </Button>
                </form>
              ) : (
                <>
                  <span className="flex-1 text-sm font-bold text-ink">
                    {section.name}
                    <span className="ml-2 font-normal text-ink-muted">
                      {section.items.length}
                    </span>
                    {!section.available && (
                      <span className="ml-2 inline-block align-middle"><Pill tone="warn">
                        hidden
                      </Pill></span>
                    )}
                  </span>
                  <button
                    type="button"
                    disabled={busy || si === 0}
                    onClick={() => moveSection(si, -1)}
                    className="px-1.5 text-sm text-ink-muted hover:text-ink disabled:opacity-30"
                    aria-label={`Move ${section.name} up`}
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    disabled={busy || si === sections.length - 1}
                    onClick={() => moveSection(si, 1)}
                    className="px-1.5 text-sm text-ink-muted hover:text-ink disabled:opacity-30"
                    aria-label={`Move ${section.name} down`}
                  >
                    ↓
                  </button>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setRenaming({ from: section.name, to: section.name })}
                    className="text-sm font-medium text-ink-muted hover:text-ink"
                  >
                    Rename
                  </button>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void run(() =>
                        api.setCategoryAvailable(id, section.name, !section.available),
                      )
                    }
                    className="text-sm font-medium text-ink-muted hover:text-ink"
                  >
                    {section.available ? 'Hide section' : 'Show section'}
                  </button>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setDeletingSection(section)}
                    className="text-sm font-medium text-ink-muted hover:text-non-veg-ink"
                  >
                    Delete section
                  </button>
                </>
              )}
            </div>

            <div className="divide-y divide-line">
              {section.items.map((item, ii) => (
                <div
                  key={item.id}
                  draggable={!busy}
                  onDragStart={() => setDragging({ section: si, item: ii })}
                  onDragOver={(e) => e.preventDefault()}
                  onDrop={() => dropItem(si, ii)}
                  className={`flex cursor-grab items-center gap-3 px-4 py-3 ${
                    dragging?.section === si && dragging.item === ii ? 'opacity-40' : ''
                  }`}
                >
                  <span className="select-none text-ink-muted" aria-hidden>
                    ⠿
                  </span>
                  <div className="h-10 w-12 shrink-0 overflow-hidden rounded-xs bg-canvas">
                    {item.image_url && (
                      <img src={item.image_url} alt="" className="h-full w-full object-cover" />
                    )}
                  </div>
                  <span
                    className={`h-3.5 w-3.5 shrink-0 rounded-[2px] border ${
                      item.is_veg ? 'border-veg' : 'border-non-veg'
                    }`}
                    title={item.is_veg ? 'Veg' : 'Non-veg'}
                  >
                    <span
                      className={`m-auto mt-[3px] block h-1.5 w-1.5 rounded-full ${
                        item.is_veg ? 'bg-veg' : 'bg-non-veg'
                      }`}
                    />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-ink">
                      {item.name}
                      {item.is_bestseller && (
                        <span className="ml-2 text-xs font-semibold text-brand-ink">
                          Bestseller
                        </span>
                      )}
                      {!item.is_available && (
                        <span className="ml-2 text-xs font-medium text-non-veg-ink">
                          Unavailable
                        </span>
                      )}
                    </p>
                    {item.description && (
                      <p className="truncate text-xs text-ink-muted">{item.description}</p>
                    )}
                  </div>
                  <span className="shrink-0 text-sm tabular-nums text-ink">{inr(item.price)}</span>
                  <button
                    type="button"
                    onClick={() => setEditing(item)}
                    className="shrink-0 text-sm font-semibold text-brand-ink hover:text-ink"
                  >
                    Edit
                  </button>
                  <button
                    type="button"
                    onClick={() => setOptioning(item)}
                    className="shrink-0 text-sm font-medium text-ink-muted hover:text-ink"
                  >
                    Options
                  </button>
                  <button
                    type="button"
                    onClick={() => setDeleting(item)}
                    className="shrink-0 text-sm font-medium text-ink-muted hover:text-non-veg-ink"
                  >
                    Delete
                  </button>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      <div className="mt-6 flex justify-end">
        <Button onClick={onNext}>Continue to review</Button>
      </div>

      {(adding || editing) && (
        <ItemDialog
          item={editing}
          categories={categories.length ? categories : ['Recommended']}
          defaultCategory={categories[0] ?? 'Recommended'}
          busy={busy}
          onCancel={() => {
            setAdding(false)
            setEditing(null)
          }}
          onSave={(payload) =>
            void run(() => api.upsertMenuItem(id, payload)).then((ok) => {
              if (ok) {
                setAdding(false)
                setEditing(null)
              }
            })
          }
        />
      )}

      {optioning && (
        // Options are read and written by this dialog alone, and it reloads the
        // menu on the way out only because a dish's cheapest configuration is its
        // own price — which this never changes. The refresh is for the day it does.
        <OptionsDialog
          item={optioning}
          onClose={() => setOptioning(null)}
          onSaved={() => {
            setOptioning(null)
            void load()
          }}
        />
      )}

      {importing && (
        <ImportDialog
          onCancel={() => setImporting(false)}
          onImport={async (rows) => {
            // Sequential, not parallel: `admin_upsert_menu_item` works out each
            // dish's rank by looking at what is already there, so two inserts
            // racing into the same section would both read the same max and both
            // claim it.
            for (const row of rows) {
              await api.upsertMenuItem(id, row)
            }
            await load()
            setImporting(false)
          }}
        />
      )}

      {deleting && (
        <ConfirmDialog
          title={`Delete ${deleting.name}?`}
          body="If this dish appears on a past order it cannot be deleted — you will be told to mark it unavailable instead, which keeps the order history intact."
          confirmLabel="Delete"
          busy={busy}
          onCancel={() => setDeleting(null)}
          onConfirm={() =>
            void run(() => api.deleteMenuItem(deleting.id)).then(
              (ok) => ok && setDeleting(null),
            )
          }
        />
      )}

      {deletingSection && (
        <ConfirmDialog
          title={`Delete ${deletingSection.name}?`}
          tone="danger"
          body={`All ${deletingSection.items.length} ${
            deletingSection.items.length === 1 ? 'dish' : 'dishes'
          } in this section go with it, and this cannot be undone. If any of them appears on a past order the whole section is kept — hide it instead.`}
          confirmLabel="Delete section"
          busy={busy}
          onCancel={() => setDeletingSection(null)}
          onConfirm={() =>
            void run(() => api.deleteCategory(id, deletingSection.name)).then(
              (ok) => ok && setDeletingSection(null),
            )
          }
        />
      )}

      {clearing && (
        <ConfirmDialog
          title="Delete the entire menu?"
          tone="danger"
          body={`Every one of the ${total} ${
            total === 1 ? 'dish' : 'dishes'
          } on this menu is deleted, across all ${sections.length} ${
            sections.length === 1 ? 'section' : 'sections'
          }. This cannot be undone, and a published restaurant with no menu has nothing for a customer to order.`}
          confirmLabel="Delete menu"
          busy={busy}
          onCancel={() => setClearing(false)}
          onConfirm={() =>
            void run(() => api.deleteMenu(id)).then((ok) => ok && setClearing(false))
          }
        />
      )}
    </Card>
  )
}
