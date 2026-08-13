-- Purohitji Dhaba, Sadri — the real catalogue, not a mock.
--
-- Seeded dark on request: `is_active = false` and `published_at = null`, so
-- nothing here reaches a customer until an admin flips it on from the console.
-- The 108 dishes and their prices are transcribed from the photo set the owner
-- supplied; the photos themselves are already on Cloudinary under
-- `zopiqnow/purohitji-dhaba/<slug>`, uploaded signed with `overwrite=true` so
-- re-running this file never duplicates an asset.
--
-- ⚠️ Three fields are placeholders and must be corrected before it goes live:
-- the map pin (Sadri's service-area centre, not the dhaba's door), the address
-- line, and the contact phone (left null). The pin drives delivery distance and
-- therefore the fee, so it is the one that costs money if it stays wrong.

begin;

insert into public.restaurants
  (id, name, cuisines, rating, rating_count, eta_minutes, price_for_two,
   is_veg, image_url, latitude, longitude, address_line, city, state,
   is_active, accepting_orders, published_at)
values
  ('5b415c10-ab9e-4557-b956-25346b40baf9',
   'Purohitji Dhaba',
   array['Rajasthani','North Indian','Thali','Dal Bati','Punjabi','Snacks'],
   0.0, 0, 30, 250, true,
   'https://res.cloudinary.com/w69i7qes/image/upload/v1786650929/zopiqnow/purohitji-dhaba/special-dal-bati.jpg',
   25.1857, 73.4386,
   'Sadri', 'Sadri', 'Rajasthan',
   false, true, null)
on conflict (id) do nothing;

-- Open every day. The dhaba's real hours replace these when the owner confirms.
insert into public.restaurant_hours (restaurant_id, day_of_week, opens, closes)
select '5b415c10-ab9e-4557-b956-25346b40baf9', d, time '09:00', time '23:00'
from generate_series(1, 7) as d
on conflict (restaurant_id, day_of_week) do nothing;

-- Every dish is vegetarian — it is a pure-veg dhaba — and `is_veg` defaults to
-- false, so it is spelled out rather than left to the default.
insert into public.menu_items
  (restaurant_id, name, description, price, is_veg, image_url,
   category, category_rank, item_rank)
