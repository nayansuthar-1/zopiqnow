-- Phase 8 (delivery), migration 46: an order knows how far the ride is.
--
-- Until now the only distance the platform could measure was haversine — the
-- straight line between the kitchen and the door (0043). It was chosen honestly
-- and with its flaw stated in that file: a straight line is never the distance
-- anybody rides, so it systematically underpays. A river, a one-way system or a
-- flyover all make the real ride longer, never shorter.
--
-- This migration adds the real number. It calls Ola Maps' Directions API, which
-- returns the *road* distance, and stores it on the order. Measured against a
-- live pair of coordinates while building this, haversine read ~3.5 km where the
-- road was 12.14 km — a rider paid on the straight line would have been paid for
-- a third of the ride.
--
-- **Three decisions worth stating once, here, because they shaped everything:**
--
--   1. **Distance is a property of the ORDER, not the claim.** It is computed
--      once, into `orders.route_km`, when the order is placed — not inside
--      `claim_delivery`. `claim_delivery` is a race decided by a partial unique
--      index; putting a multi-second HTTP call inside it would be a network
--      round-trip inside a lock contest, which is how a claim ends up slow,
--      double-fired, or timing out against the very index meant to settle it.
--
--   2. **The haversine stays, as the fallback.** `claim_delivery` reads
--      `coalesce(route_km, haversine)`. If Ola is slow, down, or the order was
--      placed a moment ago and the road distance has not landed yet, pay is
--      computed from the straight line and the job is never blocked. Road
--      distance makes pay *better* when it is there; its absence never stops a
--      rider being paid.
--
--   3. **It is all in the database.** `pg_net` makes the HTTP call, `pg_cron`
--      drives it, `supabase_vault` holds the key. No Edge Function, and so no
--      deploy — deliberate, because the only other HTTP path here is a function
--      that has been undeployed for weeks, and a pay-critical feature must not
--      wait on a deploy that keeps not happening.
--
-- **On authentication — a note for whoever touches the Ola call next.** The API
-- key is referer-restricted: Ola rejects a server-side call as "Domain not
-- allowed" unless the request carries an `Origin` header matching a domain
-- whitelisted on the credential (`zopiqnow.app` is whitelisted; we send
-- `https://zopiqnow.app`). The documented server-side path is OAuth2, but its
-- token endpoint accepts only a form-encoded body and `pg_net` can send only a
-- JSON body — so OAuth cannot be driven from Postgres at all. The key lives in
-- Vault under `ola_maps_api_key`; it is never written into this file.

-- ---------------------------------------------------------------------------
-- Where the answer is kept.
-- ---------------------------------------------------------------------------
-- Nullable, because null is a real and common state here: the order was just
-- placed and the road distance has not come back yet, or it never will because
-- Ola was unreachable. Every reader treats null as "we do not have the road
-- distance", and the haversine answers instead. A `not null` would be a lie the
-- first second of every order's life.
alter table public.orders
  add column if not exists route_km numeric(6,2);

-- ---------------------------------------------------------------------------
-- The work queue.
-- ---------------------------------------------------------------------------
-- One row per order awaiting its road distance. A row exists from the moment the
-- order is placed until `route_km` is filled (or the attempt is abandoned), at
-- which point it is deleted — so the table is a to-do list, not a log, and stays
-- small.
--
-- `request_id` is the `pg_net` request once the call has been fired, and null
-- while the job is still waiting its turn. `attempts` counts failures so a job
-- that keeps erroring is eventually given up on rather than retried forever;
-- when it is, the haversine covers that order at claim time and nothing breaks.
create table if not exists public.order_route_jobs (
  order_id   text primary key references public.orders(id) on delete cascade,
  request_id bigint,
  attempts   smallint not null default 0,
  updated_at timestamptz not null default now()
);

-- No policies, and none are coming. Nothing outside these `security definer`
-- functions has any business reading a queue of pending HTTP calls.
alter table public.order_route_jobs enable row level security;

-- ---------------------------------------------------------------------------
-- Enqueue, at the moment the order is placed.
-- ---------------------------------------------------------------------------
-- The same shape as 0021's `orders_notify_new`: an `after insert` trigger whose
-- entire body is wrapped so that it can *never* abort `place_order`. Enqueuing a
-- distance lookup is the least important thing happening when an order is
-- placed, and it must behave like it — a failure here is a missing `route_km`
-- (haversine covers it), never a failed checkout.
--
-- It only enqueues; it fires nothing. The HTTP call needs the key from Vault and
-- a retry story, and both belong in the processor below, not in the hot path of
-- checkout. An order with no delivery coordinates is skipped — there is nothing
-- to route to.
create or replace function public.enqueue_order_route()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.delivery_lat is not null and new.delivery_lng is not null then
    begin
      insert into public.order_route_jobs (order_id)
      values (new.id)
      on conflict (order_id) do nothing;
    exception when others then
      -- A queue insert must never be the reason a customer's order fails.
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_enqueue_route on public.orders;
create trigger orders_enqueue_route
  after insert on public.orders
  for each row execute function public.enqueue_order_route();

