-- Seed for the Gifts catalog (migrations 0022 + 0023): the real handmade-art
-- catalog, replacing the Pexels placeholder shops that were here first.
--
-- These are hand-painted lippan / mirror-work wall pieces. Each product carries a
-- gallery (`image_urls`) — front, side, and close-ups — with the first image the
-- card thumbnail (`image_url`). Photos live on our Cloudinary CDN (cloud
-- `mqppsahn`), uploaded from the seller's originals through the app's unsigned
-- preset.
--
-- Prices are PLACEHOLDERS (₹999) until the seller sends the real list. The shop
-- name is a placeholder too — rename `gs1` once the brand is confirmed.
--
-- Idempotent: it clears the gifts tables first, so re-running rebuilds the whole
-- catalog rather than colliding on ids.

delete from public.gift_items;
delete from public.gift_shops;

insert into public.gift_shops
  (id, name, tagline, description, image_url, rating, rating_count)
values
  ('gs1', 'Handmade Art Studio',
   'Hand-painted lippan & mirror-work art',
   'One-of-a-kind handcrafted wall art — mirror-work plates and painted motifs, made to gift and to keep.',
   'https://res.cloudinary.com/mqppsahn/image/upload/v1784569150/zopiqnow/phpxyli7gdzty1mlp8ye.jpg',
   null, 0);

insert into public.gift_items
  (id, shop_id, name, description, price, image_url, image_urls,
   category, category_rank, item_rank)
values
  ('gs1-cow-plate', 'gs1',
   'Kamdhenu Cow Mirror-Work Wall Plate',
   'A hand-painted circular wall plate with lippan mirror work — the sacred cow framed by lotuses on a marigold ground. Entirely handmade, so each piece is unique.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/v1784569150/zopiqnow/phpxyli7gdzty1mlp8ye.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/v1784569150/zopiqnow/phpxyli7gdzty1mlp8ye.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/v1784569152/zopiqnow/pm0phbkal61pqevgyylf.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/v1784569155/zopiqnow/g5tzfk5wso4bvjjcedvj.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/v1784569158/zopiqnow/wyu8rf1gholcyhm8zdua.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/v1784569160/zopiqnow/bqmmviprq55fluwcdpnu.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/v1784569163/zopiqnow/wqpx1cvg60objmuus4qj.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/v1784569165/zopiqnow/l8fkwfuunkmfxr0qldgs.jpg'
   ],
   'Wall Art', 0, 0);
