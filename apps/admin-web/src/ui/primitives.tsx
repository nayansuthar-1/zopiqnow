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
