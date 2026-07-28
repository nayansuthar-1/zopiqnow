-- ---------------------------------------------------------------------------
-- 0059 — the rider gets the road.
-- ---------------------------------------------------------------------------
-- The rider's Navigate button used to hand the job to whatever maps app the
-- phone had. It now opens a map inside the app, and that map needs the one thing
-- `my_deliveries` never returned: the road itself.
--
-- `orders.route_polyline` has been stored since 0046 and read by the customer's
-- tracking screen since 0057. The rider — the person actually riding it — could
-- not see it. One column, added to a function that already returns both ends of
-- the same ride.
--
-- **Dropped and recreated rather than replaced**, because a new column in a
-- `returns table` is a new result type and `create or replace` refuses it. The
-- argument list is unchanged (there isn't one), so this replaces the function
-- rather than creating an overload beside it — the trap 0045 fell into and
-- everything since has been careful to avoid.
--
-- The body is 0025's, unchanged but for the added column. Nothing about who may
-- call it, what it filters, or what it hides changes: the customer's phone
-- number still disappears the moment the job is delivered.

drop function if exists public.my_deliveries();

create function public.my_deliveries()
returns table (
  order_id                 text,
  state                    text,
  order_status             text,
  restaurant_name          text,
  restaurant_lat           double precision,
  restaurant_lng           double precision,
  deliver_to               text,
  deliver_lat              double precision,
  deliver_lng              double precision,
  customer_phone           text,
  total                    integer,
  payment_method           text,
  distance_km              numeric,
  pay_base                 integer,
  pay_per_km               numeric,
  rider_pay                integer,
  claimed_at               timestamptz,
  arrived_at_restaurant_at timestamptz,
  picked_up_at             timestamptz,
  arrived_at_customer_at   timestamptz,
  delivered_at             timestamptz,
  -- The road from the kitchen to the door, encoded, exactly as Ola returned it.
  -- Null until the route lookup comes back (0057 queues it on every order), and
  -- a null here means the rider's map is framed on the two pins with no line
  -- between them — which is the truth at that moment.
  route_polyline           text
)
language plpgsql
stable
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

  return query
    select o.id, d.state, o.status, r.name, r.latitude, r.longitude,
           o.delivery_to, o.delivery_lat, o.delivery_lng,
           case when d.state = 'delivered' then null else o.user_phone end,
           o.total, o.payment_method,
           d.distance_km, d.pay_base, d.pay_per_km, d.rider_pay,
           d.claimed_at, d.arrived_at_restaurant_at,
           d.picked_up_at, d.arrived_at_customer_at, d.delivered_at,
           o.route_polyline
      from public.deliveries d
      join public.orders o on o.id = d.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where d.partner_email = v_rider
       and d.state <> 'cancelled'
     order by d.claimed_at desc;
end;
$$;

grant execute on function public.my_deliveries() to authenticated;
