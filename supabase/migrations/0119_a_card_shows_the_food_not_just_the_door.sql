-- ---------------------------------------------------------------------------
-- 0119 — a restaurant card shows the food, not just the door.
-- ---------------------------------------------------------------------------
-- The Home card has carried a five-dot indicator strip since the Swiggy-style
-- redesign, and it has never indicated anything: `restaurant_card.dart` drew
-- five `Container`s, painted the first one white, and there was no `PageView`
-- behind them. One photo, five dots, nothing to swipe. It is the same class of
-- thing the favourite heart used to be before it was made live — a control that
-- looks like it does something and does not.
--
-- The photos to fill it already exist. Every restaurant has a menu and most
-- dishes have a picture; what was missing is a way to ask for a *few* of them
-- per restaurant without dragging the whole catalogue to the phone.
--
-- ## Why an RPC and not a PostgREST query
--
-- The shape wanted is "the first N rows of each group", and PostgREST cannot
-- express it — `.limit()` is a limit on the result, not per `restaurant_id`. The
-- alternatives were both bad: fetch every dish photo on the platform and slice
-- client-side (fine at 114 dishes, a megabyte of URLs at ten thousand), or fire
-- one request per visible card (nine round trips on the first screen). A lateral
-- window function is one request whose size is bounded by
-- `restaurants × p_per_restaurant`, whatever the menu grows to.
--
-- ## `security invoker`, deliberately — the opposite of 0100's call
--
-- Nearly every function in this schema is `security definer` because it has to
-- see past RLS. This one must *not*: the answer is exactly what the caller may
-- already read from `menu_items`, and the policy on that table (0032) is doing
-- four jobs that would otherwise have to be copied here and kept in step —
--
--     is_available AND category_available
--     AND menu_item_is_servable_now(serve_from, serve_to)
--     AND EXISTS (select 1 from restaurants r
--                  where r.id = menu_items.restaurant_id and r.is_active)
--
-- — availability, a shelf switched off, a breakfast dish outside its serving
-- window, and a delisted restaurant. A definer copy of that list is a second
-- place to forget the serving window, and the failure mode is a photo of a dish
-- that cannot be ordered. Invoker means the policy runs, once, where it lives.
--
-- The `where` clause below therefore filters on **nothing but the photo**; every
-- rule about who may see which dish is already applied by the time these rows
-- exist.
--
-- ## Which photos, and why the order looks arbitrary
--
-- Ordered by a hash of the dish id, which is two decisions.
--
-- **Varied**: the alternative orders are all systematically boring. By
-- `item_rank` every card shows its menu's first few dishes, which for most
-- kitchens is the starters shelf; by `rating` or `is_bestseller` the same three
-- photographs lead the card for months. Hashing spreads the picks across the
-- whole menu, so two restaurants with similar menus do not draw the same card.
--
-- **Stable**: `random()` was the obvious reading of the request and is the wrong
-- one. It would reshuffle on every refresh, which means the card the customer
-- was looking at changes under their thumb, the disk image cache misses on every
-- load, and a phone on mobile data re-downloads five photographs to show the
-- same restaurant. `md5(id)` is random-looking and fixed, which is what "show a
-- few different dishes" actually wants. Changing the pick to bestsellers-first
-- later is one `order by`.
-- ---------------------------------------------------------------------------

create or replace function public.restaurant_card_photos(
  p_per_restaurant integer default 5
)
returns table (restaurant_id text, image_url text)
language sql
stable
-- No `security definer`. See the header — this is the one place where the
-- caller's own view of `menu_items` is precisely the right answer.
set search_path = public
as $$
  select t.restaurant_id, t.image_url
    from (
      select m.restaurant_id,
             m.image_url,
             row_number() over (
               partition by m.restaurant_id
               -- Salted with the restaurant id so the same dish id in two
               -- kitchens does not land in the same position on both cards.
               order by md5(m.id || m.restaurant_id)
             ) as rn
        from public.menu_items m
       -- A dish with no photograph has nothing to contribute to a photo strip.
       -- The card falls back to its own cover, and to the branded gradient if it
       -- has none of those either.
       where m.image_url <> ''
    ) t
   -- Clamped rather than trusted. This is callable by `anon`, and an argument of
   -- two billion is a request to serialise every dish photo on the platform —
   -- the one thing this function exists to avoid. Six is the ceiling because the
   -- card shows at most six pages.
   where t.rn <= least(greatest(coalesce(p_per_restaurant, 5), 1), 6)
   order by t.restaurant_id, t.rn
$$;

-- Browsing needs no account — the food catalogue has been world-readable since
-- 0001 and this is a narrower view of it, so `anon` is on the list for the same
-- reason it can already read `menu_items` directly.
revoke execute on function public.restaurant_card_photos(integer) from public;
grant execute on function public.restaurant_card_photos(integer) to anon, authenticated;

comment on function public.restaurant_card_photos(integer) is
  'Up to N dish photos per restaurant for the Home card carousel. security INVOKER on purpose: the menu_items policy (0032) is the visibility rule and is not copied here.';

-- ---------------------------------------------------------------------------
-- The standing checks (0087, 0089)
-- ---------------------------------------------------------------------------
--   select has_function_privilege('public', 'public.restaurant_card_photos(integer)', 'execute');
--   → false. `anon` and `authenticated` are granted explicitly; PUBLIC is not.
