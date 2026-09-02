import { useCallback, useEffect, useMemo, useState } from 'react'
import { api } from '../lib/api'
import type { GiftItemRow, GiftShopRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  Card,
  CardSkeleton,
  ConfirmDialog,
  EmptyState,
  Field,
  Pill,
} from '../ui/primitives'
import { GiftItemDialog } from './GiftItemDialog'
import { GiftShopDialog } from './GiftShopDialog'

/// The gift catalogue — the second marketplace, editable at last (0118).
///
/// From 0022 until now these two tables were seeded and read-only, which meant
/// every price, name and photo on the Gifts tab could only be changed from a
/// psql prompt. That was defensible while gifts were browse-only; it stopped
/// being defensible the moment they could be bought.
///
/// **A shelf is not a row anywhere**, exactly as a menu section is not (0002).
/// `gift_items.category` is a string on each product and a shelf is the set of
/// products sharing it — so nothing in the database keeps two items on one shelf
/// agreeing about its rank, and nothing stops a typo creating a second shelf
/// with one item on it. This screen owns that consistency: shelves are derived
/// on every render, renaming goes through one RPC that rewrites every row, and
/// reordering sends the whole running order rather than the rows that moved.
///
/// Structurally this is `MenuStep` with a shop where the restaurant was, and the
/// duplication is deliberate rather than overlooked: the two catalogues share a
/// shape but not a table, not an RPC and not a row type, so the common version
/// would be a component parameterised by six callbacks and two field sets to
/// save markup that is going to diverge (a dish has a veg mark and a serving
/// window; a gift has a gallery).

type Shelf = { name: string; rank: number; items: GiftItemRow[] }

function shelvesOf(items: GiftItemRow[]): Shelf[] {
  const byName = new Map<string, Shelf>()
  for (const item of items) {
    const existing = byName.get(item.category)
    if (existing) existing.items.push(item)
    else byName.set(item.category, { name: item.category, rank: item.category_rank, items: [item] })
  }
  return [...byName.values()]
    .sort((a, b) => a.rank - b.rank)
    .map((s) => ({ ...s, items: s.items.sort((x, y) => x.item_rank - y.item_rank) }))
}

/// Flattens shelves back into the payload `admin_reorder_gift_items` wants:
/// every product, with the rank it should now have.
function orderPayload(shelves: Shelf[]) {
  return shelves.flatMap((shelf, shelfIndex) =>
    shelf.items.map((item, itemIndex) => ({
      id: item.id,
      category: shelf.name,
      category_rank: shelfIndex,
      item_rank: itemIndex,
    })),
  )
}

