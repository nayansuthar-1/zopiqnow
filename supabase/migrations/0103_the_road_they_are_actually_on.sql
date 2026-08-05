-- ---------------------------------------------------------------------------
-- 0103 — the road they are actually on.
-- ---------------------------------------------------------------------------
-- 0102 measures how far is left along the road **we quoted at checkout** — Ola's
-- answer for restaurant → door, computed once, before a rider existed. 0102 is
-- honest about the case where that road is wrong: a rider more than 250 m off it
-- gets no measurement at all, and the ETA falls back to a straight line times a
-- detour factor. The map does the same thing — `route_progress.dart` draws the
-- whole route as still ahead rather than snapping the rider onto a street they
-- are not on.
--
-- That is the right refusal and it is not an answer. A rider who takes a
-- different road — a diversion, a one-way, a closure, or simply a better route
-- than the one Ola picked an hour ago — leaves the customer watching a line the
-- delivery is not following and an estimate computed as the crow flies.
--
-- **So: ask Ola for the road they are on.** Same pipeline as 0046's, because it
-- already solves the hard parts — a queue, an async `pg_net` call, retries, a
-- key that never leaves Vault, and a cron that does the work off the hot path.
-- What this adds is a second *kind* of job on that queue.
--
-- **What it deliberately does not touch: `route_km`.** That column is the
-- distance the rider is *paid* for (`rider_pay_quote`), and it is the journey
-- they were offered when they took the job. Re-measuring it mid-delivery from
-- wherever they happen to be would silently rewrite somebody's pay while they
-- were earning it — downwards, every time they got closer. The live road goes in
-- its own three columns and the quoted one is never overwritten.
--
-- **What stops this being an open tap on the Ola account.** A re-route is only
-- enqueued when the rider is off *both* roads we know about, at most once a
-- minute per order, and only while they are actually carrying food. A rider on
-- the quoted route never triggers one; a rider on a fresh live route never
-- triggers one either, because the next measurement finds them on it.

-- ---------------------------------------------------------------------------
-- A. Somewhere to put the road they are on.
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists live_polyline  text,
  add column if not exists live_km        numeric,
  add column if not exists live_route_at  timestamptz;

comment on column public.orders.live_polyline is
  'The road from where the rider actually was to the door, when they left the '
  'quoted route. Never the basis of pay - that is route_km, which 0103 does not '
  'touch.';

-- ---------------------------------------------------------------------------
-- B. Two kinds of job on one queue.
-- ---------------------------------------------------------------------------
-- The queue was keyed by order alone, which was right when an order had exactly
-- one road to measure. It now has two, and they are asked for at different
-- moments in an order's life, so the key has to say which.
alter table public.order_route_jobs
  add column if not exists kind       text not null default 'quote',
  add column if not exists origin_lat double precision,
  add column if not exists origin_lng double precision;

alter table public.order_route_jobs
  drop constraint if exists order_route_jobs_kind_ck;
alter table public.order_route_jobs
  add constraint order_route_jobs_kind_ck check (kind in ('quote', 'live'));

do $$
begin
  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.order_route_jobs'::regclass
       and conname  = 'order_route_jobs_pkey'
       and pg_get_constraintdef(oid) = 'PRIMARY KEY (order_id)'
  ) then
    alter table public.order_route_jobs drop constraint order_route_jobs_pkey;
    alter table public.order_route_jobs add primary key (order_id, kind);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- C. The processor learns the second kind.
