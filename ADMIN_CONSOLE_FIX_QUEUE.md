# Admin console — fix queue

Audit of `apps/admin-web/` on 2026-09-01, against `main` at `f2dd99a`.

**State of the build:** `tsc -b` is clean. `oxlint` reports two `only-export-components`
warnings and nothing else. Nothing below is a compile error — every item is something
that is wrong at runtime, wrong on screen, or wrong in what it tells the person using it.

Twenty-two findings. Worked one at a time, top to bottom. Tick the box when it lands.

**Done so far:** A1, and all of B, C, D, E and F. A2 and A3 are what is left — one
fix and one decision.

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
- [x] **Done** — `src/orders/AllOrdersPage.tsx:456`

The photos modal took the default `size="md"` (`max-w-md`) and put a `sm:grid-cols-3` grid
inside it, so each photograph landed at roughly 120px square. What support is usually doing
here is reading a receipt taped to a bag.

Now `size="lg"` (`max-w-2xl`). `SupportPage`'s own copy of the same three photographs stays
small deliberately, and the code now says why: there they sit beside a complaint being
read, and this is the dedicated viewer. Full size is one click away in both.

### B4 — The restaurant status filter is the only filter row in the console that is not a `SegmentedControl`
- [x] **Done** — `src/restaurants/RestaurantsPage.tsx:134`

Hand-rolled `<button>` pills with an active state of `bg-ink text-white` — dark navy chips,
against the orange `bg-brand-soft text-brand-deep` that every other filter row uses. They
also carried no `role="radio"`, no `aria-checked` and no `type`, so a screen reader read
five unrelated buttons and never said which one was on.

Replaced with `SegmentedControl<Status | 'all'>`, which is a real `radiogroup` and brings
the focus ring with it. The five choices moved into a `filterOptions` constant beside
`statusLabels`, written out rather than derived, so that `'all'` — which is not a `Status`
and has no `statusLabels` entry — is not a special case threaded through a map.

**Verified:** a sweep for the old pill styling (`rounded-full px-3 py-1.5`, `bg-ink
text-white`) now returns nothing, and fourteen files import `SegmentedControl`. `bg-ink`
survives in exactly one place, which is the modal backdrop's `bg-ink/40` — where it belongs.

---

## C. Wrong numbers and wrong dates

A date input names a **calendar day**, in the timezone of the desk it was typed at.
`Date` does not: ECMAScript parses a bare `"2026-09-30"` as UTC midnight, which is 05:30
on the 30th here, and `toISOString().slice(0, 10)` is the same mistake read back. All
three findings below were that slip, so all three now go through one small module —
`src/lib/dates.ts`, holding `toDateInput`, `todayLocal` and `endOfDayLocal`, each built
from `getFullYear`/`getMonth`/`getDate`, which are the parts of `Date` that read the local
calendar.

The two other date fields in the console were checked and left alone: `OrderAdsPage` and
`HeroSlidesPage` use `datetime-local`, which ECMAScript parses as **local** time, so
`new Date(value).toISOString()` there is already the instant the admin meant.

### C1 — A coupon's end date expires the coupon eighteen hours early
- [x] **Done** — `src/lib/dates.ts`, `src/coupons/CouponsPage.tsx:120,213,341`

`new Date(draft.valid_until).toISOString()` handed Postgres `2026-09-30T00:00:00Z` for a
coupon set to run until the 30th — 05:30 IST that morning. Now
`endOfDayLocal(draft.valid_until)`, which is that day's last second where it was picked:
`2026-09-30T18:29:59Z`. The read back on edit is `toDateInput(new Date(c.valid_until))`
rather than `slice(0, 10)`, because east of Greenwich an instant in the small hours is
still the previous day in UTC and would reload a coupon as ending the day before the one
it was given. The field's hint now says the code works all of that day, since that is a
promise the form is making and nothing else on screen said it.

Worth noting what the old code did to *today*: `admin_save_coupon` refuses
`p_valid_until <= now()` (0074:171), so setting a coupon to run until today was not merely
short — it was rejected outright, with a sentence about a date in the past on a date the
admin had just picked from a calendar that offered it.

