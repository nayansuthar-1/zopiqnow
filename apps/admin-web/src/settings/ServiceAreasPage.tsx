import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { ServiceAreaRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  ConfirmDialog,
  DataTable,
  Field,
  Modal,
  PageBody,
  Pill,
  Select,
  TableSkeleton,
  Td,
  Th,
} from '../ui/primitives'
import { useToast } from '../ui/toast'

/// Where Zopiqnow delivers (migration 0159).
///
/// This has always been data rather than code — adding a town is one row and no
/// app release — and until now that row was written by hand in psql, which made
/// opening a town an engineering task instead of a business one.
///
/// **The counts are the screen.** A list of four names with a switch beside each
/// gives nobody a way to tell Ghanerao, seeded in August and dark ever since,
/// from Sadri, which has nine kitchens and this month's orders. Switching a town
/// off stops every customer in it from ordering, so the number of kitchens and
/// the number of recent orders belong next to the switch that does it.
///
/// Two things here are deliberately not editable. The weather columns are
/// written by `poll_weather` every five minutes — shown, because "is it raining
/// in Sadri" is what somebody reaching for the rain surcharge wants to know, and
/// not a setting because a cron overwrites them. And the id never changes: it is
/// what every restaurant's `service_area_id` points at, so a town renamed into a
/// different id would take its kitchens' addresses with it.

function when(iso: string | null) {
  if (!iso) return 'never'
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}

type Draft = {
  id?: string
  name: string
  centre_lat: string
  centre_lng: string
  radius_km: string
  catchment_id: string
}

const blank: Draft = {
  name: '',
  centre_lat: '',
  centre_lng: '',
  radius_km: '5',
  catchment_id: '',
}

