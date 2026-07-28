-- ---------------------------------------------------------------------------
-- 0056 — the job finds the rider. (B3, dispatch)
-- ---------------------------------------------------------------------------
-- Until now a delivery was something a rider had to go and *look* for. An order
-- reached `preparing`, 0047 rang every active partner's phone with the same
-- "New delivery" push, and whoever opened the app fastest got it. That is a
-- board, not a dispatcher: it is a race between riders, it rewards the one
-- staring at their phone rather than the one nearest the kitchen, and it wakes
-- forty people to give one of them a job.
--
-- This migration inverts it. The platform picks a rider and *offers* them the
-- job — one rider, one push, a countdown, Accept or Decline. Decline, or let it
-- run out, and it moves to the next one. Nobody else is disturbed.
--
-- **Four decisions worth stating once, here, because they shape the rest.**
--
--   1. **The board survives, as the fallback.** The obvious reading of "auto-
--      assign instead of self-claim" is to delete `available_deliveries`. That
--      would strand every order the fleet declines — and on a thin night, when
--      four riders are all carrying, *every* order is declined. So an order that
--      exhausts its offers goes back on the open board and the broadcast push
--      fires then, at the moment it is actually true that anyone may take it.
--      The board is what is left over, not the first thing anybody sees.
--
--   2. **"Nearest free rider" is ranked, not filtered.** 8b-4 left concurrent
--      claims uncapped on purpose — "carrying three orders from one street is
--      how delivery actually works". Excluding every rider holding a job would
--      have quietly reversed that decision. So the ordering is *(live jobs,
--      then distance)*: an idle rider always outranks a busy one, and a rider
--      already at that kitchen is the nearest busy one, which is the batching
--      case falling out for free. Three live jobs is the ceiling.
--
--   3. **A rider is offered an order at most once.** `(order_id,
--      partner_email)` is unique, so a decline is permanent for that order.
--      Cycling back round to someone who already said no is how a dispatcher
--      turns into a nuisance, and it is also how an order loops forever instead
--      of reaching the board.
--
--   4. **Accept goes through `claim_delivery`, untouched.** The race that
--      migration solved — two riders, one order, a partial unique index —
--      has not gone away just because there is normally only one offer live.
--      An offer accepted a half-second after an admin or a board claim landed
--      must lose, and it loses in exactly the same place it always did.
--
-- Locations are *not* here. Ranking by distance needs a rider position, and this
-- migration reads `rider_locations` — which 0057 creates — through a lateral
-- join that tolerates its absence. Applied alone, this dispatches by "fewest
-- jobs, then longest-waiting order", which is correct, just not yet nearest.

-- ---------------------------------------------------------------------------
-- A. Where a position will live.
-- ---------------------------------------------------------------------------
-- Created here rather than in 0057 for one reason: the dispatcher below reads
-- it, and a function that references a table that does not exist yet fails to
-- *create*, not merely to run. 0057 puts the writer, the policy and the purge
-- around it. This is the column list and nothing else.
--
-- One row per rider — the latest fix, not a track. A history table would be a
-- map of everywhere a worker has been, kept forever, and the only question
-- anything here asks is "where are they now".
create table if not exists public.rider_locations (
  partner_email text primary key
    references public.delivery_partners(email) on delete cascade,
  lat        double precision not null,
  lng        double precision not null,
  -- Degrees clockwise from north, and null when the phone would not say — a
  -- stationary device reports no bearing, and a dot pointed at 0° would be a
  -- confident claim that the rider is heading due north.
  heading    numeric(5,1),
  speed_kmh  numeric(5,1),
  updated_at timestamptz not null default now()
);

alter table public.rider_locations enable row level security;

