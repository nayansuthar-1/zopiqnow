-- ---------------------------------------------------------------------------
-- 0126 — a kitchen serves its own town.
-- ---------------------------------------------------------------------------
-- 0098 drew a circle around each town and asked "do we deliver to this point?".
-- 0100 asked the same question of the kitchen. Neither ever asked whether the
-- two points were in the *same* town, and the answer today is that they often
-- are not: a customer standing in Sadri sees Hotel Wing Orbit, which is in
-- Falna, 21 km up the road. Both ends pass every check we have. The order is
-- accepted, paid for, and becomes a 21 km inter-town delivery that the fee model
-- was never built for and no Sadri rider is near.
--
-- **The rule this adds: an order is placed inside one town, or it is refused.**
-- Not "within N km" — a radius drawn around the customer would put a Falna
-- kitchen in range of the northern edge of Sadri and out of range of the
-- southern edge, and "why can my neighbour order this and I can't" is a worse
-- conversation than "we're not in your town yet".
--
-- **Ranakpur is the exception, and it is data.** Ranakpur has no kitchens — a
-- strict lock would open the app on an empty screen for everybody in it. So a
-- town may name another town as its *catchment*, and the two share a catalogue:
-- `ranakpur` points at `sadri`, and a Ranakpur customer orders from Sadri's
-- seven kitchens exactly as they do today. Falna is its own catchment and stays
-- separate. The grouping is one column and no deploy:
--
--     update public.service_areas set catchment_id = 'sadri' where id = 'ranakpur';
--     update public.service_areas set catchment_id = null    where id = 'ranakpur';
--
-- **Where this is enforced.** Section E is the truth: a trigger on `orders`,
-- which binds every writer including the build already on somebody's phone.
-- Section D is what stops a customer reaching it — the catalogue filter — and
-- the customer app blocks at checkout *before* the gateway runs, because 0098's
-- warning still holds: every order is prepaid, so a refusal that comes from the
-- trigger comes after the money.

-- ===========================================================================
-- A. A town may share another town's catalogue.
-- ===========================================================================
-- Nullable, and null means "its own". That keeps 0098's promise intact — a
-- fourth town is still a bare INSERT, and it arrives locked to itself rather
-- than silently joining somebody else's catchment. Grouping is the thing you
-- have to say out loud.
--
-- The foreign key is self-referential, because a catchment is named by one of
-- the towns in it. That allows a chain — `a -> b -> c` — which `area_for_point`
-- below would resolve as `a -> b`, quietly splitting a catalogue somebody
-- believed they had merged. So chains are refused outright by the trigger that
-- follows, and one hop is then always the whole answer.
--
-- A trigger and not a CHECK because the rule reads other rows, which a CHECK
-- constraint cannot. It costs nothing: this table is written by hand, perhaps
-- twice a year.
alter table public.service_areas
  add column if not exists catchment_id text
    references public.service_areas(id) on delete set null;

comment on column public.service_areas.catchment_id is
  'The town whose catalogue this town shares. Null = its own. One hop only.';

-- A catchment head must not itself be grouped, and a town other towns point at
-- must not join somebody else's catchment. Both directions, because a chain can
-- be created from either end.
create or replace function public.service_areas_catchment_is_flat()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.catchment_id is not null then
    if new.catchment_id = new.id then
      raise exception 'A town cannot be its own catchment — leave catchment_id null.'
        using errcode = 'P0001';
    end if;
    if exists (select 1 from public.service_areas a
                where a.id = new.catchment_id and a.catchment_id is not null) then
      raise exception
        'Catchments are one hop: % already points at %. Point % there instead.',
        new.catchment_id,
        (select a.catchment_id from public.service_areas a where a.id = new.catchment_id),
        new.id
        using errcode = 'P0001';
    end if;
  end if;

  -- The other direction: a town that other towns point at must stay flat.
  if exists (select 1 from public.service_areas a where a.catchment_id = new.id)
     and new.catchment_id is not null then
    raise exception
      'Other towns share %''s catalogue, so % cannot join another catchment.',
      new.id, new.id
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists service_areas_catchment_is_flat on public.service_areas;
create trigger service_areas_catchment_is_flat
  before insert or update on public.service_areas
  for each row execute function public.service_areas_catchment_is_flat();

