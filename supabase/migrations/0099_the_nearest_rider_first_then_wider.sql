-- ---------------------------------------------------------------------------
-- 0099 — the nearest rider first, then wider.
-- ---------------------------------------------------------------------------
-- `offer_delivery` has always picked the nearest idle rider. Two things were
-- wrong with "nearest", and one thing was wrong with "idle".
--
--   1. **Nearest had no ceiling.** With one rider online, nearest means that
--      rider, whether they are 2 km from the kitchen or 90. The first offer now
--      only goes to riders within 4 km, and the ring widens if nobody takes it.
--
--      **Read the note on the ring predicate before judging this one working.**
--      `RiderLocationReporter` runs only while a rider is *carrying*, so an idle
--      rider has no position and cannot be placed in any ring. The ring is built
--      correctly and binds every rider we can see; it will not bind an idle
--      fleet until the reporter runs while online. Making idle riders report is
--      a separate change with a real consent question attached, and it is the
--      one thing standing between this migration and the feature as asked for.
--
--   2. **Nearest could be anywhere.** A rider outside Sadri and Ranakpur could
--      be offered a job inside them. 0098 drew the boundary for customers; this
--      applies the same boundary to the fleet.
--
--   3. **Idle-first refused to batch.** The old ordering was `live_jobs, km` —
--      an idle rider always beat a busy one, so two orders going to the same
--      street were deliberately given to two different people. When the second
--      drop is within 2 km of one a rider is already carrying, they now get
--      first refusal: that is one ride instead of two, and it is the whole
--      reason a rider may hold more than one job.
--
-- **On "more than one job", which was already true.** `live_jobs < 3` has been
-- in this function since B3 and the rider app has had a Run tab listing every
-- job in hand for as long. What was missing was dispatch ever *choosing* to
-- stack — the cap allowed it and the ordering prevented it. The cap is now
-- `dispatch_settings.max_live_jobs` and still 3.
--
-- **Why the ring widens on the clock and not on offers made.** The obvious rule
-- is "widen after each refusal", and it does not work: if nobody is inside 4 km,
-- no offer is made, so the count never rises and the ring never opens. Time
-- covers both halves of what was asked — nobody there, and nobody accepting —
-- because a decline costs seconds just as an empty ring does. `dispatch-
-- deliveries` ticks every 20 seconds, so a 60-second step is three attempts per
-- ring.
--
-- Every number is a row in `dispatch_settings`, tunable without a deploy:
--
--     update public.dispatch_settings set first_radius_km = 3 where id = 1;

-- ===========================================================================
-- A. The knobs.
-- ===========================================================================
create table if not exists public.dispatch_settings (
  id                  integer primary key default 1 check (id = 1),
  -- The first ring. A rider further than this is not asked at all until it
  -- widens.
  first_radius_km     numeric(6,2) not null default 4.00,
  radius_step_km      numeric(6,2) not null default 4.00,
  max_radius_km       numeric(6,2) not null default 12.00,
  -- How long a ring stands before the next one opens.
  widen_after_seconds integer      not null default 60,
  -- How close a second drop has to be to one already in hand before stacking
  -- them onto one rider is a favour rather than a delay.
  stack_drop_km       numeric(6,2) not null default 2.00,
  max_live_jobs       integer      not null default 3,
  updated_at          timestamptz  not null default now()
);

insert into public.dispatch_settings (id) values (1) on conflict (id) do nothing;

-- Nobody but the definer functions reads this, and nothing outside Postgres has
-- any business writing it. Same shape as `rider_pay_rates` (0043): RLS on, no
-- policies, and the grants that arrive by default taken off.
alter table public.dispatch_settings enable row level security;
revoke all on public.dispatch_settings from anon, authenticated;

-- ===========================================================================
-- B. When we started looking.
-- ===========================================================================
-- Not `created_at`: an order that cooked for ten minutes before it was ready
-- would start its search at the widest ring, which is the opposite of what the
-- ring is for. Stamped by `offer_delivery` on its first pass over an order —
-- including the pass that finds nobody, which is exactly the pass the old
-- offer-counting design could not see.
alter table public.orders
  add column if not exists dispatch_started_at timestamptz;

comment on column public.orders.dispatch_started_at is
  'First time dispatch looked for a rider. Drives the widening ring in offer_delivery.';

-- ===========================================================================
-- C. The dispatcher.
-- ===========================================================================
-- Restated from 0097's definition. The fee half is untouched — `rider_pay_quote`
-- is still the only place the money is worked out, and the offer still freezes
-- what it promised.
create or replace function public.offer_delivery(p_order_id text)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_rider    text;
  v_dist     numeric(6,2);
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_d_lat    double precision;
  v_d_lng    double precision;
  v_name     text;
  v_status   text;
  v_pay      integer;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_route    numeric(6,2);
  v_method   text;
  v_total    integer;
  v_cap      integer;
  v_started  timestamptz;
  v_radius   numeric(6,2);
  v_s        public.dispatch_settings%rowtype;