-- ---------------------------------------------------------------------------
-- B. The offer.
-- ---------------------------------------------------------------------------
-- A row per (order, rider) pair the dispatcher has proposed. It is a log as much
-- as a queue: the declined and expired rows are what stop the dispatcher
-- re-offering, and what tell it when the fleet has been exhausted.
create table if not exists public.delivery_offers (
  id            bigint generated always as identity primary key,
  order_id      text not null references public.orders(id) on delete cascade,
  partner_email text not null references public.delivery_partners(email),
  state         text not null default 'offered'
    check (state in ('offered', 'accepted', 'declined', 'expired')),
  -- Rider → kitchen at the moment of the offer, in kilometres. Null when the
  -- rider had no position on file. Frozen deliberately: it is the number the
  -- dispatcher decided on, and a value recomputed later would make an audit of
  -- "why did this rider get this job" impossible.
  distance_km   numeric(6,2),
  offered_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  responded_at  timestamptz
);

-- One live offer per order. The whole point of a dispatcher is that exactly one
-- rider is being asked at a time; two live offers is a race with a countdown on
-- it, which is worse than the board it replaced.
create unique index if not exists delivery_offers_one_live_per_order
  on public.delivery_offers (order_id) where state = 'offered';

-- Decision 3: a rider hears about an order once.
create unique index if not exists delivery_offers_once_per_rider
  on public.delivery_offers (order_id, partner_email);

-- The sweeper's read: everything still ticking, oldest deadline first.
create index if not exists delivery_offers_live_idx
  on public.delivery_offers (expires_at) where state = 'offered';

alter table public.delivery_offers enable row level security;

-- A rider may read the offers addressed to them, and nothing else. Not the
-- declines of other riders, not who else was asked, not the order rows behind
-- any of it — 0025's rule that a rider has no policy on `orders` is untouched.
drop policy if exists "riders read their own offers" on public.delivery_offers;
create policy "riders read their own offers"
  on public.delivery_offers for select to authenticated
  using (partner_email = lower((auth.jwt() ->> 'email')));

grant select on public.delivery_offers to authenticated;

-- Realtime, so an offer reaches a phone that is already open without waiting for
-- a push to round-trip through FCM. The push is what wakes a dark screen; this
-- is what makes the sheet appear instantly on one the rider is holding. The
-- policy above rides the socket, so a rider is delivered their own offers and
-- nobody else's.
do $$
begin
  alter publication supabase_realtime add table public.delivery_offers;
exception
  when duplicate_object then null;
  when undefined_object then null;
end;
$$;

-- ---------------------------------------------------------------------------
-- C. How long a rider gets.
-- ---------------------------------------------------------------------------
-- Forty-five seconds. Long enough to pull over, read two addresses and a fee,
-- and decide; short enough that a phone in a pocket costs the customer under a
-- minute. It is a constant in one function rather than a settings row because
-- nothing in ops can currently change it and a table nobody writes to is a
-- table that lies about being configurable.
create or replace function public.delivery_offer_window()
returns interval
language sql
immutable
as $$ select interval '45 seconds' $$;

