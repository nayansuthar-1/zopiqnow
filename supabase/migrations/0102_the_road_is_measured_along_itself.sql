-- ---------------------------------------------------------------------------
-- 0102 — the road is measured along itself.
-- ---------------------------------------------------------------------------
-- 0057 gave the platform an arrival time computed from where the rider actually
-- is. It measured the distance left as a **straight line** from the rider to the
-- door, multiplied by a detour factor derived from the order's own two numbers
-- (`route_km / straight_km`, clamped to 1.0–2.5, defaulting to 1.4).
--
-- That factor is a decent guess about a *whole* journey and a poor one about the
-- part of it that is left. A rider one street away with a river between them and
-- the door is 400 m in a straight line and 2 km on the road; a rider on a
-- motorway two-thirds of the way through a long route is closer to straight-line
-- than 1.4 will ever admit. The error is largest exactly where the customer is
-- watching hardest — the last few minutes.
--
-- **We already own the answer and were not reading it.** `orders.route_polyline`
-- is the road Ola measured for this order, stored since 0046 and drawn on the
-- customer's map since 0057. Measuring the rider's progress *along* it costs no
-- API call, no new data and no network — only arithmetic on a string we already
-- have. This migration does that arithmetic in Postgres, which is where the ETA
-- is computed.
--
-- **The rule kept from 0057**, because it is the honest half: when the rider is
-- not on the quoted road, this says so rather than guessing. The corridor is 250
-- metres — the same figure the customer's map uses to decide whether to draw
-- progress along the route — and outside it the ETA falls back to exactly the
-- straight-line estimate it used before. A rider who has taken a different
-- street has not "made progress along this route", and snapping them to a road
-- they are not on would be a confident answer to a question we cannot answer.
-- 0103 is what goes and asks Ola for the road they *are* on.
--
-- Nothing here changes the ETA *rules*: earlier is still free, later still needs
-- a sentence this function can name, and a move under two minutes is still not
-- written at all.

-- ---------------------------------------------------------------------------
-- A. The decoder.
-- ---------------------------------------------------------------------------
-- Google's encoded-polyline format, precision 5 — what Ola's Directions API
-- returns in `overview_polyline` and what the app's own `polyline_codec.dart`
-- decodes on the other side of the wire. The two must agree exactly or the map
-- and the ETA describe different roads, so this is a transcription of that same
-- algorithm rather than a new reading of the spec.
--
-- Flat array, `[lat1, lng1, lat2, lng2, …]`, because the only caller wants to
-- walk it in pairs and an array of composite points would cost a type nobody
-- else needs.
--
-- `result` is bigint on purpose: the shift reaches 30 bits on a large delta and
-- an integer would overflow silently, which decodes as a plausible coordinate
-- somewhere else entirely. Malformed input returns null rather than raising —
-- the caller's fallback is a straight line, which is a worse answer and not a
-- broken screen.
create or replace function public.decode_polyline(p_line text)
returns double precision[]
language plpgsql
immutable
set search_path = public
as $$
declare
  v_deltas bigint[] := '{}';
  v_out    double precision[] := '{}';
  i        integer := 1;
  k        integer;
  n        integer;
  b        integer;
  shift    integer;
  result   bigint;
  v_lat    bigint := 0;
  v_lng    bigint := 0;
