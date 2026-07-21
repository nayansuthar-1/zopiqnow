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

- [ ] **1.1** `0027_restaurant_id_and_contact.sql`
      - `alter table restaurants alter column id set default gen_random_uuid()::text`
      - add `owner_name text`, `contact_phone text`, `address_line text`, `city text`,
        `state text`, `pincode text` (checked `^[1-9][0-9]{5}$` when present)
      - all nullable, because the eight seeded rows have none of it
      → **verify:** an insert with no id succeeds; the seeded rows still read fine in the customer app.
- [ ] **1.2** `0028_restaurant_legal.sql` — `restaurant_legal (restaurant_id pk,
      fssai_number, fssai_expiry date, fssai_doc_url, gst_number, pan_number,
      pan_doc_url, updated_at)`. RLS on, **admin-only select/write** (via RPC).
      A vendor must not be able to read or edit their own licence numbers.
      → **verify:** a vendor JWT selecting the table gets zero rows.
- [ ] **1.3** `0029_restaurant_bank.sql` — `restaurant_bank_accounts (restaurant_id pk,
      account_holder, account_number, ifsc checked `^[A-Z]{4}0[A-Z0-9]{6}$`, bank_name,
      verified boolean default false, updated_at)`. Admin-only, same as legal.
      → **verify:** vendor JWT reads nothing; admin RPC round-trips a record.
- [ ] **1.4** `0030_admin_rpcs.sql` — the write surface, every function
      `security definer` + `set search_path = public` + first line `if not is_admin()
      then raise`:
      - `admin_create_restaurant(jsonb) → text` (returns new id, `is_active = false`)
      - `admin_update_restaurant(p_id text, jsonb)`
      - `admin_set_legal(p_id, jsonb)` / `admin_set_bank(p_id, jsonb)`
      - `admin_set_hours(p_id, jsonb)` — admin-scoped twin of `set_restaurant_hours`
      - `admin_set_commission(p_id, p_bps)`
      - `admin_add_staff(p_id, p_email, p_role)` / `admin_remove_staff(p_id, p_email)`
      - `admin_upsert_menu_item(p_id, jsonb) → text`, `admin_delete_menu_item(p_item_id)`
      - `admin_reorder_menu(p_id, jsonb)` — bulk category_rank/item_rank write
      - `admin_publish_restaurant(p_id)` / `admin_unpublish_restaurant(p_id)`
      - `admin_list_restaurants()` — includes drafts, which the anon policy hides
      → **verify:** each RPC raises `'Not authorized.'` under a vendor JWT and succeeds under manav's.
- [ ] **1.5** Apply 0026–0030 to the live project and re-run the vendor + customer
      apps against it.
      → **verify:** vendor app menu editing, order queue, and the customer feed all still work.

---

### Phase 2 — Console shell and restaurant list

- [ ] **2.1** App shell: sidebar (Restaurants · Add restaurant · Settings), top bar
      with the signed-in admin, sign-out. Clean and restrained — no glow, no neon.
      → **verify:** renders correctly at 1280px and 768px.
- [ ] **2.2** Restaurant list from `admin_list_restaurants()`: name, city, status
      pill (**Draft** / **Live** / **Paused by kitchen** / **Delisted**), menu item
      count, owner email. Search + status filter.
      → **verify:** the 8 seeded restaurants list as Live; a draft created by RPC appears as Draft.
- [ ] **2.3** Row actions → open the wizard in edit mode, or unpublish.
      → **verify:** unpublishing r8 removes it from the Android customer feed on refresh.

---

### Phase 3 — Onboarding wizard, steps 1–3 (the restaurant)

A stepper with a **persistent draft**: step 1 creates the row (`is_active = false`),
every later step saves against its id. Closing the browser loses nothing.

- [ ] **3.1 Step 1 — Storefront.** Name, cuisines (multi-select with free entry),
      price for two, pure-veg toggle, promo line, prep time (eta_minutes), cover photo
      → unsigned Cloudinary upload, store the returned URL. `rating` / `rating_count`
      seed to 0.
      → **verify:** Save creates a `restaurants` row with `is_active = false`, invisible to the customer app.
- [ ] **3.2 Step 2 — Address & contact.** Owner name, contact phone (10-digit),
      address line, city, state, pincode, latitude/longitude (paste or map pick),
      `distance_km` left 0 until delivery zones land.
      → **verify:** values round-trip through `admin_update_restaurant`; pincode/phone validation rejects bad input with a sentence, not a constraint dump.
- [ ] **3.3 Step 3 — Legal.** FSSAI number + expiry + document upload, GST number
      (15-char format check), PAN + document upload. Documents to Cloudinary under a
      `legal/` folder.
      → **verify:** `restaurant_legal` row written; an expired FSSAI date is refused at submit.

