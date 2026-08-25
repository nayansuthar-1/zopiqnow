-- Lily Café and Restaurant, Sadri — the real catalogue, transcribed from the
-- printed card supplied as an 8-page PDF, plus the 156 dish photos supplied
-- alongside it.
--
-- Seeded DARK: `is_active = false` and `published_at = null`, so an admin can
-- see it and no customer can. It is one UPDATE from going live — see the bottom
-- of this file — but the map pin, the opening hours and the owner are all still
-- placeholders, so do not flip it until they are real.
--
-- 154 dishes across 15 sections. Every price here is the card's price **plus the
-- ₹10 platform markup**, which is how a seeded menu has been priced since
-- 2026-08-14.
--
-- Photos are on Cloudinary under `zopiqnow/lily/<slug>`, uploaded signed with
-- `overwrite = true` so re-running the upload replaces an asset instead of
-- minting a second one. 22 of them went up with an **incoming** crop
-- transformation, so the STORED asset is clean and `image_url` stays plain —
-- which keeps the console's crop adjuster working.
--
-- ⚠️ THREE DISHES THE CARD PRINTS ARE NOT HERE. Packaged Water, Aerated
-- Beverage and Energy Drink (Red Bull) are all priced "MRP" on the card, and
-- `menu_items.price` has a `> 0` check, so they cannot go in without numbers.
-- Same reason Wing Orbit's desserts are still unseeded.
--
-- ⚠️ DAL MAKHANI'S PRICE IS A READING. The card prints "1798", which is not a
-- price — every neighbour on that column is 129–179 and the two dishes directly
-- above it are both 179. Seeded as 179 (+10 = 189). Confirm with the kitchen.
--
-- ⚠️ 24 DISHES CARRY NO PHOTO, and the reasons matter:
--   * 12 had no file supplied at all — the five Marwar Ke Starter khichiyas,
--     Makai Matar Pyaza, Rabori Kanda, Dal Ranakpuri, Rajasthani Tukkad,
--     Kiddo Maggie, Ice Cream Cart, Spaghetti Aglio E Olio.
--   * 4 were supplied with NON-VEG food in the frame, and this is a pure-veg
--     kitchen: Spring Roll (prawns), Traditional Club Sandwich (bacon and
--     turkey), Pizza Fiamma (sausage), Extra Loaded Chef Special (bacon — and
--     it is a tray of fries, not a pizza). Laziz Kathi Roll (Creamy) reads as a
--     meat filling and was held back on the same reasoning.
--   * 3 carry a watermark that cannot be cropped away: Hariyali Paneer
--     ("Cooking from Heart", dead centre), Punjabi Thali (a Dreamstime comp,
--     tiled across the whole frame), Aam Panna ("Kuch Pak Raha Hai", mid-frame —
--     the same mark that cost Purohit Bakers two photos).
--   * 1 is a YouTube thumbnail with the play button burned in: Veggie Fingers.
--   * 3 are the wrong dish: Khum Tamatar Khada Masala (a tomato thokku, no
--     mushroom, hand in frame), Agli Spinaci (creamed-spinach penne, but the
--     card describes a pizza), Karari Chole Palak Ke Kabab (the file is
--     byte-identical to the Hara Bhara Kabab photo).
--
-- ⚠️ PLACEHOLDERS THAT BLOCK PUBLISH:
--   * the map pin is **Sadri's town centre**, not the restaurant's door, and the
--     delivery fee is priced off it. The card's address is "Opp. Mukti Dham,
--     Falna Road" — a real place, but not one this file can turn into a pin.
--   * opening hours — 09:00–23:00 every day, nobody has confirmed them;
--   * no owner (`owner_name` null). The card gives lilycaferestaurant@gmail.com,
--     which is what an owner login would be built from;
--   * the cover photo is the Lily Special Tandoori Pizza dish shot;
--   * `price_for_two = 600` and `eta_minutes = 30` are estimates. The card
--     states no lead time at all, and 30 is the column's own default.
--
-- ⚠️ THE CARD CALLS ITSELF "ITALIAN | MEXICAN | PUNJABI" but there is not one
-- Mexican dish on it. `cuisines` omits Mexican on purpose — a tag drives search,
-- and matching a Mexican search with this menu would only disappoint.
--
-- ⚠️ THE CARD PRINTS CHAAS TWICE at two prices: ₹29 under Dahi Preparations
-- ("chef special, 30 minutes") and ₹39 under All Time Beverages ("plain/salted/
-- masala"). Both are seeded as printed, in their own sections. Cold Coffee is
-- the same story — ₹99 in the left beverage column and ₹150 in the right, the
-- second reading "with or without ice cream"; seeded as "Cold Coffee" and "Cold
-- Coffee with Ice Cream". Worth telling the restaurant; it looks like a printing
-- error on their side, the way Wing Orbit's duplicates did.
--
-- `prep_minutes` is null on all but two rows, because the card states a lead
-- time for exactly two dishes — Smoked Raita (25 min) and Chaas (30 min). A
-- guessed prep time is worse than silence.
--
-- Names were normalised off the card's spellings (Liliy→Lily, Italain→Italian,
-- Plater→Platter, BHARWAALOO→Bharwa Aloo, Lushooni kept as printed,
-- Khumtamatar→Khum Tamatar, Indo-Italain→Indo-Italian, Rajasthai→Rajasthani).
-- Section headings are the card's own, except "DAHI PREPRATIONS", whose typo was
-- corrected — customers read these.