-- ---------------------------------------------------------------------------
-- The processor: collect what has come back, then fire what is waiting.
-- ---------------------------------------------------------------------------
-- `pg_net` is asynchronous: a call is fired and its response lands later in
-- `net._http_response`, keyed by the request id. So one function cannot fire a
-- call and read its result — it fires on one tick and collects on a later one.
-- This runs every minute (scheduled at the end of the file) and does both, in
-- that order: collect first so a finished job leaves the queue immediately, then
-- fire the backlog.
--
-- Collect handles three outcomes for a fired job:
--   * a 200 with a parseable distance  -> write `route_km`, delete the job;
--   * a 200 that will not parse, or a non-200 -> count an attempt, requeue;
--   * no response row yet -> still in flight, leave it — unless it has been
--     waiting too long, which means the response was lost or pruned before we
--     read it, and the job is requeued so it is not stranded forever.
--
-- After five failed attempts a job is dropped. That is not giving up on the
-- order — it is giving up on the *road* distance for it, and the haversine is
-- exactly the thing that makes that safe.
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
  v_req    bigint;
  j        record;
begin
  -- 1. Collect responses for jobs already fired.
  for j in
    select order_id, request_id, updated_at
      from public.order_route_jobs
     where request_id is not null
  loop
    select status_code into v_status
      from net._http_response
     where id = j.request_id;

    if not found then
      -- Still in flight, or the response was pruned before we got to it. If it
      -- has been sitting far longer than any call should take, assume the latter
      -- and put it back in line rather than waiting on a row that will never come.
      if j.updated_at < now() - interval '10 minutes' then
        update public.order_route_jobs
           set request_id = null, attempts = attempts + 1, updated_at = now()
         where order_id = j.order_id;
      end if;
      continue;
    end if;

    if v_status = 200 then
      select (content::jsonb #>> '{routes,0,legs,0,distance}')::numeric
        into v_meters
        from net._http_response
       where id = j.request_id;

      if v_meters is not null then
        update public.orders
           set route_km = round(v_meters / 1000.0, 2)
         where id = j.order_id;
        delete from public.order_route_jobs where order_id = j.order_id;
        continue;
      end if;
    end if;

    -- 200 with a body we could not read, or any non-200: this attempt failed.
    update public.order_route_jobs
       set request_id = null, attempts = attempts + 1, updated_at = now()
     where order_id = j.order_id;
  end loop;

  -- Give up on jobs that have failed too many times; haversine covers them.
  delete from public.order_route_jobs where attempts >= 5;

  -- 2. Fire the jobs still waiting. No key, no calls — the queue simply waits.
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
      -- The key is referer-restricted; this header is what makes a server-side
      -- call pass. See the note at the top of this file.
      headers := jsonb_build_object('Origin', 'https://zopiqnow.app'),
      timeout_milliseconds := 8000
    );

    update public.order_route_jobs
       set request_id = v_req, updated_at = now()
     where order_id = j.order_id;
  end loop;
end;
$$;

-- This function makes outbound HTTP calls spending a paid quota and is driven by
-- cron alone; nothing signed-in should be able to call it. `revoke from public`
-- is not enough on Supabase — default privileges grant execute directly to the
-- named roles — so all three are revoked, the same lesson 0045 learned the hard
-- way about the payout batches.
revoke all on function public.process_order_routes()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Claiming, now measured by the road.
-- ---------------------------------------------------------------------------
-- Identical to 0043 in every respect but one: the distance the pay is computed
-- from is now `coalesce(route_km, haversine)`. When the road distance has landed
-- it is used; until then — or if it never comes — the straight line answers, so
-- the claim never waits on a third party and pay is never blocked. The snapshot
-- onto the delivery row is unchanged: whatever distance applied is frozen there,
-- auditable, exactly as before.
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
    order_id, partner_email, pickup_otp,
    distance_km, pay_base, pay_per_km, rider_pay
  )
  values (
    p_order_id,
    v_rider,
    lpad((floor(random() * 10000))::integer::text, 4, '0'),
    v_distance,
    v_base,
    v_per_km,
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
-- Run it every minute.
-- ---------------------------------------------------------------------------
-- A minute is far tighter than it needs to be — an order is claimed by a rider
-- who then has to travel to the kitchen, so there are many minutes between
-- placement and any claim reading `route_km`. But a minute is cheap (the queue
-- is empty most ticks) and it means the board can show an honest distance almost
-- as soon as an order appears.
select cron.unschedule('process-order-routes')
 where exists (select 1 from cron.job where jobname = 'process-order-routes');

select cron.schedule(
  'process-order-routes',
  '* * * * *',
  $$ select public.process_order_routes(); $$
);
