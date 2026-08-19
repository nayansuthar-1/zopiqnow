-- Red Chilli Veg Restaurant, Ghanerao — the real catalogue, not a mock.
--
-- Seeded dark on request: `is_active = false` and `published_at = null`, so the
-- menu is visible to an admin and to nobody else. The 136 dishes and their
-- prices are transcribed from the three photographed pages of the printed card;
-- every price here is the card's price **plus the ₹10 platform markup**, which is
-- how a seeded menu has been priced since 2026-08-14.
--
-- Photos are already on Cloudinary under `zopiqnow/red-chilli/<slug>`, uploaded
-- signed with `overwrite = true` so re-running the upload replaces an asset
-- instead of minting a second one.
--
-- ⚠️ Placeholders that must be corrected before it goes live:
--   * the map pin — Ghanerao's centre, not the restaurant's door, and delivery
--     distance (and therefore the fee) is priced off it;
--   * the address line, the contact phone (null) and the owner (none);
--   * opening hours — 09:00–23:00 every day, nobody has confirmed them;
--   * the cover photo, which is one of the dish photos.
--
-- ⚠️ Two dishes carry no photo — Cutlets 2 Piece and Lemon Tea. The only images
-- supplied for them are Adobe Stock comps with the watermark tiled across the
-- whole frame, so there is nothing to crop away.
--
-- ⚠️ Four dishes the card prints are NOT here: Fry Khichiya (60), Fry Masala
-- Khichiya (90), Cheese Masala Khichiya (170) and Butter Khichiya (50). No photo
-- was supplied for any of them and the user chose to hold them back.

begin;

-- ---------------------------------------------------------------------------
-- Ghanerao becomes the fourth town. Inactive, because `area_for_point` only
-- matches active areas: while this is false the restaurant's service_area_id
-- stays null and no customer can be standing "in" Ghanerao. Flipping it to true
-- re-sorts every kitchen through the statement trigger 0126 installed, so the
-- restaurant joins its town on the same statement that opens the town.
--
--     update public.service_areas set is_active = true where id = 'ghanerao';
--
-- `catchment_id` stays null on purpose: Ghanerao is its own catchment, which is
-- exactly "show this restaurant in Ghanerao only".
-- ---------------------------------------------------------------------------
insert into public.service_areas (id, name, centre_lat, centre_lng, radius_km, is_active)
values ('ghanerao', 'Ghanerao', 25.2317, 73.5378, 5.00, false)
on conflict (id) do nothing;

insert into public.restaurants
  (id, name, cuisines, rating, rating_count, eta_minutes, price_for_two,
   is_veg, image_url, latitude, longitude, address_line, city, state, pincode,
   is_active, accepting_orders, published_at)
values
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34',
   'Red Chilli Veg Restaurant',
   array['North Indian','Rajasthani','Punjabi','Chinese','Snacks','Beverages'],
   0.0, 0, 30, 450, true,
   'https://res.cloudinary.com/w69i7qes/image/upload/v1787133211/zopiqnow/red-chilli/paneer-butter-masala.jpg',
   25.2317, 73.5378,
   'Ghanerao', 'Ghanerao', 'Rajasthan', '306704',
   false, true, null)
on conflict (id) do nothing;

-- Placeholder hours, so the kitchen is not shut on every day of the week the
-- moment somebody publishes it. The owner's real hours replace these.
insert into public.restaurant_hours (restaurant_id, day_of_week, opens, closes)
select 'b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', d, time '09:00', time '23:00'
from generate_series(1, 7) as d
on conflict (restaurant_id, day_of_week) do nothing;

-- Every dish is vegetarian — it is a pure-veg restaurant — and `is_veg` defaults
-- to false, so it is spelled out rather than left to the default.
--
-- `prep_minutes` is 15 on every row because the card says so in as many words:
-- "ऑर्डर देने के पश्चात् 15 मिनट लगेंगे".
--
-- The `where not exists` makes the file safe to run twice: the whole batch goes
-- in once, or not at all.
insert into public.menu_items
  (restaurant_id, name, description, price, is_veg, image_url,
   category, category_rank, item_rank, prep_minutes)
