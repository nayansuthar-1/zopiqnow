-- Migration 44: a draft starts with a name, and a draft nobody ordered from can
-- be thrown away.
--
-- Three changes, all of them about the same thing: onboarding a restaurant
-- should begin the way it begins in real life, with somebody typing a name, and
-- everything else should be answerable later or not at all.
--
-- **What actually blocked that.** `admin_create_restaurant` (0030) demanded a
-- name, a cost for two, and a prep time. The last two are not facts an onboarder
-- has at the moment they start — a cost for two is a number you work out *after*
-- the menu exists, and a prep time is a guess until the kitchen has run a
-- service. They were required for a boring reason (both columns are `not null`
-- with no default) rather than a real one.
--
-- *(User decision, 2026-07-22: "only necessary things that real zomato/swiggy
-- people use".)*
--
-- They do not disappear. They move to where every other field on a restaurant
-- already lives — filled in on the Storefront step whenever, and **required to
-- publish**, which is the line 0030 drew and 0042 reinforced: a draft is allowed
-- to be incomplete, a live listing is not. That matters here specifically
-- because the customer app reads both columns and renders them; a live
-- restaurant advertising "₹0 for two" in a 0-minute delivery is not an empty
-- field, it is a wrong one.

-- ---------------------------------------------------------------------------
-- Zero becomes sayable.
-- ---------------------------------------------------------------------------
-- `price_for_two > 0` and `eta_minutes > 0` have been on the table since 0001,
-- and they were right while every restaurant arrived complete. They are what
-- actually made these two fields mandatory — not the RPC, which could have been
-- softened at any time.
--
-- Relaxed to `>= 0`, and the rule they were protecting moves to
-- `admin_publish_restaurant` below. This is the same trade 0030 made for every
-- other field on this table and 0042 made for the coordinates: the table
-- describes what a row may hold, and publishing describes what a row must have
-- to face a customer. A draft is not a customer-facing thing.
--
-- Nullable would have been the purer "unset", but the customer app reads both
-- columns as non-null (`restaurant_row.dart`), and widening a column that three
-- apps parse is a bigger change than this needs. Zero is not a plausible price
-- or prep time, so it carries the meaning without ambiguity.
alter table public.restaurants
  drop constraint if exists restaurants_price_for_two_check,
  drop constraint if exists restaurants_eta_minutes_check;

alter table public.restaurants
  add constraint restaurants_price_for_two_check check (price_for_two >= 0),
  add constraint restaurants_eta_minutes_check   check (eta_minutes >= 0);

-- ---------------------------------------------------------------------------
-- Creating: a name, and nothing else.
-- ---------------------------------------------------------------------------
-- Zero is the "not set yet" value for both numbers, and the publish gate below
-- is what catches it — no third column tracking whether somebody meant it.
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
    greatest(coalesce((p_profile ->> 'eta_minutes')::integer, 0), 0),
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
-- Publishing: where the two numbers became required instead.
-- ---------------------------------------------------------------------------
-- Replaced whole again, as 0033 and 0042 each had to. The only new lines are the
-- price and prep-time block; the rest is 0042 verbatim.
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

  -- New in 0044. Both are shown to customers on the restaurant card, so an
  -- unset one is not a blank space — it is a claim about the restaurant that
  -- happens to be false.
  if r.price_for_two <= 0 then
    raise exception 'Set the cost for two before publishing — customers see it on the card.'
      using errcode = 'P0001';
  end if;
  if r.eta_minutes <= 0 then
    raise exception 'Set the prep time before publishing — it is what every order quotes.'
      using errcode = 'P0001';
  end if;

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
$$;

-- ---------------------------------------------------------------------------
-- Throwing a draft away.
-- ---------------------------------------------------------------------------
-- 0040 argued there should be no `admin_remove_rider`, because
-- `deliveries.partner_email` is a foreign key and "who delivered this" is worth
-- answering a year later. The same argument applies to a restaurant that has
-- taken an order — and *only* to one that has.
--
-- A draft created by mistake, or a restaurant that pulled out during onboarding,
-- has no history to protect. Making an admin keep it forever means the console's
-- list slowly fills with rows that mean nothing, which is how a list stops being
-- read.
--
-- Two refusals, and the first is enforced by the database whatever this function
-- says: `orders.restaurant_id` is `on delete no action`, so an order makes the
-- delete fail. Checking it here turns a foreign-key error into a sentence.
--
-- Everything else — menu, hours, legal, bank, staff, notifications, device
-- tokens, favourites, settlements — is `on delete cascade` and goes with it.
-- That is the intended blast radius: none of it means anything without the
-- restaurant, and all of it is re-enterable.
create or replace function public.admin_delete_restaurant(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.restaurants%rowtype;
  v_orders integer;
begin
  perform public.assert_admin();

  select * into r from public.restaurants where id = p_id;
  if not found then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  -- Live means customers can see it right now. Deleting it out from under them
  -- is never what somebody meant by "remove"; delisting first is one extra click
  -- and makes the decision deliberate.
  if r.is_active then
    raise exception 'Delist % first. A live restaurant cannot be deleted outright.', r.name
      using errcode = 'P0001';
  end if;

  select count(*) into v_orders from public.orders o where o.restaurant_id = p_id;
  if v_orders > 0 then
    raise exception
      '% has % order(s) on record and cannot be deleted. Delisting hides it from customers and keeps that history.',
      r.name, v_orders
      using errcode = 'P0001';
  end if;

  delete from public.restaurants where id = p_id;
end;
$$;

revoke execute on function public.admin_delete_restaurant(text) from public;
grant execute on function public.admin_delete_restaurant(text) to authenticated;