begin;

insert into public.restaurants
  (id, name, cuisines, rating, rating_count, eta_minutes, price_for_two,
   is_veg, image_url, latitude, longitude, address_line, city, state, pincode,
   contact_phone, is_active, accepting_orders, published_at)
values
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e',
   'Lily Café and Restaurant',
   array['Italian','Punjabi','Rajasthani','North Indian','Chinese','Continental','Desserts','Beverages'],
   0.0, 0, 30, 600, true,
   'https://res.cloudinary.com/w69i7qes/image/upload/v1787667788/zopiqnow/lily/lily-special-tandoori-pizza.jpg',
   25.1857, 73.4386,
   'Opp. Mukti Dham, Falna Road', 'Sadri', 'Rajasthan', '306702',
   '8619534200',
   false, true, null)
on conflict (id) do nothing;

-- The 0126 trigger sets `service_area_id` from the pin, so this row joins Sadri
-- on insert with no help from this file. Move the pin and it re-sorts itself.

-- Placeholder hours, so the kitchen is not shut on every day of the week the
-- moment somebody publishes it. The owner's real hours replace these.
insert into public.restaurant_hours (restaurant_id, day_of_week, opens, closes)
select '4735d102-fdde-4ab1-8c69-fed7ef5ed30e', d, time '09:00', time '23:00'
from generate_series(1, 7) as d
on conflict (restaurant_id, day_of_week) do nothing;

-- Every dish is vegetarian — the card's own words are "Veg Multi Cuisine
-- Restaurant" — and `is_veg` defaults to false, so it is spelled out rather than
-- left to the default.
--
-- The `where not exists` makes the file safe to run twice: the whole batch goes
-- in once, or not at all.
insert into public.menu_items
  (restaurant_id, name, description, price, is_veg, image_url,
   category, category_rank, item_rank, prep_minutes)