begin
  if p_line is null or length(p_line) = 0 then
    return null;
  end if;

  n := length(p_line);

  -- Pass one: the string is a run of variable-length integers, five bits at a
  -- time, low bits first, each byte carrying a continuation flag in bit 6. Read
  -- them all out before deciding what any of them means.
  while i <= n loop
    shift := 0;
    result := 0;
    loop
      if i > n then
        return null;                      -- Truncated mid-number.
      end if;
      b := ascii(substr(p_line, i, 1)) - 63;
      i := i + 1;
      if b < 0 then
        return null;                      -- Not this alphabet.
      end if;
      result := result | ((b & 31)::bigint << shift);
      shift := shift + 5;
      exit when b < 32;
      if shift > 60 then
        return null;                      -- Runaway continuation.
      end if;
    end loop;

    -- Zig-zag: the low bit is the sign, the rest is the magnitude.
    v_deltas := v_deltas ||
      (case when (result & 1) = 1 then ~(result >> 1) else result >> 1 end);
  end loop;

  -- Pass two: they are latitude/longitude deltas in pairs, each relative to the
  -- point before it. An odd count is a malformed line — pairing what is left
  -- would silently swap the axes for the rest of the road.
  n := coalesce(array_length(v_deltas, 1), 0);
  if n < 4 or n % 2 = 1 then
    return null;                          -- Fewer than two points is not a road.
  end if;

  k := 1;
  while k < n loop
    v_lat := v_lat + v_deltas[k];
    v_lng := v_lng + v_deltas[k + 1];
    v_out := v_out || (v_lat / 1e5) || (v_lng / 1e5);
    k := k + 2;
  end loop;

  return v_out;
exception when others then
  return null;
end;
$$;

revoke execute on function public.decode_polyline(text) from public;

-- ---------------------------------------------------------------------------
-- B. How far is left, along the road.
-- ---------------------------------------------------------------------------
-- How far off the quoted road a rider may stray and still be understood as being
-- on it. A constant with a name rather than a number in three places: the map's
-- own `route_progress.dart` uses the same 250 m to decide whether to draw
-- progress, and the two must not drift apart — a map that draws progress while
-- the ETA has given up is a screen disagreeing with itself.
create or replace function public.route_corridor_km()
returns double precision
language sql
immutable
set search_path = public
as $$ select 0.25::double precision $$;

revoke execute on function public.route_corridor_km() from public;

-- Returns kilometres from [p_lat, p_lng] to the end of [p_line], measured along
-- the road; or **null** when the point is further than the corridor from every
-- part of it, which is the caller's signal to fall back rather than to invent.
--
-- The projection is done in a local planar frame centred on the rider — metres,
-- not degrees. A degree of longitude is a different distance from a degree of
-- latitude everywhere except the equator, so comparing raw coordinate deltas
-- would bias every measurement by the cosine of the latitude, which at Sadri's
-- 25°N is a 10% error in the direction that matters most.
--
-- Nearest point on a *segment*, not the nearest vertex: `overview_polyline` is
-- simplified, and its vertices can be several hundred metres apart on a straight
-- road. Snapping to vertices would make a rider mid-segment read as up to a
-- vertex-gap off the route, and the corridor test would start refusing riders
-- who are exactly where they should be.
create or replace function public.route_remaining_km(
  p_line text,
  p_lat  double precision,
  p_lng  double precision
)
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare
  pts       double precision[];
  n         integer;           -- Number of points.
  i         integer;
  kx        double precision;  -- km per degree of longitude, here.
  ky        double precision := 110.574;
  ax        double precision;  ay  double precision;
  bx        double precision;  byy double precision;
  dx        double precision;  dy  double precision;
  t         double precision;
  px        double precision;  py double precision;
  dist      double precision;
  best      double precision := null;
  best_i    integer := null;
  best_t    double precision := null;
  suffix    double precision[];
  total     double precision := 0;
  seg       double precision;
