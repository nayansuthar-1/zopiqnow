# Admin console — fix queue

Audit of `apps/admin-web/` on 2026-09-01, against `main` at `f2dd99a`.

**State of the build:** `tsc -b` is clean. `oxlint` reports two `only-export-components`
warnings and nothing else. Nothing below is a compile error — every item is something
that is wrong at runtime, wrong on screen, or wrong in what it tells the person using it.

Twenty-two findings. Worked one at a time, top to bottom. Tick the box when it lands.

**Done so far:** A1, B1, B2.

---

## A. Login and access

### A1 — A newly added admin cannot sign in, and the screen says they can
- [x] **Done** — migration `0153_an_admin_is_made_with_a_password_not_a_promise.sql`,
      `src/lib/api.ts:343`, `src/settings/SettingsPage.tsx`

`admin_add_admin` (`0038_admin_roster.sql:43`) inserted one row into `platform_admins`
and touched nothing else. The console's door is `signInWithPassword` against
`auth.users`, so an address added from Settings was authorised and could not
authenticate — there was no account to authenticate with. The copy under the form still
described the OTP door that had already been replaced.

**What shipped.** `admin_add_admin` now takes a third argument and returns a sentence:

- Address has **never** signed in to Zopiqnow → a password is required, and the function
  creates the `auth.users` row, the `auth.identities` row and the `platform_admins` row
  in one transaction.
- Address **already** has an account → the password is *refused*, out loud, and only the
  admin row is written. Setting a password on an existing account would be a way to take
  over any address on the platform by email; that is a different and larger power than
  reading one, and it is not on offer here.
- Password rules: at least 10 characters — not GoTrue's 6, because this password opens a
  console that reads every bank account and licence number on the platform, with no second
  factor and no lockout — and no leading or trailing whitespace, which is almost always a
  copy-paste artefact that hashes fine and then never matches anything typed back.

Three things the live schema taught, that the migration would otherwise have got wrong:

- The token columns (`confirmation_token`, `recovery_token`, `email_change`,
  `email_change_token_new` and the rest) must be `''`, never null — GoTrue reads them into
  Go `string`s and answers a null with an HTTP 500 whose body is `{}`, naming no column.
  Their unique indexes are partial (`WHERE token !~ '^[0-9 ]*$'`), so `''` never collides.
- `auth.identities` needs a row with `provider = 'email'` and `provider_id = user_id`, or
  GoTrue cannot resolve the sign-in at all.
- **`auth.identities.email` is a generated column** reading `identity_data->>'email'`.
  Naming it in the insert is an error, not a redundancy. The first version of this
  migration did exactly that and failed on the first real run against the database.

`extensions.crypt` / `extensions.gen_salt('bf', 10)` are schema-qualified because
`search_path` is pinned to `public` and pgcrypto lives in `extensions`. Cost 10 is what
GoTrue writes itself.

**Verified against the live database, not just compiled:**

| Check | Result |
|---|---|
| Old 2-arg signature dropped, no overload left behind | one signature: `admin_add_admin(text,text,text)` |
| `anon` cannot execute, `authenticated` can | `f` / `t` |
| Non-admin caller | refused — "You are not a Zopiqnow admin." |
| Bad email · blank name · already an admin | each refused with its own sentence |
| New address with no password · too short · trailing space | each refused |
| Existing account **+ a password** | refused; the existing password is not clobbered |
| Existing account **+ blank password** | admin row written, no second `auth.users` row |
| New account created | `aud`/`role` = `authenticated`, `$2a$10$` hash, email confirmed, every token column `''`, identity row correct |
| **Sign-in over HTTP** | `POST /auth/v1/token?grant_type=password` → **200** with a real session — no `{}` 500 |
| `is_admin()` over PostgREST with that token | `true` |
| `admin_list_admins` with that token | 200, returns the roster including the new admin |
| Wrong password | 400 |

The probe account was deleted afterwards — `auth.users`, `auth.identities`,
`auth.sessions` and `platform_admins` all back to zero rows for that address.

