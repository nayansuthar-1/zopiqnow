import { useEffect, useId, useRef, useState } from 'react'
import type {
  ButtonHTMLAttributes,
  InputHTMLAttributes,
  SelectHTMLAttributes,
  ReactNode,
  TextareaHTMLAttributes,
} from 'react'

/// The handful of shared pieces every screen in the console is built from.
/// Restrained on purpose — a flat surface, one accent colour, no glow.
///
/// Everything here is keyboard-reachable and says what it is to a screen
/// reader. That is not decoration on an internal tool: this console is where
/// somebody cancels a stranger's dinner and marks a payment as sent, and an
/// action that can only be reached with a mouse is an action that gets reached
/// by the wrong mouse.

/// The one focus ring in the console. Applied through a shared constant rather
/// than a global `*:focus` rule so that it lands on the element that should
/// show it — a `<label>` wrapping an input shows it on the input, not the label.
const RING =
  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-ink focus-visible:ring-offset-2 focus-visible:ring-offset-white'

export function Spinner({ className = '' }: { className?: string }) {
  return (
    <svg
      className={`animate-spin ${className}`}
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden="true"
    >
      <circle
        cx="8"
        cy="8"
        r="6.5"
        stroke="currentColor"
        strokeWidth="2"
        opacity="0.25"
      />
      <path
        d="M8 1.5a6.5 6.5 0 0 1 6.5 6.5"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  )
}

export function Button({
  variant = 'primary',
  size = 'md',
  loading = false,
  children,
  className = '',
  disabled,
  /// **`button`, not the HTML default.** A `<button>` with no type is a *submit*
  /// button, and most of this console's buttons live inside a `<form>` — every
  /// wizard step is one (`StepFrame`), and a dialog opened from a step renders
  /// inside it too. So a plainly-named button that opened a sheet also saved the
  /// step and advanced the wizard: the Storefront step's "Use a link" and
  /// "Adjust" flashed their modal open and landed the admin on Address.
  ///
  /// Every button that genuinely submits already says `type="submit"` — all
  /// thirteen of them, checked before this default was changed — so nothing
  /// relies on the HTML one.
  type = 'button',
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  size?: 'md' | 'sm'
  loading?: boolean
}) {
  const base = `inline-flex shrink-0 items-center justify-center gap-2 rounded-field font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50 ${RING}`
  const sizes = { md: 'h-11 px-4 text-sm', sm: 'h-9 px-3 text-sm' }[size]
  const styles = {
    primary: 'bg-brand text-ink hover:bg-brand-hover',
    secondary: 'border border-line bg-white text-ink hover:bg-canvas',
    ghost: 'text-ink-muted hover:bg-canvas hover:text-ink',
    // For the handful of actions that end something. Outlined rather than
    // filled: a solid red button is the most eye-catching thing on a screen,
    // and the most eye-catching thing should not be the irreversible one.
    danger:
      'border border-non-veg/80 bg-white text-non-veg-ink hover:bg-non-veg-soft',
  }[variant]

  return (
    <button
      className={`${base} ${sizes} ${styles} ${className}`}
      type={type}
      disabled={disabled || loading}
      // The label stays put while loading. Swapping it for "Please wait…"
      // changes the button's width mid-click and loses the one piece of
      // information that says which action is in flight.
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading && <Spinner />}
      {children}
    </button>
  )
}