export function GiftCataloguePage() {
  const [shops, setShops] = useState<GiftShopRow[] | null>(null)
  const [shopId, setShopId] = useState<string | null>(null)
  const [items, setItems] = useState<GiftItemRow[] | null>(null)
  const [fee, setFee] = useState<number | null>(null)
  const [feeDraft, setFeeDraft] = useState('')

  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const [addingShop, setAddingShop] = useState(false)
  const [editingShop, setEditingShop] = useState<GiftShopRow | null>(null)
  const [deletingShop, setDeletingShop] = useState<GiftShopRow | null>(null)

  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<GiftItemRow | null>(null)
  const [deleting, setDeleting] = useState<GiftItemRow | null>(null)
  const [deletingShelf, setDeletingShelf] = useState<Shelf | null>(null)
  const [renaming, setRenaming] = useState<{ from: string; to: string } | null>(null)
  const [dragging, setDragging] = useState<{ shelf: number; item: number } | null>(null)

  const loadShops = useCallback(async () => {
    const rows = await api.giftShops()
    setShops(rows)
    // Selection follows the data: the first load picks a shop, and a later one
    // only re-picks if the selected shop has gone. Re-picking every time would
    // throw an admin back to shop one after every save.
    setShopId((current) =>
      current && rows.some((s) => s.id === current) ? current : (rows[0]?.id ?? null),
    )
  }, [])

  const loadItems = useCallback(async () => {
    if (!shopId) return setItems([])
    setItems(await api.giftItems(shopId))
  }, [shopId])

  useEffect(() => {
    void (async () => {
      try {
        const [, settings] = await Promise.all([loadShops(), api.giftSettings()])
        setFee(settings.delivery_fee)
        setFeeDraft(String(settings.delivery_fee))
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e))
      }
    })()
  }, [loadShops])

  useEffect(() => {
    void (async () => {
      try {
        await loadItems()
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e))
      }
    })()
  }, [loadItems])

  const shop = shops?.find((s) => s.id === shopId) ?? null
  const shelves = useMemo(() => shelvesOf(items ?? []), [items])
  const shelfNames = shelves.map((s) => s.name)

  async function run(action: () => Promise<unknown>, said?: string) {
    setBusy(true)
    setError(null)
    setNote(null)
    try {
      await action()
      await Promise.all([loadShops(), loadItems()])
      if (said) setNote(said)
      return true
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      return false
    } finally {
      setBusy(false)
    }
  }

  /// Applies a reordering optimistically and persists the whole running order.
  async function reorder(next: Shelf[]) {
    if (!shopId) return
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
    await run(() => api.reorderGiftItems(shopId, orderPayload(next)))
  }

  function moveShelf(from: number, direction: -1 | 1) {
    const to = from + direction
    if (to < 0 || to >= shelves.length) return
    const next = [...shelves]
    ;[next[from], next[to]] = [next[to], next[from]]
    void reorder(next)
  }

  function dropItem(shelfIndex: number, itemIndex: number) {
    if (!dragging) return
    // Dragging between shelves would change a product's category as well as its
    // rank — a different operation with different consequences. The dialog's
    // Shelf field is where a gift changes shelf.
    if (dragging.shelf !== shelfIndex) return setDragging(null)
    const next = shelves.map((s) => ({ ...s, items: [...s.items] }))
    const [moved] = next[shelfIndex].items.splice(dragging.item, 1)
    next[shelfIndex].items.splice(itemIndex, 0, moved)
    setDragging(null)
    void reorder(next)
  }

  const total = items?.length ?? 0
  const unavailable = (items ?? []).filter((i) => !i.is_available).length
  const noPhoto = (items ?? []).filter((i) => i.image_urls.length === 0).length

  return (
    <>
      <PageHeader
        title="Gift catalogue"
        subtitle="Shops, products, shelves and photos for the Gifts tab."
        action={
          <div className="flex gap-2">
            {shop && (
              <Button variant="secondary" onClick={() => setEditingShop(shop)}>
                Edit shop
              </Button>
            )}
            <Button onClick={() => setAddingShop(true)}>Add shop</Button>
          </div>
        }
      />

      <div className="space-y-5 px-6 py-5">
        {error && (
          <Banner tone="error" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}
        {note && (
          <Banner tone="success" onDismiss={() => setNote(null)}>
            {note}
          </Banner>
        )}

        {shops === null ? (
          <CardSkeleton rows={3} />
        ) : shops.length === 0 ? (
          <EmptyState
            title="No gift shops yet"
            body="A gift shop is the seller a product belongs to. Add one and the Gifts tab has something to show."
            action={<Button onClick={() => setAddingShop(true)}>Add shop</Button>}
          />
        ) : (
          <>
            {/* The shop picker. A list rather than a dropdown because the counts
                beside each name are the reason to pick one. */}
            <Card className="p-0">
              <ul className="divide-y divide-line">
                {shops.map((s) => (
                  <li
                    key={s.id}
                    className={`flex flex-wrap items-center gap-3 px-5 py-3.5 ${
                      s.id === shopId ? 'bg-brand-soft/40' : ''
                    }`}
                  >
                    <button
                      type="button"
                      onClick={() => setShopId(s.id)}
                      className="flex min-w-0 flex-1 items-center gap-3 text-left"
                    >
                      <span className="h-10 w-10 shrink-0 overflow-hidden rounded-field bg-canvas">
                        {s.image_url && (
                          <img src={s.image_url} alt="" className="h-full w-full object-cover" />
                        )}
                      </span>
                      <span className="min-w-0">
                        <span className="block truncate text-sm font-semibold text-ink">
                          {s.name}
                        </span>
                        <span className="block truncate text-xs text-ink-muted">
                          {s.id} · {s.item_count} product{s.item_count === 1 ? '' : 's'}
                          {s.order_count > 0 &&
                            ` · ${s.order_count} order${s.order_count === 1 ? '' : 's'}`}
                        </span>
                      </span>
                    </button>
                    <Pill tone={s.is_active ? 'live' : 'neutral'}>
                      {s.is_active ? 'Live' : 'Off'}
                    </Pill>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => setEditingShop(s)}
                      className="text-sm font-semibold text-brand-ink hover:text-ink"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() =>
                        void run(
                          () => api.upsertGiftShop({ ...s, is_active: !s.is_active }),
                          s.is_active ? `${s.name} is off the app.` : `${s.name} is live.`,
                        )
                      }
                      className="text-sm font-medium text-ink-muted hover:text-ink"
                    >
                      {s.is_active ? 'Switch off' : 'Switch on'}
                    </button>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => setDeletingShop(s)}
                      className="text-sm font-medium text-ink-muted hover:text-non-veg-ink"
                    >
                      Delete
                    </button>
                  </li>
                ))}
              </ul>
            </Card>

            {shop && (
              <Card className="p-0">
                <div className="flex flex-wrap items-start justify-between gap-3 border-b border-line px-6 py-4">
                  <div>
                    <h2 className="text-base font-bold text-ink">{shop.name}</h2>
                    <p className="mt-1 text-sm text-ink-muted">
                      {total === 0
                        ? 'Nothing in this shop yet.'
                        : `${total} product${total === 1 ? '' : 's'} on ${
                            shelves.length
                          } shel${shelves.length === 1 ? 'f' : 'ves'}` +
                          (unavailable ? ` · ${unavailable} unavailable` : '') +
                          (noPhoto ? ` · ${noPhoto} without a photo` : '')}
                    </p>
                  </div>
                  <Button onClick={() => setAdding(true)}>Add gift</Button>
                </div>

                {items === null ? (
                  <div className="p-6">
                    <CardSkeleton rows={4} />
                  </div>
                ) : total === 0 ? (
                  <div className="p-6">
                    <EmptyState
                      title="No products"
                      body="Add the first gift and it appears on the Gifts tab as soon as the shop is live."
                      action={<Button onClick={() => setAdding(true)}>Add gift</Button>}
                    />
                  </div>
                ) : (
                  <div className="space-y-5 p-6">
                    {shelves.map((shelf, si) => (
                      <div key={shelf.name} className="rounded-field border border-line">
                        <div className="flex flex-wrap items-center gap-2 border-b border-line bg-canvas px-4 py-2.5">
                          {renaming?.from === shelf.name ? (
                            <form
                              className="flex flex-1 items-center gap-2"
                              onSubmit={(e) => {
                                e.preventDefault()
                                const to = renaming.to.trim()
                                if (!to || to === shelf.name) return setRenaming(null)
                                void run(() =>
                                  api.renameGiftCategory(shop.id, shelf.name, to),
                                ).then((ok) => ok && setRenaming(null))
                              }}
                            >
                              <input
                                autoFocus
                                value={renaming.to}
                                onChange={(e) =>
                                  setRenaming({ ...renaming, to: e.target.value })
                                }
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
                                {shelf.name}
                                <span className="ml-2 font-normal text-ink-muted">
                                  {shelf.items.length}
                                </span>
                              </span>
                              <button
                                type="button"
                                disabled={busy || si === 0}
                                onClick={() => moveShelf(si, -1)}
                                className="px-1.5 text-sm text-ink-muted hover:text-ink disabled:opacity-30"
                                aria-label={`Move ${shelf.name} up`}
                              >
                                ↑
                              </button>
                              <button
                                type="button"
                                disabled={busy || si === shelves.length - 1}
                                onClick={() => moveShelf(si, 1)}
                                className="px-1.5 text-sm text-ink-muted hover:text-ink disabled:opacity-30"
                                aria-label={`Move ${shelf.name} down`}
                              >
                                ↓
                              </button>
                              <button
                                type="button"
                                disabled={busy}
                                onClick={() =>
                                  setRenaming({ from: shelf.name, to: shelf.name })
                                }
                                className="text-sm font-medium text-ink-muted hover:text-ink"
                              >
                                Rename
                              </button>
                              <button
                                type="button"
                                disabled={busy}
                                onClick={() => setDeletingShelf(shelf)}
                                className="text-sm font-medium text-ink-muted hover:text-non-veg-ink"
                              >
                                Delete shelf
                              </button>
                            </>
                          )}
                        </div>

                        <div className="divide-y divide-line">
                          {shelf.items.map((item, ii) => (
                            <div
                              key={item.id}
                              draggable={!busy}
                              onDragStart={() => setDragging({ shelf: si, item: ii })}
                              onDragOver={(e) => e.preventDefault()}
                              onDrop={() => dropItem(si, ii)}
                              className={`flex cursor-grab items-center gap-3 px-4 py-3 ${
                                dragging?.shelf === si && dragging.item === ii
                                  ? 'opacity-40'
                                  : ''
                              }`}
                            >
                              <span className="select-none text-ink-muted" aria-hidden>
                                ⠿
                              </span>
                              <div className="h-12 w-12 shrink-0 overflow-hidden rounded-xs bg-canvas">
                                {item.image_url && (
                                  <img
                                    src={item.image_url}
                                    alt=""
                                    className="h-full w-full object-cover"
                                  />
                                )}
                              </div>
                              <div className="min-w-0 flex-1">
                                <p className="truncate text-sm font-medium text-ink">
                                  {item.name}
                                  {!item.is_available && (
                                    <span className="ml-2 text-xs font-medium text-non-veg-ink">
                                      Unavailable
                                    </span>
                                  )}
                                </p>
                                <p className="truncate text-xs text-ink-muted">
                                  {item.image_urls.length} photo
                                  {item.image_urls.length === 1 ? '' : 's'} ·{' '}
                                  {item.gst_rate_bps / 100}% GST
                                  {item.description ? ` · ${item.description}` : ''}
                                </p>
                              </div>
                              <span className="shrink-0 text-sm tabular-nums text-ink">
                                ₹{item.price}
                              </span>
                              <button
                                type="button"
                                disabled={busy}
                                onClick={() =>
                                  void run(() =>
                                    api.setGiftItemAvailable(item.id, !item.is_available),
                                  )
                                }
                                className="shrink-0 text-sm font-medium text-ink-muted hover:text-ink"
                              >
                                {item.is_available ? 'Mark sold out' : 'Back in stock'}
                              </button>
                              <button
                                type="button"
                                onClick={() => setEditing(item)}
                                className="shrink-0 text-sm font-semibold text-brand-ink hover:text-ink"
                              >
                                Edit
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
                )}
              </Card>
            )}

            {/* The courier fee. `gift_settings` has been one row with one integer
                since 0096 and nothing has ever been able to change it — the
                quote already reads it, so this is the last wire. */}
            <Card>
              <h2 className="text-base font-bold text-ink">Delivery fee</h2>
              <p className="mt-1 text-sm text-ink-muted">
                Charged once on every gift order, whatever is in the bag. Zero means
                delivery is free, which is what it has been so far.
              </p>
              <form
                className="mt-4 flex flex-wrap items-end gap-3"
                onSubmit={(e) => {
                  e.preventDefault()
                  const value = Number(feeDraft)
                  if (!Number.isFinite(value)) return
                  void run(
                    async () => setFee(await api.setGiftDeliveryFee(Math.round(value))),
                    'Delivery fee saved.',
                  )
                }}
              >
                <Field
                  label="Fee (₹)"
                  type="number"
                  min={0}
                  max={1000}
                  className="w-40"
                  value={feeDraft}
                  onChange={(e) => setFeeDraft(e.target.value)}
                />
                <Button
                  type="submit"
                  className="mb-0.5"
                  loading={busy}
                  disabled={fee === null || feeDraft.trim() === '' || Number(feeDraft) === fee}
                >
                  Save fee
                </Button>
              </form>
            </Card>
          </>
        )}
      </div>

      {(addingShop || editingShop) && (
        <GiftShopDialog
          shop={editingShop}
          busy={busy}
          onCancel={() => {
            setAddingShop(false)
            setEditingShop(null)
          }}
          onSave={(payload) =>
            void run(() => api.upsertGiftShop(payload)).then((ok) => {
              if (ok) {
                setAddingShop(false)
                setEditingShop(null)
              }
            })
          }
        />
      )}

      {(adding || editing) && shop && (
        <GiftItemDialog
          item={editing}
          categories={shelfNames.length ? shelfNames : ['Gifts']}
          defaultCategory={editing?.category ?? shelfNames[0] ?? 'Gifts'}
          busy={busy}
          onCancel={() => {
            setAdding(false)
            setEditing(null)
          }}
          onSave={(payload) =>
            void run(() => api.upsertGiftItem(shop.id, payload)).then((ok) => {
              if (ok) {
                setAdding(false)
                setEditing(null)
              }
            })
          }
        />
      )}

      {deletingShop && (
        <ConfirmDialog
          title={`Delete ${deletingShop.name}?`}
          tone="danger"
          body={
            deletingShop.order_count > 0
              ? `This shop has ${deletingShop.order_count} order${
                  deletingShop.order_count === 1 ? '' : 's'
                } against it, so the database will refuse — the receipts read its name. Switch it off instead and it disappears from the app.`
              : `All ${deletingShop.item_count} product${
                  deletingShop.item_count === 1 ? '' : 's'
                } in this shop go with it, and this cannot be undone.`
          }
          confirmLabel="Delete shop"
          busy={busy}
          onCancel={() => setDeletingShop(null)}
          onConfirm={() =>
            void run(() => api.deleteGiftShop(deletingShop.id)).then(
              (ok) => ok && setDeletingShop(null),
            )
          }
        />
      )}

      {deleting && (
        <ConfirmDialog
          title={`Delete ${deleting.name}?`}
          tone="danger"
          // True, and worth saying: unlike a dish, this delete is never refused.
          // `gift_order_items` copied every field its line needs and holds no
          // reference back (0096), so a past order keeps its receipt whole.
          body="This cannot be undone. Orders that already contain it keep their receipt — the line was copied, not linked. To take it off the app without deleting it, mark it sold out instead."
          confirmLabel="Delete"
          busy={busy}
          onCancel={() => setDeleting(null)}
          onConfirm={() =>
            void run(() => api.deleteGiftItem(deleting.id)).then(
              (ok) => ok && setDeleting(null),
            )
          }
        />
      )}

      {deletingShelf && shop && (
        <ConfirmDialog
          title={`Delete ${deletingShelf.name}?`}
          tone="danger"
          body={`All ${deletingShelf.items.length} product${
            deletingShelf.items.length === 1 ? '' : 's'
          } on this shelf are deleted with it, and this cannot be undone.`}
          confirmLabel="Delete shelf"
          busy={busy}
          onCancel={() => setDeletingShelf(null)}
          onConfirm={() =>
            void run(() => api.deleteGiftCategory(shop.id, deletingShelf.name)).then(
              (ok) => ok && setDeletingShelf(null),
            )
          }
        />
      )}
    </>
  )
}
