-- ---------------------------------------------------------------------------
-- 0055 — the bar stops jumping.
-- ---------------------------------------------------------------------------
-- 0052 gave the live card a ladder: eight server-side steps mapped onto a 0–100
-- number, drawn as a segmented bar with a dot at each milestone. It was honest
-- about *where* the order was and silent about *how long* anything would take,
-- so the bar sat perfectly still for twenty minutes and then jumped 40 points at
-- once. This migration replaces the ladder with a window.
--
-- **The idea in one line: the server stops sending a position and starts sending
-- a pair of instants.** Everything else follows from that.
--
--   * The device computes `(now - window_start) / (window_end - window_start)`
--     on its own clock and gets a bar that creeps. It can redo that arithmetic
--     every twenty seconds without asking the server anything, which is what
--     makes a continuously filling bar possible at all — a push per frame was
--     never going to happen.
--   * Both instants are **constant for the life of a phase**. `window_start` is
--     a timestamp already recorded (`orders.created_at`, `deliveries.picked_up_at`)
--     and `window_end` is derived from it alone. Two consecutive pushes inside
--     one phase therefore carry the identical window, so the count can only fall
--     and the bar can only advance. That is Rule 3 ("the ETA must never move
--     backwards") enforced structurally rather than by care.
--
-- **Two phases, two cards.** `phase` is the other new field, and it is what
-- splits one notification into the two the customer now gets: a `prep` card that
-- fills while the kitchen cooks and is taken down when the food leaves, and a
-- `delivery` card that starts empty at pickup and fills on the way over. The
-- device keys its notification id off this, so they are genuinely two cards and
-- not one card that changes its mind.
--
-- **`progress` survives, as an override.** Normally null — the device
-- interpolates. When it is non-null the device uses it verbatim and ignores the
-- clock. Today that carries exactly one case (`at_door` pins the bar at 100).
-- It exists mainly as the seam for B3: when `rider_locations` lands, real
-- distance-covered is written into this field and the delivery bar becomes
-- distance-driven without a single line changing on the device.
--
-- The stage names, titles and bodies from 0052 are unchanged, and so are both
-- triggers, `post_order_live`, the notification kinds and the edge function
-- (which flattens whatever jsonb it is handed, so new keys need no deploy).

-- ---------------------------------------------------------------------------
-- Where the order is, as a window rather than a step.
-- ---------------------------------------------------------------------------
-- The prep window is `created_at → ready_by`. `ready_by` (0015) is the kitchen's
-- own promise, stamped from the server clock at the moment it accepted, which
-- makes it the one authoritative answer to "when will this food be cooked". It
-- is nullable — a vendor may accept without naming a time — and the fallback is
-- 55% of the quoted ETA, the same split 0008 already uses to guess where the
-- prep half of an order ends.
--
-- The window opens at `created_at` rather than at the accept, and that is
-- deliberate even though it means the bar is already part-filled the moment the
-- kitchen accepts. The customer's wait began when they paid; a bar that ignores
-- the four minutes a vendor took to press Accept is a bar that lies about how
-- long they have been waiting.
--
-- The delivery window is `picked_up_at → picked_up_at + ride`, where the ride is
-- the road distance at 20 km/h — city-scooter pace. `route_km` (0046) is the
-- real road distance when Ola has answered, and the straight-line haversine
-- (0043) when it has not, which is the same coalesce `claim_delivery` uses to
-- pay riders. This is per-address, unlike `eta_minutes`, which is one blanket
-- number the restaurant sets for every customer it has: a 1 km hop and a 12 km
-- haul quote the same ETA today, and would have paced the same bar identically.
create or replace function public.order_live_payload(p_order_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with o as (
    select o.id, o.status, o.restaurant_name, o.created_at, o.eta_minutes,
           o.ready_by, o.route_km,
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
    -- first is a field somebody will eventually believe. `stage` is the one
    -- answer, computed from both ladders, and it is also what makes two
    -- consecutive payloads comparable in `post_order_live`.
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
                    (o.created_at + make_interval(mins => o.eta_minutes))
                      at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                  ),
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

revoke all on function public.order_live_payload(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- One more thing that has to fire now: the pickup.
-- ---------------------------------------------------------------------------
-- 0052's delivery trigger listened for the two arrivals only, and said so:
-- `picked_up` and `delivered` were skipped because both already move
-- `orders.status`, so narrating them here as well would post the same card
-- twice. That reasoning held when there was one card.
--
-- There are two now, and `picked_up` is the seam between them — the moment the
-- prep card comes down and the delivery card goes up, and the moment
-- `picked_up_at` is stamped and the delivery window can first be computed. It
-- has to be an event. The duplicate it was avoiding is handled where it always
-- should have been: `post_order_live` compares against the last payload and
-- drops a repeat, so whichever of the two writes lands second is a no-op.
create or replace function public.notify_customer_delivery_live()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user text;
begin
  if new.state is not distinct from old.state then
    return new;
  end if;

  if new.state not in ('arrived_at_restaurant', 'picked_up', 'arrived_at_customer') then
    return new;
  end if;

  begin
    select user_id into v_user from public.orders where id = new.order_id;
    if v_user is null then
      return new;
    end if;
    perform public.post_order_live(new.order_id, v_user);
  exception when others then
    null;
  end;

  return new;
end;
$$;
