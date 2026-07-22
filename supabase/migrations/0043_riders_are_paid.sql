-- Phase 8c, migration 43: a delivery is worth something.
--
-- Until now a rider could work a full shift and the database would hold no
-- number describing what they had earned. `deliveries` recorded who, what and
-- when, and nothing about money. This adds the money.
--
-- **Not to be confused with `orders.delivery_fee`**, which has existed since
-- 0003 and is what the *customer is charged*. What a customer pays for delivery
-- and what a rider is paid to deliver are two different numbers that happen to
-- describe the same ride, and conflating them is how a platform ends up unable
-- to change either one. The rider's side is named `rider_pay` throughout.
--
-- **The model — user decision, 2026-07-22: a base fee plus a per-kilometre
-- rate.** Chosen over a flat fee, and over a percentage of the order value
-- (which pays less for a ₹150 order than a ₹1500 one when the ride is
-- identical).
--
-- **The honest caveat, stated once, here.** The distance is haversine — the
-- straight line between two points. It is not the distance anybody rides. A
-- river, a one-way system or a flyover all make the real ride longer, never
-- shorter, so this formula systematically underpays and never overpays. Two
-- things follow, and both are deliberate:
--
--   1. `distance_km` is stored on the row, not just folded into a total, so
--      the number is auditable and a rider disputing their pay can be shown
--      what was measured.
--   2. The rates are editable by an admin, so the answer to "the straight line
--      is short here" is to raise the base until the average job is fair. That
--      is a dial ops can turn; a hard-coded formula is not.
--
-- Doing better needs a routing service — a road distance, a paid API, a network
-- call inside a claim. Real work, and not this slice.

-- ---------------------------------------------------------------------------
-- What a kilometre is worth.
-- ---------------------------------------------------------------------------
-- One row, platform-wide, and the primary key is what enforces that. A rate
-- table that can hold two rows invites the question "which one applies?", and
-- the honest answer today is that there is no per-city, per-restaurant or
-- per-rider variation to express. When there is, this grows a scope column and
-- the check goes; until then the constraint is the documentation.
create table if not exists public.rider_pay_rates (
  id          integer primary key default 1 check (id = 1),

  -- Whole rupees, like every other money column in this schema.
  base_fee    integer not null check (base_fee >= 0),

  -- Rupees per kilometre, and the one place fractions are allowed: ₹5.50/km is
  -- a rate somebody will want, and rounding it to ₹5 or ₹6 across a shift is
  -- real money.
  per_km_fee  numeric(6,2) not null check (per_km_fee >= 0),

  updated_at  timestamptz not null default now()
);

-- A starting point, not a considered rate. Ops sets the real numbers in the
-- console; this exists so the first claim after this migration has something to
-- read instead of failing.
insert into public.rider_pay_rates (id, base_fee, per_km_fee)
values (1, 25, 5.00)
on conflict (id) do nothing;

-- No policies, and none are coming. The admin console reaches this through
-- `security definer` functions and riders never read it at all — the rate that
-- applied to a job is copied onto the job (below), so nothing in the rider app
-- needs the live table. A rider who could read it could watch it change.
alter table public.rider_pay_rates enable row level security;

-- ---------------------------------------------------------------------------
-- How far apart two points are.
-- ---------------------------------------------------------------------------
-- Haversine, in whole SQL, because postgis is not installed and installing an
-- extension to compute one number is a heavier commitment than the number is
-- worth.
--
-- Null in, null out, on purpose: a missing coordinate is *unknown* distance,
-- which is a different fact from zero distance and must not collapse into it.
-- Every caller below treats null as "we could not measure this" and says so.
create or replace function public.delivery_distance_km(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
)
returns numeric
language sql
immutable
as $$
  select case
    when p_lat1 is null or p_lng1 is null or p_lat2 is null or p_lng2 is null
      then null
    else round(
      (2 * 6371 * asin(
        -- `least(1, …)` guards the one way this can raise: floating point can
        -- push the argument a hair past 1.0 for two points that are the same
        -- place, and `asin(1.0000000000000002)` is a domain error, not a zero.
        least(1, sqrt(
          power(sin(radians(p_lat2 - p_lat1) / 2), 2)
          + cos(radians(p_lat1)) * cos(radians(p_lat2))
            * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
        ))
      ))::numeric,
      2
    )
  end;
