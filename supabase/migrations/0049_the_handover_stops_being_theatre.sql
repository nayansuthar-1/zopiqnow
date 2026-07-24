-- ---------------------------------------------------------------------------
-- 0049 — the delivery lifecycle closes
-- ---------------------------------------------------------------------------
-- B1 of the Zomato-parity programme (`ZOMATO_PARITY.md`). Four things, one
-- story: between "a rider claimed it" and "delivered" the system was blind, and
-- the one piece of proof it did have did not prove anything.
--
-- 1. **The pickup code was readable by the rider it was meant to test.** 0025
--    wrote it onto `deliveries.pickup_otp` and, three declarations later, gave
--    riders `select` on their own delivery row. `my_deliveries` withholds the
--    column and says why — "the rider types that in, they do not read it out" —
--    but a policy is not a function, and RLS is row-level, not column-level, so
--    `from('deliveries').select('pickup_otp')` answered anyway. A rider could
--    confirm a pickup from the road. The codes move to a table with **no
--    policies at all**, and each side reads its own through a function that
--    returns one column to one identity.
-- 2. **A delivery code, the mirror of the pickup code.** The customer reads four
--    digits off their tracking screen, the rider types them in. Until now
--    `confirm_delivered` took the rider's word for it.
-- 3. **Two new states.** `arrived_at_restaurant` and `arrived_at_customer` —
--    the two moments the kitchen and the customer most want to know about, and
--    the two the schema could not express.
-- 4. **Online / offline.** `is_active` is ops saying you work here. `is_online`
--    is the rider saying they are working *now*. There was no way to end a shift.
--
-- No new `orders.status` value: the whole lifecycle still lives in
-- `deliveries.state`, exactly as 8b-1 decided, so no customer build can be
-- broken by an unknown status. (`OrderStatus.fromWire` still throws.)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. The codes leave the row the rider can read.
-- ---------------------------------------------------------------------------
-- RLS on, and **no policies** — the same shape as `rider_pay_rates` (0043).
-- Nobody reads this table through PostgREST; three security-definer functions
-- are the only way in, and each returns exactly one column to exactly one
-- identity. That is how you get column-level secrecy out of a row-level system:
-- you put the secret in its own row and let a function pick which one you meant.
--
-- One row per *order*, not per delivery: a code is about a handover, and the
-- handover survives a rider dropping the job. The codes are regenerated on every
-- claim precisely because it does — a rider who abandoned a job knows the old
-- pickup code, and must not be able to walk back and use it.
create table if not exists public.delivery_codes (
  order_id           text primary key
                     references public.orders (id) on delete cascade,

  pickup_code        text not null check (pickup_code   ~ '^[0-9]{4}$'),
  delivery_code      text not null check (delivery_code ~ '^[0-9]{4}$'),

  -- Four digits is ten thousand guesses, which is nothing to a loop. The codes
  -- are checked by a function, so the function can count. Five wrong answers
  -- and the code is dead until the person who reads it out asks for a new one.
  pickup_attempts    integer not null default 0,
  delivery_attempts  integer not null default 0,

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

alter table public.delivery_codes enable row level security;

-- Belt and braces over the "no policies" rule: without a grant, even a policy
-- added by accident later would have nothing to permit.
revoke all on table public.delivery_codes from public, anon, authenticated;

-- Carry the live codes across before the column goes. A job in somebody's hand
-- right now must not have its pickup code changed by a migration — the vendor is
-- holding a printout of the old one.
insert into public.delivery_codes (order_id, pickup_code, delivery_code)
select d.order_id,
       d.pickup_otp,
       lpad((floor(random() * 10000))::integer::text, 4, '0')
  from public.deliveries d
 where d.state <> 'cancelled'
on conflict (order_id) do nothing;

alter table public.deliveries drop column if exists pickup_otp;

-- ---------------------------------------------------------------------------
-- B. The two states nobody could express.
-- ---------------------------------------------------------------------------
-- claimed → arrived_at_restaurant → picked_up → arrived_at_customer → delivered
--
-- Each arrival is a *required* step, not a nicety the app is trusted to lead the
-- rider through. "Prevent skipping steps" is only true if the database says so:
-- an app that offers the buttons in order is one build away from offering them
-- out of order. The cost is one tap; the gain is that `arrived_at_restaurant_at`
-- is a fact, so "the rider has been waiting nine minutes" is a sentence the
-- vendor's screen can honestly say.
alter table public.deliveries drop constraint if exists deliveries_state_check;
alter table public.deliveries add constraint deliveries_state_check
  check (state in ('claimed', 'arrived_at_restaurant', 'picked_up',
                   'arrived_at_customer', 'delivered', 'cancelled'));

alter table public.deliveries
  add column if not exists arrived_at_restaurant_at timestamptz,
  add column if not exists arrived_at_customer_at   timestamptz;

-- ---------------------------------------------------------------------------
-- C. A shift has an end.
-- ---------------------------------------------------------------------------
-- Defaults true so the backfill costs nobody a shift — the same reasoning 0024
-- used for `role`, and the same reason it is safe: an existing rider's app has
-- never had a switch to flip, so the only non-lossy default is "as you were".
--
-- Deliberately **not** consulted by `delivery_partner_email()`. That function
-- answers "are you a rider", and a rider who goes off shift is still a rider —
-- if it went null they would lose the ability to finish the job in their hand.
-- Going offline is refused mid-job anyway (below), but a rule that is enforced
-- in two places disagrees with itself eventually.
alter table public.delivery_partners
  add column if not exists is_online boolean not null default true;

create or replace function public.set_rider_online(p_online boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider text;
  v_live  integer;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  if p_online is null then
    raise exception 'Online or offline — not neither.' using errcode = 'P0001';
  end if;

  -- You may not end a shift holding somebody's dinner. The order would be off
  -- the board (the partial unique index keeps it there) with nobody looking at
  -- it and no screen anywhere able to fix that — the same trap 0040 guards for
  -- deactivation, arriving here for the same reason.
  if not p_online then
    select count(*) into v_live
      from public.deliveries
     where partner_email = v_rider
       and state in ('claimed', 'arrived_at_restaurant',
                     'picked_up', 'arrived_at_customer');

    if v_live > 0 then
      raise exception
        'Finish or drop your % live job(s) before going offline.', v_live
        using errcode = 'P0001';
    end if;
  end if;

  update public.delivery_partners
     set is_online = p_online
   where email = v_rider;
end;
$$;

grant execute on function public.set_rider_online(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- D. Reading your own code.
-- ---------------------------------------------------------------------------
-- Two functions, deliberately not one with a branch. Each names its audience in
-- its guard, so neither can be talked into answering the other's question.

-- The kitchen's code, for the kitchen to read aloud. Only while there is a rider
-- actually standing there to hear it — a code with no live delivery is a code
-- nobody needs, and handing it out early is handing it to the room.
create or replace function public.order_pickup_code(p_order_id text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if public.staff_restaurant_id() is null then
    raise exception 'You are not signed in to a restaurant.' using errcode = 'P0001';
  end if;

  select c.pickup_code into v_code
    from public.delivery_codes c
    join public.orders o     on o.id = c.order_id
    join public.deliveries d on d.order_id = c.order_id
   where c.order_id = p_order_id
     and o.restaurant_id = public.staff_restaurant_id()
     and d.state in ('claimed', 'arrived_at_restaurant');

  if v_code is null then
    raise exception 'No rider is waiting on that order.' using errcode = 'P0001';
  end if;

  return v_code;
end;
$$;

grant execute on function public.order_pickup_code(text) to authenticated;

-- The customer's code. Shown only once the food is actually on its way to them:
-- before pickup there is nothing to confirm, and after delivery the code has
-- done its job and is one more thing on a screen to be shoulder-surfed.
create or replace function public.order_delivery_code(p_order_id text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  select c.delivery_code into v_code
    from public.delivery_codes c
    join public.orders o     on o.id = c.order_id
    join public.deliveries d on d.order_id = c.order_id
   where c.order_id = p_order_id
     and o.user_id = auth.uid()::text
     and d.state in ('picked_up', 'arrived_at_customer');

  if v_code is null then
    raise exception 'That order is not out for delivery.' using errcode = 'P0001';
  end if;

  return v_code;
end;
$$;

grant execute on function public.order_delivery_code(text) to authenticated;

-- Five wrong guesses locks a code. Something has to unlock it, or a fat-fingered
-- rider strands an order at the doorstep — and the safe hand to put that in is
-- the one that reads the code out, because they already know it. Regenerating
-- tells them nothing they did not have. It resets the counter, which is the
-- whole point: a fresh code with the old attempts still counted is not a fix.
create or replace function public.regenerate_pickup_code(p_order_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if public.staff_restaurant_id() is null then
    raise exception 'You are not signed in to a restaurant.' using errcode = 'P0001';
  end if;

  update public.delivery_codes c
     set pickup_code     = lpad((floor(random() * 10000))::integer::text, 4, '0'),
         pickup_attempts = 0,
         updated_at      = now()
   where c.order_id = p_order_id
     and exists (
       select 1 from public.orders o
        where o.id = c.order_id
          and o.restaurant_id = public.staff_restaurant_id()
     )
     and exists (
       select 1 from public.deliveries d
        where d.order_id = c.order_id
          and d.state in ('claimed', 'arrived_at_restaurant')
     )
  returning c.pickup_code into v_code;

  if v_code is null then
    raise exception 'No rider is waiting on that order.' using errcode = 'P0001';
  end if;

  return v_code;
end;
$$;

grant execute on function public.regenerate_pickup_code(text) to authenticated;

create or replace function public.regenerate_delivery_code(p_order_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  update public.delivery_codes c
     set delivery_code     = lpad((floor(random() * 10000))::integer::text, 4, '0'),
         delivery_attempts = 0,
         updated_at        = now()
   where c.order_id = p_order_id
     and exists (
       select 1 from public.orders o
        where o.id = c.order_id
          and o.user_id = auth.uid()::text
     )
     and exists (
       select 1 from public.deliveries d
        where d.order_id = c.order_id
          and d.state in ('picked_up', 'arrived_at_customer')
     )
  returning c.delivery_code into v_code;

  if v_code is null then
    raise exception 'That order is not out for delivery.' using errcode = 'P0001';
  end if;

  return v_code;
end;
$$;

grant execute on function public.regenerate_delivery_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- E. Claiming, now that the codes live elsewhere and a shift can be over.
-- ---------------------------------------------------------------------------
-- Same body as 0046's (pay snapshot, road distance with the haversine fallback),
-- with two changes: the codes are written to `delivery_codes` instead of onto
-- the delivery row, and an offline rider is refused.
--
-- The code write is an upsert that **regenerates both codes**. A previous rider
-- who claimed and dropped this order knows the old pickup code; if it survived
-- their abandonment they could collect the food they no longer have the job for.
create or replace function public.claim_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_online   boolean;
  v_status   text;
  v_id       bigint;
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_d_lat    double precision;
  v_d_lng    double precision;
  v_route_km numeric(6,2);
  v_base     integer;
  v_per_km   numeric(6,2);
  v_distance numeric(6,2);
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select is_online into v_online
    from public.delivery_partners where email = v_rider;

  if not coalesce(v_online, false) then
    raise exception 'You are offline. Go online to take deliveries.'
      using errcode = 'P0001';
  end if;

  select o.status, r.latitude, r.longitude, o.delivery_lat, o.delivery_lng, o.route_km
    into v_status, v_r_lat, v_r_lng, v_d_lat, v_d_lng, v_route_km
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

  -- The road distance if we have it; the straight line if we do not.
  v_distance := coalesce(
    v_route_km,
    public.delivery_distance_km(v_r_lat, v_r_lng, v_d_lat, v_d_lng)
  );

  insert into public.deliveries (
    order_id, partner_email,
    distance_km, pay_base, pay_per_km, rider_pay
  )
  values (
    p_order_id,
    v_rider,
    v_distance,
    v_base,
    v_per_km,
    v_base + round(coalesce(v_distance, 0) * v_per_km)::integer
  )
  on conflict do nothing
  returning id into v_id;

  -- The index decided it, not us. Write the codes only for the winner.
  if v_id is null then
    raise exception 'Another partner just took that one.' using errcode = 'P0001';
  end if;

  insert into public.delivery_codes (order_id, pickup_code, delivery_code)
  values (
    p_order_id,
    lpad((floor(random() * 10000))::integer::text, 4, '0'),
    lpad((floor(random() * 10000))::integer::text, 4, '0')
  )
  on conflict (order_id) do update
     set pickup_code       = excluded.pickup_code,
         delivery_code     = excluded.delivery_code,
         pickup_attempts   = 0,
         delivery_attempts = 0,
         updated_at        = now();
end;
$$;

grant execute on function public.claim_delivery(text) to authenticated;

-- ---------------------------------------------------------------------------
-- F. The four moves of a delivery.
-- ---------------------------------------------------------------------------

-- I'm at the restaurant. Allowed while the food is still cooking — that is the
-- point of it: a rider who is standing there before the bag is packed is exactly
-- what the kitchen needs to see, and what makes `ready_by` worth chasing.
create or replace function public.arrive_at_restaurant(p_order_id text)
returns void
language plpgsql
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

  update public.deliveries
     set state = 'arrived_at_restaurant',
         arrived_at_restaurant_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'claimed';

  if not found then
    raise exception 'You have no job waiting to be collected on that order.'
      using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.arrive_at_restaurant(text) to authenticated;

-- Collected. Now with a code the rider cannot look up, an attempt cap, and a
-- required arrival before it.
--
-- Scoped to the *live* row on every write, per 0025's abandon→reclaim bug: an
-- order that was claimed, dropped and claimed again has a `cancelled` row beside
-- this one, and an update keyed on `order_id` alone drags the corpse along.
--
-- **Returns a word, and does not raise on a wrong code.** This is the one place
-- in the codebase where a failure is a return value, and the reason is the
-- attempt cap: `raise` aborts the transaction, which would roll back the very
-- increment that counts the guess. A cap that unwinds itself is not a cap, it is
-- a speed bump — and ten thousand codes is nothing to a loop. Structural
-- failures (not a rider, wrong state, not packed) still raise: they write
-- nothing, so there is nothing to preserve.
--
--   'ok'          — collected
--   'wrong_code'  — counted, and said so
--   'locked'      — five wrong guesses; the restaurant must issue a new code
--
-- The caller maps anything but 'ok' to a failure in one place (the datasource),
-- so no screen has to remember to check.
--
-- Dropped first: 0025's version returned `void`, and a return type cannot be
-- replaced in place.
drop function if exists public.confirm_pickup(text, text);

create or replace function public.confirm_pickup(
  p_order_id text,
  p_otp      text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_code     text;
  v_attempts integer;
  v_status   text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- Locked: the vendor may be pressing its own hand-off button at this instant.
  select o.status into v_status
    from public.deliveries d
    join public.orders o on o.id = d.order_id
   where d.order_id = p_order_id
     and d.partner_email = v_rider
     and d.state = 'arrived_at_restaurant'
   for update of d;

  if not found then
    raise exception
      'Tap "I''ve arrived" at the restaurant before collecting the order.'
      using errcode = 'P0001';
  end if;

  if v_status <> 'ready_for_pickup' then
    raise exception 'That order isn''t packed yet.' using errcode = 'P0001';
  end if;

  select pickup_code, pickup_attempts into v_code, v_attempts
    from public.delivery_codes
   where order_id = p_order_id
   for update;

  if not found then
    raise exception 'That order has no pickup code.' using errcode = 'P0001';
  end if;

  if v_attempts >= 5 then
    return 'locked';
  end if;

  if p_otp is distinct from v_code then
    update public.delivery_codes
       set pickup_attempts = pickup_attempts + 1, updated_at = now()
     where order_id = p_order_id;

    -- The fifth wrong guess reports itself as the lockout it just caused,
    -- rather than making the rider tap once more to be told.
    return case when v_attempts + 1 >= 5 then 'locked' else 'wrong_code' end;
  end if;

  update public.deliveries
     set state = 'picked_up', picked_up_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'arrived_at_restaurant';

  update public.orders set status = 'out_for_delivery' where id = p_order_id;

  return 'ok';
end;
$$;

grant execute on function public.confirm_pickup(text, text) to authenticated;

-- I'm at the door. What turns "out for delivery" into "he's outside" on the
-- customer's screen, and what the delivery code is shown alongside.
create or replace function public.arrive_at_customer(p_order_id text)
returns void
language plpgsql
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

  update public.deliveries
     set state = 'arrived_at_customer',
         arrived_at_customer_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'picked_up';

  if not found then
    raise exception 'You aren''t carrying that order.' using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.arrive_at_customer(text) to authenticated;

-- Handed over. **The signature changed** — the one-argument version is dropped
-- rather than kept beside this one, because a no-code way to mark an order
-- delivered is the exact hole this migration exists to close, and a deprecated
-- function is still a callable one.
-- Returns a word rather than raising on a wrong code, for the same reason
-- `confirm_pickup` does: the attempt cap has to survive the guess that tripped it.
drop function if exists public.confirm_delivered(text);
drop function if exists public.confirm_delivered(text, text);

create or replace function public.confirm_delivered(
  p_order_id text,
  p_otp      text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_status   text;
  v_code     text;
  v_attempts integer;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select o.status into v_status
    from public.deliveries d
    join public.orders o on o.id = d.order_id
   where d.order_id = p_order_id
     and d.partner_email = v_rider
     and d.state = 'arrived_at_customer'
   for update of d;

  if not found then
    raise exception
      'Tap "I''ve arrived" at the customer before completing the delivery.'
      using errcode = 'P0001';
  end if;

  -- 0041's check, kept: an order that is not out for delivery cannot arrive.
  if v_status <> 'out_for_delivery' then
    raise exception 'That order is %, so it can''t be marked delivered.', v_status
      using errcode = 'P0001';
  end if;

  select delivery_code, delivery_attempts into v_code, v_attempts
    from public.delivery_codes
   where order_id = p_order_id
   for update;

  if not found then
    raise exception 'That order has no delivery code.' using errcode = 'P0001';
  end if;

  if v_attempts >= 5 then
    return 'locked';
  end if;

  if p_otp is distinct from v_code then
    update public.delivery_codes
       set delivery_attempts = delivery_attempts + 1, updated_at = now()
     where order_id = p_order_id;

    return case when v_attempts + 1 >= 5 then 'locked' else 'wrong_code' end;
  end if;

  update public.deliveries
     set state = 'delivered', delivered_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'arrived_at_customer';

  update public.orders set status = 'delivered' where id = p_order_id;

  return 'ok';
end;
$$;

grant execute on function public.confirm_delivered(text, text) to authenticated;

-- Dropping a job now covers the arrival too: a rider standing in a kitchen that
-- has not started cooking must be able to walk away. Not after pickup — once the
-- food is on the bike, walking away is a support conversation, not a button.
create or replace function public.abandon_delivery(p_order_id text)
returns void
language plpgsql
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

  update public.deliveries
     set state = 'cancelled'
   where order_id = p_order_id
     and partner_email = v_rider
     and state in ('claimed', 'arrived_at_restaurant');

  if not found then
    raise exception 'You can only drop a job you haven''t picked up yet.'
      using errcode = 'P0001';
  end if;

  -- The codes go with it. The next rider gets fresh ones from `claim_delivery`,
  -- but leaving these live in the meantime means a dropped rider still holds a
  -- working pickup code for an order back on the board.
  delete from public.delivery_codes where order_id = p_order_id;
end;
$$;

grant execute on function public.abandon_delivery(text) to authenticated;

-- ---------------------------------------------------------------------------
-- G. What the rider's own screen shows.
-- ---------------------------------------------------------------------------
-- Return shape widens by the two arrival stamps, so this is a drop-and-recreate
-- rather than a replace. 0041's phone rule is kept exactly: the customer's
-- number disappears the moment the job is done.
drop function if exists public.my_deliveries();

create or replace function public.my_deliveries()
returns table (
  order_id                 text,
  state                    text,
  order_status             text,
  restaurant_name          text,
  restaurant_lat           double precision,
  restaurant_lng           double precision,
  deliver_to               text,
  deliver_lat              double precision,
  deliver_lng              double precision,
  customer_phone           text,
  total                    integer,
  payment_method           text,
  distance_km              numeric,
  pay_base                 integer,
  pay_per_km               numeric,
  rider_pay                integer,
  claimed_at               timestamptz,
  arrived_at_restaurant_at timestamptz,
  picked_up_at             timestamptz,
  arrived_at_customer_at   timestamptz,
  delivered_at             timestamptz
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
           d.claimed_at, d.arrived_at_restaurant_at,
           d.picked_up_at, d.arrived_at_customer_at, d.delivered_at
      from public.deliveries d
      join public.orders o on o.id = d.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where d.partner_email = v_rider
       and d.state <> 'cancelled'
     order by d.claimed_at desc;
end;
$$;

grant execute on function public.my_deliveries() to authenticated;

-- An offline rider is shown an empty board rather than a refusal: they have not
-- done anything wrong, they have clocked off, and the app says so in its own
-- words. `claim_delivery` is where the actual rule lives, because a board is a
-- suggestion and a claim is a write.
create or replace function public.available_deliveries()
returns table (
  order_id        text,
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  total           integer,
  payment_method  text,
  status          text,
  ready_by        timestamptz,
  placed_at       timestamptz
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

  if not exists (
    select 1 from public.delivery_partners
     where email = v_rider and is_online
  ) then
    return;
  end if;

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status, o.ready_by, o.created_at
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
     where o.status in ('preparing', 'ready_for_pickup')
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = o.id and d.state <> 'cancelled'
       )
     order by (o.status = 'ready_for_pickup') desc, o.created_at;
end;
$$;

grant execute on function public.available_deliveries() to authenticated;

-- ---------------------------------------------------------------------------
-- H. The windows widen with the states.
-- ---------------------------------------------------------------------------
-- Every policy that named a state has to learn the two new ones, and the
-- customer's is the one that would have bitten hardest: scoped to `picked_up`
-- alone, the rider's name would have **vanished from the customer's screen at
-- the exact moment they knocked on the door**.

drop policy if exists "staff read the rider carrying their order" on public.delivery_partners;
create policy "staff read the rider carrying their order"
  on public.delivery_partners for select to authenticated
  using (
    exists (
      select 1
        from public.deliveries d
        join public.orders o on o.id = d.order_id
       where d.partner_email = delivery_partners.email
         and o.restaurant_id = public.staff_restaurant_id()
         and d.state in ('claimed', 'arrived_at_restaurant',
                         'picked_up', 'arrived_at_customer')
    )
  );

-- 0039's window, plus the doorstep. Still not `claimed` (a rider may still drop
-- it, and a name that appears then changes is worse than one that arrives late)
-- and still not `delivered` (the job is over; the rider's number is theirs again).
drop policy if exists "customers read the delivery of their order" on public.deliveries;
create policy "customers read the delivery of their order"
  on public.deliveries for select to authenticated
  using (
    deliveries.state in ('picked_up', 'arrived_at_customer')
    and exists (
      select 1 from public.orders o
       where o.id = deliveries.order_id
         and o.user_id = auth.uid()::text
    )
  );

drop policy if exists "customers read the rider carrying their order" on public.delivery_partners;
create policy "customers read the rider carrying their order"
  on public.delivery_partners for select to authenticated
  using (
    exists (
      select 1
        from public.deliveries d
        join public.orders o on o.id = d.order_id
       where d.partner_email = delivery_partners.email
         and o.user_id = auth.uid()::text
         and d.state in ('picked_up', 'arrived_at_customer')
    )
  );

-- ---------------------------------------------------------------------------
-- I. Don't wake a rider who has clocked off.
-- ---------------------------------------------------------------------------
-- 0047's fan-out wrote a job-available row for every *active* rider. Active is
-- ops saying you work here; it is not "awake at 2am". Now that a shift has an
-- end, the notification respects it. Wrapped, like every trigger since 0021, so
-- it can never abort the write it rides on.
create or replace function public.notify_riders_job_available()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'preparing' and old.status is distinct from 'preparing'
     and new.delivery_lat is not null and new.delivery_lng is not null then
    begin
      insert into public.notifications (audience, partner_email, kind, title, body, order_id)
      select 'rider', p.email, 'job_available',
             'New delivery',
             'A delivery from ' || new.restaurant_name || ' is ready to claim',
             new.id
        from public.delivery_partners p
       where p.is_active and p.is_online;
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;