**Verified** under `TZ=Asia/Kolkata`: the saved instant is `2026-09-30T18:29:59.000Z`, it
reads back into the input as `2026-09-30`, and a cart at noon on the 30th sees the coupon
live where the old value had already expired.

### C2 — Refunds says "₹0 still to send" whenever you are on the Closed tab
- [x] **Done** — `src/payouts/RefundsPage.tsx:67,70,90,119`

`load` filtered before it stored, so `rows` — and therefore `owed` — held only the active
tab. State now holds the whole list; `rows` and `owed` are both derived from it, so the
header answers the same question on Closed as on Open. `load` no longer closes over
`filter`, which also means switching tabs no longer re-fetches.

The open-ness test that was written out twice is now one `isOpen` predicate beside the
`Filter` type — it is the question the header asks as well as the one the tabs ask.

### C3 — `new Date().toISOString().slice(0, 10)` is yesterday until 05:30 IST
- [x] **Done** — `src/restaurants/steps/LegalStep.tsx:119`,
      `src/restaurants/steps/ReviewStep.tsx:21`, `src/riders/RidersPage.tsx:629`

All three now call `todayLocal()`. Between midnight and 05:30 the old expression returned
the previous day, so an FSSAI licence expiring today read as still valid on both the Legal
step and the Review checklist, and the KYC dialog's `min` accepted a licence or insurance
expiry that had already passed.

**Verified:** at 02:00 IST on 30 September, `todayLocal()` is `2026-09-30` where the old
expression was `2026-09-29`. `tsc -b` is clean, `oxlint` still reports only the two
pre-existing `only-export-components` warnings (F6), and `vite build` succeeds.

---

## D. Actions that let you do the wrong thing

Three of these are one `disabled` expression each, and the fourth is a field that stops
claiming to be editable. What they have in common is that the database was never the thing
that would stop you: it accepts a blank note, it stores a blank reason, and its upsert does
exactly what an upsert does with a code it has not seen before.

### D1 — A support ticket can be closed with an empty reply, and the customer sees nothing
- [x] **Done** — `src/support/SupportPage.tsx:314`

`disabled={reply.trim() === ''}` on "Mark answered", matching how Live orders gates Cancel
and Refunds gates Decline. `admin_resolve_ticket` normalises a blank note to null and
closes the ticket regardless, and 0095 states in its own comment that a ticket cannot be
reopened — so the one-click close was a complaint resolved, permanently, with nothing said
to the person who raised it. The field's hint already promised the opposite: *"The customer
reads this on their own order screen."*

`reply` is cleared when a ticket is opened (`:122`), so the gate cannot be satisfied by
text left over from the previous ticket.

### D2 — An order can be destroyed with no reason recorded
- [x] **Done** — `src/orders/AllOrdersPage.tsx:521`

`reason.trim() !== ''` joins the typed-id check. The two are doing different jobs and the
comment now says so: typing the id is the pause before deleting the row your mouse happened
to be over, and the reason is what survives. `admin_delete_order` stores
`left(trim(coalesce(p_reason, '')), 200)` — a blank stays blank — and once the row, its
items, its delivery, its messages and the customer's review are gone, that log line is the
only account of an order that existed and was invoiced.

### D3 — Editing a coupon's code creates a second coupon instead of renaming it
- [x] **Done** — `src/coupons/CouponsPage.tsx:53,257,288`, `src/ui/primitives.tsx:139`

`Draft` carries `isNew`, and the Code field is `readOnly` when it is false, with a hint
that says a code cannot be renamed and points at switching it off and writing a new one.
The modal title reads off the same flag instead of inferring newness by looking up the
current text in `rows` — which is what made it flip to "New coupon" mid-edit, and which was
the page telling on itself.

`Field` gained `read-only:bg-canvas read-only:text-ink-muted`, because a read-only field
that looks editable is one somebody types into and wonders why nothing happens. Focus and
selection are untouched — the code is there to be copied. **Verified in the built CSS**,
per B2's lesson: `.read-only:bg-canvas:read-only{background-color:var(--color-canvas)}` is
in `dist`, class-scoped and gated on the attribute, so no other `Field` is affected.

### D4 — A percentage coupon with no cap prints "20% off up to ₹null"
- [x] **Done** — `src/coupons/CouponsPage.tsx:275`. Half of it was not real.