$$;

-- ---------------------------------------------------------------------------
-- The job carries its own price.
-- ---------------------------------------------------------------------------
-- Four columns, and the reason there are four rather than one is that a rider
-- must be able to see *why* they were paid what they were paid. "₹25 + 4.2 km ×
-- ₹5 = ₹46" is a number somebody can check. "₹46" is a number somebody has to
-- take on faith, and pay you cannot check is pay you will eventually dispute.
--
-- All four are a snapshot taken at claim time. An admin raising the rate on
-- Friday does not retroactively repay Thursday, and — more importantly — does
-- not retroactively *reduce* it either.
--
-- Nullable, all of them. `deliveries` is empty today so nothing needs
-- backfilling, but a `not null` here would be a claim about rows written by
-- code that did not exist when they were written. Null reads as "before there
-- was a pay model", which is true and will stay true.
alter table public.deliveries
  add column if not exists distance_km numeric(6,2),
  add column if not exists pay_base    integer,
  add column if not exists pay_per_km  numeric(6,2),
  add column if not exists rider_pay   integer;

-- ---------------------------------------------------------------------------
-- Claiming, now with a price attached.
-- ---------------------------------------------------------------------------
-- Unchanged from 0025 except that the insert carries the pay snapshot: same
-- race, same partial unique index deciding it, same message to the loser.
--
-- The rate is read *before* the insert and the distance computed from the two
-- coordinate pairs — the restaurant's (0027, and required at publish since
-- 0042) and the order's (0003, set by the customer app on every order).
create or replace function public.claim_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_status   text;
  v_id       bigint;
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_d_lat    double precision;
  v_d_lng    double precision;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_distance numeric(6,2);
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select o.status, r.latitude, r.longitude, o.delivery_lat, o.delivery_lng
    into v_status, v_r_lat, v_r_lng, v_d_lat, v_d_lng
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found then
    raise exception 'That order no longer exists.' using errcode = 'P0001';
  end if;

  if v_status not in ('preparing', 'ready_for_pickup') then
    raise exception 'That order is no longer available.' using errcode = 'P0001';
  end if;

  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;

  v_distance := public.delivery_distance_km(v_r_lat, v_r_lng, v_d_lat, v_d_lng);

  insert into public.deliveries (
    order_id, partner_email, pickup_otp,
    distance_km, pay_base, pay_per_km, rider_pay
  )
  values (
    p_order_id,
    v_rider,
    -- Four digits, zero-padded. `random()` is not a cryptographic source and
    -- does not need to be: the code is checked against one specific order, by
    -- one specific rider, standing in one specific shop, within minutes.
    lpad((floor(random() * 10000))::integer::text, 4, '0'),
    v_distance,
    v_base,
    v_per_km,
    -- An unmeasurable distance pays the base and nothing more. It does not pay
    -- zero, and it does not refuse the job: a rider standing at a counter is
    -- not the right person to discover that ops never set a map pin.
    v_base + round(coalesce(v_distance, 0) * v_per_km)::integer
  )
  on conflict do nothing
  returning id into v_id;

  if v_id is null then
    raise exception 'Another partner just took that one.' using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.claim_delivery(text) to authenticated;