export function Field({
  label,
  hint,
  error,
  className = '',
  id,
  ...rest
}: InputHTMLAttributes<HTMLInputElement> & {
  label: string
  hint?: string
  error?: string
}) {
  const auto = useId()
  const inputId = id ?? auto
  const noteId = `${inputId}-note`

  return (
    <div className={className}>
      <label
        htmlFor={inputId}
        className="mb-1.5 block text-sm font-medium text-ink"
      >
        {label}
      </label>
      <input
        id={inputId}
        // The message under the field is announced with it rather than left as
        // grey text a screen reader never reaches.
        aria-describedby={error || hint ? noteId : undefined}
        aria-invalid={error ? true : undefined}
        // A read-only field that looks editable is one somebody types into and
        // wonders why nothing happens. Still focusable and still selectable —
        // the value is usually there to be copied.
        className={`h-11 w-full rounded-field border bg-white px-3 text-sm text-ink outline-none read-only:bg-canvas read-only:text-ink-muted placeholder:text-ink-muted focus:border-brand-ink ${RING} ${
          error ? 'border-non-veg' : 'border-field'
        }`}
        {...rest}
      />
      {error ? (
        <p id={noteId} className="mt-1.5 text-sm text-non-veg-ink">
          {error}
        </p>
      ) : hint ? (
        <p id={noteId} className="mt-1.5 text-sm text-ink-muted">
          {hint}
        </p>
      ) : null}
    </div>
  )
}

export function TextArea({
  label,
  hint,
  className = '',
  id,
  ...rest
}: TextareaHTMLAttributes<HTMLTextAreaElement> & {
  label: string
  hint?: ReactNode
}) {
  const auto = useId()
  const inputId = id ?? auto
  const noteId = `${inputId}-note`

  return (
    <div className={className}>
      <label
        htmlFor={inputId}
        className="mb-1.5 block text-sm font-medium text-ink"
      >
        {label}
      </label>
      <textarea
        id={inputId}
        aria-describedby={hint ? noteId : undefined}
        className={`min-h-24 w-full rounded-field border border-field bg-white px-3 py-2.5 text-sm text-ink outline-none placeholder:text-ink-muted focus:border-brand-ink ${RING}`}
        {...rest}
      />
      {hint && (
        <p id={noteId} className="mt-1.5 text-sm text-ink-muted">
          {hint}
        </p>
      )}
    </div>
  )
}