begin
  if p_lat is null or p_lng is null then
    return null;
  end if;

  pts := public.decode_polyline(p_line);
  if pts is null then
    return null;
  end if;

  n := array_length(pts, 1) / 2;
  if n < 2 then
    return null;
  end if;

  kx := 111.320 * cos(radians(p_lat));

  -- One pass to find the segment the rider is nearest to, working in kilometres
  -- relative to the rider, so the rider is the origin and every length below is
  -- already a real distance.
  for i in 1..(n - 1) loop
    ax := (pts[i * 2]     - p_lng) * kx;
    ay := (pts[i * 2 - 1] - p_lat) * ky;
    bx := (pts[i * 2 + 2] - p_lng) * kx;
    byy := (pts[i * 2 + 1] - p_lat) * ky;

    dx := bx - ax;
    dy := byy - ay;

    if dx = 0 and dy = 0 then
      t := 0;                             -- A zero-length segment; A will do.
    else
      -- The rider is the origin, so projecting the origin onto AB is just
      -- -(A·D)/|D|², clamped to the segment's own ends.
      t := least(1, greatest(0, -(ax * dx + ay * dy) / (dx * dx + dy * dy)));
    end if;

    px := ax + t * dx;
    py := ay + t * dy;
    dist := sqrt(px * px + py * py);

    if best is null or dist < best then
      best := dist;
      best_i := i;
      best_t := t;
    end if;
  end loop;

  -- Off the quoted road. Say so; do not snap.
  if best is null or best > public.route_corridor_km() then
    return null;
  end if;

  -- What is left: from the rider's foot on that segment to the segment's far
  -- end, then every segment after it, whole.
  ax := (pts[best_i * 2]     - p_lng) * kx;
  ay := (pts[best_i * 2 - 1] - p_lat) * ky;
  bx := (pts[best_i * 2 + 2] - p_lng) * kx;
  byy := (pts[best_i * 2 + 1] - p_lat) * ky;
  px := ax + best_t * (bx - ax);
  py := ay + best_t * (byy - ay);
  total := sqrt((bx - px) * (bx - px) + (byy - py) * (byy - py));

  for i in (best_i + 1)..(n - 1) loop
    seg := public.delivery_distance_km(
      pts[i * 2 - 1], pts[i * 2], pts[i * 2 + 1], pts[i * 2 + 2]
    );
    total := total + coalesce(seg, 0);
  end loop;

  return round(total::numeric, 3);
exception when others then
  return null;
end;
$$;

revoke execute on function public.route_remaining_km(text, double precision, double precision) from public;

