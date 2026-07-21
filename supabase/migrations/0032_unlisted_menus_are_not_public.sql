-- Step 11, migration 32: a menu is only as public as the restaurant serving it.
--
-- Found by the Phase 1 verification, which created a draft restaurant, confirmed
-- it was invisible to an anonymous caller — and then read its entire menu with the
-- anon key. Three dishes, names and prices, for a restaurant that does not appear
-- anywhere on the platform.
--
-- The cause is that `menu_items`' world-readable policy (0002, tightened in 0016)
-- asks only about the dish:
--
--     using (is_available and category_available)
--
-- and never about the restaurant it belongs to. Every other public policy in the
-- schema does ask: `restaurants` is `using (is_active)`, and `restaurant_hours`
-- (0018) explicitly joins back to check the same thing. This one was written first,
-- when a restaurant row could not exist without being listed, and the assumption
-- stopped being true the moment 0030 started creating drafts.
--
-- It was never exploitable into an order — `place_order` (0018) refuses an
-- inactive restaurant outright. What leaked was information: an unlaunched
-- kitchen's menu and pricing, readable by anyone with the anon key, before its
-- owner had agreed to be on the platform at all.

drop policy if exists "available menu items are world-readable" on public.menu_items;
create policy "available menu items are world-readable"
  on public.menu_items
  for select
  to anon, authenticated
  using (
    is_available
    and category_available
    and exists (
      select 1 from public.restaurants r
       where r.id = menu_items.restaurant_id
         and r.is_active
    )
  );

-- The vendor's own read policy (0009, `restaurant_id = staff_restaurant_id()`) is
-- untouched and deliberately has no `is_active` clause. A delisted restaurant must
-- still be able to see and edit its own menu — that is the moment it most needs the
-- app to work — and this migration narrows only the *public* door.
--
-- The subquery is a primary-key lookup, evaluated per row like the one in the
-- hours policy. The customer app fetches a menu only for a restaurant it already
-- found in the feed, which is to say an active one, so nothing it asks for changes.