---

### Phase 4 — Steps 4–6 (money, hours, the owner's login)

- [ ] **4.1 Step 4 — Bank & commission.** Account holder, account number
      (entered twice, must match), IFSC (format-checked, uppercased), bank name;
      commission in **percent** in the UI, stored as `commission_bps`.
      → **verify:** 20% saves as 2000 bps; mismatched account numbers block Save.
- [ ] **4.2 Step 5 — Hours.** Seven day rows, open/closed toggle, opens/closes
      pickers, "copy to all days". **Decide first:** `closes > opens` forbids an
      overnight kitchen (18:00 → 01:00). Recommended fix is a migration splitting an
      overnight window into two rows (18:00–23:59 today, 00:00–01:00 tomorrow) so
      `restaurant_is_open_now()` needs no change. Flag to the user before building.
      → **verify:** hours land in `restaurant_hours`; `restaurant_is_open_now()` returns the right answer at a time inside and outside the window.
- [ ] **4.3 Step 6 — Team.** Owner email (required — this is the vendor app login),
      optional extra staff. Writes `restaurant_staff` via `admin_add_staff`, with the
      "already on another restaurant's team" case handled.
      → **verify:** the owner email signs into the **vendor Flutter app** and sees this restaurant.

---

### Phase 5 — The menu builder

The largest step. Categories are strings on items, so the builder owns their consistency.

- [ ] **5.1** Category management: add / rename / reorder / delete a section. Rename
      rewrites `category` on every item in it; reorder rewrites `category_rank`;
      delete is refused while the section has items.
      → **verify:** renaming "Starters" → "Small plates" updates all its items and nothing else.
- [ ] **5.2** Item editor: name, description, price, veg/non-veg, bestseller,
      available, photo (Cloudinary). Add / edit / delete, delete surfacing the FK
      error as "This dish appears on past orders — mark it unavailable instead."
      → **verify:** an item added here appears in the customer app's menu for that restaurant.
- [ ] **5.3** Drag-to-reorder items within a section, saved as `item_rank` in one
      `admin_reorder_menu` call.
      → **verify:** the customer app's menu order matches the console's.
- [ ] **5.4** **CSV / bulk import** — download a template
      (`category, name, description, price, is_veg, is_bestseller, image_url`), upload,
      preview with per-row validation, then commit. This is what makes a 120-dish menu
      possible in one sitting.
      → **verify:** a 50-row CSV imports with correct ranks; a row with price 0 is rejected in the preview, not at the database.
- [ ] **5.5** Menu summary: item count per section, count missing a photo, count
      unavailable.
      → **verify:** counts match a direct SQL count.

---

### Phase 6 — Review and publish

- [ ] **6.1** Review screen: everything collected, grouped, each block linking back
      to its step.
      → **verify:** a half-filled draft shows exactly which blocks are incomplete.
- [ ] **6.2** Publish gate. `admin_publish_restaurant` refuses unless: name, cover
      photo, address, city, pincode, contact phone, FSSAI, PAN, bank account, an owner
      in `restaurant_staff`, hours for at least one day, and **at least one available
      menu item**. Each failure returns its own sentence.
      → **verify:** publishing a draft with no menu items fails with "Add at least one dish before publishing."
- [ ] **6.3** Publish flips `is_active = true`.
      → **verify:** **the restaurant appears in the Android customer app**, opens, and an order can be placed against it end to end.

---

### Phase 7 — Managing what's already live

- [ ] **7.1** Edit mode: the same wizard over an existing restaurant, with published
      state shown and changes taking effect immediately.
      → **verify:** editing r1's promo line changes the customer app card.
- [ ] **7.2** Unpublish / delist, with a confirmation naming the consequence
      ("customers will no longer see this restaurant; existing orders are unaffected").
      → **verify:** delisting does not break an in-flight order's tracking screen.
- [ ] **7.3** Team management for a live restaurant — list, add, change role, remove.
      → **verify:** a removed staff email loses vendor app access on next sign-in.
- [ ] **7.4** Admin management under Settings — add/remove other platform admins.
      → **verify:** a second admin signs in; an admin cannot remove themselves.

---

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

1. **Overnight hours** (Phase 4.2) — split-row workaround, or relax the constraint?
2. **Cloudinary folder layout** for legal documents — those are sensitive scans on a
   public CDN with an unsigned preset. Signed uploads or a private Supabase Storage
   bucket may be the right answer before 3.3 ships.
3. **`rating` on a new restaurant** (Phase 6.3) — the customer app will render `0.0`.
   Either the card treats `rating_count = 0` as a "New" badge (a small customer-app
   change), or we accept it.
