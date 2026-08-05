-- ---------------------------------------------------------------------------
-- 0097 — one number for one job.
-- ---------------------------------------------------------------------------
-- A rider was offered ZPQ-1140 at ₹672, accepted it, and the job card then said
-- ₹114. The ₹114 was the customer's bill — the accepted-job card had no fee on
-- it at all, so the order total was the only rupee figure left on the screen and
-- read as a fee that had collapsed. That half is a rider-app fix and is not in
-- this file. `deliveries.rider_pay` for that order is ₹672 and always was.
--
-- What *is* in this file is the thing the report exposed underneath it: the fee
-- formula is written out four times.
--
--   * `offer_delivery`      — for the push body and the offer row
--   * `my_offers`           — recomputed on every read of the offer sheet
--   * `available_deliveries`— recomputed on every read of the open board
--   * `claim_delivery`      — computed once more and frozen onto `deliveries`
--
-- All four agree today. Nothing makes them agree. `offer_delivery` even says so
-- in its own comment — *"deliberately computed the same way `claim_delivery`
-- will compute it a moment later — a fee quoted in the offer that differs from
-- the fee on the accepted job is the single fastest way to lose a fleet's
-- trust"* — and then enforces it by copy-paste. A single edit to the rate logic
-- in three of four places is a silent underpayment, and the rider is the only
-- person positioned to notice.
--
-- Two changes, and the second is the one that matters:
--
--   1. **One formula.** `rider_pay_quote(order_id)` is now the only place the
--      distance is chosen and the fee is multiplied. The four callers ask it.
--
--   2. **The offer is binding.** Even with one formula, the offer sheet
--      recomputed on every read while the delivery froze at claim time — and the
--      input moves underneath both. `orders.route_km` is filled asynchronously
--      by the Ola lookup (0046), so an offer made before the road distance lands
--      quotes the straight line and a claim a few seconds later freezes the
--      road. ZPQ-1140 is exactly that: `route_km` 174.39, `distance_km` 129.40 —
--      the same order, two distances, ₹225 apart in fee. Whoever the difference
--      favours, it was not the number the rider said yes to.
--
--      So the quote is frozen onto the offer when the offer is made, and
--      `claim_delivery` pays what the accepted offer promised. A rider who
--      accepts ₹672 is paid ₹672.
--
-- **The board is deliberately not frozen.** An open job on `available_deliveries`
-- has not been quoted to anybody in particular; it is a live estimate and it
-- should track the best distance we have. The freeze exists to make a *promise*
-- binding, and the board makes no promise until it is claimed — at which point
-- `claim_delivery` quotes and freezes in the same statement.
--
-- Nothing here changes what anybody is paid today. Verified against the live
-- database in rolled-back transactions: every open order's quote is rupee-for-
-- rupee what the four old copies returned.

-- ===========================================================================
-- A. The formula, once.
-- ===========================================================================
-- The distance is `coalesce(route_km, straight line)` and has been since 0046:
-- the road when Ola has answered for this order, the straight line until then —
-- so a claim never waits on a third party and pay is never blocked. Rounded to
-- two places *before* it is multiplied, because that is the value that lands in
-- `deliveries.distance_km` (`numeric(6,2)`) and a rider checking the arithmetic
-- on the earnings screen must be able to reproduce the fee from the distance
-- printed next to it.
--
-- Null distance is preserved rather than defaulted: it means the kitchen has no
-- coordinates on file, the job pays the base fee and nothing more, and both apps
-- say so instead of drawing a confident `0.0 km`.
--
-- `stable`, not `volatile` — it reads and decides nothing. Security invoker: it
-- is only ever called from inside the security-definer functions below, which
-- already run as this function's owner, and it is revoked from PUBLIC so the API
-- cannot reach it directly.
create or replace function public.rider_pay_quote(p_order_id text)
returns table (
  ride_km    numeric,
  pay_base   integer,
  pay_per_km numeric,
  rider_pay  integer
)
language sql
stable
set search_path = public
as $$
  select km.value,
         rt.base_fee,
         rt.per_km_fee,
         rt.base_fee + round(coalesce(km.value, 0) * rt.per_km_fee)::integer
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
    cross join public.rider_pay_rates rt
    cross join lateral (
      select round(
               coalesce(
                 o.route_km,
                 public.delivery_distance_km(r.latitude, r.longitude,
                                             o.delivery_lat, o.delivery_lng)
               ),
               2
             ) as value
    ) km
   where o.id = p_order_id
     and rt.id = 1;