export function Toggle({
  label,
  hint,
  checked,
  onChange,
  disabled = false,
}: {
  label: string
  hint?: ReactNode
  checked: boolean
  onChange: (next: boolean) => void
  disabled?: boolean
}) {
  return (
    <div className="flex items-start gap-3">
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={`mt-0.5 h-6 w-11 shrink-0 rounded-full p-0.5 transition-colors disabled:cursor-not-allowed disabled:opacity-50 ${RING} ${
          checked ? 'bg-brand-ink' : 'bg-field'
        }`}
      >
        <span
          className={`block h-5 w-5 rounded-full bg-white transition-transform ${
            checked ? 'translate-x-5' : ''
          }`}
        />
      </button>
      {/* Clicking the words works too, and it is a plain click handler rather
          than a wrapping <label>: the control is a <button role="switch">, and
          a label pointing at a button is ignored by every browser. */}
      <span
        className={disabled ? 'opacity-50' : 'cursor-pointer'}
        onClick={() => !disabled && onChange(!checked)}
      >
        <span className="block text-sm font-medium text-ink">{label}</span>
        {hint && <span className="block text-sm text-ink-muted">{hint}</span>}
      </span>
    </div>
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
      <div
        className={`flex min-h-11 flex-wrap items-center gap-1.5 rounded-field border border-field bg-white px-2 py-1.5 focus-within:border-brand-ink focus-within:ring-2 focus-within:ring-brand focus-within:ring-offset-2 focus-within:ring-offset-white`}
      >
        {values.map((v) => (
          <span
            key={v}
            className="inline-flex items-center gap-1 rounded-full bg-brand-soft px-2.5 py-1 text-sm font-medium text-brand-ink"
          >
            {v}
            <button
              type="button"
              className="rounded-full text-brand-ink hover:text-ink"
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
          aria-label={label}
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
      {hint && <p className="mt-1.5 text-sm text-ink-muted">{hint}</p>}
      {unused.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {unused.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => add(s)}
              className={`rounded-full border border-line px-2.5 py-1 text-xs font-medium text-ink-muted hover:border-brand-ink hover:text-brand-ink ${RING}`}
            >
              + {s}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Modal
// ---------------------------------------------------------------------------

/// The one dialog shell in the console, and the reason there is only one.
///
/// Before this there were nine hand-rolled overlays across seven files. None of
/// them closed on Escape, none of them stopped the page behind from scrolling,
/// none of them moved focus in or gave it back, and they used two different
/// backdrop colours. Every one of those is invisible until the moment somebody
/// is trying to work quickly — which, on a screen where the actions are
/// "cancel this order" and "mark ₹5,552 as paid", is every moment.
///
/// **Focus is trapped rather than merely moved.** A dialog that takes focus but
/// lets Tab walk out of it puts the keyboard on the page underneath while the
/// backdrop still says it is unreachable, and the next Enter presses a button
/// nobody can see.
export function Modal({
  title,
  onClose,
  children,
  footer,
  size = 'md',
  /// Set while an action is in flight. Escape and the backdrop stop closing —
  /// dismissing a dialog whose request is already on its way would leave the
  /// screen claiming nothing happened while the database does it anyway.
  busy = false,
}: {
  title: ReactNode
  onClose: () => void
  children: ReactNode
  footer?: ReactNode
  size?: 'sm' | 'md' | 'lg'
  busy?: boolean
}) {
  const panel = useRef<HTMLDivElement>(null)
  const titleId = useId()

  // Mount and unmount only. Deliberately separate from the key handler below,
  // which depends on `busy` — folding the two together would tear this one down
  // and rebuild it every time an action started, and its cleanup hands focus
  // back to whatever opened the dialog. Clicking "Mark paid" would have thrown
  // the keyboard to the button behind the backdrop and then snatched it back.
  useEffect(() => {
    const returnTo = document.activeElement as HTMLElement | null
    // Focus the panel itself rather than its first control: a dialog that opens
    // with the cursor already in a text box reads as a form the user asked for,
    // and this one is usually a question they did not.
    panel.current?.focus()

    const { overflow } = document.body.style
    document.body.style.overflow = 'hidden'

    return () => {
      document.body.style.overflow = overflow
      // Only hand focus back if nothing else has claimed it. When one dialog
      // closes as another opens, the panel being torn down would otherwise
      // throw the keyboard to the control behind *both* of them.
      if (!document.activeElement?.closest('[role="dialog"]')) {
        returnTo?.focus?.()
      }
    }
  }, [])

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape' && !busy) {
        e.stopPropagation()
        onClose()
        return
      }
      if (e.key !== 'Tab' || !panel.current) return

      const focusable = panel.current.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      )
      if (focusable.length === 0) return
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      const active = document.activeElement

      // Wrap at both ends, and treat "focus is on the panel" as being at the
      // start — otherwise the first Tab out of the panel escapes the dialog.
      if (e.shiftKey && (active === first || active === panel.current)) {
        e.preventDefault()
        last.focus()
      } else if (!e.shiftKey && active === last) {
        e.preventDefault()
        first.focus()
      }
    }

    document.addEventListener('keydown', onKey, true)
    return () => document.removeEventListener('keydown', onKey, true)
  }, [onClose, busy])

  const width = { sm: 'max-w-sm', md: 'max-w-md', lg: 'max-w-2xl' }[size]

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-ink/40 p-4 sm:items-center sm:p-6"
      onMouseDown={(e) => {
        // `mousedown` on the backdrop *itself*, not `click`: a click fires after
        // a drag that began inside the panel and ended outside it, so selecting
        // text in a field and releasing over the backdrop would close the
        // dialog and lose what was typed.
        if (e.target === e.currentTarget && !busy) onClose()
      }}
    >
      <div
        ref={panel}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className={`my-auto w-full ${width} rounded-card bg-white shadow-modal outline-none`}
      >
        <div className="px-6 pt-6">
          <h2 id={titleId} className="text-base font-bold text-ink">
            {title}
          </h2>
        </div>
        <div className="px-6 py-4">{children}</div>
        {footer && (
          <div className="flex flex-wrap justify-end gap-2 px-6 pb-6">
            {footer}
          </div>
        )}
      </div>
    </div>
  )
}

