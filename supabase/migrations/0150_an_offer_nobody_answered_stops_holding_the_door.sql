-- ---------------------------------------------------------------------------
-- 0150 — an offer nobody answered stops holding the door.
-- ---------------------------------------------------------------------------
-- `offer_delivery` cannot insert an offer while another one for the same order
-- is still marked 'offered', which is the point of
-- `delivery_offers_one_live_per_order` and is right. What that index cannot say
-- is *live*: `expires_at > now()` is not immutable, so a partial index will not
-- carry it, and the predicate has to be plain `state = 'offered'`.
--
-- That leaves a gap between an offer lapsing and something writing 'expired' on
-- it. A row in that gap still holds the unique slot, so `on conflict do nothing`
-- silently loses and `offer_delivery` returns null — and returns null on every
-- tick after, because nothing in the losing path clears what it lost to. The
-- order falls off dispatch and stays off.
--
-- ## Why it has never happened
--
-- `dispatch_deliveries` expires the entire board one statement before it loops
-- over dispatchable orders, in a single transaction, so the sweeper is never the
-- thing that meets a stale row. And `decline_offer`, the only other caller,
-- marks its own row 'declined' before calling in.
--
-- Both are true, and neither is written down anywhere near the function that
-- depends on them. The safety is an ordering property of two callers, which is
-- the kind of thing a later change removes without noticing: split the sweeper's
-- expiry from its loop, give it its own schedule, add a third caller, and this
-- becomes a live order nobody can be offered.
--
-- ## What changes
--
-- One `update`, scoped to the order being offered, at the top of
-- `offer_delivery`. The function now clears its own path instead of trusting
-- its callers to have cleared it, and `dispatch_deliveries` keeps its board-wide
-- expiry — that one is not redundant, it is what moves a lapsed offer off the
-- rider's screen for orders this function never reaches.
--
-- Nothing else in the body is touched. It is restated in full because
-- `create or replace` has no other form, and it was taken from
-- `pg_get_functiondef` on the live database rather than from 0148's file, so
-- what is replaced is what was actually running.
--
-- 0148's rule is intact: the rider who let the offer lapse still keeps the job
-- on their board and can still claim it. The candidate query below excludes
-- anybody holding any offer row for this order whatever its state, so expiring
-- the row does not put them back in the ring — it only stops them blocking it.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.offer_delivery(p_order_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- New in 0148. Riders are mid-tap on this one; nobody new is asked until it
  -- is settled, which is at most `contest_seconds` away.
  if exists (
    select 1 from public.delivery_claims
     where order_id = p_order_id and decided_at is null
  ) then
    return null;
  end if;

  -- ---------------------------------------------------------------------
  -- This order's own lapsed offer, cleared here rather than upstream. (0150)
  -- ---------------------------------------------------------------------
  -- `delivery_offers_one_live_per_order` is `unique (order_id) where state =
  -- 'offered'`, and expiry is not in that predicate — it cannot be, because
  -- `expires_at > now()` is not immutable and a partial index will not take it.
  -- So a row that has lapsed but has not yet been *marked* lapsed still occupies
  -- the slot, and the `on conflict do nothing` below loses to it and returns
  -- null. Every subsequent tick loses to it again: the order stops being
  -- dispatchable for as long as that row says 'offered'.
  --
  -- Nothing wedges today, and the reason is thin. `dispatch_deliveries` expires
  -- the whole board one statement before it re-offers, in the same transaction,
  -- so the sweeper never meets its own stale rows; and the only other caller,
  -- `decline_offer`, sets its own row to 'declined' before it gets here. The
  -- guarantee therefore lives in the two callers rather than in this function,
  -- and it holds only while both keep doing it — split those two statements,
  -- add a third caller, and the wedge is real.
  --
  -- One statement moves the guarantee to where it belongs. Scoped to this order,
  -- so it takes no lock the sweeper's board-wide expiry would not already have
  -- taken, and covered exactly by `delivery_offers_live_idx`.
  --
  -- The rider who let it lapse is not re-offered by the candidate query below —
  -- that excludes anybody holding *any* offer row for this order, whatever its
  -- state — and they keep the job on their board and their right to claim it,
  -- which is 0148's rule and not disturbed here.
  update public.delivery_offers
     set state = 'expired', responded_at = now()
   where order_id = p_order_id
     and state = 'offered'
     and expires_at <= now();

  -- What the job pays, at today's rate and this order's distance. One call, and
  -- the answer is written onto the offer below so that `claim_delivery` can pay
  -- this number rather than work it out again from inputs that may have moved.
  select q.ride_km, q.pay_base, q.pay_per_km, q.rider_pay
    into v_route, v_base, v_per_km, v_pay
    from public.rider_pay_quote(p_order_id) q;

  select * into v_s from public.dispatch_settings where id = 1;

  -- The clock starts on the first pass, found or not.
  --
  -- **Read before written** (0121), which is not a micro-optimisation: the
  -- unconditional `update` took a row lock on every dispatchable order on every
  -- tick, held until the sweeper committed, so a cook tapping "Ready" queued
  -- behind a write with nothing left to say. Only the first pass writes now.
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
         -- 0080. A `sql` function over an indexed primary key, inlinable by the
         -- planner, on a fleet of hundreds — the same order of cost as the cash
         -- check that has sat beside it since 0076.
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
     -- dispatch, which is worse than the problem 0099 was fixing.
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
  --
  -- `expires_at` is what bounds the **ring** on the device, the same way
  -- `accept_deadline` bounds the kitchen's (0136): a message that sat in a Doze
  -- queue for twelve seconds must ring for the three that are left, not for a
  -- fresh fifteen.
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