export function ServiceAreasPage() {
  const toast = useToast()
  const [rows, setRows] = useState<ServiceAreaRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [draft, setDraft] = useState<Draft | null>(null)
  const [toggling, setToggling] = useState<ServiceAreaRow | null>(null)

  const load = useCallback(async () => {
    try {
      setRows(await api.serviceAreas())
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function run(action: () => Promise<string>, close: () => void) {
    setBusy(true)
    setError(null)
    try {
      const said = await action()
      toast(said)
      close()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const live = rows?.filter((r) => r.is_active) ?? []

  return (
    <>
      <PageHeader
        title="Service areas"
        subtitle={
          rows === null
            ? 'Where Zopiqnow delivers.'
            : `${live.length} town${live.length === 1 ? '' : 's'} open of ${rows.length}. A customer outside all of them cannot place an order.`
        }
        action={
          <Button onClick={() => setDraft(blank)}>Add a town</Button>
        }
      />

      <PageBody>
        {error && (
          <Banner tone="error" className="mb-4 max-w-2xl" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}

        {rows === null ? (
          <TableSkeleton rows={4} />
        ) : (
          <DataTable label="Service areas" minWidth={980}>
            <thead>
              <tr>
                <Th>Town</Th>
                <Th>Centre</Th>
                <Th align="right">Kitchens</Th>
                <Th align="right">Orders, 30 days</Th>
                <Th>Weather</Th>
                <Th>Status</Th>
                <Th hideLabel>Actions</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((a) => (
                <tr key={a.id}>
                  <Td>
                    <p className="font-medium text-ink">{a.name}</p>
                    <p className="text-xs text-ink-muted">{a.id}</p>
                    {a.catchment_name && (
                      // 0126: a kitchen serves its own town, except where one
                      // town is explicitly reading another's catalogue.
                      <p className="mt-0.5 text-xs text-ink-muted">
                        Shows {a.catchment_name}'s menu
                      </p>
                    )}
                  </Td>
                  <Td className="text-ink-muted">
                    <p className="tabular-nums">
                      {a.centre_lat.toFixed(4)}, {a.centre_lng.toFixed(4)}
                    </p>
                    <p className="text-xs">{a.radius_km} km radius</p>
                  </Td>
                  <Td align="right" className="text-ink-muted">
                    <span className="font-semibold text-ink">
                      {a.live_restaurant_count}
                    </span>
                    {a.restaurant_count !== a.live_restaurant_count && (
                      <span className="text-xs"> of {a.restaurant_count}</span>
                    )}
                  </Td>
                  <Td align="right" className="text-ink-muted tabular-nums">
                    {a.orders_30d}
                  </Td>
                  <Td className="text-ink-muted">
                    {a.weather_checked_at === null ? (
                      <span className="text-xs">not polled</span>
                    ) : (
                      <>
                        <p className="text-xs">
                          {a.last_precip_mm ?? 0} mm ·{' '}
                          {when(a.weather_checked_at)}
                        </p>
                        {a.raining_until && (
                          <Pill tone="warn">Raining</Pill>
                        )}
                      </>
                    )}
                  </Td>
                  <Td>
                    <Pill tone={a.is_active ? 'live' : 'neutral'}>
                      {a.is_active ? 'Open' : 'Closed'}
                    </Pill>
                  </Td>
                  <Td>
                    <div className="flex justify-end gap-2">
                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={() =>
                          setDraft({
                            id: a.id,
                            name: a.name,
                            centre_lat: String(a.centre_lat),
                            centre_lng: String(a.centre_lng),
                            radius_km: String(a.radius_km),
                            catchment_id: a.catchment_id ?? '',
                          })
                        }
                      >
                        Edit
                      </Button>
                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={() => setToggling(a)}
                      >
                        {a.is_active ? 'Close' : 'Open'}
                      </Button>
                    </div>
                  </Td>
                </tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </PageBody>

      {draft && (
        <Modal
          busy={busy}
          onClose={() => setDraft(null)}
          title={draft.id ? `Edit ${draft.name}` : 'Add a town'}
          footer={
            <>
              <Button variant="secondary" onClick={() => setDraft(null)} disabled={busy}>
                Cancel
              </Button>
              <Button
                loading={busy}
                onClick={() =>
                  void run(
                    () =>
                      api.upsertServiceArea({
                        id: draft.id,
                        name: draft.name.trim(),
                        centre_lat: Number(draft.centre_lat),
                        centre_lng: Number(draft.centre_lng),
                        radius_km: Number(draft.radius_km),
                        catchment_id: draft.catchment_id || null,
                      }),
                    () => setDraft(null),
                  )
                }
              >
                {draft.id ? 'Save' : 'Add it'}
              </Button>
            </>
          }
        >
          <div className="space-y-3">
            <Field
              label="Name"
              value={draft.name}
              onChange={(e) => setDraft({ ...draft, name: e.target.value })}
              placeholder="Mount Abu"
              hint={
                draft.id
                  ? 'The id stays as it is — every restaurant in this town points at it.'
                  : 'The id is made from this name and cannot be changed afterwards.'
              }
            />
            <div className="grid gap-3 sm:grid-cols-2">
              <Field
                label="Centre latitude"
                value={draft.centre_lat}
                onChange={(e) => setDraft({ ...draft, centre_lat: e.target.value })}
                placeholder="25.1857"
              />
              <Field
                label="Centre longitude"
                value={draft.centre_lng}
                onChange={(e) => setDraft({ ...draft, centre_lng: e.target.value })}
                placeholder="73.4386"
              />
            </div>
            <Field
              label="Radius in kilometres"
              value={draft.radius_km}
              onChange={(e) => setDraft({ ...draft, radius_km: e.target.value })}
              hint="A delivery address outside this circle is refused at checkout."
            />
            <Select
              label="Show another town's menu"
              value={draft.catchment_id}
              onChange={(e) => setDraft({ ...draft, catchment_id: e.target.value })}
            >
              <option value="">Its own kitchens (normal)</option>
              {(rows ?? [])
                // A town cannot point at itself, and the database keeps these
                // chains flat — pointing at a town that already points elsewhere
                // is refused there rather than hidden here.
                .filter((r) => r.id !== draft.id && r.catchment_id === null)
                .map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.name}
                  </option>
                ))}
            </Select>
            {!draft.id && (
              <p className="text-sm text-ink-muted">
                It arrives closed. Publish a restaurant into it, then open it.
              </p>
            )}
          </div>
        </Modal>
      )}

      {toggling && (
        <ConfirmDialog
          busy={busy}
          tone={toggling.is_active ? 'danger' : 'default'}
          title={
            toggling.is_active
              ? `Close ${toggling.name}?`
              : `Open ${toggling.name}?`
          }
          body={
            toggling.is_active
              ? `Nobody in ${toggling.name} will be able to place an order. Its ${toggling.live_restaurant_count} open kitchen(s) stay as they are — they simply stop being reachable.`
              : `Customers in ${toggling.name} will be able to order from its ${toggling.live_restaurant_count} open kitchen(s) straight away.`
          }
          confirmLabel={toggling.is_active ? 'Close it' : 'Open it'}
          onCancel={() => setToggling(null)}
          onConfirm={() =>
            void run(
              () => api.setServiceAreaActive(toggling.id, !toggling.is_active),
              () => setToggling(null),
            )
          }
        />
      )}
    </>
  )
}