-- ---------------------------------------------------------------------------
-- D. Offering one order to one rider.
-- ---------------------------------------------------------------------------
-- The core of the dispatcher, and the only place a rider is chosen.
--
-- Returns the email offered to, or null when there was nobody left — which the
-- caller reads as "this order has exhausted the fleet" and answers by putting it
-- on the open board. Null is a normal outcome on a quiet night, not a failure.
--
-- Who is eligible:
--   * on the roster (`is_active`) and on shift (`is_online`);
--   * carrying fewer than three live jobs;
--   * not already asked about this order;
--   * not holding a live offer for some *other* order — a rider deciding about
--     one job must not have a second countdown running behind it.
--
-- Ordered by live jobs, then distance from the kitchen, then — for a fleet with
-- no positions at all — the rider idle longest, so a silent app does not mean
-- one rider gets every job.
create or replace function public.offer_delivery(p_order_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_dist     numeric(6,2);
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_name     text;
  v_status   text;
  v_pay      integer;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_route    numeric(6,2);
begin
  -- The order still has to be one that wants a rider. Checked here as well as
  -- in the sweeper because `decline_offer` calls straight into this function,
  -- and an order cancelled between the offer and the decline must not be
  -- handed to somebody else.
  select o.status, r.name, r.latitude, r.longitude,
         coalesce(
           o.route_km,
           public.delivery_distance_km(r.latitude, r.longitude,
                                       o.delivery_lat, o.delivery_lng)
         )
    into v_status, v_name, v_r_lat, v_r_lng, v_route
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found or v_status not in ('preparing', 'ready_for_pickup') then
    return null;
  end if;

  if exists (
    select 1 from public.deliveries d
     where d.order_id = p_order_id and d.state <> 'cancelled'
  ) then
    return null;
  end if;

  -- What the job pays, at today's rate and this order's distance. Shown in the
  -- offer, and deliberately computed the same way `claim_delivery` will compute
  -- it a moment later — a fee quoted in the offer that differs from the fee on
  -- the accepted job is the single fastest way to lose a fleet's trust.
  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;
  v_pay := v_base + round(coalesce(v_route, 0) * v_per_km)::integer;

  select cand.email, cand.km
    into v_rider, v_dist
    from (
      select p.email,
             public.delivery_distance_km(l.lat, l.lng, v_r_lat, v_r_lng) as km,
             (select count(*) from public.deliveries d
               where d.partner_email = p.email
                 and d.state in ('claimed', 'arrived_at_restaurant',
                                 'picked_up', 'arrived_at_customer')
             ) as live_jobs
        from public.delivery_partners p
        left join public.rider_locations l on l.partner_email = p.email
       where p.is_active
         and p.is_online
    ) cand
   where cand.live_jobs < 3
     and not exists (
       select 1 from public.delivery_offers o
        where o.order_id = p_order_id and o.partner_email = cand.email
     )
     and not exists (
       select 1 from public.delivery_offers o
        where o.partner_email = cand.email
          and o.state = 'offered'
          and o.expires_at > now()
     )
   -- Idle riders first, then nearest. `nulls last` is what keeps a rider whose
   -- app has never reported a position from being treated as zero kilometres
   -- away and winning every job in the city.
   order by cand.live_jobs, cand.km nulls last, cand.email
   limit 1;

  if v_rider is null then
    return null;
  end if;

  insert into public.delivery_offers
    (order_id, partner_email, distance_km, expires_at)
  values
    (p_order_id, v_rider, v_dist, now() + public.delivery_offer_window())
  -- Two sweeper ticks overlapping, or a decline racing the sweep. The index is
  -- what decides it; losing simply means somebody else's offer is already live.
  on conflict do nothing;

  if not found then
    return null;
  end if;

  -- The push. `data` carries the numbers so the sheet can draw itself from the
  -- notification alone — a rider woken by this is on a lock screen, and a sheet
  -- that has to round-trip before it can show a countdown has already spent the
  -- seconds it is counting.
  begin
    insert into public.notifications
      (audience, partner_email, kind, title, body, order_id, data)
    values
      ('rider', v_rider, 'job_offer',
       'New delivery — ₹' || v_pay,
       'Pick up from ' || v_name ||
         case when v_dist is null then ''
              else ' · ' || v_dist || ' km away' end,
       p_order_id,
       jsonb_build_object(
         'order_id',    p_order_id,
         'restaurant',  v_name,
         'pay',         v_pay,
         'route_km',    v_route,
         'to_pickup_km', v_dist,
         'expires_at',  to_char(
                          (now() + public.delivery_offer_window())
                            at time zone 'UTC',
                          'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                        )
       ));
  exception when others then
    -- 0021's rule, kept: the offer is the event, the push is a courtesy on top
    -- of it. A rider who missed the buzz still finds the offer in the app.
    null;
  end;

  return v_rider;
end;
$$;

-- Cron and the two response functions call this in their own definer context.
-- Nothing signed in has any business dispatching a job to somebody.
revoke all on function public.offer_delivery(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- E. Putting an order back on the open board.
-- ---------------------------------------------------------------------------
-- Called once, at the moment the fleet is exhausted. This is where 0047's
-- broadcast moved to: it is now true that anybody may take this job, so telling
-- everybody is the right thing rather than the lazy one.
--
-- Idempotent by way of the notification itself — the sweeper would otherwise
-- re-announce the same leftover order every twenty seconds for as long as it sat
-- there, which is a phone buzzing all evening about one order.
create or replace function public.announce_open_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if exists (
    select 1 from public.notifications
     where kind = 'job_available' and order_id = p_order_id
  ) then
    return;
  end if;

  select restaurant_name into v_name from public.orders where id = p_order_id;
  if v_name is null then
    return;
  end if;

  begin
    insert into public.notifications
      (audience, partner_email, kind, title, body, order_id)
    select 'rider', p.email, 'job_available',
           'Delivery on the board',
           'A delivery from ' || v_name || ' is waiting to be claimed',
           p_order_id
      from public.delivery_partners p
     where p.is_active and p.is_online;
  exception when others then
    null;
  end;
end;
$$;

revoke all on function public.announce_open_delivery(text)
  from public, anon, authenticated;

-- 0047's broadcast-on-`preparing` is what this replaces. Dropping the trigger
-- rather than the function: `notify_riders_job_available` stays in the schema,
-- unreferenced, so a rollback of this migration is one `create trigger`.
drop trigger if exists orders_notify_riders on public.orders;

-- ---------------------------------------------------------------------------
-- F. The sweeper.
-- ---------------------------------------------------------------------------
-- Runs every twenty seconds (scheduled at the end of the file) and does three
-- things in order: retire what has run out, offer what is waiting, announce what
-- nobody wanted.
--
-- Twenty seconds against a forty-five-second window means a rider who ignores an
-- offer costs the order at most about a minute before the next partner is asked.
-- A decline does not wait for this at all — `decline_offer` re-offers inline.
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
  -- 1. Offers nobody answered. The rider is not punished for it beyond never
  --    being asked about this order again, which the unique index handles.
  update public.delivery_offers
     set state = 'expired', responded_at = now()
   where state = 'offered'
     and expires_at <= now();

  -- 2. Orders that want a rider and have nobody deciding about them.
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
     -- Packed and waiting first, then the longest-waiting. The same ordering
     -- `available_deliveries` has used since 0025, for the same reason: the bag
     -- already on the counter is the one somebody should be collecting.
     order by (ord.status = 'ready_for_pickup') desc, ord.created_at
     limit 50
  loop
    v_offered := public.offer_delivery(o.id);

    -- 3. Nobody left to ask. Onto the open board, once.
    if v_offered is null then
      perform public.announce_open_delivery(o.id);
    end if;
  end loop;
end;
$$;

revoke all on function public.dispatch_deliveries()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- G. What the rider is being asked.
-- ---------------------------------------------------------------------------
-- Everything the offer sheet draws, for the offers live right now. Normally one
-- row or none.
--
-- The delivery address is here and the customer's phone number is not — the
-- same split 0025 drew between `available_deliveries` and `my_deliveries`, for
-- the same reason: a rider deciding whether to take a job needs to know where it
-- is going, and does not yet need to be able to ring anyone.
create or replace function public.my_offers()
returns table (
  order_id        text,
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  total           integer,
  payment_method  text,
  order_status    text,
  route_km        numeric,
  to_pickup_km    numeric,
  rider_pay       integer,
  offered_at      timestamptz,
  expires_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rider  text;
  v_base   integer;
  v_per_km numeric(6,2);
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status,
           coalesce(
             o.route_km,
             public.delivery_distance_km(r.latitude, r.longitude,
                                         o.delivery_lat, o.delivery_lng)
           ),
           off.distance_km,
           v_base + round(
             coalesce(
               o.route_km,
               public.delivery_distance_km(r.latitude, r.longitude,
                                           o.delivery_lat, o.delivery_lng),
               0
             ) * v_per_km
           )::integer,
           off.offered_at, off.expires_at
      from public.delivery_offers off
      join public.orders o      on o.id = off.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where off.partner_email = v_rider
       and off.state = 'offered'
       and off.expires_at > now()
     order by off.expires_at;
end;
$$;

grant execute on function public.my_offers() to authenticated;

-- ---------------------------------------------------------------------------
-- H. Yes.
-- ---------------------------------------------------------------------------
-- The offer is marked taken and `claim_delivery` does the rest, unchanged: the
-- pay snapshot, the partial unique index, the refusal sentence when somebody
-- else got there first. If it raises, this whole call rolls back — the offer is
-- still 'offered' and the rider is told plainly, which is the correct outcome
-- for a job that was taken out from under them.
create or replace function public.accept_offer(p_order_id text)
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

  update public.delivery_offers
     set state = 'accepted', responded_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'offered'
     and expires_at > now();

  if not found then
    raise exception 'That offer has expired.' using errcode = 'P0001';
  end if;

  perform public.claim_delivery(p_order_id);
end;
$$;

grant execute on function public.accept_offer(text) to authenticated;

-- ---------------------------------------------------------------------------
-- I. No.
-- ---------------------------------------------------------------------------
-- Re-offers inline rather than waiting for the sweep. A decline is a rider
-- actively telling us they cannot take it, and making the customer wait out the
-- remaining forty seconds of a countdown nobody is looking at any more would be
-- an outage we chose.
--
-- Deliberately never raises for an offer that has already gone. A rider tapping
-- Decline on a sheet that expired while it was open has done nothing wrong and
-- should not be shown an error for it.
create or replace function public.decline_offer(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider   text;
  v_offered text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  update public.delivery_offers
     set state = 'declined', responded_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'offered';

  if not found then
    return;
  end if;

  v_offered := public.offer_delivery(p_order_id);
  if v_offered is null then
    perform public.announce_open_delivery(p_order_id);
  end if;
end;
$$;

grant execute on function public.decline_offer(text) to authenticated;

-- ---------------------------------------------------------------------------
-- J. An order that ends takes its offer with it.
-- ---------------------------------------------------------------------------
-- 0051 made a cancelled order release its rider. It could not release an offer,
-- because there were none. Now there are, and a countdown ticking on a sheet for
-- an order that was cancelled thirty seconds ago is exactly the kind of thing
-- 0051 was written to stop.
--
-- Same signature, so this replaces rather than overloads — the lesson 0051 left
-- at the end of B2.
create or replace function public.release_order_delivery(
  p_order_id text,
  p_note     text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_holder  text;
  v_offered text;
  v_rider   text;
begin
  update public.deliveries
     set state = 'cancelled'
   where order_id = p_order_id
     and state not in ('delivered', 'cancelled')
  returning partner_email into v_holder;

  delete from public.delivery_codes where order_id = p_order_id;

  -- The new line. Anyone mid-decision is told by the same 'job_cancelled' push
  -- the holder gets, further down.
  update public.delivery_offers
     set state = 'expired', responded_at = now()
   where order_id = p_order_id
     and state = 'offered'
  returning partner_email into v_offered;

  -- Two variables and not one, because `returning ... into` writes null when it
  -- matches nothing: reusing a single variable would have let the second
  -- statement erase the rider the first one found, and 0051's notification —
  -- which has worked since B2 — would have silently stopped being sent for
  -- every cancelled order that had no offer live. An order cannot have both at
  -- once (the dispatcher will not offer an order that has a delivery, and
  -- `accept_offer` retires the offer in the same transaction as the claim), so
  -- at most one of these is ever set.
  v_rider := coalesce(v_holder, v_offered);

  if v_rider is not null then
    begin
      insert into public.notifications
        (audience, partner_email, kind, title, body, order_id)
      values
        ('rider', v_rider, 'job_cancelled', 'Delivery cancelled',
         p_note, p_order_id);
    exception when others then
      null;
    end;
  end if;
end;
$$;

revoke all on function public.release_order_delivery(text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- K. The board, now with the numbers on it.
-- ---------------------------------------------------------------------------
-- Two changes, and a narrowing.
--
-- **The numbers.** B3 asks for distance and pay *before* claiming, and 0046
-- already stores `route_km` on the order — the board simply never showed it. A
-- rider deciding whether a job is worth taking was being asked to decide without
-- either fact.
--
-- **The narrowing.** An order currently being offered to somebody is not
-- available. It would otherwise be possible to watch the board and snipe the
-- order a colleague is deciding about, which makes the countdown meaningless.
--
-- Drop-and-recreate, not replace: the return shape widens, and a `create or
-- replace` with a changed output column list is refused outright (and with a
-- changed *argument* list would silently overload — 0051's lesson).
drop function if exists public.available_deliveries();
create function public.available_deliveries()
returns table (
  order_id        text,
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  total           integer,
  payment_method  text,
  status          text,
  route_km        numeric,
  rider_pay       integer,
  ready_by        timestamptz,
  placed_at       timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base   integer;
  v_per_km numeric(6,2);
begin
  if public.delivery_partner_email() is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status,
           km.value,
           v_base + round(coalesce(km.value, 0) * v_per_km)::integer,
           o.ready_by, o.created_at
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
      cross join lateral (
        select coalesce(
                 o.route_km,
                 public.delivery_distance_km(r.latitude, r.longitude,
                                             o.delivery_lat, o.delivery_lng)
               ) as value
      ) km
     where o.status in ('preparing', 'ready_for_pickup')
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = o.id and d.state <> 'cancelled'
       )
       and not exists (
         select 1 from public.delivery_offers off
          where off.order_id = o.id
            and off.state = 'offered'
            and off.expires_at > now()
       )
     order by (o.status = 'ready_for_pickup') desc, o.created_at;
end;
$$;

grant execute on function public.available_deliveries() to authenticated;

-- ---------------------------------------------------------------------------
-- L. A kind for the new push.
-- ---------------------------------------------------------------------------
-- 'job_offer' is not 'job_available'. One is addressed to a person and has a
-- deadline on it; the other is a notice to a room. An app that told them apart
-- only by reading the body would eventually get it wrong.
alter table public.notifications
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check
    check (kind in (
      'new_order',      -- vendor: a customer placed an order (0021)
      'system',         -- anyone: a catch-all notice
      'order_update',   -- customer: their order changed status (0047)
      'order_live',     -- customer: silent tick for the live card (0052)
      'job_offer',      -- rider: this job is yours if you take it now (0056)
      'job_available',  -- rider: a delivery reached the open board
      'job_cancelled',  -- rider: a job they were holding was called off (0051)
      'payout',         -- rider: a payout was paid
      'account',        -- rider: their partner account was activated/deactivated
      'settlement'      -- vendor: a weekly settlement was paid
    ));

-- ---------------------------------------------------------------------------
-- M. Run it.
-- ---------------------------------------------------------------------------
-- Every twenty seconds. pg_cron 1.6 takes an interval string for anything under
-- a minute; the five-field form cannot express it. The tick is cheap — on an
-- idle platform both statements match nothing.
select cron.unschedule('dispatch-deliveries')
 where exists (select 1 from cron.job where jobname = 'dispatch-deliveries');

select cron.schedule(
  'dispatch-deliveries',
  '20 seconds',
  $$ select public.dispatch_deliveries(); $$
);
