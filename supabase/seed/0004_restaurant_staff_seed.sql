-- Who works where — seeded, because there is nowhere else for it to come from.
--
-- A restaurant account is created by ops, not by self-service signup (see the
-- long note in migration 0009: if anyone could claim a restaurant by typing its
-- email, the first person to type it would own the kitchen). Ops does not have a
-- tool yet — that is the admin dashboard, PM_CHECKLIST §8 — so for now "ops" is
-- this file.
--
-- Every real restaurant that onboards gets a row here until that tool exists.
insert into public.restaurant_staff (email, restaurant_id) values
  -- The developer account, so the vendor app can be signed into and driven
  -- against a restaurant that has a menu and (from customer-app testing) orders.
  ('manav@siteonlab.com', 'r1')
on conflict (email) do update set restaurant_id = excluded.restaurant_id;