The save-side check shipped: Save is disabled while a percentage coupon has no positive
cap, so the form answers immediately instead of the RPC answering with a banner. That is
what the field's own hint has always implied by calling an uncapped percentage an open
cheque.

**The read guard was not added, because `₹null` cannot be rendered.** `coupons` has carried
`coupon_is_flat_xor_capped_percent` since 0003 — a percentage row without a `max_off` is
not storable — and both writers refuse it with a sentence before the constraint has to
(`admin_save_coupon` 0074:160, `vendor_save_offer` 0064:428). Read off the live database
rather than the migration files, since those two have disagreed before:

| Check | Result |
|---|---|
| `coupon_is_flat_xor_capped_percent` still on the table | present, and unchanged from 0003 |
| `coupons_max_off_check` | `CHECK (max_off > 0)` |
| Rows with `percent_off is not null and max_off is null` | **0** |

A null guard in `worth()` would be a branch that cannot execute, so there is not one.

---

## E. States a screen cannot get out of

### E1 — If the reach count fails, Send is disabled forever and nothing says why
- [x] **Done** — `src/broadcast/BroadcastPage.tsx:62,86,159,172`

The failure is held in `reachError` and shown where the number would have been —
"Counting them failed, so there is no number to send to" — with a **Try again** beside it
and the raw message next to that, small, for whoever has to say what went wrong. An
`attempt` counter in the effect's dependencies is what the retry turns.

Send stays disabled, as the finding asked: the confirmation is a sentence *about* that
number, and offering to send to an audience nobody has counted is worse than not offering.
The difference is that the page now says which of the two it is instead of reading
"Counting…" for ever behind a dead button.

### E2 — Two stacked modals fight over Escape and over Tab
- [x] **Done** — `src/users/UsersPage.tsx:553`, `src/ui/primitives.tsx:391`

Took the simpler of the two options: `UserSheet` closes as `BlockDialog` opens, so there is
never a second `Modal` to argue with. Escape and Tab then have one owner by construction,
which is a stronger guarantee than `stopImmediatePropagation` plus a mounted-instance
counter would have been, and it costs nothing the page was not already doing —
`applyBlock` closes the sheet on success anyway. The only behaviour that changes is where
**Cancel** lands: the table rather than the sheet, which is refetched whenever it reopens.

One thing the swap needed. `Modal`'s unmount effect hands focus back to whatever opened it,
and one dialog closing in the same commit as another opens would have thrown the keyboard
to the control behind *both*. The hand-back is now conditional on nothing else having
claimed focus — `document.activeElement?.closest('[role="dialog"]')` — which makes the
result the same whichever order React runs the two effects in, rather than correct by
accident.

**Swept for other stacks and there are none.** Twelve files mount more than one dialog, but
in every one of them the opener is a row or a toolbar — behind the backdrop, and
unclickable — the moment any dialog is up. `UserSheet`'s footer button was the only opener
that lived *inside* a dialog. The counter in `primitives.tsx` remains the answer if a
second stack is ever wanted deliberately.

### E3 — The live board's confirmation dialog reads from a snapshot the poller has replaced
- [x] **Done** — `src/orders/LiveOrdersPage.tsx:99,120`

The 15-second poll skips a tick while a confirmation is open, through an `actingRef` read
inside the interval — the same shape as the `appliedRef` already there, and for the same
reason: the timer is not torn down and rebuilt. Chose this over re-deriving the row from
`rows` by id, because an order that leaves the live board mid-dialog has no row to
re-derive from and the dialog would have had to handle its own subject vanishing.

The one-second repaint keeps running, so the header goes on counting honestly — "updated
45s ago" is what it now says while a dialog is up, which is true. The action was never
wrong: it fires against an order id. What was wrong was the sentence the admin read before
agreeing to it.

### E4 — Deleting the last order on a page leaves an empty page with no way forward
- [x] **Done** — `src/orders/AllOrdersPage.tsx:210`

`confirmDelete` steps back a page when the row it deleted was the only one on it and there
is a page to step back to, and lets the filter effect do the reload rather than firing a
second one. Deleting the last order on page 1 still leaves page 1 empty — with the pager
gone, which is correct, because there is nothing to page through.

---

## F. Smaller gaps

