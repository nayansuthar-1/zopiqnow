-- Step ~, migration 16: a whole section can be taken off the menu.
--
-- Categories are not a table — they are the `category` text on each menu_item,
-- ordered by `category_rank` (0002). The vendor can already rename a section
-- (change that text across its rows) and reorder it (change that rank), both with
-- the update grant 0010 gave them. What they could not do is take a whole section
-- off the customer menu in one move — "we've stopped serving breakfast for the
-- day" — without flipping every dish's own `is_available` and so forgetting which
-- of them were separately sold out when the section comes back on.
--
-- `category_available` is that switch. It is denormalized onto every row of a
-- section — all rows of one category carry the same value, and the vendor writes
-- it across the section in a single update — and it sits *beside* `is_available`,
-- never on top of it. A dish reaches a customer only when it is itself available
-- AND its section is on, so turning a section off and back on leaves each dish's
-- own sold-out state exactly as it was. Default true, so every existing dish is
-- unaffected the instant this lands.

alter table public.menu_items
  add column if not exists category_available boolean not null default true;

-- The customer's read gate widens by one predicate. The customer app filters
-- nothing itself — its menu datasource never names `is_available`, it leans
-- entirely on this policy — so a section switched off vanishes from every
-- customer with no change to the customer app at all. The staff read policy
-- (0009) is gated only on `restaurant_id`, so the kitchen still sees the section
-- it turned off, which is the one moment it most needs to, to turn it back on.
drop policy if exists "available menu items are world-readable" on public.menu_items;
create policy "available menu items are world-readable"
  on public.menu_items
  for select
  to anon, authenticated
  using (is_available and category_available);
