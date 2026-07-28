-- ---------------------------------------------------------------------------
-- 0057 — the rider is somewhere, and the ETA knows it. (B3, tracking)
-- ---------------------------------------------------------------------------
-- 0056 gave the platform a dispatcher. This gives it eyes: a rider's position
-- while they are carrying, the shape of the road they are riding, and an arrival
-- time computed from both instead of promised once at checkout and never
-- revisited.
--
-- **The ETA this replaces.** Since 0003 the customer has been told "arriving by
-- HH:MM", computed as `created_at + eta_minutes` — a number picked when the
-- order was placed, before a kitchen accepted it, before a rider existed, and
-- never touched again. 0052 was explicit that this was deliberate ("the promise
-- is not recomputed... a screen that quietly moves the estimate is a screen that
-- never has to admit the food is late"), and it was right for a platform that
-- could not see anything. It can see now.
--
-- **The rule that makes recomputing honest.** B3: *the ETA must never move
-- backwards without a reason on screen.* Backwards means later — the direction
-- that costs the customer something. So:
--
--   * moving **earlier** needs nothing. Good news arrives unannounced.
--   * moving **later** is only written together with `eta_reason`, a sentence
--     naming the cause, and the tracking card renders it beside the time. There
--     are exactly three causes this migration can honestly name, and an
--     estimate that would slip for a reason outside that list is **not written
--     at all** — the old time stands. A platform that cannot say why is not
--     entitled to move the number.
--   * a slip under two minutes is not written either. An ETA that twitches every
--     ten seconds as a rider waits at a light is noise dressed as information.
--
-- **On privacy.** A rider's position is the single most sensitive thing this
-- platform holds about its own workers. Three lines defend it: it is one row per
-- rider and not a track, so there is no history to leak; it is deleted the
-- moment the rider has nothing live, so an off-shift rider is nowhere; and the
-- only reader other than the platform is the one customer whose food is
-- physically on that bike, for the minutes it is on it.

-- ---------------------------------------------------------------------------
-- A. The position, and who may see it.
-- ---------------------------------------------------------------------------
-- The table itself is 0056's (the dispatcher had to be able to read it). This
-- is everything around it.

-- The rider writes through `record_rider_location` and never touches the table,
-- so there is no insert or update policy here and none is coming — the function
-- is what enforces "only while you are actually carrying something".
--
-- The customer's read. Scoped exactly to the delivery that is theirs and in
-- flight, the same shape as 0039's two policies and for the same reason: a
-- position readable outside that window is a tracking device.
--
-- B3 writes the window as `state = 'picked_up'`. This uses `picked_up` *and*
-- `arrived_at_customer`, matching what 0049 widened 0039's own delivery policy
-- to — a rider standing at the gate is still the person the customer is looking
-- for, and a map that blanks at the last fifty metres blanks exactly when it is
-- being stared at.
drop policy if exists "customers see their rider on the map" on public.rider_locations;
create policy "customers see their rider on the map"
  on public.rider_locations for select to authenticated
  using (
    exists (
      select 1
        from public.deliveries d
        join public.orders o on o.id = d.order_id
       where d.partner_email = rider_locations.partner_email
         and o.user_id = auth.uid()::text
         and d.state in ('picked_up', 'arrived_at_customer')
    )
  );

grant select on public.rider_locations to authenticated;

-- Realtime. The map is the one screen on the platform where polling would be
-- visible as jerk — and the policy above rides the socket, so a customer who
-- subscribes early is delivered nothing until the food is on the bike.
do $$
begin
  alter publication supabase_realtime add table public.rider_locations;
exception
  when duplicate_object then null;
  when undefined_object then null;
end;
$$;

-- ---------------------------------------------------------------------------
-- B. Writing a fix.
-- ---------------------------------------------------------------------------
-- Called by the rider app on an interval while it is carrying. It refuses
-- silently — returns, does not raise — for a rider with nothing live, because
-- the alternative is an app that throws an exception every few seconds in the
-- window between a handover and the stream noticing.
--
-- The write is an upsert onto one row. The previous fix is overwritten, not
-- appended: see the privacy note at the top.
create or replace function public.record_rider_location(
  p_lat     double precision,
  p_lng     double precision,
  p_heading numeric default null,
  p_speed   numeric default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider text;
  o       record;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90
     or p_lng not between -180 and 180 then
    return;
  end if;

  -- No live job, no position. This is the retention rule enforced at the point
  -- of writing rather than only by the sweep — a rider whose job ended a second
  -- ago stops being on the map immediately, not at the next purge.
  if not exists (
    select 1 from public.deliveries d
     where d.partner_email = v_rider
       and d.state in ('claimed', 'arrived_at_restaurant',
                       'picked_up', 'arrived_at_customer')
  ) then
    delete from public.rider_locations where partner_email = v_rider;
    return;
  end if;

  insert into public.rider_locations
    (partner_email, lat, lng, heading, speed_kmh, updated_at)
  values (v_rider, p_lat, p_lng, p_heading, p_speed, now())
  on conflict (partner_email) do update
    set lat = excluded.lat,
        lng = excluded.lng,
        heading = excluded.heading,
        speed_kmh = excluded.speed_kmh,
        updated_at = now();

  -- Every order this rider is currently carrying gets its arrival time redone
  -- against the new position. Only the carried ones: an order still sitting in
  -- the kitchen is not made any later or earlier by where the rider is.
  for o in
    select d.order_id
      from public.deliveries d
     where d.partner_email = v_rider
       and d.state in ('picked_up', 'arrived_at_customer')
  loop
    begin
      perform public.recompute_order_eta(o.order_id);
    exception when others then
      -- An ETA is a courtesy on top of the position. It must never be the
      -- reason a rider's location stops being recorded.
      null;
    end;
  end loop;
end;
$$;

grant execute on function public.record_rider_location(
  double precision, double precision, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- C. Forgetting.
-- ---------------------------------------------------------------------------
-- The other half of the retention rule, for the cases the writer cannot cover:
-- a rider whose phone died mid-job, a job cancelled out from under them, an app
-- killed at the door. Anything belonging to a rider with nothing live goes.
--
-- Ten minutes of grace so a brief drop between two jobs does not blank the map
-- for a customer whose rider is a hundred metres away and momentarily between
-- states.
create or replace function public.purge_rider_locations()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.rider_locations l
   where l.updated_at < now() - interval '10 minutes'
      or not exists (
        select 1 from public.deliveries d
         where d.partner_email = l.partner_email
           and d.state in ('claimed', 'arrived_at_restaurant',
                           'picked_up', 'arrived_at_customer')
      );
$$;

revoke all on function public.purge_rider_locations()
  from public, anon, authenticated;

-- Folded into the dispatcher's tick rather than given a cron entry of its own.
-- It already runs every twenty seconds and the two are the same concern: what
-- the platform currently knows about where its riders are.
create or replace function public.dispatch_deliveries()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o record;
  v_offered text;
begin
  update public.delivery_offers
     set state = 'expired', responded_at = now()
   where state = 'offered'
     and expires_at <= now();

  for o in
    select ord.id
      from public.orders ord
     where ord.status in ('preparing', 'ready_for_pickup')
       and ord.delivery_lat is not null
       and ord.delivery_lng is not null
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = ord.id and d.state <> 'cancelled'
       )
       and not exists (
         select 1 from public.delivery_offers off
          where off.order_id = ord.id
            and off.state = 'offered'
            and off.expires_at > now()
       )
     order by (ord.status = 'ready_for_pickup') desc, ord.created_at
     limit 50
  loop
    v_offered := public.offer_delivery(o.id);
    if v_offered is null then
      perform public.announce_open_delivery(o.id);
    end if;
  end loop;

  -- New in 0057.
  perform public.purge_rider_locations();
end;
$$;

revoke all on function public.dispatch_deliveries()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- D. The shape of the road.
-- ---------------------------------------------------------------------------
-- Ola's Directions response already carries `overview_polyline` — the encoded
-- path the van of a route, the thing a map draws. 0046 read the distance out of
-- the same response and threw the rest away, because there was no map to draw
-- it on.
--
-- Stored as the encoded string exactly as Ola sends it (Google's polyline
-- algorithm, precision 5). Decoded on the device, not here: it is a few hundred
-- bytes as text and a few thousand as a coordinate array, and the phone drawing
-- it has to walk the points anyway.
alter table public.orders
  add column if not exists route_polyline text;

-- Same function as 0046, same signature, one added write. Replacing rather than
-- overloading — the argument list is unchanged, so this genuinely replaces.
create or replace function public.process_order_routes()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key    text;
  v_status integer;
  v_meters numeric;
  v_line   text;
  v_req    bigint;
  j        record;
begin
  for j in
    select order_id, request_id, updated_at
      from public.order_route_jobs
     where request_id is not null
  loop
    select status_code into v_status
      from net._http_response
     where id = j.request_id;

    if not found then
      if j.updated_at < now() - interval '10 minutes' then
        update public.order_route_jobs
           set request_id = null, attempts = attempts + 1, updated_at = now()
         where order_id = j.order_id;
      end if;
      continue;
    end if;

    if v_status = 200 then
      select (content::jsonb #>> '{routes,0,legs,0,distance}')::numeric,
             -- Null-tolerant on purpose: a response with a distance and no
             -- polyline still pays the rider correctly, and the map falls back
             -- to a straight line between the two pins.
             (content::jsonb #>> '{routes,0,overview_polyline}')
        into v_meters, v_line
        from net._http_response
       where id = j.request_id;

      if v_meters is not null then
        update public.orders
           set route_km = round(v_meters / 1000.0, 2),
               route_polyline = v_line
         where id = j.order_id;
        delete from public.order_route_jobs where order_id = j.order_id;
        continue;
      end if;
    end if;

    update public.order_route_jobs
       set request_id = null, attempts = attempts + 1, updated_at = now()
     where order_id = j.order_id;
  end loop;

  delete from public.order_route_jobs where attempts >= 5;

  select decrypted_secret into v_key
    from vault.decrypted_secrets
   where name = 'ola_maps_api_key';
  if v_key is null then
    return;
  end if;

  for j in
    select oj.order_id,
           r.latitude    as r_lat, r.longitude    as r_lng,
           o.delivery_lat as d_lat, o.delivery_lng as d_lng
      from public.order_route_jobs oj
      join public.orders o      on o.id = oj.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where oj.request_id is null
       and o.delivery_lat is not null and o.delivery_lng is not null
       and r.latitude    is not null and r.longitude    is not null
     order by oj.updated_at
     limit 25
  loop
    v_req := net.http_post(
      url    := 'https://api.olamaps.io/routing/v1/directions',
      body   := '{}'::jsonb,
      params := jsonb_build_object(
        'origin',      j.r_lat || ',' || j.r_lng,
        'destination', j.d_lat || ',' || j.d_lng,
        'api_key',     v_key
      ),
      headers := jsonb_build_object('Origin', 'https://zopiqnow.app'),
      timeout_milliseconds := 8000
    );

    update public.order_route_jobs
       set request_id = v_req, updated_at = now()
     where order_id = j.order_id;
  end loop;
end;
$$;

revoke all on function public.process_order_routes()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- E. The arrival time, and why it moved.
-- ---------------------------------------------------------------------------
-- `eta_at` is the live promise; null means nobody has recomputed one yet and the
-- original `created_at + eta_minutes` stands. `eta_reason` is the sentence shown
-- on the tracking card, and it is non-null only when the time has slipped —
-- reading it is how the customer learns the platform is not pretending.
alter table public.orders
  add column if not exists eta_at     timestamptz,
  add column if not exists eta_reason text;

-- How fast a two-wheeler actually moves through an Indian city, door to door,
-- including the lights it stops at. Twenty-two km/h is deliberately pessimistic
-- against a GPS speed reading, which measures the moving half of a journey and
-- would have every ETA arrive early and then slip.
--
-- Constants in a function rather than a settings table, for 0056's reason: a
-- table nobody can write to is a table that lies about being configurable.
create or replace function public.rider_city_speed_kmh()
returns numeric language sql immutable as $$ select 22.0 $$;

-- What a handover costs at each end: finding the gate, the lift, the code. Two
-- minutes, and it is in the estimate rather than absorbed by optimism, because
-- an ETA that expires while the rider is climbing stairs is an ETA that was
-- wrong.
create or replace function public.handover_minutes()
returns integer language sql immutable as $$ select 2 $$;

-- ---------------------------------------------------------------------------
-- F. Recomputing it.
-- ---------------------------------------------------------------------------
-- Two cases, because there are two distances that matter.
--
--   * **Not yet picked up.** The food cannot leave before it is cooked, so the
--     estimate is `when it will be ready` + `the whole ride` + handover. Ready
--     is `orders.ready_by` when the kitchen has committed to one, and the
--     original promise otherwise.
--
--   * **Carrying.** The ride left is rider → door, and the only measurement
--     available every few seconds is the straight line. A straight line is not
--     a road — 0046 measured 3.5 km of it against 12.14 km of tarmac — so it is
--     multiplied by this order's *own* detour factor: `route_km` over the
--     straight line the same route was quoted against. An order whose roads
--     wander gets a factor of 1.8; one on a highway gets 1.05. Where there is no
--     road distance to compare, 1.4 is the fallback, and it is clamped either
--     way so one bad Ola response cannot produce a three-hour estimate.
--
-- The monotonic rule from the header is enforced at the bottom, in one place.
create or replace function public.recompute_order_eta(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o          record;
  v_state    text;
  v_lat      double precision;
  v_lng      double precision;
  v_straight numeric;
  v_factor   numeric;
  v_left_km  numeric;
  v_ride     integer;
  v_new      timestamptz;
  v_current  timestamptz;
  v_reason   text;
begin
  select ord.id, ord.status, ord.created_at, ord.eta_minutes, ord.ready_by,
         ord.route_km, ord.eta_at, ord.delivery_lat, ord.delivery_lng,
         r.latitude as r_lat, r.longitude as r_lng
    into o
    from public.orders ord
    join public.restaurants r on r.id = ord.restaurant_id
   where ord.id = p_order_id;

  if not found or o.status in ('delivered', 'cancelled', 'rejected') then
    return;
  end if;

  if o.delivery_lat is null or o.delivery_lng is null then
    return;
  end if;

  v_current := coalesce(o.eta_at, o.created_at + make_interval(mins => o.eta_minutes));

  select d.state into v_state
    from public.deliveries d
   where d.order_id = p_order_id and d.state <> 'cancelled'
   order by d.claimed_at desc
   limit 1;

  -- The detour factor, from this order's own two measurements.
  v_straight := public.delivery_distance_km(
    o.r_lat, o.r_lng, o.delivery_lat, o.delivery_lng
  );
  v_factor := case
    when o.route_km is null or v_straight is null or v_straight <= 0.2 then 1.4
    else least(2.5, greatest(1.0, o.route_km / v_straight))
  end;

  if coalesce(v_state, '') in ('picked_up', 'arrived_at_customer') then
    select l.lat, l.lng into v_lat, v_lng
      from public.rider_locations l
      join public.deliveries d on d.partner_email = l.partner_email
     where d.order_id = p_order_id and d.state = v_state
     limit 1;

    if v_lat is null then
      return;                       -- Carrying, but nowhere. Leave the promise.
    end if;

    v_left_km := public.delivery_distance_km(
      v_lat, v_lng, o.delivery_lat, o.delivery_lng
    ) * v_factor;

    v_new := now()
      + make_interval(
          mins => ceil(
            (v_left_km / public.rider_city_speed_kmh()) * 60
            + public.handover_minutes()
          )::integer
        );
    v_reason := 'Slower traffic on the route';
  else
    -- Still with the kitchen, or with a rider on the way to it: when the food
    -- is ready, plus the whole ride, plus the handover.
    --
    -- `ready_by` is the kitchen's own commitment, stamped when it accepted with
    -- a prep time (0015). It is null on any order that was accepted without
    -- one, and the fallback has to be chosen carefully: `created_at +
    -- eta_minutes` is the *delivery* promise, not the kitchen's, and adding a
    -- ride on top of it would count the ride twice — a 32-minute promise on a
    -- 12 km route came out as 68 minutes on the first run of this. So the ride
    -- is subtracted back out of the promise instead, which makes the whole
    -- expression collapse to the original promise exactly. No new information,
    -- no new number.
    v_ride := ceil(
      (coalesce(o.route_km, v_straight, 0) / public.rider_city_speed_kmh()) * 60
      + public.handover_minutes()
    )::integer;

    v_new := greatest(
        now(),
        coalesce(
          o.ready_by,
          o.created_at + make_interval(mins => o.eta_minutes - v_ride)
        )
      )
      + make_interval(mins => v_ride);

    -- The two things that can honestly make an order late before it is on a
    -- bike, in the order they become true.
    v_reason := case
      when coalesce(v_state, '') = 'arrived_at_restaurant'
        then 'Your delivery partner is waiting at the restaurant'
      when v_state is null
        then 'Still finding a delivery partner'
      else null
    end;
  end if;

  if v_new is null then
    return;
  end if;

  -- ---------------------------------------------------------------------
  -- The rule. Earlier is free. Later needs a sentence, and a sentence we
  -- actually have — an estimate that would slip for a cause this function
  -- cannot name is not written, and the customer keeps the time they were
  -- given. Under two minutes either way is not written at all, so an ETA does
  -- not twitch while a rider sits at a light.
  -- ---------------------------------------------------------------------
  if v_new < v_current - interval '2 minutes' then
    update public.orders
       set eta_at = v_new, eta_reason = null
     where id = p_order_id;
  elsif v_new > v_current + interval '2 minutes' and v_reason is not null then
    update public.orders
       set eta_at = v_new, eta_reason = v_reason
     where id = p_order_id;
  else
    return;
  end if;

  -- The card redraws. `post_order_live` drops a payload identical to the last
  -- one, so an ETA that did not actually change costs nothing (0052).
  begin
    perform public.post_order_live(
      p_order_id, (select user_id from public.orders where id = p_order_id)
    );
  exception when others then
    null;
  end;
end;
$$;

revoke all on function public.recompute_order_eta(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- G. The moments worth redoing it, besides a position.
-- ---------------------------------------------------------------------------
-- A rider reaching a counter and a kitchen packing a bag both change when the
-- food will arrive, and neither produces a GPS fix. Riding on the existing
-- status/state triggers rather than adding new ones — and wrapped, per 0021.
create or replace function public.reestimate_on_order_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     and new.status in ('accepted', 'preparing', 'ready_for_pickup') then
    begin
      perform public.recompute_order_eta(new.id);
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_reestimate on public.orders;
create trigger orders_reestimate
  after update of status on public.orders
  for each row execute function public.reestimate_on_order_change();

create or replace function public.reestimate_on_delivery_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.state is distinct from old.state then
    begin
      perform public.recompute_order_eta(new.order_id);
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_reestimate on public.deliveries;
create trigger deliveries_reestimate
  after update of state on public.deliveries
  for each row execute function public.reestimate_on_delivery_change();

-- ---------------------------------------------------------------------------
-- H. The live card, told the new time.
-- ---------------------------------------------------------------------------
-- Identical to 0052 but for `eta_at` and the reason. The fallback is the old
-- arithmetic, so an order placed before this migration — or one nothing has
-- recomputed yet — reads exactly as it did yesterday.
create or replace function public.order_live_payload(p_order_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with o as (
    select id, status, restaurant_name, created_at, eta_minutes,
           eta_at, eta_reason
      from public.orders
     where id = p_order_id
  ),
  d as (
    select state
      from public.deliveries
     where order_id = p_order_id
       and state <> 'cancelled'
     order by claimed_at desc
     limit 1
  ),
  stage as (
    select case
      when o.status in ('cancelled', 'rejected')            then 'ended'
      when o.status = 'delivered'
        or coalesce(d.state, '') = 'delivered'              then 'delivered'
      when coalesce(d.state, '') = 'arrived_at_customer'    then 'at_door'
      when coalesce(d.state, '') = 'picked_up'
        or o.status = 'out_for_delivery'                    then 'on_the_way'
      when coalesce(d.state, '') = 'arrived_at_restaurant'  then 'rider_at_restaurant'
      when o.status = 'ready_for_pickup'                    then 'packed'
      when o.status = 'preparing'                           then 'preparing'
      when o.status = 'accepted'                            then 'accepted'
      else 'placed'
    end as name,
    greatest(
      case o.status
        when 'placed'           then 5
        when 'accepted'         then 15
        when 'preparing'        then 35
        when 'ready_for_pickup' then 55
        when 'out_for_delivery' then 75
        when 'delivered'        then 100
        else 0
      end,
      case coalesce(d.state, '')
        when 'claimed'               then 20
        when 'arrived_at_restaurant' then 65
        when 'picked_up'             then 75
        when 'arrived_at_customer'   then 95
        when 'delivered'             then 100
        else 0
      end
    ) as progress
    from o left join d on true
  )
  select jsonb_build_object(
    'order_id',   o.id,
    'stage',      s.name,
    'progress',   s.progress,
    'restaurant', o.restaurant_name,
    'eta_at',     to_char(
                    coalesce(
                      o.eta_at,
                      o.created_at + make_interval(mins => o.eta_minutes)
                    ) at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                  ),
    -- Null on every order running to time, which is what the card checks: the
    -- line only exists when there is something to admit.
    'eta_reason', o.eta_reason,
    'title', case s.name
      when 'accepted'            then 'Order confirmed'
      when 'preparing'           then 'Preparing your order'
      when 'packed'              then 'Order packed'
      when 'rider_at_restaurant' then 'Delivery partner is at the restaurant'
      when 'on_the_way'          then 'On the way'
      when 'at_door'             then 'Your delivery partner is outside'
      when 'delivered'           then 'Delivered'
      when 'ended'               then 'Order ended'
      else 'Order placed'
    end,
    'body', case s.name
      when 'accepted'            then o.restaurant_name || ' is getting started'
      when 'preparing'           then o.restaurant_name || ' is cooking your food'
      when 'packed'              then 'Waiting for a delivery partner to collect it'
      when 'rider_at_restaurant' then 'Collecting your order from ' || o.restaurant_name
      when 'on_the_way'          then 'Your order from ' || o.restaurant_name || ' is on its way'
      when 'at_door'             then 'Have your delivery code ready'
      when 'delivered'           then 'Your order from ' || o.restaurant_name || ' has arrived'
      when 'ended'               then 'This order is no longer running'
      else 'Waiting for ' || o.restaurant_name || ' to confirm'
    end
  )
  from o cross join stage s;
$$;

revoke all on function public.order_live_payload(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- I. What the tracking screen asks for.
-- ---------------------------------------------------------------------------
-- The map's data, in one call: both fixed ends, the road between them, and the
-- live time. Deliberately **not** the rider's position — that arrives over
-- Realtime from `rider_locations`, which the policy in section A already guards,
-- and duplicating it here would be a second gate to keep in step with the first.
--
-- `security definer` with a `user_id` check written out longhand, because the
-- restaurant's coordinates are not otherwise a customer's to read in bulk: the
-- answer is scoped to one order that belongs to the caller.
create or replace function public.order_route(p_order_id text)
returns table (
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  deliver_lat     double precision,
  deliver_lng     double precision,
  route_polyline  text,
  route_km        numeric,
  eta_at          timestamptz,
  eta_reason      text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
    select r.name, r.latitude, r.longitude,
           o.delivery_to, o.delivery_lat, o.delivery_lng,
           o.route_polyline, o.route_km,
           coalesce(o.eta_at, o.created_at + make_interval(mins => o.eta_minutes)),
           o.eta_reason
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
     where o.id = p_order_id
       and o.user_id = auth.uid()::text;
end;
$$;

grant execute on function public.order_route(text) to authenticated;

-- ---------------------------------------------------------------------------
-- J. Backfill, so the map is not blank on everything placed before today.
-- ---------------------------------------------------------------------------
-- Every live order gets re-queued for a route. `route_km` is already correct on
-- most of them (0046 has been running for days) but `route_polyline` is null on
-- all of them, and re-running the lookup is the only way to get it. The queue is
-- rate-limited to 25 a tick and orders that finish are deleted, so this drains
-- rather than floods.
insert into public.order_route_jobs (order_id)
select id from public.orders
 where status in ('placed', 'accepted', 'preparing', 'ready_for_pickup',
                  'out_for_delivery')
   and delivery_lat is not null
   and delivery_lng is not null
   and route_polyline is null
on conflict (order_id) do nothing;
