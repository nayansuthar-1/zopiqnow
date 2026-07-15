-- Step 10, migration 10: the vendor edits their own menu.
--
-- 0009 gave a vendor *read* access to their menu, including the sold-out dishes a
-- customer cannot see, and stopped there deliberately — reading was all the order
-- queue needed. Menu management needs the other three verbs, and this migration
-- grants them, scoped (like everything a vendor touches) to their own restaurant
-- by `staff_restaurant_id()`.
--
-- Why this is safe where an `update` on `orders` was not (0009): a menu price is
-- the vendor's *own* number to set. `place_order` reads `menu_items.price` at
-- checkout and freezes it onto the order — that is the whole point of price
-- authority living in this table. Editing a dish changes what the *next* order
-- costs, never a past one; `order_items` denormalizes name and unit_price for
-- exactly that reason (0003). The thing 0009 guarded against was a vendor
-- repricing an order the customer had already agreed to. Nothing here can.

-- ---------------------------------------------------------------------------
-- The database picks the id, not the client.
-- ---------------------------------------------------------------------------
-- `menu_items.id` was a bare `text primary key` because every row that ever
-- existed was seeded by hand with an id ops chose. A vendor adding a dish has no
-- id to offer and must not invent one: a client that names a primary key is a
-- client that can collide with — or guess at — another row's. A default moves
-- that decision server-side, so the insert below simply omits it.
alter table public.menu_items
  alter column id set default gen_random_uuid()::text;

-- ---------------------------------------------------------------------------
-- A vendor may write their own menu, and only their own.
-- ---------------------------------------------------------------------------
-- The `with check` is the half that matters on a write: `using` says which rows
-- a vendor may start from, `with check` says what the row is allowed to become.
-- Without it on update, a vendor could file one of their dishes under another
-- restaurant's id; without it on insert, they could create a dish there outright.
-- Both clauses pin `restaurant_id` to the caller's own kitchen — the same shape
-- as the addresses policy (0006): the only rule is "it is yours".
--
-- For a customer, `staff_restaurant_id()` is null, so `restaurant_id = null` is
-- *unknown*, never true, and none of these policies ever admit their write. A
-- customer cannot touch any menu, including through a grant made to
-- `authenticated` at large.
drop policy if exists "staff insert their own menu" on public.menu_items;
create policy "staff insert their own menu"
  on public.menu_items for insert to authenticated
  with check (restaurant_id = public.staff_restaurant_id());

drop policy if exists "staff update their own menu" on public.menu_items;
create policy "staff update their own menu"
  on public.menu_items for update to authenticated
  using (restaurant_id = public.staff_restaurant_id())
  with check (restaurant_id = public.staff_restaurant_id());

-- Delete is a *hard* delete, and the FK from `order_items.menu_item_id` (0003,
-- no cascade) is what keeps it honest: a dish that has never been ordered is
-- removed cleanly, and one that appears on a past order cannot be deleted at all
-- — Postgres raises a foreign-key violation, history stays intact, and the app
-- turns that into "mark it unavailable instead". Availability, not deletion, is
-- how a dish with a past leaves the menu (0002).
drop policy if exists "staff delete their own menu" on public.menu_items;
create policy "staff delete their own menu"
  on public.menu_items for delete to authenticated
  using (restaurant_id = public.staff_restaurant_id());

grant insert, update, delete on public.menu_items to authenticated;
