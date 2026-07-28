-- ---------------------------------------------------------------------------
-- 0058 — the card gets its window back, and the kitchen stops being told twice.
-- ---------------------------------------------------------------------------
-- Two regressions, one file, because both are a line that was written from an
-- out-of-date copy of something.
--
-- **A. The live card stopped being drawn at all.**
--
-- 0055 replaced the card's ladder with a window: the server stopped sending a
-- position and started sending `phase` plus the pair of instants
-- (`window_start`, `window_end`) the device interpolates between. The device was
-- rewritten to match, and it is strict about it — `OrderLiveCard.handle` returns
-- without drawing when either instant is missing, because a card with no window
-- has no bar and is worse shown empty than not shown.
--
-- 0057 section H then rewrote `order_live_payload` to carry the recomputed
-- `eta_at` and its reason — and wrote it from **0052's** text rather than
-- 0055's. Its own comment says so ("Identical to 0052 but for `eta_at` and the
-- reason"). So `phase`, `window_start` and `window_end` were dropped and the
-- 0052-era `progress` ladder came back with them. Every `order_live` push since
-- has been a payload the device correctly refuses to draw: the rows are in the
-- table, the pushes went out silently, and no customer has seen a live card.
--
-- This restores 0055's payload and folds 0057's two fields into it, which is
-- what section H meant to do. Nothing else about 0057 changes — the reestimate
-- triggers, `recompute_order_eta` and `order_route` are all untouched.
--
-- **B. A new order rang the kitchen twice.**
--
-- 0021 put a webhook on `orders` INSERT pointing at `send-order-push`. 0047
-- replaced that with a webhook on `notifications` INSERT pointing at
-- `send-notification`, which serves all three audiences from the one inbox row a
-- trigger already writes. Both webhooks are live on the database, so every new
-- order produces a `new_order` row *and* fires the old function directly, and
-- the vendor's phone rings twice for one order. `send-notification`'s own header
-- warned about exactly this: "do not run both".
--
-- The old trigger goes. The `send-order-push` function can be deleted from the
-- project afterwards; leaving it deployed but unwired is harmless.

-- ---------------------------------------------------------------------------
-- A. The payload, as 0055 defined it, carrying 0057's live arrival time.
-- ---------------------------------------------------------------------------
-- Every comment 0055 wrote about the two windows still applies and is not
-- repeated here. The only differences from that version:
--
--   * `eta_at` is `coalesce(orders.eta_at, created_at + eta_minutes)` — the
--     recomputed promise when something has recomputed one, the original
--     otherwise. This is 0057's line, unchanged.
--   * `eta_reason` rides along, null on an order running to time.
--
-- Neither touches the window. That is deliberate and it is the whole of Rule 3:
-- `eta_at` is allowed to slip (0057 gives it a sentence when it does), and a bar
-- paced against a deadline that can move later is a bar that walks backwards.
-- The window keeps deriving from `created_at`, `ready_by` and `picked_up_at`,
-- all of which are stamped once and never move.
create or replace function public.order_live_payload(p_order_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with o as (
    select o.id, o.status, o.restaurant_name, o.created_at, o.eta_minutes,
           o.ready_by, o.route_km, o.eta_at, o.eta_reason,
           o.delivery_lat, o.delivery_lng,
           r.latitude as r_lat, r.longitude as r_lng
      from public.orders o
      left join public.restaurants r on r.id = o.restaurant_id
     where o.id = p_order_id
  ),
  d as (
    -- The live delivery, if there is one. A dropped job leaves a 'cancelled'
    -- row beside the real one (the 0025 abandon→reclaim shape), and letting a
    -- corpse into this join is how the bar would jump back to the counter.
    select state, picked_up_at
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
    -- How long the ride should take, in minutes. Road distance if Ola answered,
    -- straight line if it did not, and 3 km if the order has no coordinates at
    -- all. Floored at 5 so a next-door delivery still has a bar worth watching,
    -- capped at 90 so one bad coordinate cannot leave a card up for hours.
    greatest(5, least(90, ceil(
      coalesce(
        o.route_km,
        public.delivery_distance_km(o.r_lat, o.r_lng, o.delivery_lat, o.delivery_lng),
        3
      ) * 3
    )::integer)) as ride_minutes
    from o left join d on true
  ),
  win as (
    select
      case when s.name in ('on_the_way', 'at_door') then 'delivery' else 'prep' end
        as phase,
      case
        when s.name in ('on_the_way', 'at_door')
          -- `picked_up_at` is stamped by `confirm_pickup`, so it is set for every
          -- order that has reached these two stages. `created_at` is the
          -- fallback purely so this can never evaluate to null and make the
          -- whole payload null — a window is not optional.
          then coalesce(d.picked_up_at, o.created_at)
        else o.created_at
      end as w_start,
      case
        when s.name in ('on_the_way', 'at_door')
          then coalesce(d.picked_up_at, o.created_at)
                 + make_interval(mins => s.ride_minutes)
        else greatest(
               -- A kitchen that names a prep time shorter than the wait already
               -- endured would otherwise hand the device an inverted window.
               coalesce(o.ready_by, o.created_at
                          + make_interval(mins => greatest(2, round(o.eta_minutes * 0.55)::int))),
               o.created_at + interval '2 minutes'
             )
      end as w_end
    from o cross join stage s left join d on true
  )
  select jsonb_build_object(
    'order_id',   o.id,
    -- `stage`, and deliberately not `orders.status` beside it. The raw status
    -- is a half-truth here — it reads 'preparing' while the rider is already
    -- standing at the counter — and a second field that disagrees with the
    -- first is a field somebody will eventually believe.
    'stage',      s.name,
    -- Which of the two cards this belongs to. 'prep' and 'delivery' are drawn;
    -- 'delivered' and 'ended' tell the device to take both of them down.
    'phase',      case when s.name in ('delivered', 'ended') then s.name
                       else w.phase end,
    'window_start', to_char(w.w_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'window_end',   to_char(w.w_end   at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    -- Null means "work it out from the clock". The rider is at the door and the
    -- bar should read full regardless of what the ride estimate said.
    'progress',   case when s.name = 'at_door' then 100 else null end,
    'restaurant', o.restaurant_name,
    'eta_at',     to_char(
                    coalesce(
                      o.eta_at,
                      o.created_at + make_interval(mins => o.eta_minutes)
                    ) at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                  ),
    -- Null on every order running to time, which is what the tracking screen
    -- checks: the line only exists when there is something to admit.
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
  from o cross join stage s cross join win w;
$$;

revoke all on function public.order_live_payload(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- B. One webhook per event.
-- ---------------------------------------------------------------------------
-- `push_on_notification_insert` on `public.notifications` is the one that stays:
-- it serves the customer, the rider and the restaurant from the single row every
-- event already writes. This is the 0021 original it superseded, still firing
-- alongside it.
drop trigger if exists on_new_order_push on public.orders;