/// A modal that states what is about to happen before it happens. Used for the
/// handful of actions a customer would notice — never for a save.
export function ConfirmDialog({
  title,
  body,
  confirmLabel,
  tone = 'default',
  busy = false,
  onConfirm,
  onCancel,
}: {
  title: string
  body: ReactNode
  confirmLabel: string
  /// `danger` for anything that cannot be undone.
  tone?: 'default' | 'danger'
  busy?: boolean
  onConfirm: () => void
  onCancel: () => void
}) {
  return (
    <Modal
      title={title}
      onClose={onCancel}
      busy={busy}
      footer={
        <>
          <Button variant="secondary" onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          <Button
            variant={tone === 'danger' ? 'danger' : 'primary'}
            onClick={onConfirm}
            loading={busy}
          >
            {confirmLabel}
          </Button>
        </>
      }
    >
      <p className="text-sm text-ink-muted">{body}</p>
    </Modal>
  )
}

// ---------------------------------------------------------------------------
// Feedback
// ---------------------------------------------------------------------------

/// The one shape for "something went wrong" / "that worked".
///
/// `role="alert"` on the error tone and not on the others, deliberately: an
/// assertive live region interrupts whatever a screen reader is reading, which
/// is right for a refusal and rude for a confirmation.
export function Banner({
  tone,
  children,
  onDismiss,
  className = '',
}: {
  tone: 'error' | 'success' | 'warn' | 'info'
  children: ReactNode
  onDismiss?: () => void
  className?: string
}) {
  const styles = {
    error: 'bg-non-veg-soft text-non-veg-ink',
    success: 'bg-veg-soft text-veg',
    warn: 'bg-warn-soft text-warn',
    info: 'bg-canvas text-ink-muted',
  }[tone]

  return (
    <div
      role={tone === 'error' ? 'alert' : 'status'}
      className={`flex items-start justify-between gap-4 rounded-field px-4 py-3 text-sm ${styles} ${className}`}
    >
      <p className="min-w-0">{children}</p>
      {onDismiss && (
        <button
          type="button"
          onClick={onDismiss}
          aria-label="Dismiss"
          className={`shrink-0 rounded-xs font-semibold opacity-70 hover:opacity-100 ${RING}`}
        >
          ×
        </button>
      )}
    </div>
  )
}

/// What a screen says when there is genuinely nothing on it. A sentence alone
/// reads like a failure; a sentence with a heading and, where there is one, the
/// action that fills the screen reads like a state.
export function EmptyState({
  title,
  body,
  action,
}: {
  title: string
  body: string
  action?: ReactNode
}) {
  return (
    <div className="rounded-card border border-dashed border-line bg-white px-6 py-12 text-center">
      <p className="text-sm font-semibold text-ink">{title}</p>
      <p className="mx-auto mt-1 max-w-md text-sm text-ink-muted">{body}</p>
      {action && <div className="mt-4 flex justify-center">{action}</div>}
    </div>
  )
}

/// The grey block a row occupies before its data lands.
///
/// A skeleton rather than the word "Loading…", because the console's tables are
/// the width of the window: the text version collapses the page to one line and
/// then throws it back to full height, and the button somebody was reaching for
/// has moved by the time they get there.
export function Skeleton({ className = '' }: { className?: string }) {
  return (
    <div
      className={`animate-pulse rounded-[6px] bg-line ${className}`}
      aria-hidden="true"
    />
  )
}

export function TableSkeleton({ rows = 4 }: { rows?: number }) {
  return (
    <div
      className="overflow-hidden rounded-card border border-line bg-white"
      role="status"
      aria-label="Loading"
    >
      {Array.from({ length: rows }, (_, i) => (
        <div
          key={i}
          className="flex items-center gap-4 border-b border-line px-5 py-4 last:border-b-0"
        >
          <Skeleton className="h-4 w-40" />
          <Skeleton className="h-4 w-24" />
          <Skeleton className="ml-auto h-4 w-20" />
        </div>
      ))}
    </div>
  )
}