select v.* from (values
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Special Tea', 'Kadak masala chai brewed with milk, ginger and cardamom.', 35, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133057/zopiqnow/red-chilli/special-tea.jpg', 'Hot / Cold Drinks', 0, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Black Tea', 'Milk-free tea, brewed strong and served piping hot.', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133058/zopiqnow/red-chilli/black-tea.jpg', 'Hot / Cold Drinks', 0, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Lemon Tea', 'Clear tea sharpened with fresh lemon — light and refreshing.', 50, true, '', 'Hot / Cold Drinks', 0, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Special Coffee', 'Hot milk coffee, frothed and served in a cup.', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133059/zopiqnow/red-chilli/special-coffee.jpg', 'Hot / Cold Drinks', 0, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Black Coffee', 'Freshly brewed black coffee — no milk, no sugar unless you ask.', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133060/zopiqnow/red-chilli/black-coffee.jpg', 'Hot / Cold Drinks', 0, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Hot Milk', 'A tall glass of hot, lightly sweetened milk.', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133061/zopiqnow/red-chilli/hot-milk.jpg', 'Hot / Cold Drinks', 0, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Sweet Lime Soda', 'Chilled soda with fresh lime and a sweet finish.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133062/zopiqnow/red-chilli/sweet-lime-soda.jpg', 'Hot / Cold Drinks', 0, 6, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Fresh Lime Water', 'Shikanji — fresh lime, chilled water and a pinch of salt.', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133063/zopiqnow/red-chilli/fresh-lime-water.jpg', 'Hot / Cold Drinks', 0, 7, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Cutlets 2 Piece', 'Two crisp-fried veg cutlets with mint chutney and ketchup.', 110, true, '', 'Snacks', 1, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Sandwich', 'Toasted bread packed with fresh vegetables and green chutney.', 110, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133064/zopiqnow/red-chilli/veg-sandwich.jpg', 'Snacks', 1, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Cheese Sandwich', 'Grilled sandwich with a thick layer of melting cheese.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133065/zopiqnow/red-chilli/cheese-sandwich.jpg', 'Snacks', 1, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Toast Sandwich', 'The classic toasted sandwich — crisp outside, warm within.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133066/zopiqnow/red-chilli/toast-sandwich.jpg', 'Snacks', 1, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Cheese Grill Sandwich', 'Grilled sandwich stacked with vegetables and cheese.', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133067/zopiqnow/red-chilli/veg-cheese-grill-sandwich.jpg', 'Snacks', 1, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Pakoda', 'Mixed vegetable fritters fried golden in besan batter.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133068/zopiqnow/red-chilli/veg-pakoda.jpg', 'Snacks', 1, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Pyaz Pakoda', 'Sliced onion fritters, spiced and fried crisp.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133069/zopiqnow/red-chilli/pyaz-pakoda.jpg', 'Snacks', 1, 6, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Pakoda', 'Thick paneer slices in besan batter, fried till golden.', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133070/zopiqnow/red-chilli/paneer-pakoda.jpg', 'Snacks', 1, 7, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Aaloo Paratha', 'Potato-stuffed paratha off the tawa, with curd and pickle.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133071/zopiqnow/red-chilli/aaloo-paratha.jpg', 'Snacks', 1, 8, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Gobhi Paratha', 'Cauliflower-stuffed paratha, roasted with butter.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133072/zopiqnow/red-chilli/gobhi-paratha.jpg', 'Snacks', 1, 9, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Paratha', 'Paratha stuffed with spiced paneer, served hot.', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133074/zopiqnow/red-chilli/paneer-paratha.jpg', 'Snacks', 1, 10, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Chole Bhature', 'Two fluffy bhature with spiced chana, onion and pickle.', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133075/zopiqnow/red-chilli/chole-bhature.jpg', 'Snacks', 1, 11, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Extra Puri', 'An extra plate of fried puri to go with your chana.', 110, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133076/zopiqnow/red-chilli/extra-puri.jpg', 'Snacks', 1, 12, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Poha', 'Light kanda poha tempered with curry leaves, peanuts and lemon.', 110, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133077/zopiqnow/red-chilli/poha.jpg', 'Snacks', 1, 13, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Bread Butter', 'Soft bread slices with a generous spread of butter.', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133078/zopiqnow/red-chilli/bread-butter.jpg', 'Snacks', 1, 14, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg Cheese Sandwich', 'Loaded veg sandwich with extra cheese, grilled to order.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133080/zopiqnow/red-chilli/veg-cheese-sandwich.jpg', 'Snacks', 1, 15, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Tomato Soup', 'Creamy tomato soup, served hot.', 110, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133080/zopiqnow/red-chilli/tomato-soup.jpg', 'A-1 Hot Soup', 2, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Manchow Soup', 'Spicy Indo-Chinese soup with chopped veg and crisp noodles.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133081/zopiqnow/red-chilli/veg-manchow-soup.jpg', 'A-1 Hot Soup', 2, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Hot ''N'' Sour Soup', 'Peppery, tangy broth with finely chopped vegetables.', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133083/zopiqnow/red-chilli/hot-n-sour-soup.jpg', 'A-1 Hot Soup', 2, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Dal Fry', 'Yellow dal tempered with jeera, garlic and tomato.', 140, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133085/zopiqnow/red-chilli/dal-fry.jpg', 'Evergreen Dals', 3, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Spl. Dal Fry Butter', 'Dal fry finished with a generous spoon of butter.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133086/zopiqnow/red-chilli/spl-dal-fry-butter.jpg', 'Evergreen Dals', 3, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Spl. Dal Tadka', 'Dal under a smoking tadka of ghee, garlic and red chilli.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133088/zopiqnow/red-chilli/spl-dal-tadka.jpg', 'Evergreen Dals', 3, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Green Salad', 'Cucumber, tomato, onion and carrot, cut fresh.', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133089/zopiqnow/red-chilli/green-salad.jpg', 'Salad & Raita', 4, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Onion Salad', 'Sliced onion rings with lemon and chaat masala.', 40, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133090/zopiqnow/red-chilli/onion-salad.jpg', 'Salad & Raita', 4, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Mirchi Fry', 'Fried green chillies with salt — hot and simple.', 40, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133091/zopiqnow/red-chilli/mirchi-fry.jpg', 'Salad & Raita', 4, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Tomato Salad', 'Fresh tomato slices with salt and pepper.', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133093/zopiqnow/red-chilli/tomato-salad.jpg', 'Salad & Raita', 4, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kachumber Salad', 'Finely chopped cucumber, tomato and onion with lemon.', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133094/zopiqnow/red-chilli/kachumber-salad.jpg', 'Salad & Raita', 4, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Jain Salad', 'Cut fresh to order, without onion or garlic.', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133095/zopiqnow/red-chilli/jain-salad.jpg', 'Salad & Raita', 4, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Boondi Raita', 'Whisked curd with soft boondi and roasted jeera.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133096/zopiqnow/red-chilli/boondi-raita.jpg', 'Salad & Raita', 4, 6, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Raita', 'Curd with chopped cucumber, tomato and onion.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133097/zopiqnow/red-chilli/veg-raita.jpg', 'Salad & Raita', 4, 7, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Pineapple Raita', 'Sweet pineapple folded into chilled, whisked curd.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133100/zopiqnow/red-chilli/pineapple-raita.jpg', 'Salad & Raita', 4, 8, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Dahi Fry', 'Curd cooked under a hot tadka — tangy and rich.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133101/zopiqnow/red-chilli/dahi-fry.jpg', 'Salad & Raita', 4, 9, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Dahi Plate', 'A plate of thick, fresh curd.', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133102/zopiqnow/red-chilli/dahi-plate.jpg', 'Salad & Raita', 4, 10, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Special Lassi', 'Thick sweet lassi, churned and topped with dry fruit.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133103/zopiqnow/red-chilli/special-lassi.jpg', 'Salad & Raita', 4, 11, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Salted Lassi', 'Chilled salted lassi, churned smooth.', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133103/zopiqnow/red-chilli/salted-lassi.jpg', 'Salad & Raita', 4, 12, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Masala Chaach', 'Buttermilk spiced with jeera, mint and black salt.', 40, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133104/zopiqnow/red-chilli/masala-chaach.jpg', 'Salad & Raita', 4, 13, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Roti', 'Tandoori roti, fresh off the clay oven.', 28, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133105/zopiqnow/red-chilli/roti.jpg', 'Tanduri Roti Ka Kamal', 5, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Butter Roti', 'Tandoori roti brushed with butter.', 30, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133106/zopiqnow/red-chilli/butter-roti.jpg', 'Tanduri Roti Ka Kamal', 5, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Sada Paratha', 'Layered plain paratha, crisp at the edges.', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133107/zopiqnow/red-chilli/sada-paratha.jpg', 'Tanduri Roti Ka Kamal', 5, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Butter Paratha', 'Flaky paratha finished with butter.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133108/zopiqnow/red-chilli/butter-paratha.jpg', 'Tanduri Roti Ka Kamal', 5, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Naan', 'Soft tandoori naan, baked to order.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133109/zopiqnow/red-chilli/naan.jpg', 'Tanduri Roti Ka Kamal', 5, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Butter Naan', 'Tandoori naan brushed generously with butter.', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133110/zopiqnow/red-chilli/butter-naan.jpg', 'Tanduri Roti Ka Kamal', 5, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Garlic Naan', 'Naan topped with chopped garlic and coriander.', 140, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133112/zopiqnow/red-chilli/garlic-naan.jpg', 'Tanduri Roti Ka Kamal', 5, 6, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Cheese Naan', 'Naan stuffed with melting cheese.', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133114/zopiqnow/red-chilli/cheese-naan.jpg', 'Tanduri Roti Ka Kamal', 5, 7, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kulcha', 'Soft tandoori kulcha, sprinkled with kalonji.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133115/zopiqnow/red-chilli/kulcha.jpg', 'Tanduri Roti Ka Kamal', 5, 8, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Butter Kulcha', 'Tandoori kulcha finished with butter.', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133116/zopiqnow/red-chilli/butter-kulcha.jpg', 'Tanduri Roti Ka Kamal', 5, 9, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Family Naan', 'One long naan, made to share across the table.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133117/zopiqnow/red-chilli/family-naan.jpg', 'Tanduri Roti Ka Kamal', 5, 10, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Stuffed Naan', 'Naan stuffed with a spiced filling, straight from the tandoor.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133119/zopiqnow/red-chilli/stuffed-naan.jpg', 'Tanduri Roti Ka Kamal', 5, 11, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Sadi Spl. Missi Roti', 'Besan-and-atta missi roti with ajwain and green chilli.', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133120/zopiqnow/red-chilli/sadi-spl-missi-roti.jpg', 'Tanduri Roti Ka Kamal', 5, 12, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Garlic Cheese Naan', 'Naan loaded with cheese and garlic.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133121/zopiqnow/red-chilli/garlic-cheese-naan.jpg', 'Tanduri Roti Ka Kamal', 5, 13, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Lacha Paratha', 'Many-layered lachha paratha off the tandoor.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133121/zopiqnow/red-chilli/lacha-paratha.jpg', 'Tanduri Roti Ka Kamal', 5, 14, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'B. Lacha Paratha', 'Lachha paratha finished with butter.', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133122/zopiqnow/red-chilli/b-lacha-paratha.jpg', 'Tanduri Roti Ka Kamal', 5, 15, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Pulav', 'Basmati rice cooked with mixed vegetables and whole spices.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133124/zopiqnow/red-chilli/veg-pulav.jpg', 'Rice Ki Khushbu', 6, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kaju Pulav', 'Pulav studded with roasted cashew.', 190, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133125/zopiqnow/red-chilli/kaju-pulav.jpg', 'Rice Ki Khushbu', 6, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kashmiri Pulav', 'Sweet-spiced pulav with dry fruit and pomegranate.', 200, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133126/zopiqnow/red-chilli/kashmiri-pulav.jpg', 'Rice Ki Khushbu', 6, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Biryani', 'Layered veg biryani with saffron rice and fried onion.', 200, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133127/zopiqnow/red-chilli/veg-biryani.jpg', 'Rice Ki Khushbu', 6, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Hyderabadi Biryani', 'Dum-cooked Hyderabadi biryani — spicier, richer.', 200, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133135/zopiqnow/red-chilli/veg-hyderabadi-biryani.jpg', 'Rice Ki Khushbu', 6, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Masala Fry Rice', 'Rice tossed with vegetables in a hot masala.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133136/zopiqnow/red-chilli/masala-fry-rice.jpg', 'Rice Ki Khushbu', 6, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Jeera Rice', 'Basmati rice tempered with cumin and ghee.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133137/zopiqnow/red-chilli/jeera-rice.jpg', 'Rice Ki Khushbu', 6, 6, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Plain Rice', 'Steamed basmati rice, plain and fluffy.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133138/zopiqnow/red-chilli/plain-rice.jpg', 'Rice Ki Khushbu', 6, 7, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Steam Rice', 'Plain steamed rice, served hot.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133139/zopiqnow/red-chilli/steam-rice.jpg', 'Rice Ki Khushbu', 6, 8, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Fried Rice', 'Indo-Chinese fried rice tossed with vegetables.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133141/zopiqnow/red-chilli/veg-fried-rice.jpg', 'Rice Ki Khushbu', 6, 9, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Masala Khichiya', 'Roasted khichiya papad topped with onion, tomato and sev.', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133142/zopiqnow/red-chilli/masala-khichiya.jpg', 'Starter', 7, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Masala Papad', 'Papad topped with chopped onion, tomato and masala.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133143/zopiqnow/red-chilli/masala-papad.jpg', 'Starter', 7, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Roasted Papad', 'Papad roasted over the flame.', 40, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133144/zopiqnow/red-chilli/roasted-papad.jpg', 'Starter', 7, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Fry Papad', 'Papad fried crisp and served hot.', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133145/zopiqnow/red-chilli/fry-papad.jpg', 'Starter', 7, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Chilli Dry', 'Paneer tossed dry with capsicum, onion and chilli.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133146/zopiqnow/red-chilli/paneer-chilli-dry.jpg', 'Starter', 7, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Chilli Liquid', 'Chilli paneer in a thick, tangy Indo-Chinese gravy.', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133151/zopiqnow/red-chilli/paneer-chilli-liquid.jpg', 'Starter', 7, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Manchurian Dry', 'Fried veg balls tossed in a dry Manchurian sauce.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133152/zopiqnow/red-chilli/veg-manchurian-dry.jpg', 'Starter', 7, 6, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Manchurian Liquid', 'Veg Manchurian balls in a hot, tangy gravy.', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133152/zopiqnow/red-chilli/veg-manchurian-liquid.jpg', 'Starter', 7, 7, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Finger Chips', 'Crisp salted French fries.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133154/zopiqnow/red-chilli/finger-chips.jpg', 'Starter', 7, 8, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Plain Chapati', 'Soft tawa chapati, made fresh.', 28, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133154/zopiqnow/red-chilli/plain-chapati.jpg', 'Tawa Roti Ka Jalwa', 8, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Butter Chapati', 'Tawa chapati with butter.', 30, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133155/zopiqnow/red-chilli/butter-chapati.jpg', 'Tawa Roti Ka Jalwa', 8, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Spl. Tikkad', 'Thick Rajasthani tikkad roti off the tawa.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133156/zopiqnow/red-chilli/spl-tikkad.jpg', 'Tawa Roti Ka Jalwa', 8, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Tawa Parantha', 'Layered paratha roasted on the tawa.', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133157/zopiqnow/red-chilli/tawa-parantha.jpg', 'Tawa Roti Ka Jalwa', 8, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Butter Tawa Parantha', 'Tawa paratha finished with butter.', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133162/zopiqnow/red-chilli/butter-tawa-parantha.jpg', 'Tawa Roti Ka Jalwa', 8, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Ghee / Gud', 'Pure ghee with jaggery — the Rajasthani finish to a meal.', 110, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133171/zopiqnow/red-chilli/ghee-gud.jpg', 'Tawa Roti Ka Jalwa', 8, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Jaipuri', 'Mixed vegetables in a spiced Jaipuri-style gravy.', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133175/zopiqnow/red-chilli/veg-jaipuri.jpg', 'Seasonal Sabjiya', 9, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Kolhapuri', 'Vegetables in a fiery Kolhapuri masala.', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133180/zopiqnow/red-chilli/veg-kolhapuri.jpg', 'Seasonal Sabjiya', 9, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Makhanwala', 'Vegetables in a mild, buttery tomato gravy.', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133182/zopiqnow/red-chilli/veg-makhanwala.jpg', 'Seasonal Sabjiya', 9, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Patiyala', 'Punjabi-style veg curry — rich and lightly spiced.', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133186/zopiqnow/red-chilli/veg-patiyala.jpg', 'Seasonal Sabjiya', 9, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Chatpata', 'Tangy chatpata mixed veg with capsicum and onion.', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133187/zopiqnow/red-chilli/veg-chatpata.jpg', 'Seasonal Sabjiya', 9, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Haandi', 'Mixed vegetables slow-cooked in a handi.', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133188/zopiqnow/red-chilli/veg-haandi.jpg', 'Seasonal Sabjiya', 9, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Mix Veg.', 'Seasonal vegetables cooked in an everyday masala.', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133189/zopiqnow/red-chilli/mix-veg.jpg', 'Seasonal Sabjiya', 9, 6, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Dum Aaloo', 'Baby potatoes simmered in a thick, spiced gravy.', 230, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133190/zopiqnow/red-chilli/dum-aaloo.jpg', 'Seasonal Sabjiya', 9, 7, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kashmiri Dum Aaloo', 'Dum aloo in a Kashmiri red gravy — mild and aromatic.', 250, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133191/zopiqnow/red-chilli/kashmiri-dum-aaloo.jpg', 'Seasonal Sabjiya', 9, 8, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Chana Masala', 'Chickpeas cooked in onion-tomato masala.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133192/zopiqnow/red-chilli/chana-masala.jpg', 'Seasonal Sabjiya', 9, 9, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Aaloo Palak', 'Potato cooked with fresh spinach.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133193/zopiqnow/red-chilli/aaloo-palak.jpg', 'Seasonal Sabjiya', 9, 10, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Aaloo Jeera', 'Dry potato tossed with cumin.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133194/zopiqnow/red-chilli/aaloo-jeera.jpg', 'Seasonal Sabjiya', 9, 11, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Aaloo Matar', 'Potato and green peas in a light gravy.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133195/zopiqnow/red-chilli/aaloo-matar.jpg', 'Seasonal Sabjiya', 9, 12, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Plain Palak', 'Fresh spinach cooked simply, with garlic.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133195/zopiqnow/red-chilli/plain-palak.jpg', 'Seasonal Sabjiya', 9, 13, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Sev Tamatar', 'The Marwari favourite — tomato gravy under crisp sev.', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133197/zopiqnow/red-chilli/sev-tamatar.jpg', 'Seasonal Sabjiya', 9, 14, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Sev Bhaji', 'Besan sev simmered in a spicy tomato gravy.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133198/zopiqnow/red-chilli/sev-bhaji.jpg', 'Seasonal Sabjiya', 9, 15, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Bhindi Masala', 'Okra sautéed with onion and dry masala.', 140, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133199/zopiqnow/red-chilli/bhindi-masala.jpg', 'Seasonal Sabjiya', 9, 16, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Aaloo Tamatar', 'Potato in a light tomato curry.', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133200/zopiqnow/red-chilli/aaloo-tamatar.jpg', 'Seasonal Sabjiya', 9, 17, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Matar Palak', 'Green peas cooked into fresh spinach gravy.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133200/zopiqnow/red-chilli/matar-palak.jpg', 'Seasonal Sabjiya', 9, 18, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Shahi Besan Gatta Masala', 'Besan gatte in a rich, shahi curd gravy.', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133201/zopiqnow/red-chilli/shahi-besan-gatta-masala.jpg', 'Seasonal Sabjiya', 9, 19, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Gatta Masala', 'Rajasthani besan gatte in a spiced curd gravy.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133202/zopiqnow/red-chilli/gatta-masala.jpg', 'Seasonal Sabjiya', 9, 20, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Lasan Chutney', 'Fiery Rajasthani garlic-and-red-chilli chutney.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133203/zopiqnow/red-chilli/lasan-chutney.jpg', 'Seasonal Sabjiya', 9, 21, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Sp. Red Chilli Paneer', 'The house paneer — fiery red chilli masala with capsicum and onion.', 250, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133204/zopiqnow/red-chilli/sp-red-chilli-paneer.jpg', 'Panner Ki Pasand', 10, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Tufani', 'Paneer in a bold, hot tufani gravy.', 250, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133205/zopiqnow/red-chilli/paneer-tufani.jpg', 'Panner Ki Pasand', 10, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Pasanda', 'Stuffed paneer slices in a creamy cashew gravy.', 270, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133205/zopiqnow/red-chilli/paneer-pasanda.jpg', 'Panner Ki Pasand', 10, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Kolhapuri', 'Paneer in a fiery Kolhapuri masala.', 240, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133206/zopiqnow/red-chilli/paneer-kolhapuri.jpg', 'Panner Ki Pasand', 10, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Handi', 'Paneer slow-cooked in a handi with onion-tomato masala.', 240, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133207/zopiqnow/red-chilli/paneer-handi.jpg', 'Panner Ki Pasand', 10, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Kadai', 'Paneer and capsicum tossed in fresh kadai masala.', 240, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133208/zopiqnow/red-chilli/paneer-kadai.jpg', 'Panner Ki Pasand', 10, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Shahi Paneer', 'Paneer in a mild, creamy shahi gravy.', 240, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133209/zopiqnow/red-chilli/shahi-paneer.jpg', 'Panner Ki Pasand', 10, 6, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Bhurji', 'Grated paneer scrambled with onion, tomato and spices.', 250, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133210/zopiqnow/red-chilli/paneer-bhurji.jpg', 'Panner Ki Pasand', 10, 7, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Butter Masala', 'Paneer in a buttery tomato gravy — mild and rich.', 240, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133211/zopiqnow/red-chilli/paneer-butter-masala.jpg', 'Panner Ki Pasand', 10, 8, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Cheese Butter Masala', 'Paneer butter masala finished with melted cheese.', 260, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133212/zopiqnow/red-chilli/paneer-cheese-butter-masala.jpg', 'Panner Ki Pasand', 10, 9, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Cheese Masala', 'Paneer and cheese in a thick, spiced masala.', 250, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133213/zopiqnow/red-chilli/paneer-cheese-masala.jpg', 'Panner Ki Pasand', 10, 10, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Tikka Masala', 'Tandoori-style paneer tikka simmered in masala gravy.', 240, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133213/zopiqnow/red-chilli/paneer-tikka-masala.jpg', 'Panner Ki Pasand', 10, 11, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kaju Paneer Masala', 'Paneer and cashew in a rich, creamy masala.', 280, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133214/zopiqnow/red-chilli/kaju-paneer-masala.jpg', 'Panner Ki Pasand', 10, 12, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kaju Curry', 'Whole cashews in a thick, mildly sweet gravy.', 280, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133215/zopiqnow/red-chilli/kaju-curry.jpg', 'Panner Ki Pasand', 10, 13, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Cheese Butter Masala', 'Cheese cubes in a buttery tomato gravy.', 270, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133216/zopiqnow/red-chilli/cheese-butter-masala.jpg', 'Panner Ki Pasand', 10, 14, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Cheese Lahsuniya', 'Cheese in a garlic-forward masala gravy.', 270, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133217/zopiqnow/red-chilli/cheese-lahsuniya.jpg', 'Panner Ki Pasand', 10, 15, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Palak Paneer', 'Paneer cubes in fresh spinach gravy.', 240, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133218/zopiqnow/red-chilli/palak-paneer.jpg', 'Panner Ki Pasand', 10, 16, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Matar Paneer', 'Paneer and green peas in onion-tomato gravy.', 240, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133219/zopiqnow/red-chilli/matar-paneer.jpg', 'Panner Ki Pasand', 10, 17, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Navratan Korma', 'Nine vegetables and dry fruit in a mild, creamy korma.', 290, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133220/zopiqnow/red-chilli/navratan-korma.jpg', 'Panner Ki Pasand', 10, 18, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kaju Fry Masala', 'Fried cashews tossed in a dry, spiced masala.', 280, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133221/zopiqnow/red-chilli/kaju-fry-masala.jpg', 'Panner Ki Pasand', 10, 19, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Malai Pyaz', 'Baby onions in a creamy malai gravy.', 230, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133222/zopiqnow/red-chilli/malai-pyaz.jpg', 'Panner Ki Pasand', 10, 20, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Veg. Kofta', 'Vegetable koftas in a rich onion-tomato gravy.', 270, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133222/zopiqnow/red-chilli/veg-kofta.jpg', 'Kofta Ka Kamal', 11, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Malai Kofta', 'Soft koftas in a creamy, mildly sweet malai gravy.', 280, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133223/zopiqnow/red-chilli/malai-kofta.jpg', 'Kofta Ka Kamal', 11, 1, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Kashmiri Kofta', 'Koftas in a Kashmiri red gravy — aromatic and mild.', 290, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133224/zopiqnow/red-chilli/kashmiri-kofta.jpg', 'Kofta Ka Kamal', 11, 2, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Cheese Kofta', 'Cheese-filled koftas in a smooth, rich gravy.', 290, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133225/zopiqnow/red-chilli/cheese-kofta.jpg', 'Kofta Ka Kamal', 11, 3, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Paneer Kofta', 'Paneer koftas simmered in a thick masala gravy.', 290, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133226/zopiqnow/red-chilli/paneer-kofta.jpg', 'Kofta Ka Kamal', 11, 4, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Cheese Anguri', 'Small cheese-stuffed koftas in a creamy gravy.', 280, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133234/zopiqnow/red-chilli/cheese-anguri.jpg', 'Kofta Ka Kamal', 11, 5, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Spl. Haldi', 'Winter special — fresh turmeric root cooked into a rich Rajasthani sabzi.', 360, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133235/zopiqnow/red-chilli/spl-haldi.jpg', 'Sardi Special', 12, 0, 15),
  ('b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34', 'Bajri Roti', 'Winter special — hand-patted millet roti, best with ghee.', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787133236/zopiqnow/red-chilli/bajri-roti.jpg', 'Sardi Special', 12, 1, 15)
) as v (restaurant_id, name, description, price, is_veg, image_url,
        category, category_rank, item_rank, prep_minutes)
where not exists (
  select 1 from public.menu_items where restaurant_id = 'b7c1e0a2-4d3f-4a56-9e21-7f0c8d5a1b34'
);

commit;
