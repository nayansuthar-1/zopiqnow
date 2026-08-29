-- ---------------------------------------------------------------------------
-- 0146 — the card shows food, not bottles.
-- ---------------------------------------------------------------------------
-- The restaurant card's photo strip (0119) fills itself with any menu item that
-- has an image. Until this week the seeded bottled drinks had drawn artwork and
-- most of them looked like nothing much; then 0144 pointed them at real
-- photographs, and they became the best-photographed things on several menus.
--
-- The result, live before this migration — of five slides per card:
--
--     Zopiq Demo Kitchen         5 drinks, 0 dishes
--     Sadri Restaurent           4 drinks, 1 dish
--     Mamaji Snacks Fast Food    3 drinks, 2 dishes
--     …9 of 12 cards carrying at least one bottle
--
-- A customer scrolling the home feed was being shown a Coca-Cola bottle as what
-- a restaurant looks like. **This is a direct consequence of fixing the
-- packshots** — worth writing down, because the same thing will happen to any
-- future range that is seeded onto every kitchen and photographed well.
--
-- The strip is for the food a kitchen cooks. `md5` ordering is untouched (see
-- 0119: stable-but-random-looking is the whole point, and `random()` would break
-- the disk image cache), and so is `security invoker` — the `menu_items` policy
-- still does the availability, category and serving-window work this must not
-- restate.
--
-- Restaurants whose only photographed items were drinks fall back to their own
-- cover image, which is what a card with nothing to show has always done.
-- ---------------------------------------------------------------------------

create or replace function public.restaurant_card_photos(p_per_restaurant integer default 5)
returns table(restaurant_id text, image_url text)
language sql
stable
set search_path to 'public'
as $function$
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
         -- New in 0146. The seeded bottled drinks (0140) are not what a kitchen
         -- looks like. `bev-` is the id prefix 0140 mints them with, and the
         -- same test `MenuItem.isBottledDrink` uses in the app.
         and m.id not like 'bev-%'
    ) t
   -- Clamped rather than trusted. This is callable by `anon`, and an argument of
   -- two billion is a request to serialise every dish photo on the platform —
   -- the one thing this function exists to avoid. Six is the ceiling because the
   -- card shows at most six pages.
   where t.rn <= least(greatest(coalesce(p_per_restaurant, 5), 1), 6)
   order by t.restaurant_id, t.rn
$function$;

-- 0119's grants, restated because `create or replace` on a function that was
-- dropped and recreated would otherwise fall back to the PUBLIC default. PUBLIC
-- never; the two roles that call it, explicitly.
revoke all on function public.restaurant_card_photos(integer) from public;
grant execute on function public.restaurant_card_photos(integer) to anon, authenticated;
