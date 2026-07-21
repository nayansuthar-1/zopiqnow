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
