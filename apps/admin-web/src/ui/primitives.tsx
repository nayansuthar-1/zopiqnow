import { useState } from 'react'
import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from 'react'

/// The handful of shared pieces every screen in the console is built from.
/// Restrained on purpose — a flat surface, one accent colour, no glow.

export function Button({
  variant = 'primary',
  loading = false,
  children,
  className = '',
  disabled,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'secondary' | 'ghost'
  loading?: boolean
}) {
  const base =
    'inline-flex items-center justify-center gap-2 rounded-[8px] px-4 h-11 text-sm font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50'
  const styles = {
    primary: 'bg-brand text-white hover:bg-brand-deep',
    secondary: 'border border-line bg-white text-ink hover:bg-canvas',
    ghost: 'text-ink-muted hover:text-ink hover:bg-canvas',
  }[variant]

  return (
    <button
      className={`${base} ${styles} ${className}`}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? 'Please wait…' : children}
    </button>
  )
}

export function Field({
  label,
  hint,
  error,
  className = '',
  ...rest
}: InputHTMLAttributes<HTMLInputElement> & {
  label: string
  hint?: string
  error?: string
}) {
  return (
    <label className={`block ${className}`}>
      <span className="mb-1.5 block text-sm font-medium text-ink">{label}</span>
      <input
        className={`h-11 w-full rounded-[8px] border bg-white px-3 text-sm text-ink outline-none placeholder:text-ink-muted focus:border-brand ${
          error ? 'border-non-veg' : 'border-line'
        }`}
        {...rest}
      />
      {error ? (
        <span className="mt-1.5 block text-sm text-non-veg">{error}</span>
      ) : hint ? (
        <span className="mt-1.5 block text-sm text-ink-muted">{hint}</span>
      ) : null}
    </label>
  )
}

export function Toggle({
  label,
  hint,
  checked,
  onChange,
}: {
  label: string
  hint?: string
  checked: boolean
  onChange: (next: boolean) => void
}) {
  return (
    <label className="flex cursor-pointer items-start gap-3">
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`mt-0.5 h-6 w-11 shrink-0 rounded-full p-0.5 transition-colors ${
          checked ? 'bg-brand' : 'bg-line'
        }`}
      >
        <span
          className={`block h-5 w-5 rounded-full bg-white transition-transform ${
            checked ? 'translate-x-5' : ''
          }`}
        />
      </button>
      <span>
        <span className="block text-sm font-medium text-ink">{label}</span>
        {hint && <span className="block text-sm text-ink-muted">{hint}</span>}
      </span>
    </label>
  )
}

/// A free-entry tag list. Used for cuisines, which are a `text[]` on the
/// restaurant with no lookup table behind them — the vendor's own words, matched
/// by the customer app's trigram search.
export function ChipsInput({
  label,
  hint,
  values,
  onChange,
  suggestions = [],
}: {
  label: string
  hint?: string
  values: string[]
  onChange: (next: string[]) => void
  suggestions?: string[]
}) {
  const [draft, setDraft] = useState('')

  function add(raw: string) {
    const value = raw.trim()
    if (!value) return
    // Case-insensitive, because "Biryani" and "biryani" are one cuisine and two
    // chips would put both into `search_text`.
    if (values.some((v) => v.toLowerCase() === value.toLowerCase())) {
      setDraft('')
      return
    }
    onChange([...values, value])
    setDraft('')
  }

  const unused = suggestions.filter(
    (s) => !values.some((v) => v.toLowerCase() === s.toLowerCase()),
  )

  return (
    <div>
      <span className="mb-1.5 block text-sm font-medium text-ink">{label}</span>
      <div className="flex min-h-11 flex-wrap items-center gap-1.5 rounded-[8px] border border-line bg-white px-2 py-1.5 focus-within:border-brand">
        {values.map((v) => (
          <span
            key={v}
            className="inline-flex items-center gap-1 rounded-full bg-brand-soft px-2.5 py-1 text-sm font-medium text-brand-deep"
          >
            {v}
            <button
              type="button"
              className="text-brand-deep/60 hover:text-brand-deep"
              onClick={() => onChange(values.filter((x) => x !== v))}
              aria-label={`Remove ${v}`}
            >
              ×
            </button>
          </span>
        ))}
        <input
          className="min-w-32 flex-1 bg-transparent px-1 py-0.5 text-sm outline-none placeholder:text-ink-muted"
          placeholder={values.length ? '' : 'Type and press Enter'}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ',') {
              e.preventDefault()
              add(draft)
            } else if (e.key === 'Backspace' && !draft && values.length) {
              onChange(values.slice(0, -1))
            }
          }}
          onBlur={() => add(draft)}
        />
      </div>
      {hint && <span className="mt-1.5 block text-sm text-ink-muted">{hint}</span>}
      {unused.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {unused.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => add(s)}
              className="rounded-full border border-line px-2.5 py-1 text-xs font-medium text-ink-muted hover:border-brand hover:text-brand-deep"
            >
              + {s}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

/// A modal that states what is about to happen before it happens. Used for the
/// handful of actions a customer would notice — never for a save.
export function ConfirmDialog({
  title,
  body,
  confirmLabel,
  busy = false,
  onConfirm,
  onCancel,
}: {
  title: string
  body: string
  confirmLabel: string
  busy?: boolean
  onConfirm: () => void
  onCancel: () => void
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-6"
      onClick={onCancel}
    >
      <div
        className="w-full max-w-md rounded-[12px] bg-white p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-base font-bold text-ink">{title}</h2>
        <p className="mt-2 text-sm text-ink-muted">{body}</p>
        <div className="mt-6 flex justify-end gap-2">
          <Button variant="secondary" onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={onConfirm} loading={busy}>
            {confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  )
}

export function Card({
  children,
  className = '',
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={`rounded-[12px] border border-line bg-white p-6 ${className}`}
    >
      {children}
    </div>
  )
}