-- ---------------------------------------------------------------------------
-- The rider's own jobs, now including what each one paid.
-- ---------------------------------------------------------------------------
-- Dropped and rebuilt rather than replaced: `create or replace` refuses to
-- widen a `returns table` shape.
--
-- Everything above the four new columns is 0041 verbatim, including the rule
-- that matters most in it — the customer's phone number is withheld once the
-- job is `delivered`, because the reason a rider was given it ("I'm outside and
-- can't find the gate") ends when the food is handed over.
drop function if exists public.my_deliveries();

create or replace function public.my_deliveries()
returns table (
  order_id        text,
  state           text,
  order_status    text,
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  deliver_lat     double precision,
  deliver_lng     double precision,
  customer_phone  text,
  total           integer,
  payment_method  text,
  distance_km     numeric,
  pay_base        integer,
  pay_per_km      numeric,
  rider_pay       integer,
  claimed_at      timestamptz,
  picked_up_at    timestamptz,
  delivered_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  return query
    select o.id, d.state, o.status, r.name, r.latitude, r.longitude,
           o.delivery_to, o.delivery_lat, o.delivery_lng,
           case when d.state = 'delivered' then null else o.user_phone end,
           o.total, o.payment_method,
           d.distance_km, d.pay_base, d.pay_per_km, d.rider_pay,
           d.claimed_at, d.picked_up_at, d.delivered_at
      from public.deliveries d
      join public.orders o on o.id = d.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where d.partner_email = v_rider
       and d.state <> 'cancelled'
     order by d.claimed_at desc;
end;
$$;

grant execute on function public.my_deliveries() to authenticated;

-- ---------------------------------------------------------------------------
-- What a rider has earned, by day.
-- ---------------------------------------------------------------------------
-- A separate function rather than letting the app total up `my_deliveries`,
-- for one reason that gets worse with time: `my_deliveries` returns every job
-- the rider has ever held, and an earnings screen that has to download a career
-- to display a week is a screen that gets slower every shift.
--
-- **Only `delivered` counts.** A job claimed and dropped pays nothing, and a job
-- in hand has not been earned yet — a rider who could watch their total rise at
-- pickup would be told they had been paid for a delivery they might still fail
-- to make. The day is the day it was *delivered*, in IST, because that is the
-- day the rider worked.
create or replace function public.rider_earnings(p_from date, p_to date)
returns table (
  day      date,
  jobs     integer,
  earnings integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'That date range runs backwards.' using errcode = 'P0001';
  end if;

  return query
    select (d.delivered_at at time zone 'Asia/Kolkata')::date,
           count(*)::integer,
           -- `coalesce` covers rows claimed before this migration existed. There
           -- are none today; there will never be a moment where that is worth a
           -- crash on an earnings screen.
           coalesce(sum(d.rider_pay), 0)::integer
      from public.deliveries d
     where d.partner_email = v_rider
       and d.state = 'delivered'
       and (d.delivered_at at time zone 'Asia/Kolkata')::date between p_from and p_to
     group by 1
     order by 1 desc;
end;
$$;

grant execute on function public.rider_earnings(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Ops turns the dial.
-- ---------------------------------------------------------------------------
-- Same shape as every other admin function since 0030: `security definer`,
-- `assert_admin()` on the first line, and no grant on the table itself.
create or replace function public.admin_get_rider_pay_rates()
returns table (
  base_fee   integer,
  per_km_fee numeric,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select r.base_fee, r.per_km_fee, r.updated_at
      from public.rider_pay_rates r where r.id = 1;
end;
$$;

revoke execute on function public.admin_get_rider_pay_rates() from public;
grant execute on function public.admin_get_rider_pay_rates() to authenticated;

-- An upper bound on each, which is not paternalism about generosity — it is
-- that a typo dropping a zero in the wrong place writes a rate every subsequent
-- claim silently snapshots, and the rows are already paid by the time anybody
-- notices. ₹500 base and ₹200/km are both far outside any real rate and well
-- inside "obviously a mistake".
create or replace function public.admin_set_rider_pay_rates(
  p_base_fee   integer,
  p_per_km_fee numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if p_base_fee is null or p_base_fee < 0 or p_base_fee > 500 then
    raise exception 'A base fee of ₹% is not a rate anybody meant to set.', p_base_fee
      using errcode = 'P0001';
  end if;
  if p_per_km_fee is null or p_per_km_fee < 0 or p_per_km_fee > 200 then
    raise exception 'A per-kilometre rate of ₹% is not a rate anybody meant to set.', p_per_km_fee
      using errcode = 'P0001';
  end if;

  insert into public.rider_pay_rates (id, base_fee, per_km_fee, updated_at)
  values (1, p_base_fee, p_per_km_fee, now())
  on conflict (id) do update
     set base_fee   = excluded.base_fee,
         per_km_fee = excluded.per_km_fee,
         updated_at = now();
end;
$$;

revoke execute on function public.admin_set_rider_pay_rates(integer, numeric) from public;
grant execute on function public.admin_set_rider_pay_rates(integer, numeric) to authenticated;