export function CardSkeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div className="space-y-3" role="status" aria-label="Loading">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="rounded-card border border-line bg-white p-5">
          <Skeleton className="h-4 w-48" />
          <Skeleton className="mt-3 h-3 w-72" />
          <Skeleton className="mt-4 h-3 w-full max-w-xl" />
        </div>
      ))}
    </div>
  )
}

/// The status pill, which five screens had each written for themselves.
export function Pill({
  tone = 'neutral',
  children,
}: {
  tone?: 'live' | 'warn' | 'danger' | 'neutral' | 'brand'
  children: ReactNode
}) {
  const styles = {
    live: 'bg-veg-soft text-veg',
    warn: 'bg-warn-soft text-warn',
    danger: 'bg-non-veg-soft text-non-veg-ink',
    neutral: 'bg-canvas text-ink-muted',
    brand: 'bg-brand-soft text-brand-ink',
  }[tone]

  return (
    <span
      className={`inline-block whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-semibold ${styles}`}
    >
      {children}
    </span>
  )
}

/// The row of filter buttons three screens repeat. A radio group rather than a
/// row of buttons, so a screen reader says "pending, 1 of 3" instead of reading
/// three unrelated buttons and leaving the current one unannounced.
export function SegmentedControl<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T
  options: { value: T; label: string }[]
  onChange: (next: T) => void
  label: string
}) {
  return (
    <div role="radiogroup" aria-label={label} className="flex flex-wrap gap-1">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={value === o.value}
          onClick={() => onChange(o.value)}
          className={`rounded-field px-3 py-1.5 text-sm font-medium transition-colors ${RING} ${
            value === o.value
              ? 'bg-brand-soft text-brand-ink'
              : 'text-ink-muted hover:bg-canvas hover:text-ink'
          }`}
        >
          {o.label}
        </button>
      ))}
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
      className={`rounded-card border border-line bg-white p-6 ${className}`}
    >
      {children}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

/// The one table in the console, and the reason there is only one.
///
/// Before this there were twelve, hand-rolled, with four header styles, three
/// ways of drawing a row divider and two row heights between them. None of the
/// twelve highlighted the row under the cursor, none kept its header visible
/// while the body scrolled, none put `scope` on a heading, and none gave any
/// sign that it continued off the right of the window.
///
/// That reads as untidiness and is not. `SettlementsPage` is nine columns wide
/// and the ninth is **Payable**, with a "Mark paid" button beside it: tracking a
/// restaurant's name from column one to a money button in column nine, on a row
/// that looks exactly like the fourteen around it, with the header gone off the
/// top, is the console's highest-consequence interaction and it had the least
/// support of any screen in the app.
///
/// **The body scrolls, not the page.** A sticky `<thead>` cannot work inside an
/// `overflow-x: auto` box — CSS computes the other axis to `auto` as well, so
/// the header sticks to a container that never scrolls vertically and therefore
/// never moves. The table is its own scroller instead, capped against the
/// viewport using the height `PageHeader` publishes. Short tables never reach
/// the cap and behave exactly as they did.
///
/// `border-separate`, not `collapse`: a collapsed border is painted by the table
/// rather than by the cell, and a sticky cell leaves it behind when it moves.
/// The row dividers sit on the cells for the same reason.
export function DataTable({
  label,
  minWidth,
  children,
  className = '',
}: {
  /// Named for a screen reader, which otherwise announces "table" and a column
  /// count. Every one of these is one of several nouns in this console.
  label: string
  /// The width below which the columns stop being readable and the table should
  /// scroll rather than crush. Two of the twelve had no floor at all and
  /// squeezed nine columns onto a phone.
  minWidth?: number
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={`scroll-shadow-x max-h-[calc(100vh-var(--page-header-h,4.5rem)-7rem)] overflow-auto rounded-card border border-line ${className}`}
    >
      <table
        aria-label={label}
        style={minWidth ? { minWidth } : undefined}
        className="w-full border-separate border-spacing-0 text-left text-sm [&_tbody_td]:border-b [&_tbody_td]:border-line [&_tbody_td]:align-top [&_tbody_tr:hover]:bg-canvas [&_tbody_tr:last-child_td]:border-b-0"
      >
        {children}
      </table>
    </div>
  )
}

