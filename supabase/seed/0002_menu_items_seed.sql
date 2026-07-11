-- The mock menu, reproduced exactly: every restaurant served the same nine
-- dishes with ids prefixed by the restaurant ("r1-m1"), so the cart could never
-- confuse one vendor's paneer for another's.
--
-- Cross-joined rather than hand-written, because 8 restaurants x 9 dishes of
-- copy-paste is 72 chances to fat-finger a price. Real menus replace this when
-- partners onboard, one restaurant at a time.
--
-- Laccha Paratha keeps its missing photo on purpose: vendors skip photos, and
-- the UI's fallback has to be exercised against real data, not just in a test.

insert into public.menu_items
  (id, restaurant_id, name, description, price, is_veg, is_bestseller, rating,
   image_url, category, category_rank, item_rank)
select
  r.id || '-' || d.local_id,
  r.id,
  d.name, d.description, d.price, d.is_veg, d.is_bestseller, d.rating,
  d.image_url, d.category, d.category_rank, d.item_rank
from public.restaurants r
cross join (values
  ('m1', 'Signature Chicken Biryani',
   'Slow-cooked basmati, tender chicken, house masala, served with raita.',
   320, false, true, 4.5::numeric,
   'https://foodish-api.com/images/biryani/biryani2.jpg', 'Recommended', 0, 0),
  ('m2', 'Paneer Butter Masala',
   'Cottage cheese in a rich, buttery tomato gravy.',
   260, true, true, 4.3::numeric,
   'https://foodish-api.com/images/butter-chicken/butter-chicken2.jpg', 'Recommended', 0, 1),
  ('m3', 'Veg Hakka Noodles',
   'Wok-tossed noodles with crunchy vegetables.',
   210, true, false, null::numeric,
   'https://foodish-api.com/images/pasta/pasta2.jpg', 'Recommended', 0, 2),

  ('s1', 'Chilli Paneer',
   'Crispy paneer tossed in a spicy indo-chinese sauce.',
   240, true, false, 4.2::numeric,
   'https://foodish-api.com/images/butter-chicken/butter-chicken3.jpg', 'Starters', 1, 0),
  ('s2', 'Chicken 65',
   'Fiery, deep-fried chicken with curry leaves.',
   280, false, true, 4.6::numeric,
   'https://foodish-api.com/images/samosa/samosa2.jpg', 'Starters', 1, 1),

  ('b1', 'Butter Garlic Naan',
   'Tandoor-baked naan brushed with garlic butter.',
   70, true, false, null::numeric,
   'https://foodish-api.com/images/butter-chicken/butter-chicken5.jpg', 'Breads', 2, 0),
  ('b2', 'Laccha Paratha',
   'Flaky, multi-layered whole-wheat paratha.',
   60, true, false, null::numeric,
   '', 'Breads', 2, 1),

  ('d1', 'Gulab Jamun (2 pcs)',
   'Warm, syrup-soaked milk dumplings.',
   90, true, false, 4.4::numeric,
   'https://foodish-api.com/images/dessert/dessert1.jpg', 'Desserts', 3, 0),
  ('d2', 'Chocolate Brownie',
   'Fudgy brownie, best with ice cream.',
   130, true, false, null::numeric,
   'https://foodish-api.com/images/dessert/dessert2.jpg', 'Desserts', 3, 1)
) as d(local_id, name, description, price, is_veg, is_bestseller, rating,
       image_url, category, category_rank, item_rank)
on conflict (id) do nothing;
