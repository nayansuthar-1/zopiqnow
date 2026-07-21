import type { ReactNode } from 'react'
import { Button } from '../../ui/primitives'

/// The frame each wizard step shares: a title, the fields, one error line, and a
/// save that says what it will do next.
///
/// Saving is per step and explicit. Autosave was tempting and is wrong here —
/// these forms write to a live restaurant once it is published, and "the field
/// saved itself while I was mid-thought about the commission rate" is not a thing
/// an ops tool should ever do.
export function StepFrame({
  title,
  description,
  error,
  busy,
  saveLabel = 'Save and continue',
  onSave,
  children,
}: {
  title: string
  description?: string
  error?: string | null
  busy?: boolean
  saveLabel?: string
  onSave: () => void
  children: ReactNode
}) {
  return (
    <form
      className="rounded-[12px] border border-line bg-white p-6"
      onSubmit={(e) => {
        e.preventDefault()
        onSave()
      }}
    >
      <h2 className="text-base font-bold text-ink">{title}</h2>
      {description && <p className="mt-1 text-sm text-ink-muted">{description}</p>}

      <div className="mt-6 space-y-5">{children}</div>

      {error && (
        <p className="mt-5 rounded-[8px] bg-[#fdeaec] px-4 py-3 text-sm text-non-veg">
          {error}
        </p>
      )}

      <div className="mt-6 flex justify-end">
        <Button type="submit" loading={busy}>
          {saveLabel}
        </Button>
      </div>
    </form>
  )
}
