-- ---------------------------------------------------------------------------
-- 0166 — the floor, seen from above.
-- ---------------------------------------------------------------------------
-- `rider_locations` has been written on every job since 0057 and the console
-- has never drawn it. The customer sees their own rider move; the platform,
-- which is the party that has to decide whether to ring a kitchen or pull a
-- job off a rider, has only ever had a text table.
--
-- One function — `admin_ops_map(service_area)` — returning everything one
-- screen needs: the live orders with the two ends of each journey, the riders
-- who are actually out there, the towns to filter by, and a count of the fleet
-- that is not on the map and why.
--
-- ## The order layer is `admin_orders`, not a second copy of it
--
-- What counts as live, and what counts as in trouble, are already decided in
-- one place (0155). Restating either here would be two definitions of a red
-- pin, drifting apart at the speed of whichever one somebody remembers to
-- edit. So this calls `admin_orders(null)` and joins coordinates onto it. The
-- inner call runs its own `assert_admin()`, which passes because this one
-- already did.
--
-- ## There is no idle-rider layer, and there cannot be one
--
-- The plan for this screen asked for pucks coloured idle / offered / carrying.
-- The first of those is not in the database and is not an oversight:
-- `purge_rider_locations` (0057, folded into the dispatcher's five-second tick)
-- deletes every position older than ten minutes **and** every position
-- belonging to a rider with nothing live. A rider's whereabouts are kept for
-- exactly as long as there is a job that justifies knowing them, which is a
-- deliberate privacy rule and a good one.
--
-- So the map draws the riders who are on a job, and the fleet counts say what
-- became of the rest: how many are online, how many are carrying something, and
-- how many have a position at all. An admin looking for a rider who is not on
-- the map gets the reason instead of an empty patch of Rajasthan.
--
-- ## What this looks like today
--
-- Empty. There are no live orders — the newest order on the platform is from
-- 27 August — and `rider_locations` is therefore empty too, correctly. The
-- screen says so rather than drawing a blank basemap; a map that cannot tell
-- "nothing is happening" from "the query failed" is a map nobody trusts at
-- three in the morning.
-- ---------------------------------------------------------------------------

create or replace function public.admin_ops_map(p_service_area_id text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  v_area   text;
  v_result jsonb;
begin
  perform public.assert_admin();

  v_area := nullif(trim(coalesce(p_service_area_id, '')), '');

  select jsonb_build_object(
    'generated_at', now(),

    -- Every town, switched on or off, because the filter is also the only place
    -- the console says which towns exist. Ghanerao is seeded and dark, and a
    -- filter that hid it would make "why is there nothing in Ghanerao" a
    -- question with no answer on screen.
    'towns', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id,
               'name', a.name,
               'centre_lat', a.centre_lat,
               'centre_lng', a.centre_lng,
               'radius_km', a.radius_km,
               'is_active', a.is_active)
             order by a.is_active desc, a.name)
        from public.service_areas a), '[]'::jsonb),

    -- The live board with coordinates on it. `breaches` and `breach_since` come
    -- from 0155 through `admin_orders`, so a pin is red for exactly the reason
    -- the board says it is.
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id', o.order_id,
               'status', o.status,
               'placed_at', o.placed_at,
               'eta_at', o.eta_at,
               'total', o.total,
               'breaches', to_jsonb(o.breaches),
               'breach_since', o.breach_since,
               'restaurant_id', o.restaurant_id,
               'restaurant_name', o.restaurant_name,
               'restaurant_lat', r.latitude,
               'restaurant_lng', r.longitude,
               'delivery_to', o.delivery_to,
               'delivery_lat', ord.delivery_lat,
               'delivery_lng', ord.delivery_lng,
               'customer_phone', o.customer_phone,
               'rider_email', o.rider_email,
               'rider_name', o.rider_name,
               'delivery_state', o.delivery_state,
               'service_area_id', r.service_area_id)
             order by o.breach_since nulls last, o.placed_at)
        from public.admin_orders(null) o
        join public.restaurants r on r.id = o.restaurant_id
        -- The two coordinates the board has no column for. Joined back to the
        -- table rather than added to `admin_orders`, because a text board has
        -- no use for them and every screen that reads it would pay for them.
        join public.orders ord on ord.id = o.order_id
       where v_area is null or r.service_area_id = v_area), '[]'::jsonb),

    -- Who is actually out there. A position exists only while a job does, so
    -- every rider here has one; the job is joined for the label rather than as
    -- a filter, so a position that outlives its delivery by a few seconds still
    -- draws instead of vanishing.
    'riders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'email', l.partner_email,
               'name', p.name,
               'vehicle', p.vehicle,
               'phone', p.phone,
               'lat', l.lat,
               'lng', l.lng,
               'heading', l.heading,
               'speed_kmh', l.speed_kmh,
               'updated_at', l.updated_at,
               'order_id', d.order_id,
               'delivery_state', d.state)
             order by p.name)
        from public.rider_locations l
        join public.delivery_partners p on p.email = l.partner_email
        left join lateral (
          select d2.order_id, d2.state
            from public.deliveries d2
           where d2.partner_email = l.partner_email
             and d2.state in ('claimed', 'arrived_at_restaurant',
                              'picked_up', 'arrived_at_customer')
           order by d2.claimed_at desc
           limit 1
        ) d on true
        left join public.orders o2 on o2.id = d.order_id
        left join public.restaurants r2 on r2.id = o2.restaurant_id
       where v_area is null
          or r2.service_area_id = v_area
          -- A rider between jobs has no restaurant to be filtered by. Keeping
          -- them out of a town view is right; dropping them from every view
          -- would hide the one rider an admin is looking for.
          or d.order_id is null), '[]'::jsonb),

    -- The riders who are not on the map, and why. Without this the screen says
    -- "no riders" when the truth is "four riders, none of them carrying
    -- anything, and we do not keep the whereabouts of a rider who isn't".
    'fleet', (
      select jsonb_build_object(
        'active', count(*) filter (where p.is_active),
        'online', count(*) filter (where p.is_active and p.is_online),
        'on_a_job', (
          select count(distinct d3.partner_email)
            from public.deliveries d3
           where d3.state in ('claimed', 'arrived_at_restaurant',
                              'picked_up', 'arrived_at_customer')),
        'with_a_position', (select count(*) from public.rider_locations))
        from public.delivery_partners p)
  ) into v_result;

  return v_result;
end;
$fn$;

comment on function public.admin_ops_map(text) is
  '0166: one payload for the operations map — live orders (through admin_orders, so breaches match the board) with both ends of each journey, the riders currently carrying one, the towns, and the fleet counts that explain who is not drawn.';

-- Born executable by PUBLIC *and* with a default grant to `authenticated`
-- (0093). Shut both, reopen the one the console signs in on.
revoke all on function public.admin_ops_map(text) from public, anon, authenticated;
grant execute on function public.admin_ops_map(text) to authenticated;
