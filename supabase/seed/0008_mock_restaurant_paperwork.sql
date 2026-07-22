-- Seed 8: the eight mock restaurants get mock paperwork.
--
-- Companion to seed 0007, and the same argument: r1–r8 are the invented demo
-- catalog from seed 0001, so inventing their details is honest. Nothing here
-- should ever be run against a restaurant a real person owns.
--
-- **Why it was needed.** All eight are live, but every one of them would fail
-- `admin_publish_restaurant` if it were ever delisted and brought back — no
-- address, no phone, no FSSAI, no PAN, no bank account, no opening hours, and no
-- owner on seven of the eight. They have been live since before the publish gate
-- existed. That makes the whole delist → fix → republish path untestable, which
-- is exactly the path an admin will one day need to work.
--
-- **Everything here is deliberately, visibly fake**, while still satisfying the
-- format checks the schema enforces (14-digit FSSAI, `AAAAA9999A` PAN,
-- `ABCD0123456` IFSC, 9–18 digit account, `[6-9]` mobile). A reader glancing at
-- `ZZZZZ0001Z` or `MOCK0000001` should not have to wonder whether it is somebody's
-- real PAN.
--
-- **The owner addresses end in `.invalid`**, which RFC 2606 reserves and which no
-- registrar can ever sell. That is the point: a `restaurant_staff` row is what
-- grants access to the vendor app, so seeding a plausible-looking real address
-- would hand a live kitchen to whoever happens to own it. Nobody can receive a
-- sign-in code at `.invalid`, ever. r1 keeps the two real owners it already has —
-- that is the account actually used for testing.

-- ---------------------------------------------------------------------------
-- Where they are, and who to call.
-- ---------------------------------------------------------------------------
-- Jetawara, Sirohi district — matching the coordinates seed 0007 gave them, so
-- the address and the map pin tell the same story.
update public.restaurants r
   set address_line  = 'Shop ' || substr(r.id, 2) || ', Main Bazaar',
       city          = 'Jetawara',
       state         = 'Rajasthan',
       pincode       = '307026',
       contact_phone = '900000000' || substr(r.id, 2)
 where r.id in ('r1','r2','r3','r4','r5','r6','r7','r8');

-- ---------------------------------------------------------------------------
-- Licences.
-- ---------------------------------------------------------------------------
-- The expiry is computed, not written down. A literal date would quietly pass
-- today and start failing the publish gate in a year or two, and the failure
-- would look like a bug in the gate rather than a stale seed.
insert into public.restaurant_legal (restaurant_id, fssai_number, fssai_expiry, pan_number)
select r.id,
       '1000000000000' || substr(r.id, 2),
       (now() at time zone 'Asia/Kolkata')::date + 730,
       'ZZZZZ000' || substr(r.id, 2) || 'Z'
  from public.restaurants r
 where r.id in ('r1','r2','r3','r4','r5','r6','r7','r8')
on conflict (restaurant_id) do update
   set fssai_number = excluded.fssai_number,
       fssai_expiry = excluded.fssai_expiry,
       pan_number   = excluded.pan_number;

-- ---------------------------------------------------------------------------
-- Somewhere to pay them.
-- ---------------------------------------------------------------------------
-- `verified` stays false. Nobody has verified these because there is nothing to
-- verify, and a seed that claims otherwise would be the one lie in the file.
insert into public.restaurant_bank_accounts
  (restaurant_id, account_holder, account_number, ifsc, bank_name)
select r.id,
       r.name,
       '00000000000' || substr(r.id, 2),
       -- 11 characters exactly: MOCK, the mandatory '0', then six more.
       'MOCK000000' || substr(r.id, 2),
       'Mock Bank of Rajasthan'
  from public.restaurants r
 where r.id in ('r1','r2','r3','r4','r5','r6','r7','r8')
on conflict (restaurant_id) do update
   set account_holder = excluded.account_holder,
       account_number = excluded.account_number,
       ifsc           = excluded.ifsc,
       bank_name      = excluded.bank_name;

-- ---------------------------------------------------------------------------
-- When they are open.
-- ---------------------------------------------------------------------------
-- `day_of_week` is 1–7, not 0–6. Nine to eleven, every day.
insert into public.restaurant_hours (restaurant_id, day_of_week, opens, closes)
select r.id, d, time '09:00', time '23:00'
  from public.restaurants r
 cross join generate_series(1, 7) as d
 where r.id in ('r1','r2','r3','r4','r5','r6','r7','r8')
on conflict (restaurant_id, day_of_week) do nothing;

-- ---------------------------------------------------------------------------
-- Somebody to run them.
-- ---------------------------------------------------------------------------
-- r1 is excluded: it already has two real owners, and adding a third that cannot
-- sign in would only clutter its Team screen.
insert into public.restaurant_staff (restaurant_id, email, role)
select r.id, 'owner.' || r.id || '@zopiqnow.invalid', 'owner'
  from public.restaurants r
 where r.id in ('r2','r3','r4','r5','r6','r7','r8')
on conflict do nothing;
