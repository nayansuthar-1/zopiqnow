-- ---------------------------------------------------------------------------
-- 0145 — the tiles learn what the town orders.
-- ---------------------------------------------------------------------------
-- The home screen's food tiles ship in a hand-written order: Sandwich, Pizza,
-- Burger, Momos, Pav Bhaji, Dosa… That order is somebody's guess from before the
-- platform had customers, and it is still the order today, on a platform that
-- now has order history. The tiles should lead with what the town actually buys.
--
-- This is the read that makes that possible. The ranking itself stays in Dart,
-- and deliberately: which tile a dish belongs to is decided by
-- `category_matching.dart` — whole-word matching over the dish's name and its
-- menu section, with per-tile aliases because menus spell food their own way
-- ("Pakoda", "Chola Bhatura", "Aaloo"). That rule was derived from this exact
-- catalogue and is verified by replaying it over a menu dump. Restating it in
-- SQL would be a second definition of "this dish is a dosa", free to drift from
-- the first, to fix a tile order.
--
-- So this answers the smaller question — *what has been ordered, and how much of
-- it* — and the client buckets the answer into tiles with the rule it already
-- owns.
--
-- ## What it counts
--
-- `order_items.name`, not a join to the live menu item: the name is frozen on
-- the line at the moment of ordering, so a dish renamed or deleted since still
-- counts towards the tile it was sold under. `menu_items.category` is joined for
-- the section, and is left null when the dish is gone — the client matches on
-- the name alone in that case, which is the stronger signal anyway.
--
-- Cancelled and rejected orders are excluded. Somebody ordered it, but the
-- platform did not sell it, and a tile order built on refunded baskets would be
-- ranking what goes wrong rather than what sells.
--
-- ## Honest note on the data as it stands today
--
-- The whole platform has **43 order lines**, and 118 of the 128 units ordered
-- are two dishes (Jeera Rice, Dal Fry) from one tester's repeated orders. Seven
-- distinct dishes have ever been ordered, across three menu sections — Dal
-- Chawal, Pizza and Sandwiches. Only Pizza and Sandwich are home tiles at all.
--
-- So on today's data this moves two tiles and leaves ~40 tied on zero. That is
-- the correct outcome and not a reason to weight or smooth anything: the
-- client's fallback is the existing hand-written order, so a tile nobody has
-- ordered keeps exactly the position it has now, and the ranking only asserts
-- itself where there is something to assert. It gets better on its own as orders
-- accumulate, with no further change here.
--
-- ## Exposure
--
-- Aggregate dish popularity and nothing else — no user, no order id, no time of
-- day, no restaurant. It is the same class of fact as the "Bestseller" badge the
-- catalogue already shows in public, so it is granted to `anon` as well as
-- `authenticated`: home renders before sign-in and the tiles are part of it.
-- ---------------------------------------------------------------------------

create or replace function public.dish_order_counts(p_days integer default 90)
returns table(dish_name text, section text, units integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select oi.name,
         coalesce(mi.category, ''),
         sum(oi.quantity)::integer
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    -- Left, so a dish deleted from the menu since it was sold still counts.
    left join public.menu_items mi on mi.id = oi.menu_item_id
   where o.status not in ('cancelled', 'rejected')
     -- Clamped rather than trusted. This is `anon`-executable, and an unbounded
     -- window is the one parameter here worth a hostile value.
     and o.created_at >= now() - make_interval(
           days => greatest(1, least(coalesce(p_days, 90), 365)))
   group by 1, 2
   order by 3 desc, 1
   -- A ceiling, not a shortlist: the platform has seven distinct dishes ever
   -- ordered, and this is far above any plausible number of *distinct* dishes a
   -- town buys in a quarter. Ordered by units first, so if it ever does bite it
   -- drops the tail rather than the signal.
   limit 400
$$;

-- Born PUBLIC-executable, like every function here. Revoke, then grant the two
-- roles that actually call it.
revoke all on function public.dish_order_counts(integer) from public;
grant execute on function public.dish_order_counts(integer) to anon, authenticated;
