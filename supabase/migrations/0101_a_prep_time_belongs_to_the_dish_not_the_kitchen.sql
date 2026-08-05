-- ---------------------------------------------------------------------------
-- 0101 — a prep time belongs to the dish, not the kitchen.
-- ---------------------------------------------------------------------------
-- Two numbers came off the admin's Storefront step: **cost for two** and **prep
-- time**. Both were required to publish (0044), and both were the kind of number
-- somebody invents once during onboarding and never revisits.
--
-- Prep time is the clearer case. It depends on what was ordered — a biryani and
-- a cold coffee are not the same wait — and the kitchen already answers it per
-- order when it accepts, which is the only moment anybody knows. A single
-- restaurant-level guess was a worse answer competing with a better one.
--
-- Cost for two goes for the same reason: on a menu of ₹40 chai and ₹400 thalis
-- it is a made-up average that the customer reads as a promise.
--
-- **The gate has to go with them.** 0044 made both required to publish, on the
-- reasoning that "an unset one is not a blank space — it is a claim about the
-- restaurant that happens to be false". That reasoning was right, and it is
-- exactly why the fields are leaving: the fix is to stop making the claim, not
-- to keep demanding a number for it. The two checks are dropped here; every
-- other publishing requirement stands untouched.
--
-- The columns stay. They are `not null` on a table with fifty-one orders behind
-- it, dropping them would restate `place_order`, and a column nobody writes
-- costs nothing. What changes is that nobody is asked for them and nobody shows
-- them.

-- ===========================================================================
-- A. The ETA an order quotes before the kitchen has answered.
-- ===========================================================================
-- `place_order` reads `restaurants.eta_minutes` into the order's `eta_minutes`,
-- and that is still the right shape: an order needs *some* ETA in the minutes
-- between placing it and the kitchen accepting. With nobody filling the column
-- in, that number would be whatever a draft was created with — zero — and the
-- customer's first view of their order would promise it in no time at all.
--
-- So the column gets a default, and it is honestly a placeholder: thirty minutes
-- until a cook says otherwise, at which point `accept_order` overwrites it with
-- the number they actually chose. Existing rows holding a real number keep it;
-- only the zeros move.
alter table public.restaurants
  alter column eta_minutes set default 30;

update public.restaurants set eta_minutes = 30 where eta_minutes <= 0;

comment on column public.restaurants.eta_minutes is
  'Placeholder ETA for the gap between placing an order and the kitchen accepting it. Not admin-editable since 0101 — the vendor sets the real prep time per order.';
comment on column public.restaurants.price_for_two is
  'Vestigial since 0101. Not asked for, not displayed. Kept because the column is not null and dropping it would restate place_order.';

-- A column default is not enough on its own, because `admin_create_restaurant`
-- names the column explicitly and supplies its own fallback:
--
--     greatest(coalesce((p_profile ->> 'eta_minutes')::integer, 0), 0)
--
-- An explicit value beats a column default, so a draft created by the new form
-- — which no longer sends the key — would land on 0 and quote every order in no
-- time at all. The fallback now defers to the default instead of inventing a
-- zero. `price_for_two` keeps its zero, which is the honest value for a number
-- nothing reads any more.
create or replace function public.admin_create_restaurant(p_profile jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id   text;
  v_name text;
begin
  perform public.assert_admin();

  v_name := trim(coalesce(p_profile ->> 'name', ''));
  if v_name = '' then
    raise exception 'The restaurant needs a name.' using errcode = 'P0001';
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
    -- Still accepted if the caller has them; simply no longer demanded.
    greatest(coalesce((p_profile ->> 'price_for_two')::integer, 0), 0),
    -- 30, not 0, when the key is absent — the placeholder ETA an order quotes
    -- until the kitchen accepts and replaces it with a real one.
    greatest(coalesce((p_profile ->> 'eta_minutes')::integer, 30), 1),
    coalesce((p_profile ->> 'is_veg')::boolean, false),
    nullif(trim(coalesce(p_profile ->> 'promo_text', '')), ''),
    coalesce(p_profile ->> 'image_url', ''),
    0, 0,
    false
  ) returning id into v_id;

  return v_id;
end;
$function$;

revoke execute on function public.admin_create_restaurant(jsonb)
  from public, anon;
grant execute on function public.admin_create_restaurant(jsonb) to authenticated;

-- ===========================================================================
-- B. Publishing stops demanding two numbers nobody is asked for.
-- ===========================================================================
-- Restated from the live definition with two `if` blocks removed and nothing
-- else touched.
create or replace function public.admin_publish_restaurant(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
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

  -- 0044's cost-for-two and prep-time checks stood here. Removed in 0101: the
  -- admin is no longer asked for either, so requiring them would make every
  -- restaurant unpublishable.

  if r.address_line is null or r.city is null or r.pincode is null then
    raise exception 'Add the full address before publishing.' using errcode = 'P0001';
  end if;
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
$function$;

revoke execute on function public.admin_publish_restaurant(text)
  from public, anon, authenticated;
grant execute on function public.admin_publish_restaurant(text) to authenticated;
