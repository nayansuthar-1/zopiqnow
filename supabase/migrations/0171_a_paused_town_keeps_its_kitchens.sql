-- 0171 — a paused town keeps its kitchens.
--
-- **The bug, found from an App Store rejection (2026-10-28, Guideline 2.1).**
-- 0126 derives `restaurants.service_area_id` with `area_for_point`, which only
-- considers *active* towns. So the moment Sadri is switched off, the next touch
-- of any Sadri restaurant row — a vendor pausing orders, the ratings trigger,
-- the statement-level re-sort that fires on the switch itself — rewrites the
-- kitchen's town to null. Switching the town back on does not put it back:
-- `restaurants_resort_service_areas` would, except it fires *before* the
-- restaurants are reconsidered only if something touches `service_areas`
-- again, and the console's toggle is one UPDATE. On 2026-10-27 the owner
-- toggled Sadri off → on → off; by review day all twelve kitchens read null and
-- the demo account's Sadri address drew an empty feed.
--
-- The fix separates two questions 0126 fused:
--   * "Which town is this kitchen in?" — a fact about coordinates. A paused
--     town is still a town. Answered by `town_for_point`, which ignores
--     `is_active`.
--   * "Do we deliver to this customer's point right now?" — gated on
--     `is_active`. Still `area_for_point`, unchanged, still what
--     `delivery_area_check` and the orders trigger use.
-- With that, pausing a town hides its feed (no customer point resolves to it)
-- without un-towning its kitchens, and unpausing it brings the feed straight
-- back.

-- ===========================================================================
-- A. The town a point is in, active or not.
-- ===========================================================================
create or replace function public.town_for_point(
  p_lat double precision,
  p_lng double precision
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(a.catchment_id, a.id)
    from public.service_areas a
   where p_lat is not null
     and p_lng is not null
     and public.delivery_distance_km(a.centre_lat, a.centre_lng, p_lat, p_lng)
         <= a.radius_km
   order by public.delivery_distance_km(a.centre_lat, a.centre_lng, p_lat, p_lng)
   limit 1;
$$;

comment on function public.town_for_point(double precision, double precision) is
  'The catchment id a point falls in, whether or not that town is active. '
  'For placing kitchens; use area_for_point to ask whether we deliver.';

revoke execute on function public.town_for_point(double precision, double precision)
  from public, anon, authenticated;

-- ===========================================================================
-- B. Both 0126 triggers place kitchens by town, not by open-for-business.
-- ===========================================================================
create or replace function public.restaurants_set_service_area()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.service_area_id := public.town_for_point(new.latitude, new.longitude);
  return new;
end;
$$;

create or replace function public.restaurants_resort_service_areas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.restaurants r
     set service_area_id = public.town_for_point(r.latitude, r.longitude)
   where r.service_area_id
         is distinct from public.town_for_point(r.latitude, r.longitude);
  return null;
end;
$$;

-- ===========================================================================
-- C. Put the twelve kitchens back in their towns.
-- ===========================================================================
update public.restaurants r
   set service_area_id = public.town_for_point(r.latitude, r.longitude)
 where r.service_area_id
       is distinct from public.town_for_point(r.latitude, r.longitude);