$$;

-- Nobody is granted it: the callers below are `security definer` and owned by
-- the same role that owns this, so they can call it while the API cannot.
--
-- **Both revokes are load-bearing, and the second one is the surprise.** 0089's
-- rule is that a new function is executable by PUBLIC and that revoking from
-- `anon, authenticated` therefore does nothing. That is half the picture: this
-- database also carries an `alter default privileges` for owner `postgres` that
-- grants EXECUTE on every new function to `authenticated` and `service_role`
-- *by name*. Revoking PUBLIC leaves that explicit grant standing, and the first
-- cut of this migration did exactly that — `has_function_privilege` said
-- `authenticated` could still call it. Revoke both, and check with
-- `has_function_privilege` rather than reading the migration back.
revoke execute on function public.rider_pay_quote(text) from public, anon, authenticated;

-- ===========================================================================
-- B. The offer remembers what it promised.
-- ===========================================================================
-- `ride_km` and not `distance_km`, because `delivery_offers.distance_km` is
-- already taken and means the *other* distance — how far the rider was from the
-- kitchen when they were picked (0056). One is why this rider got the offer; the
-- other is what the offer pays for. Naming them apart is the whole of the reason
-- this column is not called what it would obviously be called.
--
-- Nullable, and left null on every offer that already exists: an offer lives
-- forty-five seconds, so the rows in flight while this migration runs are the
-- only ones that will ever have nulls here, and the readers below fall back to a
-- live quote for exactly that case rather than paying them nothing.
alter table public.delivery_offers
  add column if not exists ride_km    numeric(6,2),
  add column if not exists pay_base   integer,
  add column if not exists pay_per_km numeric(6,2),
  add column if not exists rider_pay  integer;

comment on column public.delivery_offers.ride_km is
  'Kitchen to door, frozen when the offer was made. Not distance_km, which is rider to kitchen.';
comment on column public.delivery_offers.rider_pay is
  'What this offer promised. claim_delivery pays this, not a fresh calculation.';

-- ===========================================================================
-- C. Making the offer — quote once, and write the quote down.
-- ===========================================================================
-- Restated from the live definition (0080's, with the verification gate and the
-- cash cap), changed in three places only: the fee comes from the quote, the
-- quote is stored on the offer row, and the inline distance is gone from the
-- opening select because the quote now answers it.
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
  v_name     text;
  v_status   text;
  v_pay      integer;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_route    numeric(6,2);
  v_method   text;
  v_total    integer;
  v_cap      integer;
begin
  -- The order still has to be one that wants a rider. Checked here as well as
  -- in the sweeper because `decline_offer` calls straight into this function,
  -- and an order cancelled between the offer and the decline must not be
  -- handed to somebody else.
  select o.status, r.name, r.latitude, r.longitude, o.payment_method, o.total
    into v_status, v_name, v_r_lat, v_r_lng, v_method, v_total
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

  -- What the job pays, at today's rate and this order's distance. One call,
  -- and the answer is written onto the offer below so that `claim_delivery`
  -- can pay this number rather than work it out again from inputs that may
  -- have moved. The comment that used to sit here promised the two would
  -- agree; the row now makes it true.
  select q.ride_km, q.pay_base, q.pay_per_km, q.rider_pay
    into v_route, v_base, v_per_km, v_pay
    from public.rider_pay_quote(p_order_id) q;

  v_cap := public.rider_cash_cap();

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

-- ===========================================================================
-- D. Reading the offer — the sheet shows what was promised.
-- ===========================================================================
-- The push, the sheet and the accepted job now read one number instead of three
-- calculations that happened to match. `coalesce` onto a live quote covers the
-- handful of offers that were already open when this migration ran; every offer
-- made afterwards carries its own figures and the fallback never fires.
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
as $function$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status,
           coalesce(off.ride_km,   q.ride_km),
           off.distance_km,
           coalesce(off.rider_pay, q.rider_pay),
           off.offered_at, off.expires_at
      from public.delivery_offers off
      join public.orders o      on o.id = off.order_id
      join public.restaurants r on r.id = o.restaurant_id
      left join lateral public.rider_pay_quote(o.id) q on true
     where off.partner_email = v_rider
       and off.state = 'offered'
       and off.expires_at > now()
     order by off.expires_at;
end;
$function$;

revoke execute on function public.my_offers() from public, anon;