export function Th({
  align = 'left',
  /// For the column holding a row's actions. It still needs a name — an
  /// unlabelled column is one a screen reader reads as nothing at all — but the
  /// name is for them and not for the page.
  hideLabel = false,
  children,
  className = '',
}: {
  align?: 'left' | 'right'
  hideLabel?: boolean
  children: ReactNode
  className?: string
}) {
  return (
    <th
      scope="col"
      className={`sticky top-0 z-10 border-b border-line bg-white px-5 py-3 text-xs font-semibold tracking-wide text-ink-muted uppercase ${
        align === 'right' ? 'text-right' : ''
      } ${className}`}
    >
      {hideLabel ? <span className="sr-only">{children}</span> : children}
    </th>
  )
}

export function Td({
  align = 'left',
  children,
  className = '',
}: {
  align?: 'left' | 'right'
  children: ReactNode
  className?: string
}) {
  // A right-aligned column in this console is money or a count, and tabular
  // figures there are not optional — being scannable down the column is the
  // whole reason it is right aligned. Applied here rather than remembered at
  // thirty call sites, three of which had already forgotten.
  return (
    <td
      className={`px-5 py-3 ${align === 'right' ? 'text-right tabular-nums' : ''} ${className}`}
    >
      {children}
    </td>
  )
}

// ---------------------------------------------------------------------------
// The controls the console kept writing out by hand
// ---------------------------------------------------------------------------

/// A `<select>` that can be seen when it has focus.
///
/// All ten native selects in the console carried `outline-none
/// focus:border-brand` — which removes the browser's own ring and puts a 1px
/// border colour change in its place — and one carried no focus style at all.
/// There was no `Select` for `RING` to live in, so it lived in none of them.
export function Select({
  label,
  hint,
  error,
  size = 'md',
  /// For a filter in a toolbar, where the surrounding controls say what it
  /// filters and a printed label would be a third piece of chrome. The label is
  /// still rendered — a screen reader gets it, the layout does not.
  hideLabel = false,
  className = '',
  id,
  children,
  ...rest
  // `size` is omitted rather than merged: HTML gives <select> a numeric size
  // attribute (how many options to show unrolled), which nothing here wants and
  // which collides with the two shapes this component actually has.
}: Omit<SelectHTMLAttributes<HTMLSelectElement>, 'size'> & {
  label: string
  hint?: string
  error?: string
  size?: 'md' | 'sm'
  hideLabel?: boolean
}) {
  const auto = useId()
  const selectId = id ?? auto
  const noteId = `${selectId}-note`

  return (
    <div className={className}>
      <label
        htmlFor={selectId}
        className={
          hideLabel ? 'sr-only' : 'mb-1.5 block text-sm font-medium text-ink'
        }
      >
        {label}
      </label>
      <select
        id={selectId}
        aria-describedby={error || hint ? noteId : undefined}
        aria-invalid={error ? true : undefined}
        className={`select-chevron appearance-none rounded-field border bg-white py-0 text-sm text-ink outline-none focus:border-brand-ink ${RING} ${
          size === 'sm' ? 'h-9 pr-8 pl-2.5' : 'h-11 w-full pr-9 pl-3'
        } ${error ? 'border-non-veg' : 'border-field'}`}
        {...rest}
      >
        {children}
      </select>
      {error ? (
        <p id={noteId} className="mt-1.5 text-sm text-non-veg-ink">
          {error}
        </p>
      ) : hint ? (
        <p id={noteId} className="mt-1.5 text-sm text-ink-muted">
          {hint}
        </p>
      ) : null}
    </div>
  )
}

