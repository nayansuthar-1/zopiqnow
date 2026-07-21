-- Step 11, migration 35: the address fields answer in English too.
--
-- 0030 validates the storefront fields — a nameless restaurant, a zero price, a
-- zero prep time all come back as sentences an admin can act on. The address
-- columns added in 0027 got constraints but no such courtesy, so a malformed
-- phone number surfaces as:
--
--     new row for relation "restaurants" violates check constraint
--     "restaurants_contact_phone_is_indian_mobile"
--
-- The console validates both fields client-side and an admin will almost never
-- see that. "Almost never" is the problem: the one time it does surface — a paste
-- with a stray character, a future screen that forgets to check — it surfaces to
-- someone who now has to go and read a migration to find out what shape a phone
-- number is meant to be.
--
-- The constraints stay exactly as they are. They are the guard; this is the
-- explanation, and the two are not interchangeable.

create or replace function public.admin_update_restaurant(
  p_id      text,
  p_profile jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone   text;
  v_pincode text;
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
  if p_profile ? 'commission_bps'
     and coalesce((p_profile ->> 'commission_bps')::integer, -1) not between 0 and 10000 then
    raise exception 'Commission has to be between 0%% and 100%%.'
      using errcode = 'P0001';
  end if;

  -- New here. Empty is allowed and means "not set yet" — a draft is entitled to
  -- be incomplete, and `admin_publish_restaurant` is what insists on these later.
  v_phone := nullif(trim(coalesce(p_profile ->> 'contact_phone', '')), '');
  if p_profile ? 'contact_phone' and v_phone is not null
     and v_phone !~ '^[6-9][0-9]{9}$' then
    raise exception 'An Indian mobile number is 10 digits starting 6, 7, 8 or 9.'
      using errcode = 'P0001';
  end if;

  v_pincode := nullif(trim(coalesce(p_profile ->> 'pincode', '')), '');
  if p_profile ? 'pincode' and v_pincode is not null
     and v_pincode !~ '^[1-9][0-9]{5}$' then
    raise exception 'A pincode is 6 digits and cannot start with a zero.'
      using errcode = 'P0001';
  end if;

  -- A coordinate on land in India, roughly. Not a precise bounding box — the
  -- point is to catch a swapped pair or a stray minus sign, which puts a
  -- restaurant in the ocean and a rider nowhere.
  if p_profile ? 'latitude' and (p_profile ->> 'latitude') is not null
     and (p_profile ->> 'latitude')::double precision not between -90 and 90 then
    raise exception 'That latitude is not a real place.' using errcode = 'P0001';
  end if;
  if p_profile ? 'longitude' and (p_profile ->> 'longitude') is not null
     and (p_profile ->> 'longitude')::double precision not between -180 and 180 then
    raise exception 'That longitude is not a real place.' using errcode = 'P0001';
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
    promo_text = case when p_profile ? 'promo_text'
                then nullif(trim(coalesce(p_profile ->> 'promo_text', '')), '')
                else promo_text end,
    image_url = case when p_profile ? 'image_url'
                then coalesce(p_profile ->> 'image_url', '') else image_url end,
    owner_name = case when p_profile ? 'owner_name'
                then nullif(trim(coalesce(p_profile ->> 'owner_name', '')), '')
                else owner_name end,
    contact_phone = case when p_profile ? 'contact_phone' then v_phone else contact_phone end,
    address_line = case when p_profile ? 'address_line'
                then nullif(trim(coalesce(p_profile ->> 'address_line', '')), '')
                else address_line end,
    city = case when p_profile ? 'city'
                then nullif(trim(coalesce(p_profile ->> 'city', '')), '') else city end,
    state = case when p_profile ? 'state'
                then nullif(trim(coalesce(p_profile ->> 'state', '')), '') else state end,
    pincode = case when p_profile ? 'pincode' then v_pincode else pincode end,
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
