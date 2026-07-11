-- The eight restaurants the mock data source served, verbatim.
--
-- Deliberately identical: if swapping the data source changes what is on
-- screen, that is a bug in the swap, not new content. Real catalog data
-- replaces this when partners onboard.
--
-- Image URLs still point at foodish-api (a free photo dataset) and are still
-- mock: production must not fetch imagery from a third-party host. They move to
-- our CDN with the image pipeline.

insert into public.restaurants
  (id, name, cuisines, rating, rating_count, eta_minutes, price_for_two,
   is_veg, image_url, promo_text, distance_km)
values
  ('r1', 'Paradise Biryani',
   array['Biryani','Hyderabadi','Kebabs'], 4.4, 12800, 32, 500, false,
   'https://foodish-api.com/images/biryani/biryani1.jpg',
   '50% OFF up to ₹100', 2.1),

  ('r2', 'Green Theory',
   array['Healthy','Salads','Continental'], 4.6, 3400, 24, 450, true,
   'https://foodish-api.com/images/pasta/pasta5.jpg',
   'Free delivery', 1.3),

  -- Dollar-quoted: the apostrophe needs no '' escape, which is one fewer thing
  -- for a copy-paste into a SQL editor to silently mangle.
  ('r3', $name$Sultan's Grill$name$,
   array['Mughlai','North Indian','BBQ'], 4.2, 8900, 40, 700, false,
   'https://foodish-api.com/images/butter-chicken/butter-chicken1.jpg',
   null, 3.7),

  ('r4', 'Dosa Junction',
   array['South Indian','Dosa','Idli'], 4.5, 15600, 18, 300, true,
   'https://foodish-api.com/images/dosa/dosa1.jpg',
   '₹75 OFF above ₹199', 0.8),

  ('r5', 'Napoli Wood-Fired',
   array['Pizza','Italian','Pasta'], 4.3, 5200, 35, 850, false,
   'https://foodish-api.com/images/pizza/pizza1.jpg',
   null, 4.2),

  ('r6', 'Chai & Chaat Co.',
   array['Street Food','Snacks','Beverages'], 4.1, 2100, 22, 200, true,
   'https://foodish-api.com/images/samosa/samosa1.jpg',
   null, 1.9),

  ('r7', 'Sushi Ninja',
   array['Japanese','Sushi','Asian'], 4.7, 1800, 45, 1200, false,
   'https://foodish-api.com/images/rice/rice5.jpg',
   '20% OFF', 5.6),

  ('r8', 'The Waffle Window',
   array['Desserts','Waffles','Ice Cream'], 4.4, 6700, 28, 350, true,
   'https://foodish-api.com/images/dessert/dessert1.jpg',
   null, 2.8)
on conflict (id) do nothing;