The migration drops both the old and the new signature before creating, so re-running the
file is not an error. The CLI ledger and this database have disagreed before, and a
migration that only applies to a schema in exactly one state is one that gets hand-edited
the day that happens.

**Console side.** The form gained a Password field spanning both columns, typed `text`
rather than `password` (whoever fills this in has to read it back to the person it belongs
to — it is not mailed, and cannot be shown again — and a row of dots is how a handover
password becomes a lockout) with `autoComplete="off"` so the browser does not offer to
save somebody else's credential under this site. The RPC's returned sentence is shown in a
success banner verbatim, because it is the only thing that knows which of the two cases
happened. The false copy about a code sent to that address is gone.

**Still open, deliberately:** an admin cannot change their own password from the console.
Supabase's `updateUser({ password })` would do it for the signed-in user; there is no UI
for it yet. That is the natural follow-up, and it is what A3 should be resolved against.

### A2 — A network blip at load locks a real admin out of the console
- [ ] `src/auth/session.tsx:60`

`resolve()` treats an `is_admin()` RPC **error** and an `is_admin()` answer of **false**
as the same outcome: `setIsAdmin(false)`. Failing closed is right. Rendering the same
screen for both is not.

An admin whose first `is_admin()` call fails on a flaky connection lands on
`NotAdminPage` — "This console is for Zopiqnow staff" — whose only control is Sign out.
Nothing there suggests retrying, and nothing retries on its own until an auth state
change happens to fire.

**Fix:** keep failing closed, but carry the error out of `resolve()` and give
`NotAdminPage` a "Try again" that re-runs the check when the cause was a network failure
rather than a denial.

### A3 — No way back in from a forgotten password
- [ ] Decision needed. `src/auth/SignInPage.tsx`

No reset link, by design — the comment argues any reset is a way into an ops console that
does not start from an existing admin. That reasoning holds, but the consequence is that a
forgotten password is a permanent lockout requiring SQL, and there is no runbook for it.

**Fix:** either write the recovery procedure into `apps/admin-web/README.md`, or add a
reset restricted to addresses already in `platform_admins`. Your call — flagging it so it
is a decision rather than an omission.

---

## B. Layout that is visibly broken

### B1 — Three pages render with no page padding at all
- [x] **Done** — `src/support/SupportPage.tsx`, `src/gifts/GiftOrdersPage.tsx`,
      `src/content/OrderAdsPage.tsx`

Every other screen wraps its body in `<div className="p-6">` under the `PageHeader`.
These three did not, so their tables, banners and cards sat flush against the shell's left
edge and the window's right edge — while the sticky header above them carried its own
`px-6`, which is what made it read as broken rather than merely tight.

All three now have the wrapper. The diff is large but almost entirely re-indentation of
what the new wrapper contains; `git diff -w` shows the real change is one added line and
one closing tag per page.

### B2 — Five Tailwind classes name colours that do not exist
- [x] **Done** — `src/support/SupportPage.tsx`, `src/gifts/GiftOrdersPage.tsx`,
      `src/riders/RidersPage.tsx`

`src/index.css` defines thirteen colour tokens. `surface` and `hairline` are not among
them, and Tailwind v4 emits nothing at all for an unknown token — no error, no fallback,
just an absent rule. Confirmed before the fix: `grep -c bg-surface` against the built CSS
returned `0`.

| Where | Was | Now |
|---|---|---|
| Support ticket table | `bg-surface` — transparent, grey canvas showing through | `bg-white` |
| Support complaint quote | `bg-surface-2` — no fill, did not read as a quote | `bg-canvas` |
| Gift orders table | `bg-surface` — same transparent table | `bg-white` |
| Rider engagement radio cards | `border-hairline` — **unselected options had no border at all** | `border-line` |
| Rider employer dropdown | `border-hairline bg-surface` — a `<select>` with neither | `border-line bg-white` |

