-- Step 7, migration 6: the address book — saved addresses belong to a user.
--
-- Until now `savedAddresses()` returned two compile-time constants: every
-- account in the app shared the same "Home — Banjara Hills" and "Work — HITEC
-- City". They were seeded to unblock the picker, and they have been lying ever
-- since: an address book that cannot be added to is not an address book.
--
-- Unlike `orders`, this table is written by the client. That is fine — and it is
-- the distinction worth being precise about. `place_order` owns writes because
-- **the client must not decide what anything costs**. Nothing here costs
-- anything: an address is the customer's own text about where they live. There
-- is no rule to enforce beyond "it is yours", and RLS enforces exactly that.
--
-- Deleting an address cannot damage history: `orders` stores `delivery_to`,
-- `delivery_lat`, and `delivery_lng` on the order itself (0003), precisely so a
-- receipt still says where the food went after the address is edited or gone.

create table if not exists public.addresses (
  id          uuid primary key default gen_random_uuid(),

  -- A uuid with a real foreign key, unlike `orders.user_id` (text). That column
  -- is text because it predates auth and had to survive the mock→Supabase swap
  -- without a migration; this table has no such history. `on delete cascade`
  -- means deleting an account takes its addresses with it, which is what a
  -- deletion request means.
  user_id     uuid not null references auth.users (id) on delete cascade,

  -- "Home", "Work", or nothing: a saved address need not be tagged.
  label       text,

  -- What the rider reads. `line1` carries the flat/house detail the customer
  -- typed; the geocoder only ever produces a locality.
  line1       text not null check (length(trim(line1)) > 0),
  city        text not null,

  -- Not null: an address the dispatcher cannot place on a map is not a delivery
  -- address. The client resolves these before it saves (GPS, or a forward
  -- geocode of the typed text) and refuses to save without them.
  latitude    double precision not null,
  longitude   double precision not null,

  created_at  timestamptz not null default now()
);

create index if not exists addresses_user_idx
  on public.addresses (user_id, created_at);

alter table public.addresses enable row level security;

-- Read, add, edit, delete — all four, all scoped to the caller, all saying so.
drop policy if exists "customers read their own addresses" on public.addresses;
create policy "customers read their own addresses"
  on public.addresses for select to authenticated
  using (user_id = auth.uid());

-- `with check`, not `using`: on an insert there is no existing row to test, and
-- the thing being asserted is that the row *about to be written* is the caller's
-- own. Without this a signed-in customer could file an address under someone
-- else's account.
drop policy if exists "customers add their own addresses" on public.addresses;
create policy "customers add their own addresses"
  on public.addresses for insert to authenticated
  with check (user_id = auth.uid());

-- Both clauses: `using` decides which rows may be edited, `with check` decides
-- what they may be edited *into* — otherwise an update could hand one of my
-- addresses to another user_id.
drop policy if exists "customers edit their own addresses" on public.addresses;
create policy "customers edit their own addresses"
  on public.addresses for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "customers delete their own addresses" on public.addresses;
create policy "customers delete their own addresses"
  on public.addresses for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.addresses to authenticated;