select v.* from (values
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Tomato Soup', 'Fresh roasted chunky tomato puree with herbs and cream, along with roasted croutons.', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667578/zopiqnow/lily/tomato-soup.jpg', 'Soup', 0, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Choice of Shorba', 'It''s a spicy, sour and hot soup with vegetable that''s popular in Indo-Chinese cuisine.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667580/zopiqnow/lily/choice-of-shorba.jpg', 'Soup', 0, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Veg. Manchow Soup', 'A dark brown soup prepared with various vegetables and flavoured with garlic, ginger, soya sauce and chilli, served with crispy fried noodles.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667581/zopiqnow/lily/veg-manchow-soup.jpg', 'Soup', 0, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Sweet Corn Soup', 'Corn kernels in cream and aromatic stock, mixed with spring onion.', 119, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667582/zopiqnow/lily/sweet-corn-soup.jpg', 'Soup', 0, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Burnt Garlic Spinach Soup', 'Spinach broth base soup with the delightful flavour and aroma of burnt garlic.', 119, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667585/zopiqnow/lily/burnt-garlic-spinach-soup.jpg', 'Soup', 0, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cream of Soup', 'Vegetable / Mushroom / Spinach.', 129, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667587/zopiqnow/lily/cream-of-soup.jpg', 'Soup', 0, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Fresh Green Salad', 'A mix of fresh cucumber, tomato, onion, lemon & green chilli.', 69, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667594/zopiqnow/lily/fresh-green-salad.jpg', 'Salad', 1, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Masala Ring Onion Salad', 'Rings of onion sprinkled with tangy masala.', 59, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667595/zopiqnow/lily/masala-ring-onion-salad.jpg', 'Salad', 1, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Russian Salad', 'Originally invented by Lucien Olivier for a Moscow restaurant called Hermitage in the 1860s.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667597/zopiqnow/lily/russian-salad.jpg', 'Salad', 1, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lily Special Salad', 'Chef special healthy salad.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667598/zopiqnow/lily/lily-special-salad.jpg', 'Salad', 1, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Tossed Salad', 'Tossing greens in a chef special dressing.', 69, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667600/zopiqnow/lily/tossed-salad.jpg', 'Salad', 1, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Palak Pakodi Chat', 'Layers of crisp spinach fritters drizzled with tamarind, mint and yogurt sauce.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667601/zopiqnow/lily/palak-pakodi-chat.jpg', 'Salad', 1, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Chaat of the Day', 'Chef special, mouth-watering.', 129, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667602/zopiqnow/lily/chaat-of-the-day.jpg', 'Salad', 1, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Raita', 'Boondi / Veg. / Cucumber.', 79, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667603/zopiqnow/lily/raita.jpg', 'Dahi Preparations', 2, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pineapple Raita', 'Sweet pineapple folded into chilled, whisked curd.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667605/zopiqnow/lily/pineapple-raita.jpg', 'Dahi Preparations', 2, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Tadka Dahi', 'Whisked curd finished with a hot tempering of cumin and red chilli.', 89, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667606/zopiqnow/lily/tadka-dahi.jpg', 'Dahi Preparations', 2, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Smoked Raita', 'Chef special — please allow 25 minutes.', 119, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667608/zopiqnow/lily/smoked-raita.jpg', 'Dahi Preparations', 2, 3, 25),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Chaas (Masala or Plain)', 'Chef special — please allow 30 minutes.', 39, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667609/zopiqnow/lily/chaas-masala-or-plain.jpg', 'Dahi Preparations', 2, 4, 30),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Roasted Khichiya / Papad', 'Khichiya or papad roasted over the flame.', 49, true, '', 'Marwar Ke Starter', 3, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Fried Khichiya / Papad', 'Khichiya or papad fried crisp and served hot.', 59, true, '', 'Marwar Ke Starter', 3, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Masala Papad / Khichiya', 'Topped with chopped onion, tomato and tangy masala.', 79, true, '', 'Marwar Ke Starter', 3, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lily Special Khichiya', 'The house khichiya, dressed the chef’s own way.', 109, true, '', 'Marwar Ke Starter', 3, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Italian Fusion Khichiya', 'Khichiya given an Italian turn — herbs, cheese and a tangy dressing.', 129, true, '', 'Marwar Ke Starter', 3, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Laziz Pakoda', 'Vegetable / Moong Dal.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667610/zopiqnow/lily/laziz-pakoda.jpg', 'Snacks / Appetizer', 4, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Paneer Pakoda', 'Served with mint sauce.', 139, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667611/zopiqnow/lily/paneer-pakoda.jpg', 'Snacks / Appetizer', 4, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Paneer Chilli', 'Batter-coated fried paneer cubes, onion and capsicum tossed in a flavoured spicy sauce made with soya, chilli and vinegar.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667612/zopiqnow/lily/paneer-chilli.jpg', 'Snacks / Appetizer', 4, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Dry Manchurian', 'A delicious Indo-Chinese dish made with wisps of vegetable formed into dumplings and dunked into a sauce with a gorgeous interplay of hot, sweet, sour and salty flavour.', 149, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667613/zopiqnow/lily/dry-manchurian.jpg', 'Snacks / Appetizer', 4, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Crispy Honey Chilli Potato', 'Crispy fried fries tossed in sweet & sour Chinese sauce, topped with sesame seeds.', 149, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667614/zopiqnow/lily/crispy-honey-chilli-potato.jpg', 'Snacks / Appetizer', 4, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Italian Cheese Balls', 'Italian balls with feta & mozzarella, served with mayo dip.', 219, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667615/zopiqnow/lily/italian-cheese-balls.jpg', 'Snacks / Appetizer', 4, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cheese Mayo French Fries', 'Crispy golden-brown fries topped with melting cheese & mayo, seasoned with spices.', 209, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667617/zopiqnow/lily/cheese-mayo-french-fries.jpg', 'Snacks / Appetizer', 4, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Crispy Fries', 'Plain / Salted / Peri Peri.', 119, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667618/zopiqnow/lily/crispy-fries.jpg', 'Snacks / Appetizer', 4, 7, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Chef Special Cheese Cigar', 'Chef special cheese and herbs blend roll.', 219, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667620/zopiqnow/lily/chef-special-cheese-cigar.jpg', 'Snacks / Appetizer', 4, 8, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Crispy Vegetables', 'Assorted batter-fried vegetable tossed with hot garlic sauce.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667622/zopiqnow/lily/crispy-vegetables.jpg', 'Snacks / Appetizer', 4, 9, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Crispy Corn with Hot Garlic Sauce', 'Batter-fried corn tossed with hot garlic sauce.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667623/zopiqnow/lily/crispy-corn-with-hot-garlic-sauce.jpg', 'Snacks / Appetizer', 4, 10, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Hara Bhara Kabab', 'Deep-fried assorted minced veg. & spinach kabab served with green chutney.', 139, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667624/zopiqnow/lily/hara-bhara-kabab.jpg', 'Snacks / Appetizer', 4, 11, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Spring Roll', 'Crispy roll filled with a savoury vegetable stuffing, served with dipping sauce.', 169, true, '', 'Snacks / Appetizer', 4, 12, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Jain Hing Kachori', 'Accompanied with chef special tamarind chutney.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667626/zopiqnow/lily/jain-hing-kachori.jpg', 'Snacks / Appetizer', 4, 13, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kathi Roll', 'Paneer / Vegetables / Indo-Chinese.', 149, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667627/zopiqnow/lily/kathi-roll.jpg', 'Snacks / Appetizer', 4, 14, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Laziz Kathi Roll (Creamy)', 'Fusion of Italian wrap.', 169, true, '', 'Snacks / Appetizer', 4, 15, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cheese Corn Triangles', 'Accompanied with spicy mayo dip.', 129, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667628/zopiqnow/lily/cheese-corn-triangles.jpg', 'Snacks / Appetizer', 4, 16, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Veggie Fingers', 'Crunchy coated, finely chopped vegetable.', 119, true, '', 'Snacks / Appetizer', 4, 17, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Chole Kabab', 'Shallow-fried kebab with a rare combination of smoked & vegetables.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667630/zopiqnow/lily/chole-kabab.jpg', 'Snacks / Appetizer', 4, 18, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Karari Chole Palak Ke Kabab', 'Chef special signature dish, accompanied with mint sauce.', 159, true, '', 'Snacks / Appetizer', 4, 19, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Dahi Ke Kabab', 'Shallow-fried kabab of boiled potato and vegetables with hung curd, fig, sesame seeds and basil.', 169, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667631/zopiqnow/lily/dahi-ke-kabab.jpg', 'Snacks / Appetizer', 4, 20, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lily Special Kabab Platter', 'Assorted kabab platter served with a compliment.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667633/zopiqnow/lily/lily-special-kabab-platter.jpg', 'Snacks / Appetizer', 4, 21, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lushooni Paneer Tikka', 'Chunks of cottage cheese marinated in spices and grilled in the tandoor.', 239, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667635/zopiqnow/lily/lushooni-paneer-tikka.jpg', 'Tandoor Special Starter', 5, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Achari Tikka', 'Chunks of cottage cheese marinated in achari masala and grilled in the tandoor.', 249, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667637/zopiqnow/lily/achari-tikka.jpg', 'Tandoor Special Starter', 5, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Bharwa Aloo', 'Scooped potatoes filled with dry fruits and binding, marinated and barbequed.', 219, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667638/zopiqnow/lily/bharwa-aloo.jpg', 'Tandoor Special Starter', 5, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pasta Primavera', 'An American dish that consists of pasta in a cream sauce and fresh vegetable.', 185, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667640/zopiqnow/lily/pasta-primavera.jpg', 'Casa-Italia, Continental & Chinese', 6, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Penne Pasta', 'With choice of vegetable and sauce (Arrabbiata / Alfredo).', 169, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667641/zopiqnow/lily/penne-pasta.jpg', 'Casa-Italia, Continental & Chinese', 6, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pasta Alla Caprese', 'Made of pasta, mozzarella, tomatoes and sweet basil, seasoned with salt and olive oil.', 185, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667643/zopiqnow/lily/pasta-alla-caprese.jpg', 'Casa-Italia, Continental & Chinese', 6, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Spaghetti Aglio E Olio', 'Traditional Italian pasta dish from Naples — spaghetti, olive oil, crushed garlic and red pepper flakes.', 185, true, '', 'Casa-Italia, Continental & Chinese', 6, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Baked Macaroni with Pineapple', 'Baked pasta & pineapple with bechamel sauce & cheese.', 249, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667645/zopiqnow/lily/baked-macaroni-with-pineapple.jpg', 'Casa-Italia, Continental & Chinese', 6, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Vegetarian Lasagna', 'With fresh vegetables and chunky mushroom cream, mozzarella in tomato.', 259, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667646/zopiqnow/lily/vegetarian-lasagna.jpg', 'Casa-Italia, Continental & Chinese', 6, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Fried Rice', 'Vegetable / Manchurian / Schezwan.', 169, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667648/zopiqnow/lily/fried-rice.jpg', 'Casa-Italia, Continental & Chinese', 6, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Noodles', 'Hakka / Vegetables / Schezwan.', 139, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667650/zopiqnow/lily/noodles.jpg', 'Casa-Italia, Continental & Chinese', 6, 7, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Stir Fried Vegetables with Burnt Garlic Rice', 'In a chilli garlic soya sauce, with ginger fried rice.', 249, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667654/zopiqnow/lily/stir-fried-vegetables-with-burnt-garlic-rice.jpg', 'Casa-Italia, Continental & Chinese', 6, 8, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Garlic Sautee Vegetables', 'Exotic vegetable sautéed in olive oil with herbs.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667656/zopiqnow/lily/garlic-sautee-vegetables.jpg', 'Casa-Italia, Continental & Chinese', 6, 9, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cheese Butter Masala', 'Processed cheese simmered in rich creamy tomato gravy.', 239, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667658/zopiqnow/lily/cheese-butter-masala.jpg', 'Main Course', 7, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Paneer Butter Masala', 'Fresh Indian cottage cheese simmered in rich tomato gravy.', 209, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667659/zopiqnow/lily/paneer-butter-masala.jpg', 'Main Course', 7, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lily Special Paneer', 'The signature dish of our chef.', 239, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667661/zopiqnow/lily/lily-special-paneer.jpg', 'Main Course', 7, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Paneer Laziz', 'Tender cottage cheese slices cooked in rich onion tomato gravy.', 209, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667662/zopiqnow/lily/paneer-laziz.jpg', 'Main Course', 7, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kadhai Paneer', 'Cottage cheese cooked with tomato, onion, bell pepper and a blend of Indian spices.', 209, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667663/zopiqnow/lily/kadhai-paneer.jpg', 'Main Course', 7, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Paneer Tikka Masala', 'Barbequed marinated cottage cheese cooked in rich gravy.', 219, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667664/zopiqnow/lily/paneer-tikka-masala.jpg', 'Main Course', 7, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Hariyali Paneer', 'Cottage cheese simmered with spinach puree and finished with cream.', 269, true, '', 'Main Course', 7, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Bhindi Do Pyaza', 'Spicy stir-fried okra with an extra amount of sautéed onions.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667666/zopiqnow/lily/bhindi-do-pyaza.jpg', 'Main Course', 7, 7, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kurkuri Bhindi', 'Tasty and super crispy fries made with tender okra pods, gram flour.', 179, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667667/zopiqnow/lily/kurkuri-bhindi.jpg', 'Main Course', 7, 8, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Masala Dahi Wali Bhindi', 'Made with cut okra, creamy curd and flavoured spices.', 169, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667668/zopiqnow/lily/masala-dahi-wali-bhindi.jpg', 'Main Course', 7, 9, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kashmiri Dum Aloo', 'Boiled potato cooked in a rich and subtly spiced tomato gravy in a dum.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667670/zopiqnow/lily/kashmiri-dum-aloo.jpg', 'Main Course', 7, 10, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Makai Matar Pyaza', 'A mélange of corn kernels and peas with onion tomato gravy.', 159, true, '', 'Main Course', 7, 11, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Hing Jeera Aloo', 'Boiled diced potato tempered with asafoetida and cumin seeds.', 129, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667671/zopiqnow/lily/hing-jeera-aloo.jpg', 'Main Course', 7, 12, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Mix Veg Sagwala', 'Mixed vegetables drowned in an awesome gravy of spinach and fenugreek leaves, flavoured simply with green chilli.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667672/zopiqnow/lily/mix-veg-sagwala.jpg', 'Main Course', 7, 13, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pindi Chana', 'Kabuli chana cooked in varied spices & garnished with green chilli and lemon wedge.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667674/zopiqnow/lily/pindi-chana.jpg', 'Main Course', 7, 14, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Aloo Gobhi Adraki', 'A delicious semi-dry north Indian sabzi.', 149, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667675/zopiqnow/lily/aloo-gobhi-adraki.jpg', 'Main Course', 7, 15, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lily Special Kofta Curry', 'A chef special vegetable kofta in rich brown gravy.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667676/zopiqnow/lily/lily-special-kofta-curry.jpg', 'Main Course', 7, 16, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Khum Tamatar Khada Masala', 'Mushroom and tomato tempered with coriander seeds and spices.', 189, true, '', 'Main Course', 7, 17, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kadhai Vegetable', 'Stir-fried medley of seasonal vegetable.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667677/zopiqnow/lily/kadhai-vegetable.jpg', 'Main Course', 7, 18, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kadhi Pakoda', 'Gram flour dumplings with vegetable simmered in a yogurt base curry tempered with Indian spices.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667679/zopiqnow/lily/kadhi-pakoda.jpg', 'Main Course', 7, 19, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Dal Makhani', 'A house speciality signature dish.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667680/zopiqnow/lily/dal-makhani.jpg', 'Main Course', 7, 20, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Dal Tadka', 'All-time favourite lentil, cooked and tempered with cumin seeds.', 139, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667681/zopiqnow/lily/dal-tadka.jpg', 'Main Course', 7, 21, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Dal Dhabewali', 'All-time favourite dhaba style preparation.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667683/zopiqnow/lily/dal-dhabewali.jpg', 'Main Course', 7, 22, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Papad Methi', 'Marwari home-made dish cooked with papad and methi.', 139, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667688/zopiqnow/lily/papad-methi.jpg', 'Main Course', 7, 23, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Rabori Kanda', 'Traditional Rajasthani curry made with dry corn papad, yogurt and spices.', 149, true, '', 'Main Course', 7, 24, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Rajasthani Kadhi', 'Gram flour, yogurt base curry tempered with Indian spices.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667694/zopiqnow/lily/rajasthani-kadhi.jpg', 'Main Course', 7, 25, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Rajasthani Gatta Curry', 'Gram flour simmered in yoghurt and onion gravy.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667701/zopiqnow/lily/rajasthani-gatta-curry.jpg', 'Main Course', 7, 26, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kair Sangari', 'The traditional delicacy of local berries kair and sangari.', 209, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667712/zopiqnow/lily/kair-sangari.jpg', 'Main Course', 7, 27, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Marwari Mangori', 'Aloo / Hara Pyaz / Dhaniya / Papad.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667714/zopiqnow/lily/marwari-mangori.jpg', 'Main Course', 7, 28, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Aloo Pyaz Lehsooni', 'House speciality signature dish.', 189, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667716/zopiqnow/lily/aloo-pyaz-lehsooni.jpg', 'Main Course', 7, 29, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lehsooni Palak', 'Shredded spinach tossed with whole spices & a lot of garlic, finished with ghee.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667719/zopiqnow/lily/lehsooni-palak.jpg', 'Main Course', 7, 30, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Sev Tamatar', 'Gram flour vermicelli, tomato & Indian spices.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667724/zopiqnow/lily/sev-tamatar.jpg', 'Main Course', 7, 31, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Dal Ranakpuri', 'Blend of five lentils cooked with spices, tempered with cumin in ghee.', 189, true, '', 'Main Course', 7, 32, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Hara Matar Tamatar', 'Traditional fresh green peas and tomato cooked with Indian spices.', 139, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667726/zopiqnow/lily/hara-matar-tamatar.jpg', 'Main Course', 7, 33, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Punjabi Thali', 'A pre-plated Punjabi meal including traditional vegetarian paneer, cholle masala, lacha paratha or naan, dal makhani, aromatic rice, papad, chutney, masala chaas or raita.', 369, true, '', 'Special Meal', 8, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Shahi Indian Thali', 'A pre-plated meal — aloo paratha, tawa phulka, jeera rice, paneer dish, mix veg, dal, papad, salad, raita, completed with a sweet.', 389, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667730/zopiqnow/lily/shahi-indian-thali.jpg', 'Special Meal', 8, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Rajasthani Thali', 'A pre-plated Rajasthani meal including traditional vegetarian curries, Rajasthani dal bati, aromatic rice, papad, chutney and salad, completed by a Rajasthani sweet.', 369, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667737/zopiqnow/lily/rajasthani-thali.jpg', 'Special Meal', 8, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Tawa Phulka', 'Soft whole-wheat phulka, made fresh on the tawa.', 29, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667739/zopiqnow/lily/tawa-phulka.jpg', 'Indian Breads', 9, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Tandoori Roti', 'Whole-wheat roti baked in the clay oven.', 39, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667741/zopiqnow/lily/tandoori-roti.jpg', 'Indian Breads', 9, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Ajwani Missi Roti', 'A mixed-flour bread with local spices.', 49, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667744/zopiqnow/lily/ajwani-missi-roti.jpg', 'Indian Breads', 9, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Laccha Paratha', 'Whole wheat four-layered crispy flat bread.', 59, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667747/zopiqnow/lily/laccha-paratha.jpg', 'Indian Breads', 9, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Naan', 'Soft North Indian flat bread baked in the tandoor.', 59, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667750/zopiqnow/lily/naan.jpg', 'Indian Breads', 9, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Garlic Naan / Cheese Naan', 'North Indian flat bread infused with garlic cheese, cooked in the tandoor.', 99, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667751/zopiqnow/lily/garlic-naan-cheese-naan.jpg', 'Indian Breads', 9, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Amritsari Kulcha', 'Refined flour bread stuffed with onion / vegetable.', 89, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667761/zopiqnow/lily/amritsari-kulcha.jpg', 'Indian Breads', 9, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Bajri / Makkai Sogra', 'Millet / maize bread cooked on the griddle.', 59, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667764/zopiqnow/lily/bajri-makkai-sogra.jpg', 'Indian Breads', 9, 7, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Stuffed Tawa Paratha with Curd', 'Aloo / Gobhi / Paneer.', 119, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667765/zopiqnow/lily/stuffed-tawa-paratha-with-curd.jpg', 'Indian Breads', 9, 8, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Rajasthani Tukkad', 'Traditional wheat flour bread cooked on a clay griddle.', 59, true, '', 'Indian Breads', 9, 9, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Rajasthani Bati', 'Regular round flatbread made of whole wheat, cooked in a clay oven.', 49, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667766/zopiqnow/lily/rajasthani-bati.jpg', 'Indian Breads', 9, 10, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Steam Rice', 'Basmati rice cooked over steam.', 119, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667768/zopiqnow/lily/steam-rice.jpg', 'Rice', 10, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Jeera Rice / Tomato Rice', 'Special preparation of rice with smoked cumin seeds and tomato.', 129, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667771/zopiqnow/lily/jeera-rice-tomato-rice.jpg', 'Rice', 10, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Veg. Pulao', 'Rice dish made with rice, spices, vegetables & herbs.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667772/zopiqnow/lily/veg-pulao.jpg', 'Rice', 10, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pineapple Basil Rice', 'Chef special preparation.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667773/zopiqnow/lily/pineapple-basil-rice.jpg', 'Rice', 10, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kashmiri Pulao', 'A nutty pulao preparation finished with saffron.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667774/zopiqnow/lily/kashmiri-pulao.jpg', 'Rice', 10, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Subz-Biryani', 'A traditional dum method to cook the rice with Indian spices and aromatic flavouring agents.', 205, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667775/zopiqnow/lily/subz-biryani.jpg', 'Rice', 10, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Khichdi', 'Plain / Masala.', 149, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667776/zopiqnow/lily/khichdi.jpg', 'Rice', 10, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Curd Rice', 'Combination of basmati rice & curd cooked in Dakshin Bharat style.', 179, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667777/zopiqnow/lily/curd-rice.jpg', 'Rice', 10, 7, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Kiddo Maggie', 'Plain / Veg.', 79, true, '', 'Maggi', 11, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Schezwan Maggie Masala', 'Spicy.', 89, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667778/zopiqnow/lily/schezwan-maggie-masala.jpg', 'Maggi', 11, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Indo-Italian Maggie', 'With vegetable and a creamy texture.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667779/zopiqnow/lily/indo-italian-maggie.jpg', 'Maggi', 11, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Choice of Sandwich (Plain or Toast or Grilled)', 'Vegetable / Cheese.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667780/zopiqnow/lily/choice-of-sandwich-plain-or-toast-or-grilled.jpg', 'Sandwiches / Pizzeria', 12, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Traditional Club Sandwich', 'A multi-layered sandwich with tomato, roasted bell pepper, onion and cheese, with coleslaw and fries.', 149, true, '', 'Sandwiches / Pizzeria', 12, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Bombay Style Sandwich', 'Famous Indian street food, made with green chutney, butter and potatoes.', 139, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667781/zopiqnow/lily/bombay-style-sandwich.jpg', 'Sandwiches / Pizzeria', 12, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cheese Chilli Garlic Toast', 'Toast prepared with cheese, chilli and garlic.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667783/zopiqnow/lily/cheese-chilli-garlic-toast.jpg', 'Sandwiches / Pizzeria', 12, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pizza Margherita', 'A typical Neapolitan pizza, made with tomatoes, mozzarella cheese, fresh basil, salt and extra-virgin olive oil.', 259, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667784/zopiqnow/lily/pizza-margherita.jpg', 'Sandwiches / Pizzeria', 12, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Hawaiian Pizza', 'Originating in Canada, and traditionally topped with pineapple, tomato sauce and either soya or paneer.', 269, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667785/zopiqnow/lily/hawaiian-pizza.jpg', 'Sandwiches / Pizzeria', 12, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pizza Neapolitan', 'Tomato sauce, mushroom, cheese, oregano & basil.', 285, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667786/zopiqnow/lily/pizza-neapolitan.jpg', 'Sandwiches / Pizzeria', 12, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pizza Fiamma', 'Mozzarella, spicy layer of sauce, sliced onion, capsicum, corn, jalapeno.', 259, true, '', 'Sandwiches / Pizzeria', 12, 7, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Extra Loaded Chef Special', 'The chef’s fully loaded pizza.', 269, true, '', 'Sandwiches / Pizzeria', 12, 8, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Agli Spinaci', 'Tomato sauce, capsicum, spinach and cheese, topped with oregano, basil and olive oil.', 259, true, '', 'Sandwiches / Pizzeria', 12, 9, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lily Special Tandoori Pizza', 'Signature dish of the café.', 309, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667788/zopiqnow/lily/lily-special-tandoori-pizza.jpg', 'Sandwiches / Pizzeria', 12, 10, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Shahi Gulab Jamun', 'Milk reduced ball soaked in sugar syrup, garnished with nuts.', 119, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667789/zopiqnow/lily/shahi-gulab-jamun.jpg', 'Desserts', 13, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Shahi Gulab Jamun with Ice Cream', 'Milk reduced ball served with vanilla ice-cream, topped with chocolate sauce.', 129, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667790/zopiqnow/lily/shahi-gulab-jamun-with-ice-cream.jpg', 'Desserts', 13, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Rasgulla', 'Dumplings of chhena dough, cooked in light sugar syrup.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667791/zopiqnow/lily/rasgulla.jpg', 'Desserts', 13, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Sizzling Brownie with Ice Cream', 'Topped with a vanilla scoop & chocolate sauce.', 159, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667793/zopiqnow/lily/sizzling-brownie-with-ice-cream.jpg', 'Desserts', 13, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Sevaiyaan / Rice Kheer', 'Vermicelli / rice enriched with condensed milk, saffron and nuts.', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667793/zopiqnow/lily/sevaiyaan-rice-kheer.jpg', 'Desserts', 13, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Rajasthani Churma', 'Coarsely crushed bati mixed with sugar / jaggery / ghee & green cardamom.', 205, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667794/zopiqnow/lily/rajasthani-churma.jpg', 'Desserts', 13, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Moong Dal Halwa / Gajar / Lauki', 'Traditional Rajasthani sweet dish with dry fruits.', 149, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667797/zopiqnow/lily/moong-dal-halwa-gajar-lauki.jpg', 'Desserts', 13, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Ice Cream Cart', 'Select your ice-cream from the available range.', 179, true, '', 'Desserts', 13, 7, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Fresh Lime Soda', 'Sweet / salted / plain.', 69, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667798/zopiqnow/lily/fresh-lime-soda.jpg', 'All Time Beverages', 14, 0, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Choice of Preserve Juice', 'Choose from the day’s range of preserve juices.', 89, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667798/zopiqnow/lily/choice-of-preserve-juice.jpg', 'All Time Beverages', 14, 1, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lassi', 'Sweet, mango, strawberry, chocolate.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667800/zopiqnow/lily/lassi.jpg', 'All Time Beverages', 14, 2, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cold Coffee', 'Chilled milk coffee, churned and served tall.', 109, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667801/zopiqnow/lily/cold-coffee.jpg', 'All Time Beverages', 14, 3, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Chaas', 'Plain / salted / masala.', 49, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667801/zopiqnow/lily/chaas.jpg', 'All Time Beverages', 14, 4, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Jal Jeera', 'Chilled cumin-and-mint cooler with a tangy finish.', 39, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667803/zopiqnow/lily/jal-jeera.jpg', 'All Time Beverages', 14, 5, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Aam Panna', 'Raw mango cooler with roasted cumin and mint.', 59, true, '', 'All Time Beverages', 14, 6, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cup of Tea', 'Kadak masala chai, brewed with milk and spices.', 39, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667803/zopiqnow/lily/cup-of-tea.jpg', 'All Time Beverages', 14, 7, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Coffee', 'Hot milk coffee, frothed and served in a cup.', 49, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667804/zopiqnow/lily/coffee.jpg', 'All Time Beverages', 14, 8, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Add on Flavor', 'Blue curacao syrup, lemon juice, mint leaves, ginger juice, lemon rings & soda sprite with ice cubes.', 30, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667805/zopiqnow/lily/add-on-flavor.jpg', 'All Time Beverages', 14, 9, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Lemon Mint Cooler', 'Refreshing tangy drink.', 135, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667807/zopiqnow/lily/lemon-mint-cooler.jpg', 'All Time Beverages', 14, 10, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Mint Mojito', 'Bar tender special.', 210, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667808/zopiqnow/lily/mint-mojito.jpg', 'All Time Beverages', 14, 11, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cold Coffee with Ice Cream', 'With or without ice cream.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667809/zopiqnow/lily/cold-coffee-with-ice-cream.jpg', 'All Time Beverages', 14, 12, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Choice of Milk Shakes', 'Vanilla / chocolate / mango / strawberry / banana.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667810/zopiqnow/lily/choice-of-milk-shakes.jpg', 'All Time Beverages', 14, 13, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Classic Tea', 'Assam tea / Darjeeling tea / Earl Grey / Chamomile / Green Tea.', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667810/zopiqnow/lily/classic-tea.jpg', 'All Time Beverages', 14, 14, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Pot of Tea / Coffee', 'Indian readymade.', 105, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667811/zopiqnow/lily/pot-of-tea-coffee.jpg', 'All Time Beverages', 14, 15, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Cafe Latte', 'Espresso lengthened with steamed milk.', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667812/zopiqnow/lily/cafe-latte.jpg', 'All Time Beverages', 14, 16, null),
  ('4735d102-fdde-4ab1-8c69-fed7ef5ed30e', 'Nourishing Drink', 'Hot chocolate, milk, Bournvita.', 135, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1787667813/zopiqnow/lily/nourishing-drink.jpg', 'All Time Beverages', 14, 17, null)
) as v (restaurant_id, name, description, price, is_veg, image_url,
        category, category_rank, item_rank, prep_minutes)
where not exists (
  select 1 from public.menu_items where restaurant_id = '4735d102-fdde-4ab1-8c69-fed7ef5ed30e'
);

commit;

-- To publish, once the pin, the hours and the owner are real:
--
--     update public.restaurants
--        set is_active = true, published_at = now()
--      where id = '4735d102-fdde-4ab1-8c69-fed7ef5ed30e';
