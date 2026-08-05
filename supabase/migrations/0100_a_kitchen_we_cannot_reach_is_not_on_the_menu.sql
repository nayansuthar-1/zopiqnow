-- ---------------------------------------------------------------------------
-- 0100 — a kitchen we cannot reach is not on the menu.
-- ---------------------------------------------------------------------------
-- 0098 drew the boundary around the **delivery address** and stopped there, and
-- the gap showed up the first time somebody stood in Sadri and opened the app:
-- eight of the nine restaurants are 125–134 km away, all of them still on the
-- home feed, and an order from one of them to a Sadri address passed every check
-- we had. The address was serviceable. Nobody asked whether the kitchen was.
--
-- What that order does next is the point. `offer_delivery` measures its ring
-- from the *kitchen*, so a rider standing in Sadri is 130 km outside every ring
-- and is never offered the job. The order is accepted, paid for, and cannot be
-- dispatched to anybody — the failure is silent and it happens after the money.
--
-- Two changes, and both are the same rule the delivery address already obeys.

-- ===========================================================================
-- A. `serviceable_point` has to be callable by the people it now filters.
-- ===========================================================================
-- 0098 revoked it from everybody, which was right when only `delivery_area_check`
-- and a trigger called it. A row-level policy is different: its expression runs
-- as **the querying role**, not as the policy's author, so a policy that calls a
-- function `authenticated` may not execute fails the query outright rather than
-- filtering it.
--
-- Granting it leaks nothing. It answers exactly the question
-- `delivery_area_check` already answers for anybody who asks, signed in or not:
-- do you deliver here?
--
-- **And it has to become `security definer` to be callable at all.** It calls
-- `delivery_distance_km`, which is granted to nobody, and a chain evaluated as
-- the caller needs every link. The alternative — opening the haversine to `anon`
-- as well — hands out a primitive for measuring against any two points we store,
-- to buy nothing. Definer keeps the chain closed and exposes only the boolean.
create or replace function public.serviceable_point(
  p_lat double precision,
  p_lng double precision
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_lat is not null
     and p_lng is not null
     and exists (
       select 1
         from public.service_areas a
        where a.is_active
          and public.delivery_distance_km(a.centre_lat, a.centre_lng,
                                          p_lat, p_lng) <= a.radius_km
     );
$$;

revoke execute on function public.serviceable_point(double precision, double precision)
  from public;
grant execute on function public.serviceable_point(double precision, double precision)
  to anon, authenticated;

-- ===========================================================================
-- B. The catalogue.
-- ===========================================================================
-- Done as a policy rather than in the three places the app queries restaurants,
-- because the app queries restaurants in three places — home, search, and the
-- category lists — and a filter written three times is a filter that will be
-- written twice next time. One policy covers every reader, including ones not
-- written yet.
drop policy if exists "active restaurants are world-readable" on public.restaurants;
create policy "active restaurants we can actually deliver from"
  on public.restaurants for select
  using (
    is_active
    and public.serviceable_point(latitude, longitude)
  );

-- **The history hole this would otherwise open.** Orders join `restaurants` for
-- the name and the photo, and 43 of the 51 orders in this database were placed
-- with kitchens that the policy above now hides. Without this, every one of
-- those turns into a blank card in the customer's own order list — we would have
-- rewritten their history to match a boundary drawn afterwards.
--
-- Policies are OR'd, so this restores exactly those rows and nothing else: a
-- restaurant you have ordered from stays visible to you, wherever it is.
drop policy if exists "a restaurant you ordered from stays readable" on public.restaurants;
create policy "a restaurant you ordered from stays readable"
  on public.restaurants for select
  using (
    exists (
      select 1 from public.orders o
       where o.restaurant_id = restaurants.id
         -- `orders.user_id` is `text`, not `uuid` — the cast is on the uuid so
         -- the comparison stays sargable against the column's own index.
         and o.user_id = auth.uid()::text
    )
  );

-- Staff keep their own restaurant through the policy 0001 gave them, which is
-- untouched: a kitchen outside the delivery area still has a vendor app, still
-- sees its own orders, and is simply not offered to new customers. Closing a
-- restaurant is `is_active`, and this is not that.

-- ===========================================================================
-- C. The backstop, extended.
-- ===========================================================================
-- The trigger checked the drop. It now checks both ends, and names which one
-- failed — "we don't deliver to that address" is a different problem for the
-- customer than "that kitchen is too far away", and telling them the wrong one
-- sends them to change the wrong thing.
create or replace function public.orders_within_service_area()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r_lat  double precision;
  v_r_lng  double precision;
  v_towns  text;
begin
  select string_agg(a.name, ' and ' order by a.name)
    into v_towns
    from public.service_areas a where a.is_active;

  if not public.serviceable_point(new.delivery_lat, new.delivery_lng) then
    raise exception
      'We''re not delivering to that address yet. We''re still only in %, and we''re expanding — we''ll be there soon.',
      v_towns
      using errcode = 'P0001';
  end if;

  select r.latitude, r.longitude into v_r_lat, v_r_lng
    from public.restaurants r where r.id = new.restaurant_id;

  if not public.serviceable_point(v_r_lat, v_r_lng) then
    raise exception
      'That restaurant is outside our delivery area. We only deliver from kitchens in %.',
      v_towns
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke execute on function public.orders_within_service_area()
  from public, anon, authenticated;