/// The find-an-order box, which two screens had written out character for
/// character. A `<form>` rather than an input with a click handler, so Enter
/// submits it the way Enter submits everything else in the console.
export function SearchField({
  label,
  placeholder,
  value,
  onChange,
  onSubmit,
  onClear,
  clearLabel = 'Clear',
  submitLabel = 'Find',
  className = '',
}: {
  label: string
  placeholder: string
  value: string
  onChange: (next: string) => void
  onSubmit: () => void
  /// Passed only while a search is actually applied — the way back is not an
  /// action until there is something to come back from.
  onClear?: () => void
  clearLabel?: string
  submitLabel?: string
  className?: string
}) {
  const id = useId()

  return (
    <form
      className={`flex max-w-xl gap-2 ${className}`}
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit()
      }}
    >
      <input
        id={id}
        type="search"
        className={`h-11 min-w-0 flex-1 rounded-field border border-field bg-white px-3 text-sm text-ink outline-none placeholder:text-ink-muted focus:border-brand-ink ${RING}`}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        aria-label={label}
      />
      <Button type="submit" variant="secondary">
        {submitLabel}
      </Button>
      {onClear && (
        <Button type="button" variant="ghost" onClick={onClear}>
          {clearLabel}
        </Button>
      )}
    </form>
  )
}

/// Previous, where you are, Next — which three screens repeated verbatim.
export function Pager({
  page,
  pages,
  onChange,
}: {
  /// Zero-based, the way all three callers already count.
  page: number
  pages: number
  onChange: (next: number) => void
}) {
  if (pages <= 1) return null

  return (
    <nav
      aria-label="Pages"
      className="mt-4 flex items-center justify-center gap-3"
    >
      <Button
        variant="secondary"
        disabled={page === 0}
        onClick={() => onChange(page - 1)}
      >
        Previous
      </Button>
      {/* Announced when it changes, because the thing that moved is the list
          above it and a screen reader has no way to notice that by itself. */}
      <span aria-live="polite" className="text-sm text-ink-muted">
        Page {page + 1} of {pages}
      </span>
      <Button
        variant="secondary"
        disabled={page + 1 >= pages}
        onClick={() => onChange(page + 1)}
      >
        Next
      </Button>
    </nav>
  )
}

/// One number, said once. Analytics and People each had their own, differing in
/// weight, in label weight, in both margins, and in whether the figure was set
/// in tabular figures at all.
export function StatTile({
  label,
  value,
  sub,
}: {
  label: string
  value: string
  sub?: string
}) {
  return (
    <div className="rounded-card border border-line bg-white p-6">
      <p className="text-xs font-medium tracking-wide text-ink-muted uppercase">
        {label}
      </p>
      <p className="mt-2 text-2xl font-bold tabular-nums text-ink">{value}</p>
      {sub && <p className="mt-1 text-sm text-ink-muted">{sub}</p>}
    </div>
  )
}

/// What every screen puts under its `PageHeader`.
///
/// Eighteen pages wrote `p-6`, one wrote `px-6 py-6` — the same thing, spelled
/// differently — and one wrote `px-6 py-5`, which is off the grid. Width was
/// worse: `RidersPage` capped at `3xl` and `SettingsPage` at `2xl` while
/// `UsersPage`, the same kind of roster screen, ran full bleed to whatever
/// monitor it happened to be on.
///
/// Three widths, because there are three kinds of screen here, and a rule you
/// can state is a rule a new screen can be right about.
export function PageBody({
  width = 'list',
  children,
  className = '',
}: {
  /// `list` — a table or a board. Takes the room, but stops at 1600px: a
  /// nine-column settlement table stretched across a 27-inch monitor puts a
  /// restaurant's name and its payable figure two feet apart.
  ///
  /// `form` — fields being filled in. A long measure is hard to read and a text
  /// input the width of a monitor is hard to aim at.
  ///
  /// `wide` — the two screens that are a list of lists: the wizard's menu step
  /// and the home hero.
  width?: 'list' | 'form' | 'wide'
  children: ReactNode
  className?: string
}) {
  const max = {
    list: 'max-w-[1600px]',
    form: 'max-w-2xl',
    wide: 'max-w-4xl',
  }[width]

  return <div className={`p-6 ${max} ${className}`}>{children}</div>
}