The stray `rounded-xl` on those elements went to the house `rounded-[12px]` / `rounded-[8px]`
at the same time, since they were the only four uses of it on these surfaces.

**Verified, not assumed.** A sweep of every colour utility in `src/**/*.tsx` against the
`--color-*` names in `index.css` now comes back with an empty "used but not defined" list,
and the rebuilt CSS carries real declarations for the replacements
(`.bg-white{background-color:var(--color-white)}`, `.bg-canvas{…var(--color-canvas)}`).
That sweep is worth re-running after any future styling work — it is the only thing that
catches this class of bug, because the build stays green either way.

### B3 — The evidence modal squeezes three photos into a 448px dialog
- [ ] `src/orders/AllOrdersPage.tsx:459`

The photos modal takes the default `size="md"` (`max-w-md`) and puts a
`sm:grid-cols-3` grid inside it. Each photograph lands at roughly 120px square. Support
opens this to look at a receipt taped to a bag.

`SupportPage`'s own copy of the same three photos is a deliberate glance, and small is
correct there. This one is the dedicated viewer.

**Fix:** `size="lg"` on the modal.

### B4 — The restaurant status filter is the only filter row in the console that is not a `SegmentedControl`
- [ ] `src/restaurants/RestaurantsPage.tsx:112-127`

Hand-rolled `<button>` pills, active state `bg-ink text-white` — dark navy chips, against
the orange `bg-brand-soft text-brand-deep` that Orders, Support, Refunds, Alerts, Users,
Settlements, Payouts and Gift orders all use. They also carry no `role="radio"`, no
`aria-checked` and no `type`, so a screen reader reads five unrelated buttons and never
says which one is on.

**Fix:** swap for `SegmentedControl<Status | 'all'>`.

---

## C. Wrong numbers and wrong dates

### C1 — A coupon's end date expires the coupon eighteen hours early
- [ ] **High.** `src/coupons/CouponsPage.tsx:115`

```ts
valid_until: draft.valid_until ? new Date(draft.valid_until).toISOString() : null
```

`draft.valid_until` comes from `<input type="date">`, so it is `"2026-09-30"`. ECMAScript
parses a bare date-only string as **UTC midnight**, not local midnight. `toISOString()`
then hands Postgres `2026-09-30T00:00:00Z` — which is 05:30 IST on the 30th.

A coupon an admin set to run until the 30th dies at half past five that morning. The
round trip compounds it: `valid_until.slice(0, 10)` on edit reads the UTC date back, so a
late-evening timestamp reloads as the previous day.

**Fix:** build the instant in local time and take end-of-day —
`new Date(`${draft.valid_until}T23:59:59`)` — and format the value back for the input from
the local date parts rather than slicing the ISO string.

### C2 — Refunds says "₹0 still to send" whenever you are on the Closed tab
- [ ] `src/payouts/RefundsPage.tsx:122,132`

`owed` sums `rows`, and `rows` is already narrowed by the active filter. On **Closed**,
every row is `paid` or `declined`, the sum is zero, and the header states as fact that
nothing is owed — while the Open tab, one click away, is full of money.

**Fix:** keep the unfiltered list in state and derive both `rows` and `owed` from it, so
the header answers the same question on every tab.

### C3 — `new Date().toISOString().slice(0, 10)` is yesterday until 05:30 IST
- [ ] Low. `src/restaurants/steps/LegalStep.tsx:119`,
      `src/restaurants/steps/ReviewStep.tsx:20`, `src/riders/RidersPage.tsx:628`

The same UTC-vs-local slip as C1, in the other direction. Between midnight and 05:30 IST
this yields the previous day, so an FSSAI licence that expires today reads as still valid,
and the KYC override's `min` date allows a date already past.

**Fix:** one shared `todayLocal()` helper built from `getFullYear/getMonth/getDate`, used
in all three places.

---

## D. Actions that let you do the wrong thing

