-- The eight restaurants the mock data source served, verbatim.
--
-- Deliberately identical: if swapping the data source changes what is on
-- screen, that is a bug in the swap, not new content. Real catalog data
-- replaces this when partners onboard.
--
-- Image URLs are hosted on our own Cloudinary CDN (cloud `mqppsahn`), sourced
-- from Pexels (free licence) and matched to each restaurant's cuisine. The
-- earlier foodish-api links went dead (503) and are gone.

insert into public.restaurants
  (id, name, cuisines, rating, rating_count, eta_minutes, price_for_two,
   is_veg, image_url, promo_text, distance_km)
values
  ('r1', 'Paradise Biryani',
   array['Biryani','Hyderabadi','Kebabs'], 4.4, 12800, 32, 500, false,
   'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/zopiqnow/restaurant/paradise-biryani.jpg',
   '50% OFF up to ₹100', 2.1),

  ('r2', 'Green Theory',
   array['Healthy','Salads','Continental'], 4.6, 3400, 24, 450, true,
   'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/zopiqnow/restaurant/green-theory.jpg',
   'Free delivery', 1.3),

  -- Dollar-quoted: the apostrophe needs no '' escape, which is one fewer thing
  -- for a copy-paste into a SQL editor to silently mangle.
  ('r3', $name$Sultan's Grill$name$,
   array['Mughlai','North Indian','BBQ'], 4.2, 8900, 40, 700, false,
   'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/zopiqnow/restaurant/sultans-grill.jpg',
   null, 3.7),

  ('r4', 'Dosa Junction',
   array['South Indian','Dosa','Idli'], 4.5, 15600, 18, 300, true,
   'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/zopiqnow/restaurant/dosa-junction.jpg',
   '₹75 OFF above ₹199', 0.8),

  ('r5', 'Napoli Wood-Fired',
   array['Pizza','Italian','Pasta'], 4.3, 5200, 35, 850, false,
   'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/zopiqnow/restaurant/napoli-wood-fired.jpg',
   null, 4.2),

  ('r6', 'Chai & Chaat Co.',
   array['Street Food','Snacks','Beverages'], 4.1, 2100, 22, 200, true,
   'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/zopiqnow/restaurant/chai-chaat-co.jpg',
   null, 1.9),

  ('r7', 'Sushi Ninja',
   array['Japanese','Sushi','Asian'], 4.7, 1800, 45, 1200, false,
   'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/zopiqnow/restaurant/sushi-ninja.jpg',
   '20% OFF', 5.6),

  ('r8', 'The Waffle Window',
   array['Desserts','Waffles','Ice Cream'], 4.4, 6700, 28, 350, true,
   'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/zopiqnow/restaurant/waffle-window.jpg',
   null, 2.8)
on conflict (id) do nothing;