revoke execute on function public.service_areas_catchment_is_flat()
  from public, anon, authenticated;

update public.service_areas set catchment_id = 'sadri'
 where id = 'ranakpur' and catchment_id is distinct from 'sadri';

-- ===========================================================================
-- B. Which catalogue does a point belong to?
-- ===========================================================================
-- The catchment id, or null for a point we do not serve at all. Null is the
-- same answer `serviceable_point` gives as false, and callers must treat it that
-- way: `null = null` is not true in SQL, so two unserviceable points are never
-- "in the same town" by accident.
--
-- `limit 1` because the circles do not overlap today and the ordering makes the
-- answer deterministic if somebody ever tunes a radius until they do. Nearest
-- centre wins, which is the answer a person would give.
create or replace function public.area_for_point(
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
     and a.is_active
     and public.delivery_distance_km(a.centre_lat, a.centre_lng, p_lat, p_lng)
         <= a.radius_km
   order by public.delivery_distance_km(a.centre_lat, a.centre_lng, p_lat, p_lng)
   limit 1;
$$;

comment on function public.area_for_point(double precision, double precision) is
  'The catchment id a point belongs to, or null if we do not deliver there.';

-- Called only from the definer functions and triggers below, which run as the
-- owner. The standing rule from 0089: a new function arrives executable by
-- PUBLIC *and* separately granted to `authenticated`, so both routes come off.
revoke execute on function public.area_for_point(double precision, double precision)
  from public, anon, authenticated;

-- A catchment, named for a customer to read. The head town's own name — so a
-- Ranakpur address reads as "Sadri" in the one sentence that needs a town name,
-- which is honest: Sadri is where the food comes from.
create or replace function public.area_display_name(p_area_id text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select a.name from public.service_areas a where a.id = p_area_id;
$$;

revoke execute on function public.area_display_name(text)
  from public, anon, authenticated;

-- ===========================================================================
-- C. Every kitchen carries its town.
-- ===========================================================================
-- A stored column and not a computed one, because the customer app filters the
-- catalogue on it over PostgREST and PostgREST filters columns. Derived data in
-- a column is a staleness risk, and the risk here has exactly one source — the
-- radius of a town changing — so that is the thing that recomputes it. 0098's
-- promise that a radius is one UPDATE and no deploy survives: the UPDATE now
-- re-sorts the kitchens too.
alter table public.restaurants
  add column if not exists service_area_id text;

comment on column public.restaurants.service_area_id is
  'Derived from latitude/longitude by area_for_point. Never write this by hand — '
  'a trigger overwrites it on every insert and update.';

create index if not exists restaurants_service_area_idx
  on public.restaurants (service_area_id) where is_active;

create or replace function public.restaurants_set_service_area()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Unconditional, so the column cannot be set to a town the coordinates do not
  -- support. A vendor updating their own row through the vendor app writes
  -- whatever they like here and it is discarded.
  new.service_area_id := public.area_for_point(new.latitude, new.longitude);
  return new;
end;
$$;

drop trigger if exists restaurants_set_service_area on public.restaurants;
create trigger restaurants_set_service_area
  before insert or update on public.restaurants
  for each row execute function public.restaurants_set_service_area();

revoke execute on function public.restaurants_set_service_area()
  from public, anon, authenticated;

-- The other half: a town that moves, widens, closes or appears re-sorts every
-- kitchen. Statement-level, because tuning a radius is one statement and there
-- are ten restaurants.
--
-- The `is distinct from` is not an optimisation. Without it this rewrites every
-- restaurant row on any touch of `service_areas`, which fires the audit and
-- search-text triggers on all of them and writes a row of noise per kitchen into
-- `admin_actions`.
create or replace function public.restaurants_resort_service_areas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.restaurants r
     set service_area_id = public.area_for_point(r.latitude, r.longitude)
   where r.service_area_id
         is distinct from public.area_for_point(r.latitude, r.longitude);
  return null;
end;
$$;

drop trigger if exists restaurants_resort_service_areas on public.service_areas;
create trigger restaurants_resort_service_areas
  after insert or update or delete on public.service_areas
  for each statement execute function public.restaurants_resort_service_areas();

revoke execute on function public.restaurants_resort_service_areas()
  from public, anon, authenticated;

-- Backfill. The `where` is not decoration: `pg_safeupdate` is loaded for
-- `authenticated` (0086) and a WHERE-less UPDATE is a habit worth not having.
update public.restaurants r
   set service_area_id = public.area_for_point(r.latitude, r.longitude)
 where r.service_area_id
       is distinct from public.area_for_point(r.latitude, r.longitude);

-- ===========================================================================
-- D. The app is told which town it is standing in.
-- ===========================================================================
-- `delivery_area_check` gains a column. Dropped and recreated rather than
-- replaced, because `create or replace function` cannot change a return type.
--
-- **Additive for the builds already installed.** They read `serviceable`,
-- `headline` and `detail` off the row by name and ignore what they do not know,
-- so a phone that never heard of `area_id` behaves exactly as it does today —
-- which is the whole reason section E exists to catch it.
drop function if exists public.delivery_area_check(double precision, double precision);

create function public.delivery_area_check(
  p_lat double precision,
  p_lng double precision
)
returns table (serviceable boolean, headline text, detail text, area_id text)
language sql
stable
security definer
set search_path = public
as $$
  select area.id is not null,
         case when area.id is not null then 'We deliver here'
              else 'We''ll be there soon' end,
         case when area.id is not null
              then 'You''re inside our delivery area.'
              else 'We''re not delivering to this address yet — we''re still '
                   || 'only in ' || public.service_area_names()
                   || '. We''re expanding, and this is high on the list.'
         end,
         area.id
    from (select public.area_for_point(p_lat, p_lng) as id) area;
$$;

comment on function public.delivery_area_check(double precision, double precision) is
  'Do we deliver to this point, what to say about it, and which catchment it is in.';

revoke execute on function public.delivery_area_check(double precision, double precision)
  from public;
grant execute on function public.delivery_area_check(double precision, double precision)
  to anon, authenticated;

-- ===========================================================================
-- E. The refusal.
-- ===========================================================================
-- Restated in full rather than patched, as 0117 did: `create or replace` is the
-- only way to change a body and a reader deserves to see what the function now
-- is.
--
-- Three checks, in the order that produces the most useful sentence. The first
-- two are 0100's and unchanged — "we don't reach your street" and "that kitchen
-- is too far out" send the customer to fix different things. The third is new,
-- and only reachable when both ends are individually fine.
--
-- The comparison is on the catchment, so Ranakpur → Sadri passes and Sadri →
-- Falna does not. Both sides are non-null by the time it runs, because the two
-- checks above have already refused every point `area_for_point` returns null
-- for — but it is written `is distinct from` anyway, since the failure mode of
-- `<>` against a null is to let the order through.
create or replace function public.orders_within_service_area()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r_lat   double precision;
  v_r_lng   double precision;
  v_towns   text;
  v_here    text;
  v_kitchen text;
begin
  v_towns := public.service_area_names();

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

  v_here    := public.area_for_point(new.delivery_lat, new.delivery_lng);
  v_kitchen := public.area_for_point(v_r_lat, v_r_lng);

  if v_here is distinct from v_kitchen then
    raise exception
      'That kitchen is in %, and you''re ordering to %. We deliver within a town, not between towns — please pick a kitchen in %.',
      public.area_display_name(v_kitchen),
      public.area_display_name(v_here),
      public.area_display_name(v_here)
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke execute on function public.orders_within_service_area()
  from public, anon, authenticated;

-- The trigger itself is unchanged — `create or replace function` rebinds it, and
-- dropping and recreating it would only widen the window in which `orders` has
-- no backstop.