-- ---------------------------------------------------------------------------
-- 0057's function, with three changes and nothing else touched: it reads `kind`
-- off the job, it writes the live columns for a live job, and it takes the
-- origin from the job row rather than always from the restaurant.
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
    select order_id, kind, request_id, updated_at
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
         where order_id = j.order_id and kind = j.kind;
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
        if j.kind = 'live' then
          -- The road ahead, and the time it was true. Never route_km: that is
          -- what the rider is paid for and it belongs to the job they accepted.
          update public.orders
             set live_polyline = v_line,
                 live_km       = round(v_meters / 1000.0, 2),
                 live_route_at = now()
           where id = j.order_id;
        else
          update public.orders
             set route_km       = round(v_meters / 1000.0, 2),
                 route_polyline = v_line
           where id = j.order_id;
        end if;

        delete from public.order_route_jobs
         where order_id = j.order_id and kind = j.kind;
        continue;
      end if;
    end if;

    update public.order_route_jobs
       set request_id = null, attempts = attempts + 1, updated_at = now()
     where order_id = j.order_id and kind = j.kind;
  end loop;

  delete from public.order_route_jobs where attempts >= 5;

  select decrypted_secret into v_key
    from vault.decrypted_secrets
   where name = 'ola_maps_api_key';
  if v_key is null then
    return;
  end if;

  for j in
    select oj.order_id, oj.kind,
           -- A live job carries its own origin: where the rider was when they
           -- were found to be off the route. A quote job starts at the kitchen.
           coalesce(oj.origin_lat, r.latitude)  as o_lat,
           coalesce(oj.origin_lng, r.longitude) as o_lng,
           o.delivery_lat as d_lat, o.delivery_lng as d_lng
      from public.order_route_jobs oj
      join public.orders o      on o.id = oj.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where oj.request_id is null
       and o.delivery_lat is not null and o.delivery_lng is not null
       and (oj.kind = 'live'
            or (r.latitude is not null and r.longitude is not null))
       and coalesce(oj.origin_lat, r.latitude)  is not null
       and coalesce(oj.origin_lng, r.longitude) is not null
     order by
       -- A live job is somebody watching a wrong line on a map right now; a
       -- quote job is a number nobody reads for another twenty minutes.
       case when oj.kind = 'live' then 0 else 1 end,
       oj.updated_at
     limit 25
  loop
    v_req := net.http_post(
      url    := 'https://api.olamaps.io/routing/v1/directions',
      body   := '{}'::jsonb,
      params := jsonb_build_object(
        'origin',      j.o_lat || ',' || j.o_lng,
        'destination', j.d_lat || ',' || j.d_lng,
        'api_key',     v_key
      ),
      headers := jsonb_build_object('Origin', 'https://zopiqnow.app'),
      timeout_milliseconds := 8000
    );

    update public.order_route_jobs
       set request_id = v_req, updated_at = now()
     where order_id = j.order_id and kind = j.kind;
  end loop;
end;
$$;

revoke execute on function public.process_order_routes() from public;

