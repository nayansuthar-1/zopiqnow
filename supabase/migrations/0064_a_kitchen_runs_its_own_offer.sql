-- ---------------------------------------------------------------------------
-- 0064 — a kitchen runs its own offer. (Phase B6, vendor-created offers)
-- ---------------------------------------------------------------------------
-- `coupons` has been a platform table since 0003: one flat namespace of codes,
-- every one of them valid at every restaurant, writable by nobody but whoever
-- had psql open. That was right when there was one operator and five seeded
-- kitchens. It is wrong the moment a restaurant wants to discount *its own*
-- food, because there is no way to say so — a 30% code would be 30% off every
-- kitchen on the platform, paid for by all of them.
--
-- One nullable column fixes the model:
--
--   * `restaurant_id is null`  → a platform offer. Ours, valid anywhere. Every
--     code that exists today is one of these, and none of them change.
--   * `restaurant_id = 'r3'`   → r3's offer. Valid on an r3 cart and refused,
--     by the database, on anybody else's.
--
-- **The refusal is in `validate_coupon`, not in the app.** A scope that the
-- checkout screen enforces is a scope anybody with a REST client walks around.
-- So `validate_coupon` gains the restaurant it is being asked about, and a code
-- belonging to another kitchen is answered with the same "isn't valid" sentence
-- as a code that does not exist — a different message for each would turn the
-- function into a way to enumerate other restaurants' promotions.
--
-- **Dropped, not replaced.** A third argument is a different signature, so
-- `create or replace` would leave the two-argument version of 0003 standing
-- beside this one and PostgREST would be free to bind either. That is the
-- overload trap 0045 fell into, and the reason the drop below names the exact
-- old signature. The new argument is defaulted, so an installed app that sends
-- only a code and a subtotal still binds here — and gets platform offers only,
-- which is precisely what that build knows how to show.

-- ===========================================================================
-- A. Whose offer it is, and until when.
-- ===========================================================================
alter table public.coupons
  add column if not exists restaurant_id text
    references public.restaurants (id) on delete cascade;

-- An offer nobody turns off is an offer that runs until somebody notices. Null
-- stays legal — every platform code today has no end date and gains none — but
-- a vendor-created one is given a date by the RPC below, because a kitchen
-- setting up a weekend promotion should not have to remember Monday.
alter table public.coupons
  add column if not exists valid_until timestamptz;

create index if not exists coupons_restaurant_idx
  on public.coupons (restaurant_id) where restaurant_id is not null;

-- The world-readable policy of 0003 narrows to what it always meant: *our*
-- codes are advertised to everybody. A restaurant's own offer is advertised on
-- that restaurant's page, through the function below, and a customer browsing
-- the app has no business receiving a list of every promotion every kitchen on
-- the platform is currently running.
drop policy if exists "active coupons are world-readable" on public.coupons;
create policy "active platform coupons are world-readable"
  on public.coupons for select to anon, authenticated
  using (is_active and restaurant_id is null);

-- 0061's lesson. `coupons` predates the habit and has carried Supabase's
-- default insert/update/delete grants for `anon` and `authenticated` since the
-- day it was created — RLS with no write policy has been the only thing
-- standing between a stranger and a 100%-off code. Revoke the grants and
-- re-grant the one verb the policy above is about.
revoke all on public.coupons from public, anon, authenticated;
grant select on public.coupons to anon, authenticated;

-- ===========================================================================
-- B. Honouring one.
-- ===========================================================================
drop function if exists public.validate_coupon(text, integer);

