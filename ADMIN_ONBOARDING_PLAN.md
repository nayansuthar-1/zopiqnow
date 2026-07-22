# Zopiqnow — Restaurant Onboarding Console (Web)

**Status date:** 2026-07-22
**Scope:** a React + Tailwind web app where a **platform admin** onboards a
restaurant end to end — storefront, address, legal papers, bank details, hours,
commission, the owner's login, and the full menu — and then publishes it so it
appears in the Android customer app.

This is the first non-Flutter surface in the repo and the first admin identity the
platform has ever had.

---

## Decisions locked

- **Admin-only. No self-service.** A restaurant never signs itself up. There is no
  public application form, no pending queue fed by outsiders. The admin has full
  control and is the only one who can create a restaurant. *(User decision, 2026-07-22.)*
- **Admin console lives in the same web app** as the onboarding wizard, at `/admin`,
  gated by a new `platform_admins` table. *(User decision, 2026-07-22.)*
- **Collect everything at onboarding:** FSSAI, GST, PAN, owner name + phone, full
  address, bank account + IFSC. *(User decision, 2026-07-22.)*
- **Stack:** Vite + React 18 + TypeScript + Tailwind + `@supabase/supabase-js`,
  in `apps/admin-web/`. Same Supabase project as the three Flutter apps.
- **Every write is a `security definer` RPC gated on `is_admin()`** — the same rule
  the whole backend already follows. No table is granted `insert`/`update` to the
  browser, and the **service-role key never leaves the server**; the admin's own
  JWT is the authority.

---

## What exists today (analysis)

Read from `supabase/migrations/0001`–`0025` and the vendor app.

### The restaurant record

`public.restaurants` — id `text` **primary key with no default** (rows so far are
hand-seeded `'r1'`…`'r8'`), name, cuisines `text[]`, rating + rating_count,
eta_minutes, price_for_two, is_veg, image_url, promo_text, latitude, longitude,
distance_km, is_active, accepting_orders, commission_bps (default 2000),
search_text (trigger-maintained from name + cuisines).

- `is_active` is **ops delisting a vendor** — the customer feed policy is
  `using (is_active)`. This is our publish gate.
- `accepting_orders` is the *kitchen's* pause switch (`set_accepting_orders`), not ops'.
- Vendors edit seven columns only, via `update_restaurant_profile` (0013). They can
  never touch rating, is_active, or commission.

### Who works where

`public.restaurant_staff (email pk, restaurant_id, role)` — role is `'owner'` or
`'staff'` (0024). Access is granted to an **email address**, which the vendor proves
by receiving an OTP at it. `staff_restaurant_id()` and `staff_role()` are the
predicates behind every vendor policy. Owners can add their own staff in-app; the
**first owner must be created by us**.

### The menu

`public.menu_items` — id defaults to `gen_random_uuid()::text` (0010), restaurant_id,
name, description, price (integer, paise-free rupees, `> 0`), is_veg, is_bestseller,
rating (nullable), image_url (defaults `''`), `category` as **free text on the item**
plus `category_rank` and `item_rank`, `is_available`, `category_available` (0016).
Customer-visible only when `is_available and category_available`.

There is no categories table — a category is the set of items sharing a string. The
web builder must therefore write the same `category` + `category_rank` to every item
in a section, consistently.

### Hours

`public.restaurant_hours (restaurant_id, day_of_week 1–7, opens, closes)` with
`check (closes > opens)`. `restaurant_is_open_now()` treats **no rows as always
open**, and `place_order` refuses a closed kitchen.

### Money

`settlements` computes `net_payable` per period — and there is **nowhere to pay it
to**. No bank details exist in the database at all.

### Gaps this project must close

| Missing | Why it matters |
|---|---|
| No id generator on `restaurants.id` | An admin creating a restaurant has no id to offer, and a client that names a primary key can collide with one |
| No address, city, state, pincode | Riders need a pickup address; the feed's distance is currently a hand-typed number |
| No contact phone / owner name | No way to call a kitchen that stops responding |
| No FSSAI / GST / PAN | Legally required to list a food business in India |
| No bank account anywhere | `settlements.net_payable` has no destination |
| No admin identity | The platform has customers, vendors, and riders — and no one who can create a vendor |
| `rating` is `not null` | A brand-new restaurant will read `0.0` in the feed unless the UI is told to treat `rating_count = 0` as "New" |
| `closes > opens` | An 18:00–01:00 kitchen cannot be expressed. Flagged; handled in Phase 4 |