begin
  -- The order still has to be one that wants a rider. Checked here as well as
  -- in the sweeper because `decline_offer` calls straight into this function,
  -- and an order cancelled between the offer and the decline must not be
  -- handed to somebody else.
  select o.status, r.name, r.latitude, r.longitude,
         o.delivery_lat, o.delivery_lng, o.payment_method, o.total
    into v_status, v_name, v_r_lat, v_r_lng,
         v_d_lat, v_d_lng, v_method, v_total
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

  -- What the job pays, at today's rate and this order's distance. One call, and
  -- the answer is written onto the offer below so that `claim_delivery` can pay
  -- this number rather than work it out again from inputs that may have moved.
  select q.ride_km, q.pay_base, q.pay_per_km, q.rider_pay
    into v_route, v_base, v_per_km, v_pay
    from public.rider_pay_quote(p_order_id) q;

  select * into v_s from public.dispatch_settings where id = 1;

  -- The clock starts on the first pass, found or not. `coalesce` rather than a
  -- conditional so two sweeper ticks racing cannot reset it.
  update public.orders
     set dispatch_started_at = coalesce(dispatch_started_at, now())
   where id = p_order_id
  returning dispatch_started_at into v_started;

  -- 0–60 s: 4 km. 60–120 s: 8 km. Then 12 km and no wider.
  v_radius := least(
    v_s.first_radius_km
      + v_s.radius_step_km
      * floor(extract(epoch from (now() - v_started)) / v_s.widen_after_seconds),
    v_s.max_radius_km
  );
  v_cap := public.rider_cash_cap();

  select cand.email, cand.km
    into v_rider, v_dist
    from (
      select p.email,
             public.delivery_distance_km(l.lat, l.lng, v_r_lat, v_r_lng) as km,
             l.lat is not null and l.lng is not null                     as has_fix,
             public.serviceable_point(l.lat, l.lng)                      as in_area,
             (select count(*) from public.deliveries d
               where d.partner_email = p.email
                 and d.state in ('claimed', 'arrived_at_restaurant',
                                 'picked_up', 'arrived_at_customer')
             ) as live_jobs,
             -- Already carrying something that finishes near where this one
             -- finishes. The comparison is drop to drop and not pickup to
             -- pickup: two orders from one kitchen going to opposite ends of
             -- town are two rides however close the counters are.
             exists (
               select 1
                 from public.deliveries d
                 join public.orders o2 on o2.id = d.order_id
                where d.partner_email = p.email
                  and d.state in ('claimed', 'arrived_at_restaurant',
                                  'picked_up', 'arrived_at_customer')
                  and public.delivery_distance_km(o2.delivery_lat, o2.delivery_lng,
                                                  v_d_lat, v_d_lng)
                      <= v_s.stack_drop_km
             ) as stackable
        from public.delivery_partners p
        left join public.rider_locations l on l.partner_email = p.email
       where p.is_active
         and p.is_online
         -- New in 0080. A `sql` function over an indexed primary key, inlinable
         -- by the planner, on a fleet of hundreds — the same order of cost as
         -- the cash check that has sat beside it since 0076.
         and public.rider_is_verified(p.email)
         -- Evaluated per candidate, which is a sum over one rider's ledger rows
         -- on an indexed column, and only for a cash order. A fleet is hundreds
         -- of rows, not millions.
         and (v_method <> 'cod'
              or public.rider_cash_in_hand(p.email) + v_total <= v_cap)
    ) cand
   where cand.live_jobs < v_s.max_live_jobs
     -- The ring, and the boundary — **for riders we can actually place.**
     --
     -- A rider with no position is not excluded, only outranked. That is a
     -- deliberate retreat from the obvious rule, and the reason is worth
     -- writing down: `RiderLocationReporter` is started and stopped by the
     -- rider's own live jobs, so **an idle rider reports nothing**, and an idle
     -- rider is precisely who a fresh order is looking for. Gating them on the
     -- ring would have meant every order waiting for the widest ring before it
     -- could be offered to anybody — a two-minute delay added to every single
     -- dispatch, which is worse than the problem this migration is fixing.
     --
     -- So the ring binds whoever we can see, the rest queue behind them, and
     -- the ring becomes fully effective the day the reporter runs while a rider
     -- is online rather than only while carrying. Until then it does real work
     -- in exactly one case, which happens to be the case that matters most
     -- here: a rider already carrying a job **is** reporting, so stacking is
     -- always decided on a real distance.
     and (
       not cand.has_fix
       or (cand.in_area and cand.km <= v_radius)
     )
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
   -- Stackable first — a rider already going that way turns two rides into one,
   -- and that is worth more than the few minutes an idle rider would have
   -- saved. Then a rider we can actually see, because a known 3 km beats an
   -- unknown anything. Then the old rule: least busy, then nearest.
   order by cand.stackable desc, cand.has_fix desc,
            cand.live_jobs, cand.km nulls last, cand.email
   limit 1;

  if v_rider is null then
    return null;
  end if;

  insert into public.delivery_offers
    (order_id, partner_email, distance_km, expires_at,
     ride_km, pay_base, pay_per_km, rider_pay)
  values
    (p_order_id, v_rider, v_dist, now() + public.delivery_offer_window(),
     v_route, v_base, v_per_km, v_pay)
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
$function$;

revoke execute on function public.offer_delivery(text) from public, anon;
