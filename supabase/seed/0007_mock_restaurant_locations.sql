-- Seed 7: the eight mock restaurants get mock locations.
--
-- A **seed**, not a migration, and the distinction is the point. Migration 0042
-- deliberately refused to backfill these: a latitude is a real place, and a
-- migration that guesses one pays a rider the wrong amount with the authority of
-- having been written down. That reasoning holds for real restaurants and does
-- not apply here, because r1–r8 are not real restaurants. They are the demo
-- catalog from seed 0001 and always have been.
--
-- Every real restaurant gets its coordinates typed into the admin console by
-- somebody who knows where the kitchen is. This file is only for the eight that
-- were invented.
--
-- **Why these particular numbers.** The obvious choice was Hyderabad, since the
-- seeded names and the one seeded order point there. It would have been wrong:
-- every order actually placed on this database is delivered to Jetawara or Sadri
-- in Rajasthan (24.58, 72.31 and 25.13, 73.45) — the real addresses on the real
-- account doing the testing. Kitchens in Hyderabad would put roughly 900 km
-- between every restaurant and every customer, and at ₹5/km migration 0043 would
-- price a plate of biryani's delivery at about ₹4,500. Correct arithmetic on
-- nonsense input, which is the kind of bug that survives a demo and is believed.
--
-- So they are scattered 0.7–6 km around Jetawara, which is where the food is
-- actually going. Distances come out between roughly 1 and 6 km and the pay
-- between ₹28 and ₹55, which is what a delivery fee is supposed to look like.

update public.restaurants set latitude = 24.6061, longitude = 72.3283 where id = 'r1';
update public.restaurants set latitude = 24.5771, longitude = 72.3373 where id = 'r2';
update public.restaurants set latitude = 24.6201, longitude = 72.3073 where id = 'r3';
update public.restaurants set latitude = 24.5621, longitude = 72.2993 where id = 'r4';
update public.restaurants set latitude = 24.5941, longitude = 72.3573 where id = 'r5';
update public.restaurants set latitude = 24.5841, longitude = 72.3113 where id = 'r6';
update public.restaurants set latitude = 24.6331, longitude = 72.3493 where id = 'r7';
update public.restaurants set latitude = 24.5501, longitude = 72.3243 where id = 'r8';