-- ---------------------------------------------------------------------------
-- C. The ETA reads the road.
-- ---------------------------------------------------------------------------
-- The only change to 0057's function is the four lines that decide `v_left_km`
-- for a rider who is carrying. Everything else — the detour factor for the
-- kitchen half, the three nameable reasons, the two-minute deadband, the
-- earlier-is-free rule, the live-card repost — is 0057's and is restated here
-- unchanged because `create or replace` takes a whole body.
--
-- **The fallback is the old behaviour exactly.** No polyline, an undecodable
-- one, or a rider outside the corridor, and this computes the straight line
-- times the detour factor, which is what it did before. So the worst case of
-- this migration is the status quo.
create or replace function public.recompute_order_eta(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o          record;
  v_state    text;
  v_lat      double precision;
  v_lng      double precision;
  v_straight numeric;
  v_factor   numeric;
  v_left_km  numeric;
  v_road     numeric;
  v_ride     integer;
  v_new      timestamptz;
  v_current  timestamptz;
  v_reason   text;
begin
  select ord.id, ord.status, ord.created_at, ord.eta_minutes, ord.ready_by,
         ord.route_km, ord.route_polyline, ord.eta_at,
         ord.delivery_lat, ord.delivery_lng,
         r.latitude as r_lat, r.longitude as r_lng
    into o
    from public.orders ord
    join public.restaurants r on r.id = ord.restaurant_id
   where ord.id = p_order_id;

  if not found or o.status in ('delivered', 'cancelled', 'rejected') then
    return;
  end if;

  if o.delivery_lat is null or o.delivery_lng is null then
    return;
  end if;

  v_current := coalesce(o.eta_at, o.created_at + make_interval(mins => o.eta_minutes));

  select d.state into v_state
    from public.deliveries d
   where d.order_id = p_order_id and d.state <> 'cancelled'
   order by d.claimed_at desc
   limit 1;

  -- The detour factor, from this order's own two measurements.
  v_straight := public.delivery_distance_km(
    o.r_lat, o.r_lng, o.delivery_lat, o.delivery_lng
  );
  v_factor := case
    when o.route_km is null or v_straight is null or v_straight <= 0.2 then 1.4
    else least(2.5, greatest(1.0, o.route_km / v_straight))
  end;

  if coalesce(v_state, '') in ('picked_up', 'arrived_at_customer') then
    select l.lat, l.lng into v_lat, v_lng
      from public.rider_locations l
      join public.deliveries d on d.partner_email = l.partner_email
     where d.order_id = p_order_id and d.state = v_state
     limit 1;

    if v_lat is null then
      return;                       -- Carrying, but nowhere. Leave the promise.
    end if;

    -- The road first, and the straight line only when the road cannot answer.
    v_road := public.route_remaining_km(o.route_polyline, v_lat, v_lng);

    v_left_km := coalesce(
      v_road,
      public.delivery_distance_km(v_lat, v_lng, o.delivery_lat, o.delivery_lng)
        * v_factor
    );

    v_new := now()
      + make_interval(
          mins => ceil(
            (v_left_km / public.rider_city_speed_kmh()) * 60
            + public.handover_minutes()
          )::integer
        );
    v_reason := 'Slower traffic on the route';
  else
    -- Still with the kitchen, or with a rider on the way to it: when the food
    -- is ready, plus the whole ride, plus the handover.
    --
    -- `ready_by` is the kitchen's own commitment, stamped when it accepted with
    -- a prep time (0015). It is null on any order that was accepted without
    -- one, and the fallback has to be chosen carefully: `created_at +
    -- eta_minutes` is the *delivery* promise, not the kitchen's, and adding a
    -- ride on top of it would count the ride twice — a 32-minute promise on a
    -- 12 km route came out as 68 minutes on the first run of this. So the ride
    -- is subtracted back out of the promise instead, which makes the whole
    -- expression collapse to the original promise exactly. No new information,
    -- no new number.
    v_ride := ceil(
      (coalesce(o.route_km, v_straight, 0) / public.rider_city_speed_kmh()) * 60
      + public.handover_minutes()
    )::integer;

    v_new := greatest(
        now(),
        coalesce(
          o.ready_by,
          o.created_at + make_interval(mins => o.eta_minutes - v_ride)
        )
      )
      + make_interval(mins => v_ride);

    -- The two things that can honestly make an order late before it is on a
    -- bike, in the order they become true.
    v_reason := case
      when coalesce(v_state, '') = 'arrived_at_restaurant'
        then 'Your delivery partner is waiting at the restaurant'
      when v_state is null
        then 'Still finding a delivery partner'
      else null
    end;
  end if;

  if v_new is null then
    return;
  end if;

  -- ---------------------------------------------------------------------
  -- The rule. Earlier is free. Later needs a sentence, and a sentence we
  -- actually have — an estimate that would slip for a cause this function
  -- cannot name is not written, and the customer keeps the time they were
  -- given. Under two minutes either way is not written at all, so an ETA does
  -- not twitch while a rider sits at a light.
  -- ---------------------------------------------------------------------
  if v_new < v_current - interval '2 minutes' then
    update public.orders
       set eta_at = v_new, eta_reason = null
     where id = p_order_id;
  elsif v_new > v_current + interval '2 minutes' and v_reason is not null then
    update public.orders
       set eta_at = v_new, eta_reason = v_reason
     where id = p_order_id;
  else
    return;
  end if;

  -- The card redraws. `post_order_live` drops a payload identical to the last
  -- one, so an ETA that did not actually change costs nothing (0052).
  begin
    perform public.post_order_live(
      p_order_id, (select user_id from public.orders where id = p_order_id)
    );
  exception when others then
    null;
  end;
end;
$$;

revoke execute on function public.recompute_order_eta(text) from public;

-- ---------------------------------------------------------------------------
-- The two standing release checks (0087, 0089) must still return zero rows.
-- Three functions are created above and all three are revoked from PUBLIC in
-- the same breath, per 0087's rule.
-- ---------------------------------------------------------------------------