-- ===========================================================================
-- E. Taking the job — pay what was offered.
-- ===========================================================================
-- Restated from the live definition (the work block from 0080 and the cash cap
-- from 0076 are both in it), changed in one place: where the fee comes from.
--
-- An accepted offer is looked for first, and it is found whenever this claim
-- came through `accept_offer` — that function sets `state = 'accepted'` and then
-- calls this one inside the same transaction, so the row is there to read. What
-- gets frozen onto the delivery is then, to the rupee, what the rider was shown
-- before they said yes.
--
-- A claim straight off the open board has no offer, and quotes fresh. That is
-- the honest answer for a job nobody was promised anything about: the board
-- redraws from the same quote, so the number on the card and the number on the
-- delivery are computed within milliseconds of each other from the same input.
create or replace function public.claim_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_rider    text;
  v_online   boolean;
  v_status   text;
  v_id       bigint;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_distance numeric(6,2);
  v_pay      integer;
  v_method   text;
  v_total    integer;
  v_cash     integer;
  v_cap      integer;
  v_block    text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- New in 0080. Before the online check, because "your licence expired" is the
  -- more useful sentence of the two when both are true.
  v_block := public.rider_work_block(v_rider);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  select is_online into v_online
    from public.delivery_partners where email = v_rider;

  if not coalesce(v_online, false) then
    raise exception 'You are offline. Go online to take deliveries.'
      using errcode = 'P0001';
  end if;

  select o.status, o.payment_method, o.total
    into v_status, v_method, v_total
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found then
    raise exception 'That order no longer exists.' using errcode = 'P0001';
  end if;

  if v_status not in ('preparing', 'ready_for_pickup') then
    raise exception 'That order is no longer available.' using errcode = 'P0001';
  end if;

  if v_method = 'cod' then
    v_cash := public.rider_cash_in_hand(v_rider);
    v_cap  := public.rider_cash_cap();

    if v_cash + v_total > v_cap then
      raise exception
        'You''re holding ₹% in cash and this order collects ₹%, which is over the ₹% limit. Deposit what you''re carrying to take cash orders again.',
        v_cash, v_total, v_cap
        using errcode = 'P0001';
    end if;
  end if;

  -- What this rider was promised, if anybody promised them anything.
  select off.ride_km, off.pay_base, off.pay_per_km, off.rider_pay
    into v_distance, v_base, v_per_km, v_pay
    from public.delivery_offers off
   where off.order_id = p_order_id
     and off.partner_email = v_rider
     and off.state = 'accepted'
     and off.rider_pay is not null
   order by off.responded_at desc nulls last
   limit 1;

  -- Off the board, or an offer made before 0097 and so carrying no figures.
  if not found then
    select q.ride_km, q.pay_base, q.pay_per_km, q.rider_pay
      into v_distance, v_base, v_per_km, v_pay
      from public.rider_pay_quote(p_order_id) q;
  end if;

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
    v_pay
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
$function$;

revoke execute on function public.claim_delivery(text) from public, anon;
grant execute on function public.claim_delivery(text) to authenticated;

-- ===========================================================================
-- F. The open board — a live estimate, from the same formula.
-- ===========================================================================
-- `left join lateral ... on true` rather than `cross join`: a quote that
-- returned no row would silently drop the order off the board, and an order
-- missing from a rider's board is a much quieter failure than one showing an
-- odd fee.
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
  route_km        numeric,
  rider_pay       integer,
  ready_by        timestamptz,
  placed_at       timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_email    text;
  v_headroom integer;
  v_block    text;
begin
  v_email := public.delivery_partner_email();
  if v_email is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- New in 0080. Raised rather than returning nothing: an empty board reads as
  -- "no work right now", which is a different and much worse thing to tell
  -- somebody whose documents are sitting unverified in a queue.
  v_block := public.rider_work_block(v_email);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  -- How much more cash this rider may be holding. Computed once here rather
  -- than per row: it does not change while the query runs.
  v_headroom := public.rider_cash_cap() - public.rider_cash_in_hand(v_email);

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status,
           q.ride_km,
           q.rider_pay,
           o.ready_by, o.created_at
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
      left join lateral public.rider_pay_quote(o.id) q on true
     where o.status in ('preparing', 'ready_for_pickup')
       and (o.payment_method <> 'cod' or o.total <= v_headroom)
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
$function$;

revoke execute on function public.available_deliveries() from public, anon;
grant execute on function public.available_deliveries() to authenticated;
