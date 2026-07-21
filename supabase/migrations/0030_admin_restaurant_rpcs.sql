-- Step 11, migration 30: the console's write surface for a restaurant.
--
-- Everything an admin can do to a restaurant, as functions. The shape is the one
-- this schema has used for every privileged write since 0009, and the argument
-- has not changed: RLS chooses *rows*, not *columns*. An update policy on
-- `restaurants` that let an admin set `address_line` would be one widened clause
-- away from letting them set `rating` — which is earned from customers, not typed
-- by staff — and there would be nothing in the database to say so.
--
-- So there is no update grant on `restaurants` for anybody, still. There are these
-- functions, each of which can reach a fixed set of columns, and each of which
-- asks `is_admin()` before it does anything at all.
--
-- Note on what an admin *cannot* touch, even here:
--   * `rating` / `rating_count` — earned, never assigned;
--   * `accepting_orders` — the kitchen's own pause switch (0011), not ops';
--   * `is_active` — reachable only through publish/unpublish at the bottom of this
--     file, which is a gate with conditions, not an assignment.

-- ---------------------------------------------------------------------------
-- The guard, once.
-- ---------------------------------------------------------------------------
-- Every function below opens with this. Written once so that the day the rule
-- changes there is one place to change it, and so a new RPC cannot quietly ship
-- without it — a missing `perform assert_admin()` is visible at a glance in a way
-- a missing four-line `if` block is not.
create or replace function public.assert_admin() returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'You are not a Zopiqnow admin.' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.assert_admin() from public;
grant execute on function public.assert_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- Create: a draft, never a listing.
-- ---------------------------------------------------------------------------
-- `is_active = false`, which is the whole safety property of this console. A
-- restaurant comes into existence invisible: the customer feed's policy is
-- `using (is_active)`, so a half-onboarded kitchen with no menu and no address
-- cannot be ordered from, no matter how far through the wizard someone got before
-- they closed the tab.
--
-- Three fields are required because the table requires them — `price_for_two > 0`
-- and `eta_minutes > 0` are constraints from 0001, and a nameless restaurant is
-- not a thing. They are all on step 1 of the wizard, so this costs nothing.
create or replace function public.admin_create_restaurant(p_profile jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   text;
  v_name text;
begin
  perform public.assert_admin();

  v_name := trim(coalesce(p_profile ->> 'name', ''));
  if v_name = '' then
    raise exception 'The restaurant needs a name.' using errcode = 'P0001';
  end if;
  if coalesce((p_profile ->> 'price_for_two')::integer, 0) <= 0 then
    raise exception 'The cost for two has to be more than zero.'
      using errcode = 'P0001';
  end if;
  if coalesce((p_profile ->> 'eta_minutes')::integer, 0) <= 0 then
    raise exception 'The prep time has to be more than zero minutes.'
      using errcode = 'P0001';
  end if;

  insert into public.restaurants (
    name, cuisines, price_for_two, eta_minutes, is_veg, promo_text, image_url,
    -- A restaurant nobody has ordered from has no rating. Zero here is not a
    -- score of zero, it is the absence of one, and `rating_count = 0` is what
    -- says so — the customer card reads that pair, not `rating` alone.
    rating, rating_count,
    is_active
  ) values (
    v_name,
    coalesce(array(select jsonb_array_elements_text(p_profile -> 'cuisines')), '{}'),
    (p_profile ->> 'price_for_two')::integer,
    (p_profile ->> 'eta_minutes')::integer,
    coalesce((p_profile ->> 'is_veg')::boolean, false),
    nullif(trim(coalesce(p_profile ->> 'promo_text', '')), ''),
    coalesce(p_profile ->> 'image_url', ''),
    0, 0,
    false
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.admin_create_restaurant(jsonb) from public;
grant execute on function public.admin_create_restaurant(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Update: only the keys that were sent.
-- ---------------------------------------------------------------------------
-- `p_profile ? 'key'` rather than `coalesce(p_profile ->> 'key', name)`, and the
-- difference is not pedantry: with coalesce there is no way to *clear* a field,
-- because "absent" and "set to null" collapse into the same thing. A wizard step
-- that saves four fields must not have to resend the other twelve to avoid wiping
-- them, and an admin removing a promo line must be able to actually remove it.
create or replace function public.admin_update_restaurant(
  p_id      text,
  p_profile jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  if p_profile ? 'name' and trim(coalesce(p_profile ->> 'name', '')) = '' then
    raise exception 'The restaurant needs a name.' using errcode = 'P0001';
  end if;
  if p_profile ? 'price_for_two'
     and coalesce((p_profile ->> 'price_for_two')::integer, 0) <= 0 then
    raise exception 'The cost for two has to be more than zero.'
      using errcode = 'P0001';
  end if;
  if p_profile ? 'eta_minutes'
     and coalesce((p_profile ->> 'eta_minutes')::integer, 0) <= 0 then
    raise exception 'The prep time has to be more than zero minutes.'
      using errcode = 'P0001';
  end if;
  -- Held as basis points because that is how `settlements` computes with it
  -- (0017). The console shows a percentage; this is the storage unit, and 10000
  -- would be a restaurant that earns nothing.
  if p_profile ? 'commission_bps'
     and coalesce((p_profile ->> 'commission_bps')::integer, -1) not between 0 and 10000 then
    -- `%%` because RAISE reads a bare `%` as a placeholder for an argument that
    -- is not there, and refuses to compile the function at all.
    raise exception 'Commission has to be between 0%% and 100%%.'
      using errcode = 'P0001';
  end if;

  update public.restaurants set
    name = case when p_profile ? 'name'
                then trim(p_profile ->> 'name') else name end,
    cuisines = case when p_profile ? 'cuisines'
                then coalesce(array(select jsonb_array_elements_text(p_profile -> 'cuisines')), '{}')
                else cuisines end,
    price_for_two = case when p_profile ? 'price_for_two'
                then (p_profile ->> 'price_for_two')::integer else price_for_two end,
    eta_minutes = case when p_profile ? 'eta_minutes'
                then (p_profile ->> 'eta_minutes')::integer else eta_minutes end,
    is_veg = case when p_profile ? 'is_veg'
                then coalesce((p_profile ->> 'is_veg')::boolean, false) else is_veg end,
    -- An empty offer line is *no* offer, not an empty badge on the card. Same
    -- rule `update_restaurant_profile` (0012) applies for the vendor.
    promo_text = case when p_profile ? 'promo_text'
                then nullif(trim(coalesce(p_profile ->> 'promo_text', '')), '')
                else promo_text end,
    image_url = case when p_profile ? 'image_url'
                then coalesce(p_profile ->> 'image_url', '') else image_url end,
    owner_name = case when p_profile ? 'owner_name'
                then nullif(trim(coalesce(p_profile ->> 'owner_name', '')), '')
                else owner_name end,
    contact_phone = case when p_profile ? 'contact_phone'
                then nullif(trim(coalesce(p_profile ->> 'contact_phone', '')), '')
                else contact_phone end,
    address_line = case when p_profile ? 'address_line'
                then nullif(trim(coalesce(p_profile ->> 'address_line', '')), '')
                else address_line end,
    city = case when p_profile ? 'city'
                then nullif(trim(coalesce(p_profile ->> 'city', '')), '') else city end,
    state = case when p_profile ? 'state'
                then nullif(trim(coalesce(p_profile ->> 'state', '')), '') else state end,
    pincode = case when p_profile ? 'pincode'
                then nullif(trim(coalesce(p_profile ->> 'pincode', '')), '') else pincode end,
    latitude = case when p_profile ? 'latitude'
                then (p_profile ->> 'latitude')::double precision else latitude end,
    longitude = case when p_profile ? 'longitude'
                then (p_profile ->> 'longitude')::double precision else longitude end,
    commission_bps = case when p_profile ? 'commission_bps'
                then (p_profile ->> 'commission_bps')::integer else commission_bps end
  where id = p_id;
end;
$$;

revoke execute on function public.admin_update_restaurant(text, jsonb) from public;
grant execute on function public.admin_update_restaurant(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- The list, drafts included.
-- ---------------------------------------------------------------------------
-- `security definer`, which is what makes this different from selecting the table:
-- the anon policy is `using (is_active)`, so a draft is invisible through
-- PostgREST to everyone including the admin who just created it. This function is
-- the only way to see a restaurant that is not live.
create or replace function public.admin_list_restaurants()
returns table (
  id               text,
  name             text,
  city             text,
  is_active        boolean,
  accepting_orders boolean,
  image_url        text,
  menu_item_count  integer,
  owner_email      text,
  created_at       timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select
      r.id, r.name, r.city, r.is_active, r.accepting_orders, r.image_url,
      (select count(*)::integer from public.menu_items m where m.restaurant_id = r.id),
      (select s.email from public.restaurant_staff s
        where s.restaurant_id = r.id and s.role = 'owner'
        order by s.created_at limit 1),
      r.created_at
    from public.restaurants r
    -- Drafts first: they are the ones with unfinished work on them.
    order by r.is_active, r.created_at desc;
end;
$$;

revoke execute on function public.admin_list_restaurants() from public;
grant execute on function public.admin_list_restaurants() to authenticated;

-- ---------------------------------------------------------------------------
-- One restaurant, everything about it.
-- ---------------------------------------------------------------------------
-- The wizard in edit mode needs the profile, the papers, the bank, the hours, and
-- the team. Five round trips would be five chances for a screen to render half a
-- restaurant, so it is one call and one object.
--
-- The bank account comes back as its **last four digits only**. The console can
-- confirm which account is on file; it cannot display the number, and neither can
-- anything that scrapes the response. Changing it means typing it again, which is
-- the correct amount of friction for the field that decides where money goes.
create or replace function public.admin_get_restaurant(p_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  perform public.assert_admin();

  select jsonb_build_object(
    'restaurant', to_jsonb(r) - 'search_text',
    'legal', (select to_jsonb(l) from public.restaurant_legal l
               where l.restaurant_id = p_id),
    'bank', (select jsonb_build_object(
                'account_holder', b.account_holder,
                'account_last4', right(b.account_number, 4),
                'ifsc', b.ifsc,
                'bank_name', b.bank_name,
                'verified', b.verified)
               from public.restaurant_bank_accounts b
              where b.restaurant_id = p_id),
    'hours', coalesce((select jsonb_agg(jsonb_build_object(
                'day', h.day_of_week, 'opens', h.opens, 'closes', h.closes)
                order by h.day_of_week)
               from public.restaurant_hours h
              where h.restaurant_id = p_id), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(jsonb_build_object(
                'email', s.email, 'role', s.role) order by (s.role = 'owner') desc, s.created_at)
               from public.restaurant_staff s
              where s.restaurant_id = p_id), '[]'::jsonb)
  ) into v_result
  from public.restaurants r
  where r.id = p_id;

  if v_result is null then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  return v_result;
end;
$$;

revoke execute on function public.admin_get_restaurant(text) from public;
grant execute on function public.admin_get_restaurant(text) to authenticated;

-- ---------------------------------------------------------------------------
-- The papers.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_legal(p_id text, p_legal jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  -- Checked here so an admin gets a sentence rather than a constraint dump. The
  -- table's own checks (0028) are still the guard behind these — a check the
  -- client can read is a check, not a guard.
  if nullif(trim(coalesce(p_legal ->> 'fssai_number', '')), '') is not null
     and trim(p_legal ->> 'fssai_number') !~ '^[0-9]{14}$' then
    raise exception 'An FSSAI licence number is 14 digits.' using errcode = 'P0001';
  end if;
  if nullif(trim(coalesce(p_legal ->> 'gst_number', '')), '') is not null
     and upper(trim(p_legal ->> 'gst_number'))
         !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$' then
    raise exception 'That GST number doesn''t look right.' using errcode = 'P0001';
  end if;
  if nullif(trim(coalesce(p_legal ->> 'pan_number', '')), '') is not null
     and upper(trim(p_legal ->> 'pan_number')) !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' then
    raise exception 'That PAN doesn''t look right.' using errcode = 'P0001';
  end if;

  insert into public.restaurant_legal (
    restaurant_id, fssai_number, fssai_expiry, fssai_doc_url,
    gst_number, pan_number, pan_doc_url, updated_at
  ) values (
    p_id,
    nullif(trim(coalesce(p_legal ->> 'fssai_number', '')), ''),
    (p_legal ->> 'fssai_expiry')::date,
    nullif(trim(coalesce(p_legal ->> 'fssai_doc_url', '')), ''),
    nullif(upper(trim(coalesce(p_legal ->> 'gst_number', ''))), ''),
    nullif(upper(trim(coalesce(p_legal ->> 'pan_number', ''))), ''),
    nullif(trim(coalesce(p_legal ->> 'pan_doc_url', '')), ''),
    now()
  )
  on conflict (restaurant_id) do update set
    fssai_number  = excluded.fssai_number,
    fssai_expiry  = excluded.fssai_expiry,
    fssai_doc_url = excluded.fssai_doc_url,
    gst_number    = excluded.gst_number,
    pan_number    = excluded.pan_number,
    pan_doc_url   = excluded.pan_doc_url,
    updated_at    = now();
end;
$$;

revoke execute on function public.admin_set_legal(text, jsonb) from public;
grant execute on function public.admin_set_legal(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- The bank account.
-- ---------------------------------------------------------------------------
-- Writing new details clears `verified`. Somebody checked *that* account was
-- real; they did not check this one, and a verified flag that survives an edit is
-- a verified flag that means nothing.
create or replace function public.admin_set_bank(p_id text, p_bank jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account text;
  v_ifsc    text;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  v_account := nullif(trim(coalesce(p_bank ->> 'account_number', '')), '');
  v_ifsc    := nullif(upper(trim(coalesce(p_bank ->> 'ifsc', ''))), '');

  if v_account is not null and v_account !~ '^[0-9]{9,18}$' then
    raise exception 'An account number is 9 to 18 digits.' using errcode = 'P0001';
  end if;
  if v_ifsc is not null and v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$' then
    raise exception 'That IFSC code doesn''t look right.' using errcode = 'P0001';
  end if;

  insert into public.restaurant_bank_accounts (
    restaurant_id, account_holder, account_number, ifsc, bank_name,
    verified, updated_at
  ) values (
    p_id,
    nullif(trim(coalesce(p_bank ->> 'account_holder', '')), ''),
    v_account, v_ifsc,
    nullif(trim(coalesce(p_bank ->> 'bank_name', '')), ''),
    coalesce((p_bank ->> 'verified')::boolean, false),
    now()
  )
  on conflict (restaurant_id) do update set
    account_holder = excluded.account_holder,
    account_number = excluded.account_number,
    ifsc           = excluded.ifsc,
    bank_name      = excluded.bank_name,
    verified       = excluded.verified,
    updated_at     = now();
end;
$$;

revoke execute on function public.admin_set_bank(text, jsonb) from public;
grant execute on function public.admin_set_bank(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Opening hours.
-- ---------------------------------------------------------------------------
-- The admin-scoped twin of `set_restaurant_hours` (0018), which resolves the
-- restaurant from `staff_restaurant_id()` and so cannot be used by someone who
-- does not work at one. Same delete-then-insert: the payload is the whole week,
-- because a partial update of a schedule is how a Tuesday gets left behind.
create or replace function public.admin_set_hours(p_id text, p_hours jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  delete from public.restaurant_hours where restaurant_id = p_id;

  insert into public.restaurant_hours (restaurant_id, day_of_week, opens, closes)
  select p_id, (e ->> 'day')::smallint, (e ->> 'opens')::time, (e ->> 'closes')::time
  from jsonb_array_elements(coalesce(p_hours, '[]'::jsonb)) as e;
end;
$$;

revoke execute on function public.admin_set_hours(text, jsonb) from public;
grant execute on function public.admin_set_hours(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- The team.
-- ---------------------------------------------------------------------------
-- The admin twins of the owner-facing functions in 0024. They exist because the
-- *first* owner cannot be added by an owner: `add_restaurant_staff` resolves the
-- restaurant from the caller's own staff row, so a restaurant with no staff has
-- nobody who can give it any. That bootstrap is what these close.
create or replace function public.admin_add_staff(
  p_id    text,
  p_email text,
  p_role  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email    text;
  v_existing text;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  v_email := lower(trim(p_email));
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'That doesn''t look like an email address.' using errcode = 'P0001';
  end if;
  if p_role not in ('owner', 'staff') then
    raise exception 'Unknown role: %.', p_role using errcode = 'P0001';
  end if;

  -- `restaurant_staff.email` is the primary key, so one address works at one
  -- restaurant. That is the design (0009), not a limitation to route around: the
  -- whole vendor authorisation model is "this email means this kitchen".
  select s.restaurant_id into v_existing
    from public.restaurant_staff s where s.email = v_email;
  if v_existing = p_id then
    raise exception '% already works here.', v_email using errcode = 'P0001';
  elsif v_existing is not null then
    raise exception '% is already on another restaurant''s team.', v_email
      using errcode = 'P0001';
  end if;

  insert into public.restaurant_staff (email, restaurant_id, role)
  values (v_email, p_id, p_role);
end;
$$;

revoke execute on function public.admin_add_staff(text, text, text) from public;
grant execute on function public.admin_add_staff(text, text, text) to authenticated;

create or replace function public.admin_set_staff_role(
  p_id    text,
  p_email text,
  p_role  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if p_role not in ('owner', 'staff') then
    raise exception 'Unknown role: %.', p_role using errcode = 'P0001';
  end if;

  update public.restaurant_staff
     set role = p_role
   where email = lower(trim(p_email)) and restaurant_id = p_id;

  if not found then
    raise exception '% is not on that restaurant''s team.', lower(trim(p_email))
      using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_set_staff_role(text, text, text) from public;
grant execute on function public.admin_set_staff_role(text, text, text) to authenticated;

create or replace function public.admin_remove_staff(p_id text, p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  perform public.assert_admin();
  v_email := lower(trim(p_email));

  -- A live restaurant with no owner is one nobody can run: no order queue, no
  -- menu edits, no earnings. Removing the last owner is refused rather than
  -- allowed-and-regretted.
  if exists (
    select 1 from public.restaurant_staff s
     where s.email = v_email and s.restaurant_id = p_id and s.role = 'owner'
  ) and (
    select count(*) from public.restaurant_staff s
     where s.restaurant_id = p_id and s.role = 'owner'
  ) = 1 then
    raise exception 'That is the only owner. Add another owner before removing this one.'
      using errcode = 'P0001';
  end if;

  delete from public.restaurant_staff
   where email = v_email and restaurant_id = p_id;

  if not found then
    raise exception '% is not on that restaurant''s team.', v_email
      using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_remove_staff(text, text) from public;
grant execute on function public.admin_remove_staff(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Publish: the gate.
-- ---------------------------------------------------------------------------
-- The only thing in the system that sets `is_active = true`, and it is a list of
-- conditions rather than an assignment. Every one of them is something a customer
-- would otherwise discover the hard way — a restaurant with no menu, a rider sent
-- to no address, a kitchen nobody can log in to run, a lapsed licence.
--
-- Each failure raises its own sentence, because "publish failed" tells an admin
-- to go hunting and "Add at least one dish before publishing" tells them what to do.
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
  if r.contact_phone is null then
    raise exception 'Add a contact phone number before publishing.' using errcode = 'P0001';
  end if;

  select * into v_legal from public.restaurant_legal where restaurant_id = p_id;
  if v_legal.fssai_number is null then
    raise exception 'Add the FSSAI licence before publishing.' using errcode = 'P0001';
  end if;
  -- A licence that expires tomorrow is fine to publish on. One that expired
  -- yesterday is a restaurant that should not be listed at all.
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

  -- No rows means "always open" to `restaurant_is_open_now` (0018). True for the
  -- eight seeded restaurants and harmless there, but for a kitchen being listed
  -- for the first time it is far more likely to mean nobody filled the step in.
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

  update public.restaurants set is_active = true where id = p_id;
end;
$$;

revoke execute on function public.admin_publish_restaurant(text) from public;
grant execute on function public.admin_publish_restaurant(text) to authenticated;

-- Delisting. Deliberately without conditions — whatever the reason a restaurant
-- has to come off the platform right now, it is not the database's business to
-- argue. Orders already placed are untouched: `orders` denormalises the
-- restaurant's name (0003) and the vendor's own read policy (0009) is `id =
-- staff_restaurant_id()` with no `is_active` clause, so a delisted kitchen can
-- still see and finish the orders it has.
create or replace function public.admin_unpublish_restaurant(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  update public.restaurants set is_active = false where id = p_id;
  if not found then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_unpublish_restaurant(text) from public;
grant execute on function public.admin_unpublish_restaurant(text) to authenticated;
