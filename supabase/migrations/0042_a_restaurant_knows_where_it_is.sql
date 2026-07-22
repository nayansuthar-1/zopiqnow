-- Phase 8c, migration 42: a restaurant may not go live without a location.
--
-- 0027 added `latitude`/`longitude` to `restaurants` and left them nullable,
-- correctly: the eight seeded rows had none and were not going to be invented
-- into having them. The console has offered both fields since it was built
-- (`AddressStep`), also optional. The result, measured today: **all eight
-- restaurants have `latitude = null`.** Not one row on the platform knows where
-- it is.
--
-- That was survivable while nothing read the columns. 0043 makes a rider's pay
-- depend on the distance from the kitchen to the door, and a distance whose
-- start point is unknown is not a small inaccuracy — it is the difference
-- between a per-km rate that works and one that silently pays the base fee
-- forever while looking, in every screen, exactly like it is working.
--
-- So the gate moves. Not onto the table — a draft is allowed to be incomplete,
-- and 0030 already made that argument about every other field — but onto
-- `admin_publish_restaurant`, which is where "this is finished enough for
-- customers" is decided.
--
-- What this does NOT do: touch the eight live restaurants. They were published
-- before this rule existed and stay published; the check runs when somebody
-- publishes, and nobody is republishing them today. It does mean a restaurant
-- delisted and brought back needs its coordinates first. That is the intended
-- consequence and not an accident of where the check landed.
--
-- *(User decision, 2026-07-22: per-km rider pay, accepting that this gate is
-- its precondition.)*

-- ---------------------------------------------------------------------------
-- Publishing requires a point on the map.
-- ---------------------------------------------------------------------------
-- Everything here is unchanged from 0033 except the one new block; the function
-- is replaced whole because `create or replace` gives no other option.
--
-- The two columns are checked together. `AddressStep` already refuses to submit
-- one without the other ("Enter both latitude and longitude, or neither"), so a
-- half-set pair should be unreachable — which is exactly why it is worth
-- catching here rather than trusting a form.
create or replace function public.admin_publish_restaurant(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.restaurants%rowtype;
  v_legal public.restaurant_legal%rowtype;
  v_bank  public.restaurant_bank_accounts%rowtype;
begin
  perform public.assert_admin();

  select * into r from public.restaurants where id = p_id;
  if not found then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  if coalesce(r.image_url, '') = '' then
    raise exception 'Add a cover photo before publishing.' using errcode = 'P0001';
  end if;
  if r.address_line is null or r.city is null or r.pincode is null then
    raise exception 'Add the full address before publishing.' using errcode = 'P0001';
  end if;

  -- The new one. Phrased so an admin knows why a map pin is suddenly required
  -- to open a kitchen: it is not paperwork, it is somebody's wages.
  if r.latitude is null or r.longitude is null then
    raise exception 'Set the map location before publishing — riders are paid by distance from the kitchen.'
      using errcode = 'P0001';
  end if;

  if r.contact_phone is null then
    raise exception 'Add a contact phone number before publishing.' using errcode = 'P0001';
  end if;

  select * into v_legal from public.restaurant_legal where restaurant_id = p_id;
  if v_legal.fssai_number is null then
    raise exception 'Add the FSSAI licence before publishing.' using errcode = 'P0001';
  end if;
  if v_legal.fssai_expiry is null
     or v_legal.fssai_expiry < (now() at time zone 'Asia/Kolkata')::date then
    raise exception 'That FSSAI licence has expired. Publishing needs a valid one.'
      using errcode = 'P0001';
  end if;
  if v_legal.pan_number is null then
    raise exception 'Add the PAN before publishing.' using errcode = 'P0001';
  end if;

  select * into v_bank from public.restaurant_bank_accounts where restaurant_id = p_id;
  if v_bank.account_number is null or v_bank.ifsc is null then
    raise exception 'Add the bank account before publishing — settlements need somewhere to pay.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.restaurant_staff s
     where s.restaurant_id = p_id and s.role = 'owner'
  ) then
    raise exception 'Add the owner''s email before publishing — nobody can run this kitchen without it.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.restaurant_hours h where h.restaurant_id = p_id
  ) then
    raise exception 'Set the opening hours before publishing.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.menu_items m
     where m.restaurant_id = p_id and m.is_available and m.category_available
  ) then
    raise exception 'Add at least one dish before publishing.' using errcode = 'P0001';
  end if;

  update public.restaurants
     set is_active = true,
         published_at = coalesce(published_at, now())
   where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- The eight that are already live
-- ---------------------------------------------------------------------------
-- Deliberately not backfilled here. A latitude is a real place, and a migration
-- that guesses one is a migration that pays a rider the wrong amount with the
-- authority of having been written down. They are typed into the console, per
-- restaurant, by somebody who knows where the kitchen is.
--
-- Until then those eight produce `distance_km = null` on every job, and 0043
-- pays the base fee and records the null rather than pretending the distance
-- was zero.