### D1 — A support ticket can be closed with an empty reply, and the customer sees nothing
- [ ] **High.** `src/support/SupportPage.tsx:309`

"Mark answered" is never disabled. `admin_resolve_ticket`
(`0095_a_customer_with_a_complaint.sql:295`) declares `p_note text default null` and
normalises blank to null, so the database accepts it happily.

The field's own hint says *"The customer reads this on their own order screen."* A
one-click close therefore resolves somebody's complaint and tells them nothing, and the
ticket cannot be reopened — that is stated as a design rule in the same file.

**Fix:** `disabled={reply.trim() === ''}`, matching how Live orders gates Cancel and
Refunds gates Decline.

### D2 — An order can be destroyed with no reason recorded
- [ ] **High.** `src/orders/AllOrdersPage.tsx:511`

The Delete button is gated on typing the order id and on nothing else.
`admin_delete_order` takes `p_reason text default ''` and stores
`left(trim(coalesce(p_reason, '')), 200)`, so blank is stored as blank.

The field's hint reads *"It is the only record that will remain"* — and for a delivered,
invoiced order it genuinely is: the row, its items, its delivery, its messages and the
customer's review all go, leaving a permanent gap in that restaurant's GST invoice series.
An empty string is not a record.

**Fix:** add `reason.trim() !== ''` to the `disabled` expression.

### D3 — Editing a coupon's code creates a second coupon instead of renaming it
- [ ] `src/coupons/CouponsPage.tsx:263`

`admin_save_coupon` is an upsert keyed on `p_code`. The Code field stays editable when
editing an existing coupon, so changing `WELCOME50` to `WELCOME60` and saving leaves
`WELCOME50` live and creates `WELCOME60` alongside it. The modal title already betrays
this — it flips from the code to "New coupon" the moment the field is touched.

**Fix:** make the Code field read-only when the draft came from an existing row (track an
`isNew` flag on `Draft`), with a hint saying a code cannot be renamed.

### D4 — A percentage coupon with no cap prints "20% off up to ₹null"
- [ ] Low. `src/coupons/CouponsPage.tsx:40-44`

`worth()` interpolates `c.max_off` without a null guard. Save sends `Number('') → 0` for a
blank cap, so this needs both the read guard and a save-side check.

**Fix:** guard the render, and disable Save when a percentage coupon has no cap — the
form's own hint already calls an uncapped percentage "an open cheque".

---

## E. States a screen cannot get out of

### E1 — If the reach count fails, Send is disabled forever and nothing says why
- [ ] `src/broadcast/BroadcastPage.tsx:92`

```ts
.catch(() => { if (live) setReach(null) })
```

`ready` requires `reach !== null && reach > 0`, so a failed count disables Send
permanently. The line beside the audience picker reads "Counting…" and never stops. The
error is swallowed, so the page looks like it is still working.

**Fix:** hold the failure in state, show it, and offer a retry. Keep Send disabled — the
confirmation is *about* that number — but say so.

### E2 — Two stacked modals fight over Escape and over Tab
- [ ] `src/users/UsersPage.tsx:127,550`

"Block this person" is inside the open `UserSheet`, and `setConfirming` mounts
`BlockDialog` on top without closing the sheet. Both are `<Modal>`, and `Modal` registers
its key handler on `document` in the capture phase.

- **Escape** calls `e.stopPropagation()`, which does not stop sibling listeners on the
  same node — that needs `stopImmediatePropagation`. So one Escape closes the confirmation
  *and* the person sheet behind it.
- **Tab** runs both focus traps. Each tries to wrap focus into its own panel, and whichever
  runs second wins, so tabbing inside the confirmation lands unpredictably on the sheet.

**Fix:** the narrow version is `stopImmediatePropagation` plus having only the topmost
`Modal` act — a small mounted-instance counter inside `primitives.tsx`. The simpler
version is to close `UserSheet` when `BlockDialog` opens, since the sheet is refetched on
reopen anyway.

