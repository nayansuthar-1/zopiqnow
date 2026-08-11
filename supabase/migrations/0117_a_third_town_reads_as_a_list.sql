-- ---------------------------------------------------------------------------
-- 0117 — a third town, and a sentence that can hold it.
-- ---------------------------------------------------------------------------
-- Falna joins Sadri and Ranakpur. 0098 promised that "a third town is an INSERT
-- rather than a migration" and that promise holds everywhere it matters: the
-- delivery gate (`delivery_area_check`), the insert backstop
-- (`orders_within_service_area`), the restaurant catalogue policy (0100) and
-- rider dispatch (`offer_delivery`) all read `service_areas` at query time, so
-- none of them changes and no app ships to add a city. Section A is the whole
-- feature.
--
-- Section B is the part 0098 did not foresee. It joined the town names with
-- `string_agg(name, ' and ')`, which is correct for exactly two towns and wrong
-- for every other number:
--
--     "we're still only in Falna and Ranakpur and Sadri"
--
-- That string is customer-facing in three places — the address sheet's refusal,
-- the order trigger's two exception messages — and it is the first thing a
-- customer in a town we do not serve reads about us. A fourth town would make it
-- worse. So the join moves into one function that renders a real list, and the
-- two callers ask it instead of building the string themselves.
--
-- **THE SEEDED COORDINATES AND RADIUS ARE APPROXIMATE AND WANT CONFIRMING**, the
-- same caveat 0098 attached to the first two. Falna is placed at 25.2333N
-- 73.2333E — the town centre, near the railway station — with the same 5 km
-- radius as its neighbours, which covers the built-up town with room to spare.
-- It sits about 21 km north-west of Sadri, so the three circles do not touch.
-- Check it against where deliveries actually go and tune it; it is one statement
-- and needs no deploy:
--
--     update public.service_areas set radius_km = 7 where id = 'falna';

-- ===========================================================================
-- A. Falna.
-- ===========================================================================
insert into public.service_areas (id, name, centre_lat, centre_lng, radius_km)
values ('falna', 'Falna', 25.2333, 73.2333, 5.00)
on conflict (id) do nothing;

-- ===========================================================================
-- B. The towns, as a sentence.
-- ===========================================================================
-- "Sadri", "Ranakpur and Sadri", "Falna, Ranakpur and Sadri". Alphabetical, as
-- before, because any other order is a claim about which town matters most.
--
-- Empty is '' and not null: this is concatenated into copy, and `'only in ' ||
-- null` is null, which would blank the entire refusal message rather than one
-- clause of it. There is no state in which `service_areas` is legitimately empty,
-- but a message that survives one is cheaper than finding out.
create or replace function public.service_area_names()
returns text
language sql
stable
security definer
set search_path = public
as $$
  with towns as (
    select array_agg(a.name order by a.name) as names
      from public.service_areas a
     where a.is_active
  )
  select case
           when names is null or cardinality(names) = 0 then ''
           when cardinality(names) = 1 then names[1]
           else array_to_string(names[1:cardinality(names) - 1], ', ')
                || ' and ' || names[cardinality(names)]
         end
    from towns;
$$;

comment on function public.service_area_names() is
  'Active service-area names as English prose: "Falna, Ranakpur and Sadri".';

-- Called only from inside the two `security definer` functions below, which run
-- as the owner and so need no grant of their own. The standing rule: a new
-- function arrives executable by PUBLIC *and* separately granted to
-- `authenticated`, so both routes come off.
revoke execute on function public.service_area_names() from public, anon, authenticated;

-- ===========================================================================
-- C. The two callers, restated.
-- ===========================================================================
-- Identical to 0098/0100 but for the one subquery each. Restated in full rather
-- than patched, because `create or replace` is the only way to change a function
-- body and a reader deserves to see what the function now is.
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
                   || 'only in ' || public.service_area_names()
                   || '. We''re expanding, and this is high on the list.'
         end
    from (select public.serviceable_point(p_lat, p_lng) as value) ok;
$$;

revoke execute on function public.delivery_area_check(double precision, double precision)
  from public, anon;
grant execute on function public.delivery_area_check(double precision, double precision)
  to anon, authenticated;

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

  return new;
end;
$$;

revoke execute on function public.orders_within_service_area()
  from public, anon, authenticated;

-- The trigger itself is unchanged — `create or replace function` rebinds it, and
-- dropping and recreating the trigger would only widen the window in which
-- `orders` has no backstop.
