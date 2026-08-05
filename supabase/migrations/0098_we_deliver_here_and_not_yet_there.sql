-- ---------------------------------------------------------------------------
-- 0098 — we deliver here, and not yet there.
-- ---------------------------------------------------------------------------
-- Zopiqnow delivers in Sadri and Ranakpur. Until now it delivered anywhere a
-- customer could geocode an address, and ZPQ-1140 is what that looks like in
-- practice: a `route_km` of 174.39, a ₹40 delivery fee, and ₹672 owed to the
-- rider who would have had to ride it. Nothing in the database said no, because
-- nothing in the database had ever been told where we work.
--
-- **The boundary is data, not code.** Two rows in `service_areas`, each a centre
-- and a radius, and a third town is an INSERT rather than a migration. The
-- alternative — a polygon per town — is more faithful to a real boundary and
-- needs PostGIS, a source for the polygons, and somebody to maintain them. A
-- circle around a town of this size is wrong at the edges by a few hundred
-- metres and right everywhere that matters, and it can be tuned by whoever is
-- watching the refusals without waiting for a release.
--
-- **THE SEEDED COORDINATES AND RADII ARE APPROXIMATE AND WANT CONFIRMING.**
-- They put Sadri at 25.1857N 73.4386E and Ranakpur at 25.1153N 73.4714E with a
-- 5 km radius each — enough to cover both towns and most of the road between
-- them, which is about 9 km apart. Check them against where deliveries actually
-- go and adjust; it is one statement and needs no deploy:
--
--     update public.service_areas set radius_km = 6 where id = 'sadri';
--
-- **Where this is enforced, and where it is not.** The trigger below is the
-- backstop, not the gate. Every order is prepaid and goes through the gateway
-- *first* (`CheckoutController.placeOrder`), so an order refused at insert is a
-- customer who has already paid — the worst possible moment to discover we do
-- not deliver to them. The real gate is in the customer app, before the money
-- moves, and it reads `delivery_area_check` below. The trigger exists for the
-- build that is already on somebody's phone and does not know to ask.

-- ===========================================================================
-- A. Where we work.
-- ===========================================================================
create table if not exists public.service_areas (
  id         text primary key,
  name       text        not null,
  centre_lat double precision not null,
  centre_lng double precision not null,
  -- Kilometres, straight line from the centre. `delivery_distance_km` is the
  -- same haversine the rider fee has used since 0043, so "5 km" means the same
  -- thing here as it does on a job card.
  radius_km  numeric(6,2) not null check (radius_km > 0),
  is_active  boolean     not null default true,
  created_at timestamptz not null default now()
);

comment on table public.service_areas is
  'Where Zopiqnow delivers. Circles, not polygons — tune radius_km rather than deploying.';

insert into public.service_areas (id, name, centre_lat, centre_lng, radius_km)
values
  ('sadri',    'Sadri',    25.1857, 73.4386, 5.00),
  ('ranakpur', 'Ranakpur', 25.1153, 73.4714, 5.00)
on conflict (id) do nothing;

-- Readable by everybody, because it is the answer to "do you deliver to me?"
-- and a customer deserves that before they sign in. Written by nobody: 0093's
-- rule is that a new table arrives with write grants to `anon` that RLS hides
-- rather than removes, so they come off explicitly.
alter table public.service_areas enable row level security;

drop policy if exists "anyone may read where we deliver" on public.service_areas;
create policy "anyone may read where we deliver"
  on public.service_areas for select
  using (true);

revoke all on public.service_areas from anon, authenticated;
grant select on public.service_areas to anon, authenticated;

-- ===========================================================================
-- B. Is this point one we deliver to?
-- ===========================================================================
-- Null coordinates are **not** serviceable. Every one of the 51 orders and 5
-- addresses in this database has a point, because the address form refuses to
-- save one the geocoder could not place, so a null here is not a customer in a
-- badly-mapped village — it is a code path that lost the coordinates, and the
-- safe answer to "should we send a rider 174 km" is no.
create or replace function public.serviceable_point(
  p_lat double precision,
  p_lng double precision
)
returns boolean
language sql
stable
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
  from public, anon, authenticated;

-- What the app asks before it takes any money. Returns the answer *and* the
-- sentence, so the wording lives in one place and a change to it does not need
-- three store releases — the same rule 0061 set for the canned messages.
create or replace function public.delivery_area_check(
  p_lat double precision,
  p_lng double precision
)
returns table (serviceable boolean, headline text, detail text)
language sql
stable
security definer
set search_path = public
as $$
  select ok.value,
         case when ok.value then 'We deliver here'
              else 'We''ll be there soon' end,
         case when ok.value
              then 'You''re inside our delivery area.'
              else 'We''re not delivering to this address yet — we''re still '
                   || 'only in ' || (
                     select string_agg(a.name, ' and ' order by a.name)
                       from public.service_areas a where a.is_active
                   )
                   || '. We''re expanding, and this is high on the list.'
         end
    from (select public.serviceable_point(p_lat, p_lng) as value) ok;
$$;

revoke execute on function public.delivery_area_check(double precision, double precision)
  from public, anon;
grant execute on function public.delivery_area_check(double precision, double precision)
  to anon, authenticated;

-- ===========================================================================
-- C. The backstop.
-- ===========================================================================
-- A trigger and not a check inside `place_order`, for the reason 0084 gave when
-- it refused cash the same way: `place_order` is 353 lines that have drifted
-- from this repo four times, and a rule bolted to the table cannot be lost the
-- next time somebody restates the function. It also binds every writer, which
-- is the point of a backstop.
--
-- Existing orders are untouched — this fires on insert only, and a boundary
-- drawn today is not a verdict on last week's deliveries.
--
-- **Which is just as well, because 43 of the 51 would fail it.** Measured, not
-- assumed. The delivery points in this database cluster at 24.5783/72.3109 (23
-- orders) and 24.5881/72.3163 (12) — around Sirohi, roughly 100 km from Sadri,
-- and the reason ZPQ-1140 quoted a 174 km ride. Seven sit at 25.1668/73.4525,
-- which is 2.5 km from the Sadri centre and inside. Six are in Istanbul and one
-- is in Hyderabad, which is what an emulator does when nobody tells it where it
-- is.
--
-- The practical consequence, and it wants reading before the next test order:
-- **whoever has been testing from the Sirohi cluster will be refused after this
-- migration.** That is the feature working. If that location needs to keep
-- working, it is one row and no deploy:
--
--     insert into public.service_areas (id, name, centre_lat, centre_lng, radius_km)
--     values ('sirohi-test', 'Sirohi', 24.5783, 72.3109, 5.00);
create or replace function public.orders_within_service_area()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.serviceable_point(new.delivery_lat, new.delivery_lng) then
    raise exception
      'We''re not delivering to that address yet. We''re still only in %, and we''re expanding — we''ll be there soon.',
      (select string_agg(a.name, ' and ' order by a.name)
         from public.service_areas a where a.is_active)
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_within_service_area on public.orders;
create trigger orders_within_service_area
  before insert on public.orders
  for each row execute function public.orders_within_service_area();

revoke execute on function public.orders_within_service_area()
  from public, anon, authenticated;