### E3 — The live board's confirmation dialog reads from a snapshot the poller has replaced
- [ ] Low. `src/orders/LiveOrdersPage.tsx:113`

`acting` holds a captured `AdminOrderRow`. The 15-second poll calls `setRows` underneath
it, so an open "Release rider" dialog can go on naming a rider who has since been changed
— and the confirm still fires against the order id, which is right, but the sentence the
admin read may not be.

**Fix:** pause the poll while `acting !== null`, or re-derive the row from `rows` by id on
each render.

### E4 — Deleting the last order on a page leaves an empty page with no way forward
- [ ] Low. `src/orders/AllOrdersPage.tsx:197`

`confirmDelete` reloads at the same `page`. If that page held one row, the reload returns
nothing, `total` becomes 0, and the pager disappears — including the Previous button.

**Fix:** after a delete that empties the page, step back one page when `page > 0`.

---

## F. Smaller gaps

### F1 — Two order statuses cannot be filtered on
- [ ] `src/orders/AllOrdersPage.tsx:57-65`

`statusOptions` omits `accepted` and `ready_for_pickup`, though both are valid
`OrderStatus` values that `admin_all_orders` accepts. "Everything the kitchen has taken but
not started" is not askable.

### F2 — Gift orders cannot be filtered to delivered or cancelled
- [ ] `src/gifts/GiftOrdersPage.tsx:31-36`

Same shape: `placed`, `accepted`, `dispatched`, `all`. Finding one delivered gift means
paging through All.

### F3 — Six pages leave an error banner with no dismiss
- [ ] `src/restaurants/RestaurantsPage.tsx`, `src/users/UsersPage.tsx`,
      `src/settings/SettingsPage.tsx`, `src/settlements/SettlementsPage.tsx`,
      `src/payouts/CashPage.tsx`, `src/support/SupportPage.tsx`

`Banner` takes `onDismiss` and most screens pass it. On these, an error sticks until the
next action clears it.

### F4 — `exhaustive-deps` is not enforced, and one effect already relies on that
- [ ] `.oxlintrc.json`, `src/restaurants/RestaurantsPage.tsx:44`

`load` there is a plain function, not a `useCallback`, and its effect has `[]` for
dependencies. Harmless today because `load` closes over nothing that changes — but the
rule that would have caught it is off, and this is the class of bug that arrives silently
during a refactor.

### F5 — Wizard step tabs scroll away under the sticky header
- [ ] Low. `src/restaurants/WizardPage.tsx:103`

`PageHeader` is `sticky top-0`. The step bar immediately below it is not, so on the Menu
step — the one long enough to scroll — the eight steps leave the screen and the header
stays.

### F6 — `only-export-components` warnings
- [ ] Low. `src/auth/session.tsx:114`, `src/ui/MapPicker.tsx:60`

The two lint warnings. Cosmetic (they cost a full reload instead of a hot update in dev),
but they are the only two and clearing them makes a clean lint run mean something.

---

## Not findings — checked and correct

Recorded so they are not re-audited:

- All **105** RPC names in `src/lib/api.ts` resolve to a function defined in
  `supabase/migrations/`. `admin_list_refunds` is defined with bare `create function`
  in `0077`, redefined in `0115` and `0116`; the last definition survives.
- The only Supabase call outside `api.ts` is `is_admin()` in `session.tsx:55`. Nothing
  reaches a table directly — the whole console goes through named `security definer`
  functions, as documented.
- `.env.local` and `dist/` are both untracked (`*.local` and `dist` in `.gitignore`).
  Only the anon key reaches the browser.
- No `dangerouslySetInnerHTML`, no `target="_blank"` without `rel="noreferrer"`, no
  stray `console.log`, `alert()`, `TODO` or `FIXME` in `src/`.
- `vercel.json` sets `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff` and a
  `strict-origin-when-cross-origin` referrer policy.
- The `session.tsx` `loading` handling is right, and the comment explaining why
  `onAuthStateChange` must not raise it again is worth keeping.
