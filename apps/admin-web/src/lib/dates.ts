/// Local calendar days.
///
/// `<input type="date">` speaks in local calendar days — `"2026-09-30"` is the
/// day the admin pointed at, in the timezone they are sitting in. `Date` does
/// not: ECMAScript parses a bare date-only string as **UTC midnight**, so a
/// round trip through `new Date(x).toISOString()` is off by the offset, and in
/// IST that is five and a half hours in the direction that loses a day.
///
/// Everything here works off `getFullYear`/`getMonth`/`getDate`, which read the
/// local calendar and are the only parts of `Date` that do.

function pad(n: number) {
  return String(n).padStart(2, '0')
}

/// A `Date` as the `YYYY-MM-DD` an `<input type="date">` wants, off the local
/// calendar. `toISOString().slice(0, 10)` is the same string in UTC — which,
/// east of Greenwich, is a different day for part of every night.
export function toDateInput(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

/// Today, as this desk's calendar has it. Compares directly against a
/// `YYYY-MM-DD` from an input or from a `date` column, both of which are already
/// calendar days with no timezone of their own.
export function todayLocal(): string {
  return toDateInput(new Date())
}

/// A `YYYY-MM-DD` from a date input as the instant that day *ends*, locally.
/// A date input names a day, and a `timestamptz` column wants a moment; the
/// moment a day named as a deadline means is its last second, not its first.
export function endOfDayLocal(value: string): Date {
  return new Date(`${value}T23:59:59`)
}