### F1 — Two order statuses cannot be filtered on
- [x] **Done** — `src/orders/AllOrdersPage.tsx:60,62`

`accepted` and `ready_for_pickup` are in `statusOptions`, in lifecycle order, labelled
from `STATUS_LABEL` like the rest. `admin_all_orders` compares `p_status` to `o.status`
with no allow-list of its own (0069:125), so both were always askable — the console just
never asked.

### F2 — Gift orders cannot be filtered to delivered or cancelled
- [x] **Done** — `src/gifts/GiftOrdersPage.tsx:35`

Same shape, same fix: **Delivered** and **Cancelled** before **All**. `admin_gift_orders`
also filters on a bare `p_status` (0096:545).

### F3 — Six pages leave an error banner with no dismiss
- [x] **Done** — eight banners in seven files. The list in the finding was not right.

`SettlementsPage` and `CashPage` were named but both already pass `onDismiss`. What a
sweep of every `<Banner` in `src/**/*.tsx` actually turns up is seventeen without one, of
which eight are stuck errors:

| File | Where |
|---|---|
| `src/gifts/GiftOrdersPage.tsx:171` | page error |
| `src/restaurants/RestaurantsPage.tsx:148` | page error |
| `src/restaurants/WizardPage.tsx:135` | wizard error |
| `src/riders/RidersPage.tsx:227` | page error |
| `src/settings/SettingsPage.tsx:249` | rider-pay card error |
| `src/support/SupportPage.tsx:175` | page error |
| `src/users/UsersPage.tsx:135` | inside the person sheet |
| `src/users/UsersPage.tsx:450` | page error |

The other nine were left alone deliberately, and are not the same thing: they are `warn`
and `success` banners that *are* the content — the invoice warning in the delete dialog,
the KYC state on a rider, the "no photographs" line in the evidence viewer. A dismiss on
those would offer to hide the answer to the question the screen was asked.
`ImportDialog`'s `headerProblem` is the third kind: a verdict on the file just chosen,
cleared by choosing another.

### F4 — `exhaustive-deps` is not enforced, and one effect already relies on that
- [x] **Done** — `.oxlintrc.json`, `src/restaurants/RestaurantsPage.tsx:61`.
      The second half of the finding does not hold.

`"react/exhaustive-deps": "error"` is on, and the whole of `src/` passes it today — no
suppressions, nothing to clean up first. Verified it is actually running rather than
silently unmatched, by putting a deliberate violation in a scratch file: it was reported,
`react-hooks(exhaustive-deps)`, from the config alone with no CLI flag.

**But the effect the finding names would not have been caught by it.** `load` there was a
plain function declared in the component body and called from an effect with `[]` — and
oxlint's implementation does not flag that shape. Checked directly, with exactly that
shape in a scratch file: nothing. So the rule was never what was holding that line up.

What was holding it up is that `load` closed over nothing that changes. `load` is now a
`useCallback`, with the effect depending on it, like every other list in the console —
which is the shape the rule *does* check, so a future dependency added to it has something
watching.

### F5 — Wizard step tabs scroll away under the sticky header
- [x] **Done** — `src/restaurants/WizardPage.tsx:95`

The header and the step bar are wrapped in one `sticky top-0 z-20` and stick together. No
hard-coded offset: `PageHeader`'s height depends on whether it has a subtitle, and a
`top-[73px]` on the bar would have been a number that goes wrong the first time the copy
above it wraps to two lines.

### F6 — `only-export-components` warnings
- [x] **Done** — `src/auth/context.ts` and `src/ui/mapsKey.ts` are new;
      `src/auth/session.tsx`, `src/ui/MapPicker.tsx`, `src/App.tsx`, `src/ui/AppShell.tsx`,
      `src/settings/SettingsPage.tsx`, `src/restaurants/steps/AddressStep.tsx` follow.

Both warnings were a component file exporting one other thing. `session.tsx` kept
`SessionProvider` and gave up `AdminSession`, `SessionContext` and `useSession` to
`auth/context.ts`; `MapPicker.tsx` kept its component and gave up the browser key and
`mapPickerAvailable` to `ui/mapsKey.ts`. Three import lines moved with them.

**`oxlint` now exits 0 with no output at all**, which is the point of clearing the last two:
a lint run that always prints something is a lint run nobody reads.

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