values
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Regular Thali', '4 roti, 1 sabji, 1 dal, chawal, papad', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650925/zopiqnow/purohitji-dhaba/regular-thali.jpg', 'Regular & Specials', 0, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Special Thali', 'Sweet, 4 roti, 2 sabji, 1 dal, salad, chawal, chatni, papad, chaach', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650927/zopiqnow/purohitji-dhaba/special-thali.jpg', 'Regular & Specials', 0, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dal Bati', '2 bati with dal', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650928/zopiqnow/purohitji-dhaba/dal-bati.jpg', 'Regular & Specials', 0, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Special Dal Bati', '2 bati, dal, churma, salad, chaach, papad', 270, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650929/zopiqnow/purohitji-dhaba/special-dal-bati.jpg', 'Regular & Specials', 0, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Poha', '', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650931/zopiqnow/purohitji-dhaba/poha.jpg', 'Nashta & Soup', 1, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Plain Maggi', '', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650932/zopiqnow/purohitji-dhaba/plain-maggi.jpg', 'Nashta & Soup', 1, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Masala Maggi', '', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650934/zopiqnow/purohitji-dhaba/masala-maggi.jpg', 'Nashta & Soup', 1, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Cheese Maggi', '', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650935/zopiqnow/purohitji-dhaba/cheese-maggi.jpg', 'Nashta & Soup', 1, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Puri Bhaji', '4 puri with bhaji', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650937/zopiqnow/purohitji-dhaba/puri-bhaji.jpg', 'Nashta & Soup', 1, 4),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Pakoda', '', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650938/zopiqnow/purohitji-dhaba/veg-pakoda.jpg', 'Nashta & Soup', 1, 5),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Pakoda', '', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650940/zopiqnow/purohitji-dhaba/paneer-pakoda.jpg', 'Nashta & Soup', 1, 6),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Hot & Sour Soup', '', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650941/zopiqnow/purohitji-dhaba/hot-and-sour-soup.jpg', 'Nashta & Soup', 1, 7),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Tomato Soup', '', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650943/zopiqnow/purohitji-dhaba/tomato-soup.jpg', 'Nashta & Soup', 1, 8),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Malai Paneer', '', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650944/zopiqnow/purohitji-dhaba/malai-paneer.jpg', 'Paneer Sabji', 2, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Chana', '', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650946/zopiqnow/purohitji-dhaba/paneer-chana.jpg', 'Paneer Sabji', 2, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Mutter Paneer', '', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650947/zopiqnow/purohitji-dhaba/mutter-paneer.jpg', 'Paneer Sabji', 2, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Masala', '', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650948/zopiqnow/purohitji-dhaba/paneer-masala.jpg', 'Paneer Sabji', 2, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Tikka Masala', '', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650950/zopiqnow/purohitji-dhaba/paneer-tikka-masala.jpg', 'Paneer Sabji', 2, 4),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Palak Paneer', '', 190, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650951/zopiqnow/purohitji-dhaba/palak-paneer.jpg', 'Paneer Sabji', 2, 5),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Kadhai', '', 190, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650953/zopiqnow/purohitji-dhaba/paneer-kadhai.jpg', 'Paneer Sabji', 2, 6),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Handi', '', 190, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650954/zopiqnow/purohitji-dhaba/paneer-handi.jpg', 'Paneer Sabji', 2, 7),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Kolhapuri', '', 190, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650956/zopiqnow/purohitji-dhaba/paneer-kolhapuri.jpg', 'Paneer Sabji', 2, 8),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Bhurji', '', 190, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650961/zopiqnow/purohitji-dhaba/paneer-bhurji.jpg', 'Paneer Sabji', 2, 9),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Cheese Butter Paneer', '', 200, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650966/zopiqnow/purohitji-dhaba/cheese-butter-paneer.jpg', 'Paneer Sabji', 2, 10),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Kaju Paneer', '', 200, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650973/zopiqnow/purohitji-dhaba/kaju-paneer.jpg', 'Paneer Sabji', 2, 11),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Pasanda', '', 200, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650975/zopiqnow/purohitji-dhaba/paneer-pasanda.jpg', 'Paneer Sabji', 2, 12),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Toofani', '', 200, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650976/zopiqnow/purohitji-dhaba/paneer-toofani.jpg', 'Paneer Sabji', 2, 13),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Malai Kofta', '', 210, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650977/zopiqnow/purohitji-dhaba/malai-kofta.jpg', 'Paneer Sabji', 2, 14),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Malai Pyaz', '', 210, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650978/zopiqnow/purohitji-dhaba/malai-pyaz.jpg', 'Paneer Sabji', 2, 15),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Butter Masala', '', 210, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650979/zopiqnow/purohitji-dhaba/paneer-butter-masala.jpg', 'Paneer Sabji', 2, 16),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Kaju Masala', '', 210, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650981/zopiqnow/purohitji-dhaba/paneer-kaju-masala.jpg', 'Paneer Sabji', 2, 17),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Shahi Paneer', '', 210, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650982/zopiqnow/purohitji-dhaba/shahi-paneer.jpg', 'Paneer Sabji', 2, 18),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Kofta', '', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650983/zopiqnow/purohitji-dhaba/paneer-kofta.jpg', 'Paneer Sabji', 2, 19),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Shahi Paneer Masala', '', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650984/zopiqnow/purohitji-dhaba/shahi-paneer-masala.jpg', 'Paneer Sabji', 2, 20),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Kaju Curry', '', 230, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650986/zopiqnow/purohitji-dhaba/kaju-curry.jpg', 'Paneer Sabji', 2, 21),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Khoya Kaju Sabji', '', 230, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650987/zopiqnow/purohitji-dhaba/khoya-kaju-sabji.jpg', 'Paneer Sabji', 2, 22),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Angara', '', 270, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650988/zopiqnow/purohitji-dhaba/paneer-angara.jpg', 'Paneer Sabji', 2, 23),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Rajasthani Special Kadhi', '', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650990/zopiqnow/purohitji-dhaba/rajasthani-special-kadhi.jpg', 'Mix Sabji Ka Tadka', 3, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Methi Papad', '', 110, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650992/zopiqnow/purohitji-dhaba/methi-papad.jpg', 'Mix Sabji Ka Tadka', 3, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Rabodi Pyaz', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650993/zopiqnow/purohitji-dhaba/rabodi-pyaz.jpg', 'Mix Sabji Ka Tadka', 3, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Sev Masala', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650994/zopiqnow/purohitji-dhaba/sev-masala.jpg', 'Mix Sabji Ka Tadka', 3, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Sev Pyaz', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650995/zopiqnow/purohitji-dhaba/sev-pyaz.jpg', 'Mix Sabji Ka Tadka', 3, 4),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Sev Tamatar', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786650999/zopiqnow/purohitji-dhaba/sev-tamatar.jpg', 'Mix Sabji Ka Tadka', 3, 5),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Aloo Palak', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651001/zopiqnow/purohitji-dhaba/aloo-palak.jpg', 'Mix Sabji Ka Tadka', 3, 6),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Aloo Pyaz', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651003/zopiqnow/purohitji-dhaba/aloo-pyaz.jpg', 'Mix Sabji Ka Tadka', 3, 7),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Chana Masala', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651004/zopiqnow/purohitji-dhaba/chana-masala.jpg', 'Mix Sabji Ka Tadka', 3, 8),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Matar Masala', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651006/zopiqnow/purohitji-dhaba/matar-masala.jpg', 'Mix Sabji Ka Tadka', 3, 9),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Plain Palak', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651007/zopiqnow/purohitji-dhaba/plain-palak.jpg', 'Mix Sabji Ka Tadka', 3, 10),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Tamatar Chutney', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651009/zopiqnow/purohitji-dhaba/tamatar-chutney.jpg', 'Mix Sabji Ka Tadka', 3, 11),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Aloo Gobhi', '', 140, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651010/zopiqnow/purohitji-dhaba/aloo-gobhi.jpg', 'Mix Sabji Ka Tadka', 3, 12),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Aloo Matar', '', 140, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651012/zopiqnow/purohitji-dhaba/aloo-matar.jpg', 'Mix Sabji Ka Tadka', 3, 13),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Besan Gatta', '', 140, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651013/zopiqnow/purohitji-dhaba/besan-gatta.jpg', 'Mix Sabji Ka Tadka', 3, 14),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Bhindi Fry', '', 140, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651018/zopiqnow/purohitji-dhaba/bhindi-fry.jpg', 'Mix Sabji Ka Tadka', 3, 15),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Bhindi Masala', '', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651020/zopiqnow/purohitji-dhaba/bhindi-masala.jpg', 'Mix Sabji Ka Tadka', 3, 16),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dahi Bhindi', '', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651021/zopiqnow/purohitji-dhaba/dahi-bhindi.jpg', 'Mix Sabji Ka Tadka', 3, 17),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Gatta Kadhi', '', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651022/zopiqnow/purohitji-dhaba/gatta-kadhi.jpg', 'Mix Sabji Ka Tadka', 3, 18),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Lahsun Chutney', '', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651023/zopiqnow/purohitji-dhaba/lahsun-chutney.jpg', 'Mix Sabji Ka Tadka', 3, 19),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Shimla Masala', '', 150, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651024/zopiqnow/purohitji-dhaba/shimla-masala.jpg', 'Mix Sabji Ka Tadka', 3, 20),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dum Aloo', '', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651026/zopiqnow/purohitji-dhaba/dum-aloo.jpg', 'Mix Sabji Ka Tadka', 3, 21),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Kadhai', '', 160, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651027/zopiqnow/purohitji-dhaba/veg-kadhai.jpg', 'Mix Sabji Ka Tadka', 3, 22),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Handi', '', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651028/zopiqnow/purohitji-dhaba/veg-handi.jpg', 'Mix Sabji Ka Tadka', 3, 23),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Kofta', '', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651030/zopiqnow/purohitji-dhaba/veg-kofta.jpg', 'Mix Sabji Ka Tadka', 3, 24),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Kolhapuri', '', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651031/zopiqnow/purohitji-dhaba/veg-kolhapuri.jpg', 'Mix Sabji Ka Tadka', 3, 25),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Toofani', '', 170, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651032/zopiqnow/purohitji-dhaba/veg-toofani.jpg', 'Mix Sabji Ka Tadka', 3, 26),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Lasaniya Aloo', '', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651033/zopiqnow/purohitji-dhaba/lasaniya-aloo.jpg', 'Mix Sabji Ka Tadka', 3, 27),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Mix Veg', '', 180, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651034/zopiqnow/purohitji-dhaba/mix-veg.jpg', 'Mix Sabji Ka Tadka', 3, 28),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dal Fry', '', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651038/zopiqnow/purohitji-dhaba/dal-fry.jpg', 'Dal Ka Tadka', 4, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dal Jeera', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651039/zopiqnow/purohitji-dhaba/dal-jeera.jpg', 'Dal Ka Tadka', 4, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dal Butter', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651040/zopiqnow/purohitji-dhaba/dal-butter.jpg', 'Dal Ka Tadka', 4, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dal Hyderabadi', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651042/zopiqnow/purohitji-dhaba/dal-hyderabadi.jpg', 'Dal Ka Tadka', 4, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dal Tadka', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651043/zopiqnow/purohitji-dhaba/dal-tadka.jpg', 'Dal Ka Tadka', 4, 4),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Steam Rice', '', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651045/zopiqnow/purohitji-dhaba/steam-rice.jpg', 'Rice', 5, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Jeera Rice', '', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651051/zopiqnow/purohitji-dhaba/jeera-rice.jpg', 'Rice', 5, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Pulao', '', 110, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651052/zopiqnow/purohitji-dhaba/veg-pulao.jpg', 'Rice', 5, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dal Khichdi', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651054/zopiqnow/purohitji-dhaba/dal-khichdi.jpg', 'Rice', 5, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Kashmiri Pulao', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651059/zopiqnow/purohitji-dhaba/kashmiri-pulao.jpg', 'Rice', 5, 4),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Biryani', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651061/zopiqnow/purohitji-dhaba/veg-biryani.jpg', 'Rice', 5, 5),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Hyderabadi Veg Biryani', '', 200, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651063/zopiqnow/purohitji-dhaba/hyderabadi-veg-biryani.jpg', 'Rice', 5, 6),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Pulao', '', 210, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651068/zopiqnow/purohitji-dhaba/paneer-pulao.jpg', 'Rice', 5, 7),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Biryani', '', 220, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651075/zopiqnow/purohitji-dhaba/paneer-biryani.jpg', 'Rice', 5, 8),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Plain Roti', '', 12, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651076/zopiqnow/purohitji-dhaba/plain-roti.jpg', 'Roti & Paratha', 6, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Butter Chapati', '', 15, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651077/zopiqnow/purohitji-dhaba/butter-chapati.jpg', 'Roti & Paratha', 6, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Plain Jadi Roti', '', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651079/zopiqnow/purohitji-dhaba/plain-jadi-roti.jpg', 'Roti & Paratha', 6, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Sada Paratha', '', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651080/zopiqnow/purohitji-dhaba/sada-paratha.jpg', 'Roti & Paratha', 6, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Butter Paratha', '', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651082/zopiqnow/purohitji-dhaba/butter-paratha.jpg', 'Roti & Paratha', 6, 4),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Aloo Paratha', '', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651083/zopiqnow/purohitji-dhaba/aloo-paratha.jpg', 'Roti & Paratha', 6, 5),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Khoba Roti', '', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651084/zopiqnow/purohitji-dhaba/khoba-roti.jpg', 'Roti & Paratha', 6, 6),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Gobhi Paratha', '', 110, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651085/zopiqnow/purohitji-dhaba/gobhi-paratha.jpg', 'Roti & Paratha', 6, 7),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Mix Veg Paratha', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651086/zopiqnow/purohitji-dhaba/mix-veg-paratha.jpg', 'Roti & Paratha', 6, 8),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Paneer Paratha', '', 130, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651088/zopiqnow/purohitji-dhaba/paneer-paratha.jpg', 'Roti & Paratha', 6, 9),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Masala Chaach', '', 20, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651090/zopiqnow/purohitji-dhaba/masala-chaach.jpg', 'Rayta & Salad', 7, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Kachumbar Salad', '', 40, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651099/zopiqnow/purohitji-dhaba/kachumbar-salad.jpg', 'Rayta & Salad', 7, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Tamatar Salad', '', 40, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651105/zopiqnow/purohitji-dhaba/tamatar-salad.jpg', 'Rayta & Salad', 7, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Green Salad', '', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651112/zopiqnow/purohitji-dhaba/green-salad.jpg', 'Rayta & Salad', 7, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Plain Dahi', '', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651114/zopiqnow/purohitji-dhaba/plain-dahi.jpg', 'Rayta & Salad', 7, 4),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Boondi Raita', '', 90, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651120/zopiqnow/purohitji-dhaba/boondi-raita.jpg', 'Rayta & Salad', 7, 5),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Dahi Tikari', '', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651122/zopiqnow/purohitji-dhaba/dahi-tikari.jpg', 'Rayta & Salad', 7, 6),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Veg Raita', '', 100, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651123/zopiqnow/purohitji-dhaba/veg-raita.jpg', 'Rayta & Salad', 7, 7),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Roasted Papad', '', 20, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651126/zopiqnow/purohitji-dhaba/roasted-papad.jpg', 'Papad', 8, 0),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Roasted Khichiya', '', 25, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651130/zopiqnow/purohitji-dhaba/roasted-khichiya.jpg', 'Papad', 8, 1),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Fry Papad', '', 30, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651132/zopiqnow/purohitji-dhaba/fry-papad.jpg', 'Papad', 8, 2),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Masala Papad Namkeen', '', 50, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651135/zopiqnow/purohitji-dhaba/masala-papad-namkeen.jpg', 'Papad', 8, 3),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Masala Khichiya', '', 60, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651138/zopiqnow/purohitji-dhaba/masala-khichiya.jpg', 'Papad', 8, 4),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Cheese Masala Papad', '', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651139/zopiqnow/purohitji-dhaba/cheese-masala-papad.jpg', 'Papad', 8, 5),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Papad Churi', '', 70, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651141/zopiqnow/purohitji-dhaba/papad-churi.jpg', 'Papad', 8, 6),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Khichiya Churi', '', 80, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651142/zopiqnow/purohitji-dhaba/khichiya-churi.jpg', 'Papad', 8, 7),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Cheese Masala Khichiya', '', 90, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651144/zopiqnow/purohitji-dhaba/cheese-masala-khichiya.jpg', 'Papad', 8, 8),
  ('5b415c10-ab9e-4557-b956-25346b40baf9', 'Papad Khichiya Churi', '', 120, true, 'https://res.cloudinary.com/w69i7qes/image/upload/v1786651145/zopiqnow/purohitji-dhaba/papad-khichiya-churi.jpg', 'Papad', 8, 9);

commit;
