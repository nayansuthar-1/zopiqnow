import { useState } from 'react'
import { csvTemplate, missingColumns, parseCsv, toMenuItem } from './csv'
import type { ParsedRow } from './csv'
import { Button } from '../ui/primitives'

/// Bulk import, with a preview that has to be looked at before anything is written.
///
/// The preview is the feature. A CSV that half-imports is worse than one that does
/// not import at all — you cannot tell which half — so every row is validated here
/// first, the bad ones are named by line number, and the button says how many rows
/// are actually going in.

export function ImportDialog({
  onImport,
  onCancel,
}: {
  onImport: (items: Record<string, unknown>[]) => Promise<void>
  onCancel: () => void
}) {
  const [rows, setRows] = useState<ParsedRow[] | null>(null)
  const [headerProblem, setHeaderProblem] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function read(file: File) {
    const text = await file.text()
    const missing = missingColumns(text)
    if (missing.length) {
      setHeaderProblem(
        `That file has no ${missing.join(', ')} column. Start from the template.`,
      )
      setRows(null)
      return
    }
    setHeaderProblem(null)
    setRows(parseCsv(text))
  }

  const good = (rows ?? []).filter((r) => !r.problem)
  const bad = (rows ?? []).filter((r) => r.problem)

  function downloadTemplate() {
    const url = URL.createObjectURL(
      new Blob([csvTemplate], { type: 'text/csv;charset=utf-8' }),
    )
    const a = document.createElement('a')
    a.href = url
    a.download = 'zopiqnow-menu-template.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-6"
      onClick={onCancel}
    >
      <div
        className="w-full max-w-2xl rounded-[12px] bg-white p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-base font-bold text-ink">Import a menu</h2>
        <p className="mt-1 text-sm text-ink-muted">
          One row per dish. Sections are created in the order they first appear, and
          dishes keep the order they are listed in.
        </p>

        <div className="mt-5 flex flex-wrap items-center gap-3">
          <label className="inline-flex h-10 cursor-pointer items-center rounded-[8px] border border-line px-4 text-sm font-semibold text-ink hover:bg-canvas">
            Choose CSV file
            <input
              type="file"
              accept=".csv,text/csv"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0]
                e.target.value = ''
                if (file) void read(file)
              }}
            />
          </label>
          <button
            type="button"
            onClick={downloadTemplate}
            className="text-sm font-semibold text-brand hover:text-brand-deep"
          >
            Download template
          </button>
        </div>

        {headerProblem && (
          <p className="mt-4 rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {headerProblem}
          </p>
        )}

        {rows && (
          <div className="mt-5">
            <p className="text-sm text-ink">
              <span className="font-semibold">{good.length}</span> dishes ready
              {bad.length > 0 && (
                <span className="text-non-veg">
                  {' '}
                  · {bad.length} {bad.length === 1 ? 'row' : 'rows'} will be skipped
                </span>
              )}
            </p>

            {bad.length > 0 && (
              <ul className="mt-3 max-h-32 overflow-y-auto rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
                {bad.map((r) => (
                  <li key={r.line}>
                    Line {r.line}: {r.problem}
                  </li>
                ))}
              </ul>
            )}

            <div className="mt-3 max-h-64 overflow-auto rounded-[8px] border border-line">
              <table className="w-full min-w-[560px] text-left text-sm">
                <thead className="border-b border-line text-xs uppercase text-ink-muted">
                  <tr>
                    <th className="px-3 py-2 font-semibold">Section</th>
                    <th className="px-3 py-2 font-semibold">Dish</th>
                    <th className="px-3 py-2 text-right font-semibold">Price</th>
                    <th className="px-3 py-2 font-semibold">Veg</th>
                  </tr>
                </thead>
                <tbody>
                  {good.map((r) => (
                    <tr key={r.line} className="border-b border-line last:border-0">
                      <td className="px-3 py-2 text-ink-muted">{r.values.category}</td>
                      <td className="px-3 py-2 text-ink">{r.values.name}</td>
                      <td className="px-3 py-2 text-right tabular-nums">
                        ₹{r.values.price}
                      </td>
                      <td className="px-3 py-2 text-ink-muted">
                        {toMenuItem(r).is_veg ? 'Veg' : 'Non-veg'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {error && (
          <p className="mt-4 rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
        )}

        <div className="mt-6 flex justify-end gap-2">
          <Button variant="secondary" onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          <Button
            disabled={!good.length}
            loading={busy}
            onClick={() => {
              setBusy(true)
              setError(null)
              onImport(good.map(toMenuItem))
                .catch((e) => setError(e instanceof Error ? e.message : String(e)))
                .finally(() => setBusy(false))
            }}
          >
            {good.length ? `Import ${good.length} dishes` : 'Import'}
          </Button>
        </div>
      </div>
    </div>
  )
}
