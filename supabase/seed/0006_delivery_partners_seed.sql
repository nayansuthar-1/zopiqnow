-- The first rider, seeded, because there is nowhere else for it to come from.
--
-- Exactly the situation `0004_restaurant_staff_seed.sql` describes and for the
-- same reason: a delivery partner is onboarded by ops, not by self-service
-- signup. If anyone could become a rider by typing an address, the fleet would
-- be whoever felt like it — and a rider can see a customer's phone number and
-- home address the moment they claim a job.
--
-- Ops has no tool yet (that is the admin dashboard, PM_CHECKLIST §8), so for now
-- "ops" is this file. Every real partner who onboards gets a row here until that
-- tool exists, and the honest note is that this stops scaling somewhere around
-- the tenth of them.
insert into public.delivery_partners (email, name, phone, vehicle) values
  -- The developer's rider account, so the rider app can actually be signed into
  -- and driven against real orders. A *different* address from the vendor
  -- account on purpose: `restaurant_staff` and `delivery_partners` are separate
  -- identities, and one person cannot be both the kitchen and the bike — the
  -- vendor app and the rider app would each resolve the same JWT to a different
  -- role and disagree about who is standing there.
  ('nayan@siteonlab.com', 'Nayan', '+919000000001', 'bike')
on conflict (email) do update
  set name    = excluded.name,
      phone   = excluded.phone,
      vehicle = excluded.vehicle;