create function public.validate_coupon(
  p_code          text,
  p_subtotal      integer,
  p_restaurant_id text default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.coupons;
  v_discount integer;
begin
  select * into c from public.coupons
    where code = upper(trim(p_code))
      and is_active
      -- The scope, as a join condition rather than as a check afterwards: a
      -- code that is not ours to use simply does not match, and falls into the
      -- same `not found` branch as a code that was never issued.
      and (restaurant_id is null or restaurant_id = p_restaurant_id);

  if not found then
    raise exception 'This code isn''t valid.' using errcode = 'P0001';
  end if;

  if c.valid_until is not null and now() > c.valid_until then
    raise exception 'This offer has ended.' using errcode = 'P0001';
  end if;

  if p_subtotal < c.min_subtotal then
    raise exception 'Add items worth ₹% more to use %.',
      c.min_subtotal - p_subtotal, c.code using errcode = 'P0001';
  end if;

  v_discount := coalesce(
    c.flat_off,
    least(round(p_subtotal * c.percent_off / 100.0)::integer, c.max_off)
  );

  -- A discount may never exceed the subtotal: no coupon turns an order into a
  -- payout. Cheap to state, catastrophic to omit. (0003, unchanged.)
  return least(v_discount, p_subtotal);
end;
$$;

grant execute on function public.validate_coupon(text, integer, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- place_order passes the cart's restaurant to it.
-- ---------------------------------------------------------------------------
-- The whole of 0061's function, byte-for-byte, but for the one call on the
-- coupon line. The signature does not change, so this is a `create or replace`
-- and not a drop — no app has to be updated for its checkout to keep working,
-- and the re-validation that has been here since 0003 now re-validates the
-- scope as well as the minimum. A code the app was somehow shown for the wrong
-- kitchen dies here, at the only moment that charges anybody.
create or replace function public.place_order(
  p_user_phone       text,
  p_restaurant_id    text,
  p_items            jsonb,
  p_delivery_to      text,
  p_payment_method   text,
  p_delivery_lat     double precision default null,
  p_delivery_lng     double precision default null,
  p_coupon_code      text default null,
  p_payment_id       text default null,
  p_delivery_notes   text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      text;
  v_order_id     text;
  v_subtotal     integer := 0;
  v_delivery_fee integer;
  v_taxes        integer;
  v_discount     integer := 0;
  v_total        integer;
  v_eta          integer;
  v_name         text;
  v_accepting    boolean;
  v_notes        text;
  v_line         jsonb;
  v_seq          integer;
  v_mi_id        text;
  v_mi_name      text;
  v_base         integer;
  v_qty          integer;
  v_opt_ids      text[];
  v_opts         jsonb;
  v_addons       integer;
  v_unit         integer;
  v_line_total   integer;
  v_line_id      bigint;
  v_row          record;
begin
  v_user_id := auth.uid()::text;
  if v_user_id is null then
    raise exception 'Please sign in to place an order.' using errcode = 'P0001';
  end if;

  if p_user_phone is null or length(trim(p_user_phone)) = 0 then
    raise exception 'We need a phone number for your rider.' using errcode = 'P0001';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty.' using errcode = 'P0001';
  end if;

  if p_payment_method = 'upi'
     and (p_payment_id is null or length(trim(p_payment_id)) = 0) then
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  -- Trimmed and truncated rather than refused. A note is a courtesy the customer
  -- typed on the way past; failing an order over its length would be absurd.
  v_notes := nullif(trim(coalesce(p_delivery_notes, '')), '');
  v_notes := left(v_notes, 160);

  select name, eta_minutes, accepting_orders
    into v_name, v_eta, v_accepting
    from public.restaurants where id = p_restaurant_id and is_active;
  if not found then
    raise exception 'This restaurant isn''t available right now.'
      using errcode = 'P0001';
  end if;

  if not v_accepting then
    raise exception 'This restaurant has stopped taking orders for now.'
      using errcode = 'P0001';
  end if;

  if not public.restaurant_is_open_now(p_restaurant_id) then
    raise exception 'This restaurant is closed right now. Please check its hours before ordering.'
      using errcode = 'P0001';
  end if;

  -- Pass one: price every line into a scratch table, options and all, and total
  -- the subtotal — without touching `orders` yet, so an invalid coupon below is
  -- still answered with a sentence rather than a foreign-key violation.
  create temp table _lines (
    seq          integer,
    menu_item_id text,
    name         text,
    unit_price   integer,
    quantity     integer,
    line_total   integer,
    options      jsonb
  ) on commit drop;

  for v_line, v_seq in
    select value, ordinality from jsonb_array_elements(p_items) with ordinality
  loop
    v_qty := (v_line ->> 'quantity')::integer;
    if v_qty is null or v_qty < 1 then
      raise exception 'Your cart has an invalid quantity.' using errcode = 'P0001';
    end if;

    select id, name, price into v_mi_id, v_mi_name, v_base
      from public.menu_items
     where id = (v_line ->> 'menu_item_id')
       and restaurant_id = p_restaurant_id
       and is_available;
    if not found then
      raise exception 'Something in your cart is no longer available.'
        using errcode = 'P0001';
    end if;

    -- The claimed options for this line (absent → empty → all defaults filled).
    v_opt_ids := coalesce(
      (select array_agg(value)
         from jsonb_array_elements_text(coalesce(v_line -> 'option_ids', '[]'::jsonb))),
      array[]::text[]
    );

    -- Resolve once into what is actually charged (name + delta, frozen), then
    -- price off that so the sum and the stored choices can never disagree.
    select coalesce(
             jsonb_agg(jsonb_build_object('name', option_name, 'price_delta', price_delta)),
             '[]'::jsonb
           )
      into v_opts
      from public.resolve_order_line_options(v_mi_id, v_opt_ids);

    v_addons := coalesce(
      (select sum((e ->> 'price_delta')::integer)
         from jsonb_array_elements(v_opts) as e),
      0
    );

    v_unit := v_base + v_addons;
    v_line_total := v_unit * v_qty;
    v_subtotal := v_subtotal + v_line_total;

    insert into _lines
      values (v_seq, v_mi_id, v_mi_name, v_unit, v_qty, v_line_total, v_opts);
  end loop;

  v_delivery_fee := case when v_subtotal >= 500 then 0 else 40 end;
  v_taxes := round(v_subtotal * 0.05)::integer;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);
  end if;

  v_total := v_subtotal + v_delivery_fee + v_taxes - v_discount;

  insert into public.orders (
    user_id, user_phone, restaurant_id, restaurant_name,
    subtotal, delivery_fee, taxes, discount, total,
    coupon_code, payment_method, payment_id,
    delivery_to, delivery_lat, delivery_lng, delivery_notes, eta_minutes
  ) values (
    v_user_id, p_user_phone, p_restaurant_id, v_name,
    v_subtotal, v_delivery_fee, v_taxes, v_discount, v_total,
    nullif(upper(trim(coalesce(p_coupon_code, ''))), ''), p_payment_method, p_payment_id,
    p_delivery_to, p_delivery_lat, p_delivery_lng, v_notes, v_eta
  ) returning id into v_order_id;

  -- Pass two: the lines, in order, each with its frozen options.
  for v_row in select * from _lines order by seq
  loop
    insert into public.order_items
      (order_id, menu_item_id, name, unit_price, quantity, line_total)
    values (v_order_id, v_row.menu_item_id, v_row.name, v_row.unit_price,
            v_row.quantity, v_row.line_total)
    returning id into v_line_id;

    insert into public.order_item_options (order_item_id, name, price_delta)
    select v_line_id, e ->> 'name', (e ->> 'price_delta')::integer
      from jsonb_array_elements(v_row.options) as e;
  end loop;

  return jsonb_build_object(
    'id', v_order_id,
    'restaurant_name', v_name,
    'delivery_to', p_delivery_to,
    'total', v_total,
    'payment_method', p_payment_method,
    'payment_id', p_payment_id,
    'eta_minutes', v_eta
  );
end;
$$;

grant execute on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text, text
) to authenticated;

-- ===========================================================================
-- C. What the customer is shown.
-- ===========================================================================
-- Platform offers plus this restaurant's own, in one list, cheapest-to-qualify
-- first — the ordering `fetchCouponHints` has used since 0003, kept, because a
-- customer scanning offers wants the one they can already use.
--
-- The wording is built here and not on the phone. "20% off up to ₹100" and
-- "₹75 off" are the *contents of the rule*, and the day the rule grows a case
-- the sentence has to grow with it — in one place, next to the arithmetic that
-- honours it, rather than in three apps that each guessed.
create or replace function public.restaurant_offers(p_restaurant_id text)
returns table (
  code         text,
  label        text,
  min_subtotal integer,
  is_exclusive boolean,
  valid_until  timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.code,
         case
           when c.flat_off is not null then '₹' || c.flat_off || ' off'
           else c.percent_off || '% off up to ₹' || c.max_off
         end,
         c.min_subtotal,
         c.restaurant_id is not null,
         c.valid_until
    from public.coupons c
   where c.is_active
     and (c.valid_until is null or c.valid_until > now())
     and (c.restaurant_id is null or c.restaurant_id = p_restaurant_id)
   order by c.restaurant_id is null, c.min_subtotal;
$$;

grant execute on function public.restaurant_offers(text) to anon, authenticated;

-- ===========================================================================
-- D. What the kitchen can do.
-- ===========================================================================
-- The owner's, not all staff's — the same line 0024 drew around settlements,
-- for the same reason. A discount is money out of the business, and a cook who
-- can read a ticket should not be able to give the shop away.
--
-- **The code is namespaced by force.** A vendor RPC that accepted any string
-- would let one restaurant claim `WELCOME50` and shadow a platform code, or
-- squat on a name a competitor wanted. So the caller supplies the readable half
-- and this function prefixes the restaurant id: `R3-WEEKEND`. That also makes
-- every vendor code visibly a vendor code in the orders table.
create or replace function public.vendor_save_offer(
  p_code         text,
  p_min_subtotal integer,
  p_flat_off     integer     default null,
  p_percent_off  integer     default null,
  p_max_off      integer     default null,
  p_valid_until  timestamptz default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_suffix     text;
  v_code       text;
  v_owner      text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You are not signed in to a restaurant.' using errcode = 'P0001';
  end if;

  if public.staff_role() <> 'owner' then
    raise exception 'Only the owner can run offers.' using errcode = 'P0001';
  end if;

  -- Letters and digits, upper-cased. A code with a space in it is a code
  -- somebody mistypes at checkout and blames us for.
  v_suffix := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(v_suffix) < 3 or length(v_suffix) > 16 then
    raise exception 'Give the offer a code of 3 to 16 letters or numbers.'
      using errcode = 'P0001';
  end if;

  v_code := upper(v_restaurant) || '-' || v_suffix;

  -- The XOR the table has enforced since 0003, checked here so the vendor gets
  -- a sentence rather than a constraint violation. The constraint still exists
  -- and still refuses the row — a check the caller can read is a courtesy, not
  -- a guard.
  if (p_flat_off is not null) = (p_percent_off is not null) then
    raise exception 'An offer is either a flat amount off or a percentage, not both.'
      using errcode = 'P0001';
  end if;

  if p_flat_off is not null and p_flat_off <= 0 then
    raise exception 'A flat discount has to be more than ₹0.' using errcode = 'P0001';
  end if;

  if p_percent_off is not null
     and (p_percent_off <= 0 or p_percent_off > 100
          or p_max_off is null or p_max_off <= 0) then
    raise exception 'A percentage offer needs a percentage from 1 to 100 and a cap.'
      using errcode = 'P0001';
  end if;

  if coalesce(p_min_subtotal, 0) < 0 then
    raise exception 'A minimum order value cannot be negative.' using errcode = 'P0001';
  end if;

  if p_valid_until is not null and p_valid_until <= now() then
    raise exception 'That end date has already passed.' using errcode = 'P0001';
  end if;

  -- The guard that makes the namespacing mean something: if this code already
  -- exists and belongs to somebody else — the platform, or another kitchen —
  -- it is not ours to overwrite. Only reachable if a restaurant id is a prefix
  -- of another, but "only reachable if" is how tables get overwritten.
  select restaurant_id into v_owner from public.coupons where code = v_code;
  if found and v_owner is distinct from v_restaurant then
    raise exception 'That code is already in use.' using errcode = 'P0001';
  end if;

  insert into public.coupons
    (code, restaurant_id, min_subtotal, flat_off, percent_off, max_off,
     valid_until, is_active)
  values
    (v_code, v_restaurant, coalesce(p_min_subtotal, 0), p_flat_off, p_percent_off,
     p_max_off, p_valid_until, true)
  on conflict (code) do update
     set min_subtotal = excluded.min_subtotal,
         flat_off     = excluded.flat_off,
         percent_off  = excluded.percent_off,
         max_off      = excluded.max_off,
         valid_until  = excluded.valid_until;

  return v_code;
end;
$$;

grant execute on function public.vendor_save_offer(
  text, integer, integer, integer, integer, timestamptz
) to authenticated;

-- Paused, not deleted. An order placed last week carries `coupon_code` as a
-- foreign key into this table (0003), so deleting a code would either fail or
-- take the receipt with it. Ending an offer is a boolean.
create or replace function public.vendor_set_offer_active(
  p_code   text,
  p_active boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null or public.staff_role() <> 'owner' then
    raise exception 'Only the owner can run offers.' using errcode = 'P0001';
  end if;

  update public.coupons
     set is_active = p_active
   where code = upper(trim(p_code))
     -- The scope, again as a predicate. A kitchen cannot switch off a platform
     -- offer, and cannot touch another kitchen's at all.
     and restaurant_id = v_restaurant;

  if not found then
    raise exception 'We couldn''t find that offer.' using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.vendor_set_offer_active(text, boolean)
  to authenticated;

-- The kitchen's own list, with the one figure a promotion is actually judged
-- on: how many orders used it, and what it cost. Counted from `orders` rather
-- than from a tally column, for the reason 0062 recomputes ratings — a counter
-- that is incremented is a counter that is wrong after the first refund.
create or replace function public.vendor_offers()
returns table (
  code         text,
  label        text,
  min_subtotal integer,
  flat_off     integer,
  percent_off  integer,
  max_off      integer,
  valid_until  timestamptz,
  is_active    boolean,
  times_used   integer,
  total_given  integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_restaurant text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You are not signed in to a restaurant.' using errcode = 'P0001';
  end if;

  return query
    select c.code,
           case
             when c.flat_off is not null then '₹' || c.flat_off || ' off'
             else c.percent_off || '% off up to ₹' || c.max_off
           end,
           c.min_subtotal, c.flat_off, c.percent_off, c.max_off,
           c.valid_until, c.is_active,
           coalesce(u.n, 0)::integer,
           coalesce(u.given, 0)::integer
      from public.coupons c
      left join (
        select o.coupon_code, count(*) as n, sum(o.discount) as given
          from public.orders o
         where o.restaurant_id = v_restaurant
           and o.coupon_code is not null
           and o.status <> 'cancelled'
         group by o.coupon_code
      ) u on u.coupon_code = c.code
     where c.restaurant_id = v_restaurant
     order by c.is_active desc, c.code;
end;
$$;

grant execute on function public.vendor_offers() to authenticated;