---

## Build order

Each step is a checkbox with an explicit **verify**. Nothing is "done" until its
verify passes. Work top to bottom; stop at the end of each phase for review.

---

### Phase 0 — Scaffold and admin identity

- [x] **0.1** Create `apps/admin-web/` — Vite + React + TS, Tailwind configured with
      the Zopiq design tokens (`#FC8019` primary) mirrored from `packages/zopiq_ui`.
      Add it to `.gitignore` for `node_modules`/`dist`, and keep it out of the Dart
      workspace (melos discovers packages by `pubspec.yaml`, so no config change needed).
      → **verify:** `npm run dev` serves a blank shell at localhost; `flutter analyze`
      at the repo root is unaffected.
- [x] **0.2** `.env.local` for the web app: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`,
      `VITE_CLOUDINARY_CLOUD_NAME`, `VITE_CLOUDINARY_UPLOAD_PRESET`. Anon key only —
      never the service role. Add to `.gitignore`.
      → **verify:** a smoke query against `restaurants` returns the 8 seeded rows.
- [x] **0.3** Migration `0026_platform_admins.sql`: `platform_admins (email pk,
      name, created_at)` with the lowercase check, RLS on and **no select policy**,
      plus `is_admin()` — `security definer`, `stable`, reading `auth.jwt() ->> 'email'`.
      Seed `manav@siteonlab.com`.
      → **verify:** `select is_admin()` returns true signed in as manav, false/null otherwise.
- [x] **0.4** Email-OTP login screen using the existing Supabase auth (Brevo SMTP,
      already live). On sign-in, call `is_admin()`; a non-admin is signed straight
      back out with "This console is for Zopiqnow staff."
      → **verify:** manav@ reaches the shell; a customer email is rejected.
      *(Built and building clean; the browser round-trip needs a real OTP, so the
      final sign-in check is the user's to make.)*

---

### Phase 1 — Schema for everything onboarding collects

One migration per concern, so a mistake rolls back cleanly.

- [x] **1.1** `0027_restaurant_id_and_contact.sql`
      - `alter table restaurants alter column id set default gen_random_uuid()::text`
      - add `owner_name text`, `contact_phone text`, `address_line text`, `city text`,
        `state text`, `pincode text` (checked `^[1-9][0-9]{5}$` when present)
      - all nullable, because the eight seeded rows have none of it
      → **verify:** an insert with no id succeeds; the seeded rows still read fine in the customer app.
- [x] **1.2** `0028_restaurant_legal.sql` — `restaurant_legal (restaurant_id pk,
      fssai_number, fssai_expiry date, fssai_doc_url, gst_number, pan_number,
      pan_doc_url, updated_at)`. RLS on, **admin-only select/write** (via RPC).
      A vendor must not be able to read or edit their own licence numbers.
      → **verify:** a vendor JWT selecting the table gets zero rows.
- [x] **1.3** `0029_restaurant_bank.sql` — `restaurant_bank_accounts (restaurant_id pk,
      account_holder, account_number, ifsc checked `^[A-Z]{4}0[A-Z0-9]{6}$`, bank_name,
      verified boolean default false, updated_at)`. Admin-only, same as legal.
      → **verify:** vendor JWT reads nothing; admin RPC round-trips a record.
- [x] **1.4** The write surface — **split into two migrations**, because the
      restaurant and its menu are separate concerns and one file would have been
      900 lines. Every function is `security definer` + `set search_path = public`,
      opens with `perform assert_admin()`, and has `execute` revoked from `public`
      (Postgres grants it by default, so a bare `grant … to authenticated` would
      have left the door open to `anon`).
      - `0030_admin_restaurant_rpcs.sql` — `assert_admin`, `admin_create_restaurant`,
        `admin_update_restaurant`, `admin_list_restaurants`, `admin_get_restaurant`,
        `admin_set_legal`, `admin_set_bank`, `admin_set_hours`, `admin_add_staff`,
        `admin_set_staff_role`, `admin_remove_staff`, `admin_publish_restaurant`,
        `admin_unpublish_restaurant`
      - `0031_admin_menu_rpcs.sql` — `admin_list_menu`, `admin_upsert_menu_item`,
        `admin_delete_menu_item`, `admin_reorder_menu`, `admin_rename_category`,
        `admin_set_category_available`
      - **Deviations from the sketch above:** commission folded into
        `admin_update_restaurant` rather than its own `admin_set_commission` (same
        table, same guard, one fewer thing to keep in step); `admin_get_restaurant`
        and `admin_list_menu` added, because an admin cannot read a draft or a
        sold-out dish through RLS at all; the publish gate implemented here in full
        rather than deferred to 6.2, so Phase 6 builds UI against a finished rule.
      → **verify:** ✅ six representative RPCs each raise *"You are not a Zopiqnow
        admin."* under a vendor JWT and succeed under manav's.
- [x] **1.5** Apply 0026–0032 to the live project and re-check the vendor and
      customer surfaces against it.
      → **verify:** ✅ full lifecycle exercised — draft created with a generated id,
        all eight publish-gate refusals fired with their own sentences, menu ranks
        auto-assigned, publish flipped `is_active`, `rating` ignored when an admin
        tried to set it, last-owner removal refused, bank returned as last-4 only.
        Vendor policies unchanged (own menu 9 items, own restaurant, role `owner`);
        the 8 seeded restaurants and 72 menu items intact; test row cascaded away.
- [x] **1.6** `0032_unlisted_menus_are_not_public.sql` — **unplanned, found by the
      1.5 verification.** A draft restaurant was correctly invisible to the anon key
      while its entire menu was not: `menu_items`' public policy asked only
      `is_available and category_available`, never whether the restaurant was
      listed. Not exploitable into an order (`place_order` refuses an inactive
      restaurant), but an unlaunched kitchen's dishes and prices were world-readable.
      The policy now joins back to `restaurants.is_active`, like `restaurant_hours`
      already did. The vendor's own read policy is untouched — a delisted kitchen
      must still see its menu.
      → **verify:** ✅ draft menu now 0 items to anon; live r1 menu still 9.

---

### Phase 2 — Console shell and restaurant list

- [x] **2.0** `0033_published_at.sql` — **added during the phase.** The four pills
      below need a fact the database did not hold: `is_active = false` meant only
      one thing (ops delisted them) until 0030 made it mean two. A nullable
      `published_at`, set on *first* publish, separates *not yet* from *not any
      more*; the eight seeded rows are backfilled from `created_at`.
      `admin_list_restaurants` was dropped and rebuilt to carry it — a `returns
      table` shape cannot be widened by `create or replace`.
      → **verify:** ✅ all 8 seeded rows backfilled; republishing a delisted
        restaurant keeps its original publish date.
- [x] **2.1** App shell: sidebar (Restaurants · Add restaurant · Settings), top bar
      with the signed-in admin, sign-out. Clean and restrained — no glow, no neon.
      → **verify:** builds clean; sidebar collapses to a tab row under `md`.
- [x] **2.2** Restaurant list from `admin_list_restaurants()`: name, city, status
      pill (**Draft** / **Live** / **Paused by kitchen** / **Delisted**), menu item
      count, owner email. Search + status filter.
      → **verify:** ✅ 9 rows returned with a test restaurant present, statuses
        deriving correctly. Status is computed from `is_active` + `accepting_orders`
        + `published_at`, never stored — a status column would be a third thing
        that could disagree with the two that already answer the question.
- [x] **2.3** Row actions → open the wizard in edit mode, or delist behind a
      confirmation naming the consequence.
      → **verify:** ✅ delisting a published test restaurant dropped the anon feed
        from 9 to 8 and moved its pill to Delisted; republishing restored it.
        **Not** tested on r8 as originally written: r8 would fail today's publish
        gate (no address, no licence, no bank), so delisting it would have stranded
        a real restaurant off the platform with no way back.

---

### Phase 3 — Onboarding wizard, steps 1–3 (the restaurant)

A stepper with a **persistent draft**: step 1 creates the row (`is_active = false`),
every later step saves against its id. Closing the browser loses nothing.

- [x] **3.1 Step 1 — Storefront.** Name, cuisines (multi-select with free entry),
      price for two, pure-veg toggle, promo line, prep time (eta_minutes), cover photo
      → unsigned Cloudinary upload, store the returned URL. `rating` / `rating_count`
      seed to 0.
      → **verify:** ✅ draft created with `is_active = false`, `published_at` null,
        rating 0/0 — and invisible in a plain `select` even to the admin's own
        `authenticated` role, which is the customer-facing policy doing its job.
- [x] **3.2 Step 2 — Address & contact.** Owner name, contact phone (10-digit),
      address line, city, state, pincode, latitude/longitude (paste or map pick),
      `distance_km` left 0 until delivery zones land.
      → **verify:** ✅ every field round-trips; step 1's name/cuisines/veg survive a
        step 2 save untouched (the `p_profile ? 'key'` partial update); clearing a
        field to empty stores null without touching its neighbours.
- [x] **3.3 Step 3 — Legal.** FSSAI number + expiry + document upload, GST number
      (15-char format check), PAN + document upload. Documents to a **private
      Supabase bucket** (see 3.0), not Cloudinary.
      → **verify:** ✅ `restaurant_legal` row written and read back; `"NOTAPAN"` →
        *"That PAN doesn't look right."*, a 3-digit FSSAI → *"An FSSAI licence
        number is 14 digits."*, and an expired licence is refused at publish.
- [x] **3.0** `0034_restaurant_docs_bucket.sql` — **the open question, settled.**
      Private `restaurant-docs` bucket; admin-only policies on select/insert/update/
      delete, each naming the bucket so they do not grant the run of all storage.
      `restaurant_legal.*_doc_url` renamed to `*_doc_path`, because a column called
      `url` holding a bucket path is a small lie that costs someone an afternoon
      later — free to fix while the table has no rows.
      → **verify:** ✅ anon upload → *"new row violates row-level security"*; anon
        download → 404; the public-URL route → *"Bucket not found"*.
- [x] **3.4** `0035_address_gets_sentences.sql` — **added after 3.2's verify.** The
      address constraints from 0027 had no matching sentence in the RPC, so a bad
      phone came back as a raw `violates check constraint` dump. The constraints are
      unchanged — they are the guard; this is the explanation.
      → **verify:** ✅ *"An Indian mobile number is 10 digits starting 6, 7, 8 or 9."*,
        *"A pincode is 6 digits and cannot start with a zero."*, *"That latitude is
        not a real place."*, *"Commission has to be between 0% and 100%."*

---

### Phase 4 — Steps 4–6 (money, hours, the owner's login)

- [x] **4.1 Step 4 — Bank & commission.** Account holder, account number
      (entered twice, **paste disabled** — pasting the same wrong number twice
      defeats the only check this field exists for), IFSC format-checked and
      uppercased, bank name; commission in percent, stored as `commission_bps`.
      The stored number is never sent back to the browser, so the field starts
      empty and the screen shows the last four digits of what is on file.
      → **verify:** ✅ 17.5% → 1750 bps; a bad IFSC → *"That IFSC code doesn't look
        right."*; the account survives a save that does not mention it (see 4.4).
- [x] **4.2 Step 5 — Hours.** Seven day rows, open/closed toggle, time pickers,
      "copy to all days". **Decided 2026-07-22: support overnight properly** rather
      than the split-row workaround this plan originally sketched — the workaround
      leaves the vendor looking at two confusing rows in their own app and unable
      to edit either without breaking the pair.
      `0036_overnight_hours.sql` widens `closes > opens` to `closes <> opens`,
      teaches `restaurant_is_open_now()` that `closes < opens` crosses midnight
      (and to look at *yesterday's* row at 00:30), and the vendor app's Dart
      validation is updated in the same commit so a kitchen can set it there too.
      → **verify:** ✅ nine scenarios through the rewritten logic — Mon 19:00 open,
        Mon 17:59 closed, **Tue 00:30 open under Monday's row**, Tue 01:30 closed,
        Sun→Mon wrap open, and a normal day still closed at exactly its closing
        time. `flutter analyze` clean, all 62 vendor tests pass.
      → **behaviour change:** the window is now half-open (`>= opens and < closes`)
        where 0018 used `between`. A kitchen closing at 22:00 is closed at 22:00;
        the old version accepted an order at exactly 22:00:00.
- [x] **4.3 Step 6 — Team.** Owner email (this is the vendor app login), optional
      extra staff, role changes and removal in place.
      → **verify:** ✅ owner + staff added and read back lower-cased; an address
        already on another restaurant's team is refused by name. **Still owed:**
        the owner email actually signing into the vendor Flutter app — needs a real
        inbox, so it is yours to confirm.
- [x] **4.4** `0037_partial_saves_do_not_erase.sql` — **a bug I wrote, caught by
      4.1's verify.** `admin_set_bank` was a plain upsert, so a key absent from the
      payload was written as null. The bank step deliberately omits the account
      number unless it is being replaced — correct on the client, destructive on the
      server: an admin fixing a typo in the bank's name would have wiped the account
      settlements are paid to, and the only symptom would be a publish gate that
      suddenly failed. Both `admin_set_bank` and `admin_set_legal` now use the same
      `?` presence test `admin_update_restaurant` had from the start: **absent means
      leave it, present-and-empty means clear it.** `admin_set_hours` is left alone —
      its payload is the whole week on purpose.
      → **verify:** ✅ a bank-name-only save keeps last4 and IFSC; a GST-only save
        keeps the FSSAI and PAN; an explicit `""` still clears; a null payload is
        refused instead of erasing the row.

---

### Phase 5 — The menu builder

The largest step. Categories are strings on items, so the builder owns their consistency.

- [x] **5.1** Section management: add (by naming one on a dish), rename, reorder,
      hide/show. Rename rewrites `category` on every item in one statement; reorder
      rewrites `category_rank` for the whole menu; hiding writes `category_available`
      across the section.
      → **verify:** ✅ rename moved both Breads dishes and touched nothing else;
        section reorder and item reorder both landed; a new section joins the end.
      → **deviation:** there is no *delete a section*. A section has no row of its
        own — it exists only as a string its dishes share — so an empty one cannot
        exist to be deleted. Removing the last dish removes the section. The
        original line ("delete is refused while the section has items") described a
        button that could only ever be disabled.
- [x] **5.2** Item editor: name, description, price, veg/non-veg, bestseller,
      available, photo. Add / edit / delete.
      → **verify:** ✅ deleting a dish that appears on a real past order →
        *"This dish appears on past orders, so it can't be deleted. Mark it
        unavailable instead."* and the dish survives; an unordered dish deletes
        cleanly. Ranks are assigned server-side, so a new dish joins the end of its
        section and a new section the end of the menu.
- [x] **5.3** Drag-to-reorder dishes within a section (native HTML5 drag, no
      library), persisted as one `admin_reorder_menu` call carrying the menu's whole
      running order. Sections move with ↑/↓ on their header.
      → **verify:** ✅ dragging Chicken Biryani above Paneer Tikka, then moving
        Breads above Recommended, both produced the expected `category_rank.item_rank`
        for every row.
      → **note:** dragging *between* sections is deliberately inert. That would
        change a dish's category as well as its rank — a different operation with
        different consequences — and the dialog's Section field is where that happens.
- [x] **5.4** **CSV / bulk import** — template download, per-row validation, a
      preview that must be looked at, then commit. Written by hand rather than with
      a library: the format is the one our own template emits.
      → **verify:** ✅ against deliberately messy input — Excel's byte-order mark,
        CRLF, a quoted field containing a comma, `""` escaping inside a quoted
        field, and `yes`/`NO`/`VEG`/`y` booleans all parsed correctly; the four bad
        rows were each skipped with a reason and a line number (*"A dish has to cost
        more than zero."*, *"Price "90.5" is not a whole number."*, *"No section."*,
        *"No dish name."*). Imports run sequentially, not in parallel — the RPC works
        out each dish's rank from what is already there, so two racing inserts would
        both claim the same one.
- [x] **5.5** Menu summary: dish count, section count, how many are unavailable, how
      many have no photo.
      → **verify:** ✅ derived from the same `admin_list_menu` rows the list renders,
        so there is no second count to disagree.

---

### Phase 6 — Review and publish

- [x] **6.1** Review screen: a readiness checklist with a Fix link back to whichever
      step owns each gap, plus a storefront summary.
      → **verify:** ✅ the checklist is a *mirror*, not the rule.
        `admin_publish_restaurant` re-checks every condition server-side, and if the
        two ever disagree the database wins and its sentence is shown verbatim.
- [x] **6.2** Publish gate — built in 1.4 and verified there; this phase wired the UI
      to it. The button is disabled while anything is outstanding, but the gate
      remains the authority. Original text kept below.
      → **verify:** ✅ all eight refusals fired in Phase 1, each with its own sentence.

      *Original:* `admin_publish_restaurant` refuses unless: name, cover
      photo, address, city, pincode, contact phone, FSSAI, PAN, bank account, an owner
      in `restaurant_staff`, hours for at least one day, and **at least one available
      menu item**. Each failure returns its own sentence.
      → **verify:** publishing a draft with no menu items fails with "Add at least one dish before publishing."
- [x] **6.3** Publish flips `is_active = true`.
      → **verify:** ✅ **the full loop, run for real against the live project.** A
        restaurant built entirely through the console's own RPCs — storefront,
        address, legal, bank, owner, seven days of hours, two dishes — then:
        - published, and a **customer** JWT saw it in the feed and read its menu;
        - ordering before opening time was refused: *"This restaurant is closed right
          now. Please check its hours before ordering."*;
        - after an 11:00–03:00 window was set, `restaurant_is_open_now()` returned
          true at **00:49 IST** — migration 0036 doing exactly what it was built for —
          and the order went through;
        - `place_order` priced it server-side: 2 × ₹260 = ₹520, free delivery over
          ₹500, 5% tax → **₹546**, receipt `ZPQ-1015`;
        - the **owner email added in step 6** resolved through `staff_restaurant_id()`,
          saw the order and its line item, and moved it to `accepted`.
        Test order and restaurant deleted afterwards; counts back to 8 restaurants,
        72 dishes.
      → **still owed:** the same journey through the actual Android build rather than
        through the policies it runs on. That needs a device, so it is yours.

---

### Phase 7 — Managing what's already live

- [x] **7.1** Edit mode — no new screen. The wizard loads by id and every step
      saves against it, so editing a live restaurant is the same eight tabs with
      "Live — changes take effect immediately" in the header instead of "Draft".
      → **verify:** ✅ **r1's offer line, edited on the live row** — "50% OFF up to
        ₹100" → "Edited by the console" → restored. `is_active` stayed true
        throughout; a customer would have seen the card change and change back.
- [x] **7.2** Delist behind a confirmation naming the consequence *and* the
      non-consequence, from both the list and the review screen.
      → **verify:** ✅ **the in-flight case, run for real.** Order ZPQ-1016 placed,
        restaurant delisted underneath it, then: the customer still read the order,
        its name, and its lines (`orders` denormalises `restaurant_name`, and the
        customer's read policy is `user_id = auth.uid()` with no `is_active`
        clause); the restaurant was gone from the feed; and the **delisted kitchen
        still saw the order and moved it to `accepted`** — 0009's staff policy has
        no `is_active` clause either, deliberately.
- [x] **7.3** Team management for a live restaurant — list, add, change role, remove.
      → **verify:** ✅ added a cook to r2, promoted them to owner, and the attempt to
        remove them was refused: *"That is the only owner. Add another owner before
        removing this one."* Demoted and removed cleanly; r2 back to no staff.
      → **still owed:** a removed address actually losing access on next sign-in.
        That is a real inbox and a real device, so it is yours.
- [x] **7.4** `0038_admin_roster.sql` + Settings — add and remove platform admins.
      Two rules, both guarding the same failure (a platform with nobody who can run
      it): you cannot remove yourself, and you cannot remove the last admin. Until
      today there was exactly one admin, and losing that account would have meant no
      restaurant could ever be onboarded again without a migration.
      → **verify:** ✅ *"You can't remove yourself."*, *"Who is this? Add a name."*
        (a roster of bare addresses is one nobody can audit later), *"That doesn't
        look like an email address."*, adding twice refused by name; add → list →
        remove round-tripped and the roster is back to one.
      → **still owed:** a second admin actually signing in. Needs their inbox.

---

### Phase 7b — The rider fleet  ✅ **DONE** *(2026-07-22, migration `0040`)*

Unplanned when this document was written, and pulled in from `DELIVERY_PLAN.md`,
which had named an ops console "the honest next dependency" for the delivery
phase: riders were added by editing a seed file. Fine for the first one,
untenable by the tenth — the same argument this whole project rests on.

- [x] **7b.1** `0040_admin_rider_roster.sql` — `admin_list_riders`,
      `admin_add_rider`, `admin_update_rider`, `admin_set_rider_active`. All
      `security definer` behind `assert_admin()`, no table write granted to the
      browser, and **no select policy added for admins** — a policy would expose
      every rider's address through PostgREST, and the RPC answers the only
      question worth asking.
      → **verified:** exercised in a rolled-back transaction — a signed-in
      non-admin is refused both read and write; bad email, empty name and a
      9-digit phone are each rejected; adding the same address twice is refused;
      email is lower-cased, name trimmed, phone stripped to digits.
- [x] **7b.2** Riders page in the console: roster with live-job and delivered
      counts, add, edit, deactivate/reactivate.
      → **verified:** `tsc -b` and `oxlint` clean.
- [x] **7b.3** **Deactivating a rider mid-delivery is refused, by the database.**
      Not a nicety: `delivery_partner_email()` returns null for a deactivated
      rider, so they could no longer confirm pickup or delivery — and the partial
      unique index keeps the job off the board for everyone else, because it is
      live, not cancelled. The order would simply be undeliverable, by anyone,
      with no screen able to fix it. The RPC refuses and names the order; the
      rider drops it in their own app first. The console also greys the button
      and says why, which is belt and braces on purpose.

**Not built, deliberately:** there is no `admin_remove_rider`.
`deliveries.partner_email` is a foreign key, so a delete would either fail or
take the delivery history with it, and "who delivered this" is worth answering a
year later. Deactivation is the removal, and it is reversible.

### Phase 8 — Ship

- [ ] **8.1** Cross-check the console against all three Flutter apps: customer feed +
      order, vendor queue + menu edit, rider claim.
      → **verify:** a restaurant onboarded entirely through the web app completes a full order lifecycle including delivery.
- [ ] **8.2** Deploy to Vercel with env vars set; access limited to admin emails by
      `is_admin()` (the app is public, the data is not).
      → **verify:** the deployed URL signs in and lists restaurants; a non-admin gets bounced.
- [ ] **8.3** Update `README.md` and `VENDOR_TASKS.md` to point at the console as the
      way restaurants are created. Commit and push.

---

## Open questions to settle before the phase that needs them

1. ~~**Overnight hours** (Phase 4.2).~~ **Settled 2026-07-22:** relaxed properly —
   migration 0036 plus a matching change to the vendor app. See 4.2.
2. ~~**Cloudinary folder layout** for legal documents.~~ **Settled 2026-07-22:**
   a private Supabase Storage bucket (`restaurant-docs`, migration 0034), admin-only
   RLS on all four verbs, paths in the database instead of URLs, five-minute signed
   links to view. A PAN scan is identity-theft material and a Cloudinary URL is
   permanent, unauthenticated, and edge-cached — there is no revoking one.
3. **`rating` on a new restaurant** (Phase 6.3) — the customer app will render `0.0`.
   Either the card treats `rating_count = 0` as a "New" badge (a small customer-app
   change), or we accept it.
