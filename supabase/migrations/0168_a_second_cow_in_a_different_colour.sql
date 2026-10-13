-- ---------------------------------------------------------------------------
-- 0168 — a second cow, in a different colour.
-- ---------------------------------------------------------------------------
-- 0167 priced fourteen of the fifteen gifts and left `gs1-kamdhenu-cow` at 999,
-- because no photograph of it came back from the seller. What arrived instead
-- was a *different* Kamdhenu cow plate: the same motif and the same marigold
-- ground, but a crimson jhool where the cataloged one wears navy, and red
-- lotuses where it has pink. A second piece, not a second photograph of the
-- first — so it is inserted beside it rather than written over it.
--
-- ## The old cow is still unpriced, and that is not an oversight
--
-- `gs1-kamdhenu-cow` keeps 999 and keeps it as a placeholder. This migration
-- deliberately does not touch that row: pricing it from the crimson one's
-- number would be inventing a price for a piece the seller has not quoted.
-- It is the last row in the catalogue still waiting on them.
--
-- ## One photograph, two renditions, the usual way round
--
-- The seller sent one picture, so the gallery has one entry. It is a fresh
-- upload to Cloudinary cloud `w69i7qes` — the current one — under a
-- deterministic public_id (`zopiqnow/gifts/kamdhenu-cow-crimson`) so a better
-- photograph can replace it in place later. Every other gift still points at
-- the old `mqppsahn` cloud; those assets resolve, so they are left alone.
--
-- `w_600` in `image_url` and `w_1200` in `image_urls[1]` off the same asset,
-- which is the convention 0118 encodes and `gift_asset_key()` checks: the card
-- thumbnail is a narrower rendition of the gallery lead, not a second picture.
--
-- ## It sits at the end of its shelf
--
-- `item_rank` 6 puts it last in Devotional Art rather than next to the navy cow
-- at rank 0, which would mean renumbering five untouched rows to open a gap.
-- Merchandising order is a drag in the console; five UPDATEs here would be a
-- migration's worth of churn for it.

insert into public.gift_items
  (id, shop_id, name, description, price, image_url, image_urls,
   category, category_rank, item_rank)
values
  ('gs1-kamdhenu-cow-crimson', 'gs1',
   'Crimson Kamdhenu Cow Lippan Wall Plate',
   'The sacred cow in a crimson jhool, ringed by red lotuses and mirror inlay on a marigold ground. Hand-painted lippan work, so no two are alike.',
   1200,
   'https://res.cloudinary.com/w69i7qes/image/upload/f_auto,q_auto,w_600,c_limit/v1791880059/zopiqnow/gifts/kamdhenu-cow-crimson.jpg',
   array[
     'https://res.cloudinary.com/w69i7qes/image/upload/f_auto,q_auto,w_1200,c_limit/v1791880059/zopiqnow/gifts/kamdhenu-cow-crimson.jpg'
   ],
   'Devotional Art', 0, 6)
on conflict (id) do nothing;
