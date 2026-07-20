-- Seed for the Gifts catalog (migration 0022): three dedicated gift shops and
-- the products they sell. This is what the customer Gifts tab renders until real
-- gift sellers onboard, one shop at a time.
--
-- Images are direct Pexels CDN links (free licence), each verified to resolve at
-- seed time and chosen to match the product. Unlike the restaurant seed, these
-- are not proxied through our Cloudinary CDN — there is no upload pipeline for
-- gifts yet, and the customer app's ZopiqNetworkImage degrades any dead URL into
-- the same branded gradient placeholder restaurants use, so a link that rots
-- later reads as deliberate, not broken.

insert into public.gift_shops
  (id, name, tagline, description, image_url, rating, rating_count)
values
  ('g1', 'Artisan Corner',
   'Handcrafted homeware & wall art',
   'Small-batch pottery, framed prints, and handwoven decor from independent makers.',
   'https://images.pexels.com/photos/1509534/pexels-photo-1509534.jpeg?auto=compress&cs=tinysrgb&w=800',
   4.7, 1240),

  ('g2', 'The Gifting Studio',
   'Personalised gifts & keepsakes',
   'Custom mugs, leather journals, and curated hampers made to order for someone special.',
   'https://images.pexels.com/photos/264985/pexels-photo-264985.jpeg?auto=compress&cs=tinysrgb&w=800',
   4.5, 860),

  ('g3', 'Bloom & Craft',
   'Plants, candles & handmade charm',
   'Potted greens, soy candles, fairy lights, and handcrafted jewellery to brighten any room.',
   'https://images.pexels.com/photos/1974508/pexels-photo-1974508.jpeg?auto=compress&cs=tinysrgb&w=800',
   4.6, 2010);

insert into public.gift_items
  (id, shop_id, name, description, price, image_url, category, category_rank, item_rank)
values
  -- g1 · Artisan Corner
  ('g1-i1', 'g1', 'Framed Wall Art Set',
   'A pair of gallery-style framed prints to anchor a living room wall.',
   2199, 'https://images.pexels.com/photos/1509534/pexels-photo-1509534.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Wall Art', 0, 0),
  ('g1-i2', 'g1', 'Abstract Canvas Painting',
   'Hand-finished abstract canvas, ready to hang, signed by the artist.',
   1899, 'https://images.pexels.com/photos/1585325/pexels-photo-1585325.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Wall Art', 0, 1),
  ('g1-i3', 'g1', 'Handwoven Macrame Hanging',
   'Cotton macrame wall hanging, knotted by hand — no two are identical.',
   1299, 'https://images.pexels.com/photos/1670723/pexels-photo-1670723.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Wall Art', 0, 2),
  ('g1-i4', 'g1', 'Ceramic Bud Vase',
   'Matte stoneware bud vase, thrown and glazed in small batches.',
   649, 'https://images.pexels.com/photos/6207364/pexels-photo-6207364.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Home Decor', 1, 0),
  ('g1-i5', 'g1', 'Wooden Photo Frame',
   'Solid-wood tabletop frame with a soft natural finish.',
   499, 'https://images.pexels.com/photos/1927149/pexels-photo-1927149.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Home Decor', 1, 1),

  -- g2 · The Gifting Studio
  ('g2-i1', 'g2', 'Curated Gift Hamper',
   'A ready-to-gift box of small treats, wrapped and ribboned.',
   1499, 'https://images.pexels.com/photos/264985/pexels-photo-264985.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Hampers', 0, 0),
  ('g2-i2', 'g2', 'Handmade Leather Journal',
   'Refillable leather-bound journal with unlined recycled pages.',
   599, 'https://images.pexels.com/photos/6032280/pexels-photo-6032280.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Personalised', 1, 0),
  ('g2-i3', 'g2', 'Personalised Ceramic Mug',
   'Add a name or message — glazed ceramic, dishwasher safe.',
   399, 'https://images.pexels.com/photos/264771/pexels-photo-264771.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Personalised', 1, 1),
  ('g2-i4', 'g2', 'Custom Name Coffee Mug',
   'A cheerful printed mug, personalised with the name of your choice.',
   449, 'https://images.pexels.com/photos/1493088/pexels-photo-1493088.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Personalised', 1, 2),
  ('g2-i5', 'g2', 'Premium Notebook Set',
   'A set of three softcover notebooks, perfect for gifting a planner.',
   349, 'https://images.pexels.com/photos/4041392/pexels-photo-4041392.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Stationery', 2, 0),

  -- g3 · Bloom & Craft
  ('g3-i1', 'g3', 'Potted Succulent',
   'A low-maintenance succulent in a hand-glazed pot — desk-sized joy.',
   299, 'https://images.pexels.com/photos/1974508/pexels-photo-1974508.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Plants', 0, 0),
  ('g3-i2', 'g3', 'Indoor Potted Plant',
   'A leafy indoor plant in a ceramic planter, ready to brighten a corner.',
   699, 'https://images.pexels.com/photos/1005058/pexels-photo-1005058.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Plants', 0, 1),
  ('g3-i3', 'g3', 'Scented Soy Candle',
   'Hand-poured soy candle with a warm, long-burning fragrance.',
   549, 'https://images.pexels.com/photos/4195509/pexels-photo-4195509.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Candles & Fragrance', 1, 0),
  ('g3-i4', 'g3', 'Candle Gift Set of 3',
   'Three coordinated scents in a giftable set of soy candles.',
   999, 'https://images.pexels.com/photos/1123262/pexels-photo-1123262.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Candles & Fragrance', 1, 1),
  ('g3-i5', 'g3', 'Handmade Soap Bars',
   'A trio of cold-pressed soap bars, naturally scented and gift-wrapped.',
   449, 'https://images.pexels.com/photos/7262444/pexels-photo-7262444.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Bath & Body', 2, 0),
  ('g3-i6', 'g3', 'Warm Fairy Lights',
   'Ten metres of warm-white fairy lights for a cosy, gifted glow.',
   399, 'https://images.pexels.com/photos/1303081/pexels-photo-1303081.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Home Decor', 3, 0),
  ('g3-i7', 'g3', 'Copper String Lights',
   'Delicate copper-wire string lights, battery powered and flexible.',
   599, 'https://images.pexels.com/photos/716658/pexels-photo-716658.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Home Decor', 3, 1),
  ('g3-i8', 'g3', 'Handcrafted Earrings',
   'Lightweight handmade earrings — a small, thoughtful keepsake.',
   799, 'https://images.pexels.com/photos/1191531/pexels-photo-1191531.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Jewellery', 4, 0),
  ('g3-i9', 'g3', 'Beaded Jewellery Set',
   'A coordinated set of beaded pieces, presented in a gift box.',
   1099, 'https://images.pexels.com/photos/998521/pexels-photo-998521.jpeg?auto=compress&cs=tinysrgb&w=800',
   'Jewellery', 4, 1);
