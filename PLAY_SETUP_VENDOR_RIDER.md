# Play Console setup — Zopiq Partner and Zopiq Rider

Everything Play asks before it will accept a release, with the answer already
decided. Work down it; nothing here needs a judgement call except the two things
flagged **YOU DECIDE**.

The detail behind these answers is in `PLAY_DATA_SAFETY.md` — this file is the
click-by-click version for the two apps that have no listing yet.

> **Why Claude cannot do this part.** These are forms in your browser, signed in
> as you. The Play API covers releases, not listings — there is no endpoint for
> content rating, data safety, or store copy. The upload half is automated; this
> half is not automatable by anyone.

---

## 0. The one thing to create first: a demo mailbox

~~Both apps sign in with an email OTP and nothing else.~~ **Superseded — both
apps now have Google Sign-In.** A reviewer signs in with a demo Google account
from the system picker, with no code to relay out of a mailbox. You still supply
that account and its password in App access, but the fragile step is gone. See
OAUTH_SETUP_VENDOR_RIDER.md for the two client registrations this needs.

The original problem, for the record: Supabase has no fixed test-OTP
for email (it has one for SMS only — checked, `sms_test_otp`), so there is no way
to hand out a code that always works.

The way through: **create one throwaway Gmail** — say `zopiqdemo2026@gmail.com` —
and give Google that address *and its password* in the App access form, with
instructions to read the OTP from it.

Do not reuse `zopiqnow@gmail.com` or `zopiqnow2026@gmail.com`. The first is your
developer account and the second sends your OTP email; neither password should
ever be typed into a Google form.

**Tell Claude the address once it exists** and it will be wired up as restaurant
staff *and* as a delivery partner in the database, so the same login works in both
apps.

---

## 1. Store listing (both apps)

| Field | Zopiq Partner | Zopiq Rider |
|---|---|---|
| App name | `Zopiq Partner` | `Zopiq Rider` |
| Short description | `Manage your restaurant's orders and menu on Zopiqnow.` | `Accept deliveries and get paid, on Zopiqnow.` |
| Category | Business | Business |
| Email | `zopiqnow@gmail.com` | `zopiqnow@gmail.com` |
| Privacy policy | `https://nayansuthar-1.github.io/zopiqnow/privacy.html` | same |

That privacy URL is live — verified, HTTP 200.

**Full description** — Partner:

> Zopiq Partner is for restaurants listed on Zopiqnow. Accept incoming orders,
> set preparation times, manage your menu and pricing, mark dishes unavailable,
> and track what you have earned. Orders arrive as notifications so nothing is
> missed during service.

**Full description** — Rider:

> Zopiq Rider is for delivery partners working with Zopiqnow. See delivery
> offers near you, navigate to the restaurant and the customer, confirm handover
> with a delivery code, and track your earnings and payouts.

**Graphics needed** (Play will not let you publish without them):

- App icon, 512×512 PNG
- Feature graphic, 1024×500
- At least 2 phone screenshots each — take them from the running app

---

## 2. App content — the forms that block releases

### Privacy policy
Paste the URL above. Both apps.

### App access
**Not** "all functionality available without special access" — both require login.

Choose *All or some functionality is restricted*, add one instruction set:

- **Name:** `Demo login`
- **Username:** the demo Google account from step 0
- **Password:** that account's password
- **Instructions:**
  > Add this Google account to the device (Settings → Accounts → Add account →
  > Google), then open the app and tap **Continue with Google** and choose it.
  > No emailed code is needed.
  >
  > An emailed 6-digit code also works if you prefer: enter the same address on
  > the sign-in screen, tap Send code, and read the code from that mailbox.

The Google route is the one to lead with — it is the one that does not depend on
mail arriving during review.

### Ads
**No**, both apps. There is no ad SDK in either.

### Content rating
Answer the questionnaire; for both apps every question is **No**. Category
**Utility / Productivity / Communication**. Expected result: rated for everyone.
`PLAY_DATA_SAFETY.md` line ~291 has the reasoning behind each answer.

### Target audience
**18 and over**, both. Not designed for children; no child-directed content.

### Data safety
⚠️ **Do the two forms separately. Rider is not a copy of Partner.**

**Zopiq Partner** — collected, all linked to the user, none sold or shared:

- Personal info → Email address, Name, Phone number *(account management)*
- Photos → *(menu photography; app functionality)*
- App activity → none
- Crash logs and diagnostics → *(Crashlytics)*

**Zopiq Rider** — everything above, plus the two that matter:

- **Location → Precise location.** Collected **in the foreground, during an active
  delivery only**. Purpose: app functionality. This also needs the prominent
  in-app disclosure, which the app already shows.
- **Personal info → Other info** — KYC documents: driving licence, insurance,
  ID, vehicle registration.

**Tick nowhere on the form:** advertising or marketing, tracking, data sold to
third parties. The privacy policy says none of that happens and the form has to
agree. `PLAY_DATA_SAFETY.md` line ~141 lists the rest of the do-not-tick set.

### Government apps / Financial features / Health
No, no, no — both apps.

---

## 3. Then Claude ships them

Once each app exists with App content complete:

```bash
node tool/ship.mjs vendor internal
node tool/ship.mjs rider internal
```

Both bundles already build, are signed, and target API 36.

---

## YOU DECIDE — two things

1. **Should these be public at all?** Partner and Rider are staff tools. Play has
   no "internal only" distribution short of Managed Google Play, so a production
   listing is publicly installable by anyone — they just cannot sign in. Most
   delivery platforms accept that. If you would rather they never went public,
   keep both on a closed track for ever and skip production entirely.
2. **The demo account's password goes to Google either way.** App access requires
   credentials for an app behind a login, and no sign-in method avoids that.
   Google Sign-In removed the *fragile* half — the mailbox round-trip — not the
   password. Which is why it should be a throwaway account that owns nothing.
