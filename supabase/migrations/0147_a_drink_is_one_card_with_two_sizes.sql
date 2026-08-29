-- ---------------------------------------------------------------------------
-- 0147 — a drink is one card with two sizes.
-- ---------------------------------------------------------------------------
-- 0140 seeded each bottled drink twice — `Coca Cola (250 ml)` and
-- `Coca Cola (750 ml)` as two independent `menu_items`. That is sixteen cards
-- per kitchen showing eight drinks, with every brand drawn twice at two prices,
-- and it reads as a listing error rather than a choice.
--
-- One card per drink now, with the size asked on ADD. That is exactly what the
-- variant machinery from 0048 is for, and this is the first thing on the
-- platform to use it — `menu_option_groups` + `menu_options` have been built and
-- unused in all three surfaces since they shipped.
--
-- ## Why this is safe to do destructively
--
-- **No order has ever contained a beverage** (`order_items where menu_item_id
-- like 'bev-%'` is empty), so there is no receipt whose line points at a row
-- being deleted. Had there been, nothing would break anyway — `order_items`
-- freezes the name, the unit price and the chosen options at the time of the
-- order and `menu_item_id` carries no foreign key — but "no history to
-- preserve" is why this can be a delete rather than a soft retirement.
--
-- ## The shape
--
-- The 250 ml row survives and becomes the drink. It keeps its id, its packshot
-- and its ₹30 — **the base price has to be the cheapest size**, because
-- `menu_options_price_delta_check` refuses a negative delta, so the large size
-- is a `+₹20` on top rather than the small being a discount off ₹50.
--
--     Coca Cola            ₹30
--       Size  (choose 1)
--         250 ml           +₹0
--         750 ml          +₹20
--
-- `min_select = 1` so a size is always chosen. It is not a trap for a client
-- that forgets to send one: `resolve_order_line_options` fills any group under
-- its minimum with its cheapest-ranked available options, so an ADD carrying no
-- option prices as 250 ml — the honest default, and the one the card's own
-- price already promised.
--
-- The large label is read off the row being deleted rather than assumed. Seven
-- drinks come in 750 ml and **Maaza's large is 600 ml**, because no 750 ml Maaza
-- is made (0140), and hardcoding "750 ml" here would print a bottle size that
-- does not exist onto twelve menus.
--
-- ## What this does not change
--
-- Prices, GST slab (500 bps, an explicit call in 0140), packshots, the `bev-`
-- id prefix every surface filters on, and the two kitchens whose `Beverages`
-- section also holds a made-to-order drink. 192 rows become 96.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The size group, on the row that survives.
-- ---------------------------------------------------------------------------
insert into public.menu_option_groups (menu_item_id, name, min_select, max_select, rank)
select small.id, 'Size', 1, 1, 0
  from public.menu_items small
 where small.id like 'bev-%-0'
   and not exists (
     select 1 from public.menu_option_groups g where g.menu_item_id = small.id
   );

-- ---------------------------------------------------------------------------
-- 2. The two sizes. The small is the base and adds nothing; the large carries
--    the difference between the two rows, computed rather than assumed.
-- ---------------------------------------------------------------------------
insert into public.menu_options (group_id, name, price_delta, rank)
select g.id,
       -- '250 ml', out of 'Coca Cola (250 ml)'.
       regexp_replace(small.name, '^.*\((.*)\)$', '\1'),
       0,
       0
  from public.menu_items small
  join public.menu_option_groups g on g.menu_item_id = small.id and g.name = 'Size'
 where small.id like 'bev-%-0';

insert into public.menu_options (group_id, name, price_delta, rank)
select g.id,
       regexp_replace(large.name, '^.*\((.*)\)$', '\1'),
       large.price - small.price,
       1
  from public.menu_items small
  join public.menu_option_groups g on g.menu_item_id = small.id and g.name = 'Size'
  -- The large row is the same id with its trailing `-0` swapped for `-1`.
  join public.menu_items large
    on large.id = left(small.id, length(small.id) - 1) || '1'
 where small.id like 'bev-%-0';

-- ---------------------------------------------------------------------------
-- 3. The name loses its size. 'Coca Cola (250 ml)' was only ever a name because
--    there was a second row to tell it apart from.
-- ---------------------------------------------------------------------------
update public.menu_items
   set name = btrim(regexp_replace(name, '\s*\(.*\)$', ''))
 where id like 'bev-%-0';

-- ---------------------------------------------------------------------------
-- 4. The large rows go. `menu_option_groups` cascades from `menu_items`, and
--    these carry none anyway.
-- ---------------------------------------------------------------------------
delete from public.menu_items where id like 'bev-%-1';