-- ---------------------------------------------------------------------------
-- D. Asking for one, and how often.
-- ---------------------------------------------------------------------------
-- The throttle is the point of this function existing at all. A rider on a
-- diversion reports a position every two seconds (the rider app since today),
-- and every one of them finds the same "off the route" condition — so without a
-- ceiling this would ask Ola for the same road thirty times a minute.
--
-- One minute between re-routes for one order, held in the job row's own
-- `updated_at` and in `live_route_at`, so there is no bucket table to drift.
-- A pending job blocks a second one outright: `on conflict do nothing`.
create or replace function public.request_live_route(
  p_order_id text,
  p_lat      double precision,
  p_lng      double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_lat is null or p_lng is null then
    return;
  end if;

  -- Asked for one recently enough. `live_route_at` is when the last answer
  -- landed, and a rider who is still off-route a minute later gets another.
  if exists (
    select 1 from public.orders
     where id = p_order_id
       and live_route_at is not null
       and live_route_at > now() - interval '1 minute'
  ) then
    return;
  end if;

  insert into public.order_route_jobs (order_id, kind, origin_lat, origin_lng)
  values (p_order_id, 'live', p_lat, p_lng)
  on conflict (order_id, kind) do update
     set origin_lat = excluded.origin_lat,
         origin_lng = excluded.origin_lng,
         updated_at = now()
   -- Only when the pending one has gone stale. A job already in flight is left
   -- exactly alone; overwriting its origin mid-request would file the answer
   -- against a position it was never asked about.
   where order_route_jobs.request_id is null
     and order_route_jobs.updated_at < now() - interval '1 minute';
end;
$$;

revoke execute on function public.request_live_route(text, double precision, double precision) from public;

-- ---------------------------------------------------------------------------
-- E. The ETA prefers the road they are on.
-- ---------------------------------------------------------------------------
-- 0102's function with one block changed: three sources for "how far is left",
-- tried in the order of how much they know, and the re-route request that fires
-- when none of them can answer.
--
--   1. the live road, if one has been fetched and the rider is on it
--   2. the road we quoted at checkout, if they are on that
--   3. the straight line times the detour factor - 0057's answer, kept as the
--      floor, because an estimate is better than no estimate
--
-- A live road older than fifteen minutes is not consulted: it was measured from
-- a position the rider left long ago, and a rider who is still on it will be
-- measured against the quoted road perfectly well.
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
  v_road     numeric;
  v_ride     integer;
  v_new      timestamptz;
  v_current  timestamptz;
  v_reason   text;
begin
  select ord.id, ord.status, ord.created_at, ord.eta_minutes, ord.ready_by,
         ord.route_km, ord.route_polyline, ord.eta_at,
         ord.live_polyline, ord.live_route_at,
         ord.delivery_lat, ord.delivery_lng,
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

    -- The road they are on, then the road we quoted, then the crow.
    v_road := case
      when o.live_polyline is not null
       and o.live_route_at is not null
       and o.live_route_at > now() - interval '15 minutes'
      then public.route_remaining_km(o.live_polyline, v_lat, v_lng)
    end;

    if v_road is null then
      v_road := public.route_remaining_km(o.route_polyline, v_lat, v_lng);

      -- Off both. Go and ask what road they *are* on; it lands within the
      -- minute and the next position is measured against it. Never allowed to
      -- be the reason an ETA is not written.
      if v_road is null then
        begin
          perform public.request_live_route(p_order_id, v_lat, v_lng);
        exception when others then
          null;
        end;
      end if;
    end if;

    v_left_km := coalesce(
      v_road,
      public.delivery_distance_km(v_lat, v_lng, o.delivery_lat, o.delivery_lng)
        * v_factor
    );

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

revoke execute on function public.recompute_order_eta(text) from public;

-- ---------------------------------------------------------------------------
-- F. The map is told about it.
-- ---------------------------------------------------------------------------
-- One more pair of columns on the same RPC. The customer's map draws the quoted
-- road as the journey and the live road as what is left of it; when there is no
-- live road — the ordinary case, a rider following the route — the screen looks
-- exactly as it did.
--
-- **Dropped and recreated rather than replaced**, because `create or replace`
-- refuses to change a function's return type and `returns table` is part of it.
-- The argument list is unchanged, so this does not leave an overload behind —
-- the trap that has bitten this schema before. The grant is restated below
-- because dropping the function takes its privileges with it.
drop function if exists public.order_route(text);

create or replace function public.order_route(p_order_id text)
returns table(
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  deliver_lat     double precision,
  deliver_lng     double precision,
  route_polyline  text,
  route_km        numeric,
  eta_at          timestamptz,
  eta_reason      text,
  live_polyline   text,
  live_km         numeric
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
           o.eta_reason,
           -- Stale live roads are not sent at all: the same fifteen minutes the
           -- ETA uses, so the map and the estimate cannot describe different
           -- roads.
           case
             when o.live_route_at is not null
              and o.live_route_at > now() - interval '15 minutes'
             then o.live_polyline
           end,
           case
             when o.live_route_at is not null
              and o.live_route_at > now() - interval '15 minutes'
             then o.live_km
           end
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
     where o.id = p_order_id
       and o.user_id = auth.uid()::text;
end;
$$;

revoke execute on function public.order_route(text) from public;
grant execute on function public.order_route(text) to authenticated;

-- ---------------------------------------------------------------------------
-- The two standing release checks (0087, 0089) must still return zero rows.
-- `request_live_route` is new and is revoked from PUBLIC above; the three
-- replaced functions keep the grants they had, and `orders` gains three columns
-- rather than a table, so 0089's default has nothing to do here.
-- ---------------------------------------------------------------------------
