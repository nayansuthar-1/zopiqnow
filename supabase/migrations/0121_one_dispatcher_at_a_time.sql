-- ---------------------------------------------------------------------------
-- 0121 — one dispatcher at a time, and a lock only where there is something to say.
-- ---------------------------------------------------------------------------
-- `dispatch-deliveries` runs every 20 seconds, holds no mutual exclusion, and
-- takes a row lock on every order it looks at. Two of those three are fine.
--
-- ## The deadlock
--
-- The sweeper loops up to 50 orders and calls `offer_delivery` on each, which
-- opens with
--
--     update public.orders set dispatch_started_at = coalesce(…) where id = …
--
-- — a row lock held until the sweeper's transaction commits. The loop order is
--
--     order by (ord.status = 'ready_for_pickup') desc, ord.created_at
--
-- and **that order changes between ticks**: an order moving `preparing` →
-- `ready_for_pickup` jumps to the front of the queue. So a run still going when
-- the next one starts can hold A and want B while the newer run holds B and
-- wants A. Postgres breaks the cycle by killing one of them, and the one it
-- kills is a dispatch tick that silently did nothing.
--
-- Nothing forces two runs to overlap today — `deadlocks` is 0 and a tick
-- averages 0.01 s against 55 lifetime orders. It is a load-triggered bug, which
-- is the kind that arrives on the busiest evening rather than a quiet one.
--
-- **`pg_try_advisory_xact_lock`, not `pg_advisory_lock`.** Two differences and
-- both matter. `try` returns rather than queues, so a tick that finds the board
-- already being worked leaves instead of joining a line that grows faster than
-- it drains. `xact` releases at commit *or rollback*, so a run that raises
-- cannot strand the lock and wedge dispatch until somebody notices — which is
-- the classic way a session-scoped advisory lock in a cron job fails.
--
-- ## The vendor's "Ready" button, which is the same bug in a different hat
--
-- `set_order_status` opens with `select … for update` on the order. The sweeper
-- was holding row locks on up to 50 orders for the length of its transaction, so
-- a cook tapping **Ready** queued behind it. The advisory lock caps that at one
-- run's duration rather than a pile-up — but the better half of the fix is that
-- most of those locks should never have been taken at all.
-- `dispatch_started_at` is written once and then rewritten to its own value on
-- every subsequent tick, for ever. `offer_delivery` now reads it first and
-- writes only when it is null, so an order is locked by dispatch exactly once in
-- its life.
--
-- Together: at most one sweeper, and a sweeper that locks only what it changes.

-- ===========================================================================
-- A. The advisory-lock key registry.
-- ===========================================================================
-- Two-argument form, so the first number is a namespace this project owns and
-- the second names the holder. A bare one-argument key shares a single 64-bit
-- space with every extension and migration tool that ever takes an advisory
-- lock, and a collision there is a job that mysteriously never runs.
--
--   namespace 4242 — Zopiqnow background jobs
--     1  dispatch_deliveries
--
-- Take the next integer for a new holder. Never reuse one.

-- ===========================================================================
-- B. The sweeper.
-- ===========================================================================
-- Restated from the live definition; the only change is the guard at the top.
create or replace function public.dispatch_deliveries()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  o record;
  v_offered text;
begin
  -- A tick already working the board owns it. Leaving is the correct answer and
  -- not a dropped beat: the next tick is 20 seconds away, the run in progress is
  -- doing the very work this one would have done, and an order it has not
  -- reached yet is still on the board for the run after.
  if not pg_try_advisory_xact_lock(4242, 1) then
    return;
  end if;

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

  -- New in 0057. Inside the guard, so a skipped tick skips this too — it is a
  -- purge of stale rows and the next tick does it just as well.
  perform public.purge_rider_locations();
end;
$function$;

revoke all on function public.dispatch_deliveries()
  from public, anon, authenticated;

comment on function public.dispatch_deliveries() is
  'The 20-second dispatch tick. Holds advisory lock (4242, 1) for its transaction so two runs cannot interleave their order-row locks and deadlock (0121).';

-- ===========================================================================
-- C. The dispatcher stops locking what it is not changing.
-- ===========================================================================
-- Restated from the live definition. The only change is the `dispatch_started_at`
-- block, which now reads before it writes — see the note inside it.
create or replace function public.offer_delivery(p_order_id text)
returns text
language plpgsql
security definer
set search_path to 'public'
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

  -- The clock starts on the first pass, found or not.
  --
  -- **Read before written**, which is P6/P7 rather than a micro-optimisation.
  -- The unconditional `update` took a row lock on *every dispatchable order on
  -- every tick*, held until the sweeper's transaction committed — so a cook
  -- tapping "Ready" (which opens `select … for update` on that same row) queued
  -- behind a write that had nothing left to say. Only the first pass over an
  -- order writes now; every later one reads and locks nothing.
  --
  -- `coalesce` stays inside the `update` and is still load-bearing. Two callers
  -- can both read null and both fall through — `decline_offer` re-offers inline
  -- and does not hold the sweeper's advisory lock — and the one that arrives
  -- second re-evaluates the row under the lock it waited for, so it preserves
  -- the first one's timestamp instead of resetting the ring.
  select dispatch_started_at into v_started
    from public.orders where id = p_order_id;

  if v_started is null then
    update public.orders
       set dispatch_started_at = coalesce(dispatch_started_at, now())
     where id = p_order_id
    returning dispatch_started_at into v_started;
  end if;

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

-- ---------------------------------------------------------------------------
-- Verification — all three must hold before this counts as applied.
-- ---------------------------------------------------------------------------
-- 1. **The lock actually excludes.** In one session, hold it:
--
--      begin;
--      select pg_try_advisory_xact_lock(4242, 1);   -- t
--
--    and in a *second* session, while the first is still open:
--
--      select pg_try_advisory_xact_lock(4242, 1);   -- f
--      select public.dispatch_deliveries();          -- returns at once, no wait
--
--    Then `rollback` the first and confirm the second can take it. The rollback
--    half is the point: it proves the lock cannot be stranded by a run that
--    raises.
--
-- 2. **A second pass over an order takes no row lock.** With every dispatchable
--    order already carrying a `dispatch_started_at`:
--
--      begin;
--      select public.dispatch_deliveries();
--      select count(*) from pg_locks
--       where locktype = 'tuple' and relation = 'public.orders'::regclass;
--      rollback;
--
--    Before 0121 this was one row lock per dispatchable order, on every tick,
--    held for the life of the transaction.
--
-- 3. **`offer_delivery` still offers.** The rewrite touched one block of a long
--    function, so the cheapest proof it is intact is that a dispatchable order
--    still produces an offer with a frozen quote on it. See the run recorded in
--    the commit message.
--
-- And the two standing release checks (0087, 0089) must still return zero rows.
-- ---------------------------------------------------------------------------
