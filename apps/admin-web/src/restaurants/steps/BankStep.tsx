import { useState } from 'react'
import { api } from '../../lib/api'
import type { RestaurantDetail } from '../../lib/api'
import { Field } from '../../ui/primitives'
import { StepFrame } from './StepFrame'

/// Where the settlement money goes, and how much of the order we keep.
///
/// Two things on one screen because they are the same conversation with the
/// restaurant — the commercial terms — even though they land in different tables.

export function BankStep({
  id,
  detail,
  onSaved,
  onNext,
}: {
  id: string
  detail: RestaurantDetail | null
  onSaved: () => Promise<void>
  onNext: () => void
}) {
  const b = detail?.bank
  const existingLast4 = b?.account_last4 ?? null

  // Never pre-filled, because it is never sent back to us — `admin_get_restaurant`
  // returns four digits and no more. Changing the account means typing it again,
  // which is the right amount of friction for the field that decides where money
  // goes.
  const [accountNumber, setAccountNumber] = useState('')
  const [confirmNumber, setConfirmNumber] = useState('')
  const [holder, setHolder] = useState(b?.account_holder ?? '')
  const [ifsc, setIfsc] = useState(b?.ifsc ?? '')
  const [bankName, setBankName] = useState(b?.bank_name ?? '')

  // Percent in the UI, basis points in the database. `settlements` computes with
  // bps (0017), and a percentage stored as a float is how a commission ends up
  // being 19.999999%.
  const [commissionPercent, setCommissionPercent] = useState(
    detail ? String(detail.restaurant.commission_bps / 100) : '20',
  )

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const changingAccount = accountNumber !== '' || confirmNumber !== ''

  function localProblem(): string | null {
    if (changingAccount) {
      if (accountNumber !== confirmNumber) {
        return 'The two account numbers do not match.'
      }
      if (!/^[0-9]{9,18}$/.test(accountNumber)) {
        return 'An account number is 9 to 18 digits.'
      }
    }
    if (ifsc && !/^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifsc)) {
      return 'An IFSC is 4 letters, a zero, then 6 more characters — like HDFC0001234.'
    }
    const percent = Number(commissionPercent)
    if (!Number.isFinite(percent) || percent < 0 || percent > 100) {
      return 'Commission has to be between 0% and 100%.'
    }
    if (Math.round(percent * 100) !== percent * 100) {
      return 'Commission can go to two decimal places at most.'
    }
    return null
  }

  async function save() {
    const problem = localProblem()
    if (problem) {
      setError(problem)
      return
    }
    setBusy(true)
    setError(null)
    try {
      await api.updateRestaurant(id, {
        commission_bps: Math.round(Number(commissionPercent) * 100),
      })
      // Sending the bank block only when there is something to send: an admin who
      // came here to change the commission alone must not blank the account by
      // leaving the untouched (and deliberately empty) number fields alone.
      if (changingAccount || holder || ifsc || bankName) {
        await api.setBank(id, {
          account_holder: holder,
          ifsc,
          bank_name: bankName,
          ...(changingAccount ? { account_number: accountNumber } : {}),
        })
      }
      await onSaved()
      onNext()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <StepFrame
      title="Bank and commission"
      description="Where settlements are paid, and the platform's cut. Not visible to the restaurant."
      error={error}
      busy={busy}
      onSave={() => void save()}
    >
      <Field
        label="Account holder's name"
        value={holder}
        onChange={(e) => setHolder(e.target.value)}
        placeholder="As printed on the passbook"
      />

      {existingLast4 && !changingAccount ? (
        <div className="rounded-[8px] bg-canvas px-4 py-3">
          <p className="text-sm text-ink">
            Account on file ends in{' '}
            <span className="font-semibold tabular-nums">{existingLast4}</span>
            {b?.verified ? (
              <span className="ml-2 text-veg">· verified</span>
            ) : (
              <span className="ml-2 text-ink-muted">· not verified yet</span>
            )}
          </p>
          <p className="mt-1 text-sm text-ink-muted">
            The full number is never shown again. Type a new one below to replace it.
          </p>
        </div>
      ) : null}

      <div className="grid gap-5 sm:grid-cols-2">
        <Field
          label={existingLast4 ? 'New account number' : 'Account number'}
          inputMode="numeric"
          value={accountNumber}
          onChange={(e) => setAccountNumber(e.target.value.replace(/\D/g, ''))}
          placeholder="9 to 18 digits"
        />
        <Field
          label="Confirm account number"
          inputMode="numeric"
          value={confirmNumber}
          onChange={(e) => setConfirmNumber(e.target.value.replace(/\D/g, ''))}
          // Pasting the same wrong number twice defeats the check entirely, which
          // is the one thing this field exists to prevent.
          onPaste={(e) => e.preventDefault()}
          placeholder="Type it again"
          error={
            confirmNumber !== '' && confirmNumber !== accountNumber
              ? 'These do not match.'
              : undefined
          }
          hint="Typed twice on purpose — paste is off."
        />
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <Field
          label="IFSC"
          maxLength={11}
          value={ifsc}
          onChange={(e) => setIfsc(e.target.value.toUpperCase())}
          placeholder="HDFC0001234"
        />
        <Field
          label="Bank name"
          value={bankName}
          onChange={(e) => setBankName(e.target.value)}
          placeholder="HDFC Bank"
        />
      </div>

      <Field
        label="Commission (%)"
        type="number"
        step="0.01"
        min={0}
        max={100}
        value={commissionPercent}
        onChange={(e) => setCommissionPercent(e.target.value)}
        hint="The platform's share of each delivered order's subtotal. Default is 20%."
      />
    </StepFrame>
  )
}
