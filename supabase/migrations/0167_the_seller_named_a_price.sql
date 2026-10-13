-- ---------------------------------------------------------------------------
-- 0167 — the seller named a price.
-- ---------------------------------------------------------------------------
-- Every gift in the catalogue has been priced at 999 since it was seeded. That
-- was never a price, it was a stand-in: `supabase/seed/0005_gifts_seed.sql`
-- says so in its own header — "PLACEHOLDERS, to be replaced when the seller
-- confirms: every price is 999". The seller has now confirmed, by sending the
-- photographs back with the price in each filename.
--
-- ## Why this is an UPDATE and not a re-seed
--
-- The seed file rebuilds the catalogue by deleting both gift tables first, so
-- running it against production would take every gift order's catalogue
-- reference down with it. The photographs did not change — they are the same
-- Cloudinary assets already on these rows, which is how each price was matched
-- to an item in the first place. Only the integer moved, so only the integer
-- is written here. The seed file is corrected alongside this migration so a
-- database built from scratch lands on the same numbers.
--
-- ## These are the prices the customer pays
--
-- Gifts carry no platform markup. Food does — the +10 that `menu_items` prices
-- are seeded with — but `gift_bag_quote` (0112) prices a bag straight off
-- `gift_items.price` and `place_gift_order` charges what it quoted, so what is
-- written here is what is charged. Nothing is added on the way to the bill.
--
-- ## Kamdhenu Cow is deliberately not in this list
--
-- Fourteen of the fifteen gifts arrived with a price. `gs1-kamdhenu-cow` did
-- not, so it keeps 999 — and keeps it as a placeholder, not as a confirmed
-- price. It is the one row still waiting on the seller.
--
-- `gs1-red-lotus-plate` is listed at 999 even though the number does not move:
-- the seller sent it, so it is confirmed now rather than assumed, and leaving
-- it out would make it indistinguishable from the cow.

update public.gift_items as g
   set price = v.price
  from (values
          ('gs1-shivling',             499),
          ('gs1-peacock-key-holder',   799),
          ('gs1-red-lotus-plate',      999),
          ('gs1-blue-lotus-frame',    1100),
          ('gs1-personalised-name',   1100),
          ('gs1-shri-charan',         1200),
          ('gs1-ivory-mirror',        1200),
          ('gs1-yellow-floral-mirror',1200),
          ('gs1-radha-naam',          1300),
          ('gs1-evil-eye-hanging',    2500),
          ('gs1-krishnaya-mantra',    4500),
          ('gs1-sita-ram',            4500),
          ('gs1-rose-mandala',        7000),
          ('gs1-lotus-arch-panel',   10000)
       ) as v (id, price)
 where g.id = v.id;
