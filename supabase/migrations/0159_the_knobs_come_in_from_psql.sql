-- ---------------------------------------------------------------------------
-- 0159 — the knobs come in from psql.
-- ---------------------------------------------------------------------------
-- Four product levers live in tables nothing can read but a psql session:
--
--   * `service_areas` — where Zopiqnow delivers. The memory of this project says
--     it out loud: *where we deliver is data, not code; adding a city is one
--     INSERT and no app release.* That INSERT is still hand-written, which makes
--     opening a town an engineering task rather than a business one.
--   * `dispatch_settings` — 0148's ring: fifteen seconds exclusive, then relay;
--     two riders reaching for one order settled by distance inside two seconds.
--     Four numbers that are the entire feel of the delivery network.
--   * `delivery_surcharge_settings` — 0129's +₹20 after 8pm and +₹20 in rain.
--   * `payment_settings` — 0085's gate.
--
-- Every one of these is a judgement about this town on this evening, not a fact
-- about the software, and each currently costs a migration to change.
--
-- ## Two things this migration found and did not assume
--
-- **The payment gate is already on.** It was armed on 2026-08-29 and the plan
-- this work follows still described it as shipping off. So the screen behind
-- `admin_set_payment_gate` is not a switch waiting to be thrown — it is a switch
-- that is *already thrown*, and the dangerous direction is now off.
--
-- **The rider cash cap is already editable.** `admin_set_rider_cash_cap` (0076)
-- and the Cash screen's own dialog have covered it since before this plan named
-- it as missing. Nothing here touches it.
--
-- ## What never leaves the database
--
-- `delivery_surcharge_settings.weather_api_key` is a secret sitting in an
-- ordinary column. This returns **whether it is set** and never its value —
-- the console has no use for the key, and a settings screen that round-tripped
-- one through a browser would be a credential in a bundle and in every future
-- screenshot of that page.
--
-- The weather columns on `service_areas` are the same shape of problem in the
-- other direction: `raining_until`, `last_precip_mm` and `weather_checked_at`
-- are written by `poll_weather` every five minutes. They are readable here,
-- because "is it raining in Sadri right now" is exactly what somebody turning
-- the rain surcharge off wants to know — and they are not writable, because a
-- value a cron overwrites four minutes later is not a setting.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- The audit trail learns to keep a secret.
-- ---------------------------------------------------------------------------
-- `record_admin_action` writes `to_jsonb(old)` and `to_jsonb(new)` — the whole
-- row, which is the right thing to store, because a dispute is answered by the
-- whole row and not by the columns somebody thought to record.
--
-- It becomes the wrong thing the moment the row has a credential in it.
-- `delivery_surcharge_settings.weather_api_key` is one, sitting in an ordinary
-- text column, and auditing that table unchanged would copy the key into
-- `admin_actions` on every save — a table the console reads, and one this plan
-- intends to put a screen in front of.
--
-- So the helper takes optional extra arguments naming columns to leave out.
-- Additive: all twenty-three existing triggers pass one argument, `tg_nargs` is
-- 1 for them, and the loop below does not run.
create or replace function public.record_admin_action()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_actor text;
  v_old   jsonb;
  v_new   jsonb;
  i       integer;
begin
  -- Whoever the request belonged to. No JWT means a migration, a cron job or a
  -- trigger cascade — `system` says that honestly.
  v_actor := coalesce(
    lower(nullif(trim(coalesce(auth.jwt() ->> 'email', '')), '')),
    'system'
  );

  if tg_op = 'DELETE' then
    v_old := to_jsonb(old);
  elsif tg_op = 'INSERT' then
    v_new := to_jsonb(new);
  else
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
  end if;

  -- Everything after the id column is a column not to keep. `jsonb - text` on a
  -- null is null, so the arm that did not run stays null.
  if tg_nargs > 1 then
    for i in 1 .. tg_nargs - 1 loop
      v_old := v_old - tg_argv[i];
      v_new := v_new - tg_argv[i];
    end loop;
  end if;

  insert into public.admin_actions
    (actor_email, action, target_type, target_id, detail)
  values (
    v_actor,
    lower(tg_op),
    tg_table_name,
    coalesce(v_old, v_new) ->> tg_argv[0],
    case
      when tg_op = 'DELETE' then jsonb_build_object('deleted', v_old)
      when tg_op = 'INSERT' then jsonb_build_object('created', v_new)
      else jsonb_build_object('before', v_old, 'after', v_new)
    end
  );

  -- An `after` trigger's return value is ignored; null is the conventional way
  -- to say so.
  return null;
end;
$fn$;

comment on function public.record_admin_action() is
  '0092, extended by 0159: appends one row to admin_actions. First argument is the id column; any after it name columns to leave out of the record, for rows that carry a credential.';

-- ---------------------------------------------------------------------------
-- Where we deliver.
-- ---------------------------------------------------------------------------
-- The counts are the point. Switching a town off is a decision about the
-- kitchens and the customers in it, and a list of four names with a toggle each
-- gives somebody no way to tell Ghanerao — seeded, never opened, nothing behind
-- it — from Sadri, which has six kitchens and this week's orders.
create or replace function public.admin_service_areas()
returns table (
  id text,
  name text,
  centre_lat double precision,
  centre_lng double precision,
  radius_km numeric,
  is_active boolean,
  -- Ranakpur shares Sadri's catalogue (0126). Null is the normal case: a town
  -- serves its own kitchens.
  catchment_id text,
  catchment_name text,
  restaurant_count bigint,
  live_restaurant_count bigint,
  orders_30d bigint,
  -- Written by `poll_weather`, shown so that switching the rain surcharge is an
  -- informed act. Never written from here.
  raining_until timestamptz,
  last_precip_mm numeric,
  weather_checked_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  perform public.assert_admin();

  return query
  select a.id, a.name, a.centre_lat, a.centre_lng, a.radius_km, a.is_active,
         a.catchment_id, parent.name,
         coalesce(r.total, 0), coalesce(r.live, 0), coalesce(o.n, 0),
         a.raining_until, a.last_precip_mm, a.weather_checked_at, a.created_at
    from public.service_areas a
    left join public.service_areas parent on parent.id = a.catchment_id
    left join lateral (
      select count(*) as total,
             count(*) filter (where x.is_active and x.accepting_orders) as live
        from public.restaurants x
       where x.service_area_id = a.id
    ) r on true
    left join lateral (
      select count(*) as n
        from public.orders ord
        join public.restaurants x on x.id = ord.restaurant_id
       where x.service_area_id = a.id
         and ord.created_at > now() - interval '30 days'
    ) o on true
   order by a.is_active desc, a.name;
end;
$fn$;

comment on function public.admin_service_areas() is
  '0159: every town Zopiqnow serves or has seeded, with what is behind it — kitchens, a month of orders, and whether it is raining there now.';

revoke all on function public.admin_service_areas() from public, anon, authenticated;
grant execute on function public.admin_service_areas() to authenticated;

-- ---------------------------------------------------------------------------
-- Open a town, or move its centre.
-- ---------------------------------------------------------------------------
-- Insert and update are one function because they are one form. The id is a slug
-- derived from the name on insert and immutable after — it is what
-- `restaurants.service_area_id` points at, and a town that could be renamed into
-- a different id would take its kitchens' addresses with it.
create or replace function public.admin_upsert_service_area(p jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_id     text;
  v_name   text;
  v_slug   text;
  v_exists boolean;
begin
  perform public.assert_admin();

  v_id   := nullif(trim(coalesce(p ->> 'id', '')), '');
  v_name := nullif(trim(coalesce(p ->> 'name', '')), '');

  if v_name is null then
    raise exception 'A service area needs a name.' using errcode = 'P0001';
  end if;

  if (p ->> 'radius_km')::numeric <= 0 then
    raise exception 'The radius has to be more than zero kilometres.'
      using errcode = 'P0001';
  end if;

  if v_id is null then
    -- `sadri` from `Sadri`, `mount-abu` from `Mount Abu`. Lowercase, letters and
    -- digits, single hyphens, no leading or trailing one — the shape the four
    -- existing rows already have.
    v_slug := trim(both '-' from
                regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g'));

    if v_slug = '' then
      raise exception 'That name has no letters or digits in it to make an id from.'
        using errcode = 'P0001';
    end if;

    select exists (select 1 from public.service_areas s where s.id = v_slug)
      into v_exists;

    if v_exists then
      raise exception 'There is already a service area called %.', v_name
        using errcode = 'P0001';
    end if;

    insert into public.service_areas
      (id, name, centre_lat, centre_lng, radius_km, is_active, catchment_id)
    values (
      v_slug, v_name,
      (p ->> 'centre_lat')::double precision,
      (p ->> 'centre_lng')::double precision,
      (p ->> 'radius_km')::numeric,
      -- A new town arrives switched **off**. Opening one is two deliberate acts:
      -- draw it, then turn it on once a kitchen is in it. An area that went live
      -- the moment it was saved would put an empty feed in front of customers.
      false,
      nullif(trim(coalesce(p ->> 'catchment_id', '')), '')
    );

    return v_slug;
  end if;

  update public.service_areas
     set name        = v_name,
         centre_lat  = (p ->> 'centre_lat')::double precision,
         centre_lng  = (p ->> 'centre_lng')::double precision,
         radius_km   = (p ->> 'radius_km')::numeric,
         catchment_id = nullif(trim(coalesce(p ->> 'catchment_id', '')), '')
   where id = v_id;

  if not found then
    raise exception 'No such service area.' using errcode = 'P0001';
  end if;

  return v_id;
end;
$fn$;

comment on function public.admin_upsert_service_area(jsonb) is
  '0159: creates a service area (switched off, id slugged from the name) or moves an existing one. The id never changes.';

revoke all on function public.admin_upsert_service_area(jsonb) from public, anon, authenticated;
grant execute on function public.admin_upsert_service_area(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Switch a town on or off.
-- ---------------------------------------------------------------------------
-- Its own function rather than a field on the upsert, for the same reason
-- publishing a restaurant is: this is the one act with a customer on the other
-- end of it, and it should not be reachable by saving a form about a radius.
create or replace function public.admin_set_service_area_active(
  p_id text,
  p_active boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_name text;
  v_live bigint;
begin
  perform public.assert_admin();

  select name into v_name from public.service_areas where id = p_id;
  if v_name is null then
    raise exception 'No such service area.' using errcode = 'P0001';
  end if;

  if p_active then
    -- 0126's town lock means a customer in this area sees this area's kitchens.
    -- Switching on a town with none is a feed with nothing in it, which reads to
    -- a customer as a broken app rather than as a town we do not serve yet.
    select count(*) into v_live
      from public.restaurants x
     where x.service_area_id = p_id and x.is_active and x.accepting_orders;

    if v_live = 0 and not exists (
      select 1 from public.service_areas s
       where s.catchment_id = p_id or s.id = (
         select catchment_id from public.service_areas where id = p_id
       )
    ) then
      raise exception 'No open kitchen serves %, so customers there would see an empty feed. Publish a restaurant into it first, or point it at another town''s catalogue.', v_name
        using errcode = 'P0001';
    end if;
  end if;

  update public.service_areas set is_active = p_active where id = p_id;

  return case when p_active then v_name || ' is open. Customers there can order now.'
              else v_name || ' is closed. Nobody there can place an order.' end;
end;
$fn$;

comment on function public.admin_set_service_area_active(text, boolean) is
  '0159: opens or closes a town. Refuses to open one with no kitchen and no shared catalogue behind it.';

revoke all on function public.admin_set_service_area_active(text, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_service_area_active(text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- The three single-row settings, read together.
-- ---------------------------------------------------------------------------
-- One call because it is one screen. Three round trips to draw four cards would
-- also be three chances to show a page half from before somebody's change and
-- half from after.
create or replace function public.admin_platform_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_result jsonb;
begin
  perform public.assert_admin();

  select jsonb_build_object(
    'dispatch', (
      select to_jsonb(d) from public.dispatch_settings d where d.id = 1
    ),
    'surcharge', (
      select to_jsonb(s) - 'weather_api_key'
             || jsonb_build_object(
                  -- Whether, never what. See the header.
                  'has_weather_key',
                  nullif(trim(coalesce(s.weather_api_key, '')), '') is not null)
        from public.delivery_surcharge_settings s where s.id = 1
    ),
    'payments', jsonb_build_object(
      'require_verified_payment', (
        select p.require_verified_payment from public.payment_settings p
      ),
      -- The number that decides whether turning the gate **on** is safe, and the
      -- number that says what turning it off has been costing. Live orders only:
      -- a finished order's payment is somebody else's problem now.
      'unverified_live_orders', (
        select count(*) from public.orders o
         where o.status not in ('delivered', 'cancelled', 'rejected')
           and o.payment_method = 'upi'
           and not exists (
             select 1 from public.payment_intents pi
              where pi.order_id = o.id and pi.verified_at is not null
           )
      )
    ),
    'cash', jsonb_build_object(
      -- Read-only here. The Cash screen owns this one and has since 0076.
      'cap', (select c.cap from public.rider_cash_policy c where c.id = 1)
    )
  ) into v_result;

  return v_result;
end;
$fn$;

comment on function public.admin_platform_settings() is
  '0159: dispatch, surcharge and payment settings in one object, plus the rider cash cap for reference. Never returns the weather API key.';

revoke all on function public.admin_platform_settings() from public, anon, authenticated;
grant execute on function public.admin_platform_settings() to authenticated;

-- ---------------------------------------------------------------------------
-- The dispatch ring.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_dispatch_settings(p jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_window   integer := (p ->> 'offer_window_seconds')::integer;
  v_contest  numeric := (p ->> 'contest_seconds')::numeric;
  v_first    numeric := (p ->> 'first_radius_km')::numeric;
  v_step     numeric := (p ->> 'radius_step_km')::numeric;
  v_max      numeric := (p ->> 'max_radius_km')::numeric;
  v_widen    integer := (p ->> 'widen_after_seconds')::integer;
  v_stack    numeric := (p ->> 'stack_drop_km')::numeric;
  v_jobs     integer := (p ->> 'max_live_jobs')::integer;
begin
  perform public.assert_admin();

  -- Each of these is a way to stop the network dispatching at all, which is why
  -- they are sentences rather than a check constraint's error code.
  if v_window < 5 or v_window > 120 then
    raise exception 'A rider needs between 5 and 120 seconds to answer an offer.'
      using errcode = 'P0001';
  end if;
  if v_contest < 0 or v_contest > 10 then
    raise exception 'The contest window has to be between 0 and 10 seconds.'
      using errcode = 'P0001';
  end if;
  if v_first <= 0 or v_step <= 0 or v_max <= 0 then
    raise exception 'Every radius has to be more than zero kilometres.'
      using errcode = 'P0001';
  end if;
  if v_max < v_first then
    raise exception 'The widest radius cannot be smaller than the first one.'
      using errcode = 'P0001';
  end if;
  if v_jobs < 1 then
    raise exception 'A rider has to be able to hold at least one job.'
      using errcode = 'P0001';
  end if;

  update public.dispatch_settings
     set offer_window_seconds = v_window,
         contest_seconds      = v_contest,
         first_radius_km      = v_first,
         radius_step_km       = v_step,
         max_radius_km        = v_max,
         widen_after_seconds  = v_widen,
         stack_drop_km        = v_stack,
         max_live_jobs        = v_jobs,
         updated_at           = now()
   where id = 1;

  return 'Dispatch updated. It takes effect on the next order offered.';
end;
$fn$;

comment on function public.admin_set_dispatch_settings(jsonb) is
  '0159: the ring, the relay and the contest window (0148), from a form instead of a migration.';

revoke all on function public.admin_set_dispatch_settings(jsonb) from public, anon, authenticated;
grant execute on function public.admin_set_dispatch_settings(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Night and rain.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_surcharge_settings(p jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_night_amount integer := (p ->> 'night_amount')::integer;
  v_rain_amount  integer := (p ->> 'rain_amount')::integer;
  v_min_mm       numeric := (p ->> 'rain_min_mm')::numeric;
  v_hold         integer := (p ->> 'rain_hold_minutes')::integer;
begin
  perform public.assert_admin();

  if v_night_amount < 0 or v_rain_amount < 0 then
    raise exception 'A surcharge cannot be negative — that would be a discount nobody asked for.'
      using errcode = 'P0001';
  end if;
  if v_night_amount > 200 or v_rain_amount > 200 then
    raise exception 'A surcharge over ₹200 is almost certainly a typo. Refused.'
      using errcode = 'P0001';
  end if;
  if v_min_mm < 0 then
    raise exception 'Rainfall cannot be negative.' using errcode = 'P0001';
  end if;
  if v_hold < 0 then
    raise exception 'The hold cannot be negative.' using errcode = 'P0001';
  end if;

  update public.delivery_surcharge_settings
     set night_from        = (p ->> 'night_from')::time,
         night_to          = (p ->> 'night_to')::time,
         night_amount      = v_night_amount,
         rain_amount       = v_rain_amount,
         rain_min_mm       = v_min_mm,
         rain_hold_minutes = v_hold,
         enabled           = coalesce((p ->> 'enabled')::boolean, true),
         updated_at        = now()
   where id = 1;

  -- Said on every save, because it is the fact most easily forgotten about this
  -- setting and the one a rider would most like to be different (0129).
  return 'Surcharges updated. They ride in surge_fee, and riders are paid none of it.';
end;
$fn$;

comment on function public.admin_set_surcharge_settings(jsonb) is
  '0159: the night and rain surcharges (0129). Never touches the weather API key.';

revoke all on function public.admin_set_surcharge_settings(jsonb) from public, anon, authenticated;
grant execute on function public.admin_set_surcharge_settings(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- The payment gate.
-- ---------------------------------------------------------------------------
-- 0085's trigger refuses an order whose payment has not been verified. It has
-- been **on** since 2026-08-29.
--
-- The console gets this switch because the dangerous direction is now *off*, and
-- off is a thing somebody might genuinely need at three in the morning when
-- Razorpay's verification is down and no order can be placed at all. That is a
-- decision worth making in ten seconds from a screen rather than in ten minutes
-- from a psql prompt somebody has to find the password for.
create or replace function public.admin_set_payment_gate(p_on boolean)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_was boolean;
  v_unverified bigint;
begin
  perform public.assert_admin();

  select require_verified_payment into v_was from public.payment_settings;

  if v_was = p_on then
    return case when p_on then 'The gate was already on.'
                else 'The gate was already off.' end;
  end if;

  update public.payment_settings
     set require_verified_payment = p_on, updated_at = now();

  if p_on then
    return 'Payment verification is on. An order whose payment is not proved will be refused.';
  end if;

  select count(*) into v_unverified
    from public.orders o
   where o.status not in ('delivered', 'cancelled', 'rejected')
     and o.payment_method = 'upi'
     and not exists (
       select 1 from public.payment_intents pi
        where pi.order_id = o.id and pi.verified_at is not null
     );

  return 'Payment verification is OFF. Orders will be accepted without proof that they were paid for — turn this back on as soon as the gateway is healthy. '
    || v_unverified || ' live order(s) currently have no verified payment.';
end;
$fn$;

comment on function public.admin_set_payment_gate(boolean) is
  '0159: arms or disarms 0085''s payment-verification trigger. On since 2026-08-29; the dangerous direction is off.';

revoke all on function public.admin_set_payment_gate(boolean) from public, anon, authenticated;
grant execute on function public.admin_set_payment_gate(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- All four, in the trail.
-- ---------------------------------------------------------------------------
-- 0092's rule: a table joins the audit trail with one line. These are settings
-- that change what customers are charged, whether orders can be placed at all,
-- and which towns can order — every one of them is something a later dispute
-- will ask "who changed this, and when".
--
-- `service_areas` is audited on update only, deliberately: `poll_weather` writes
-- `raining_until` every five minutes on every open town, and auditing that would
-- bury the trail under a thousand rows a day saying it is still not raining.
-- The `when` clause below keeps the weather out of it.

-- Two triggers rather than one `insert or update`, because a `when` clause
-- cannot ask `tg_op` and cannot read `old` on an insert. Splitting them is how
-- the update half gets to name the columns it cares about.
drop trigger if exists service_areas_audit_insert on public.service_areas;
create trigger service_areas_audit_insert
  after insert on public.service_areas
  for each row execute function public.record_admin_action('id');

drop trigger if exists service_areas_audit_update on public.service_areas;
create trigger service_areas_audit_update
  after update on public.service_areas
  for each row
  when (
    old.name is distinct from new.name
    or old.is_active is distinct from new.is_active
    or old.centre_lat is distinct from new.centre_lat
    or old.centre_lng is distinct from new.centre_lng
    or old.radius_km is distinct from new.radius_km
    or old.catchment_id is distinct from new.catchment_id
  )
  execute function public.record_admin_action('id');

drop trigger if exists dispatch_settings_audit on public.dispatch_settings;
create trigger dispatch_settings_audit
  after update on public.dispatch_settings
  for each row execute function public.record_admin_action('id');

drop trigger if exists surcharge_settings_audit on public.delivery_surcharge_settings;
create trigger surcharge_settings_audit
  after update on public.delivery_surcharge_settings
  for each row
  -- The weather poller writes nothing here, but a future one might; keep the
  -- trail to changes a person made.
  when (
    old.night_from is distinct from new.night_from
    or old.night_to is distinct from new.night_to
    or old.night_amount is distinct from new.night_amount
    or old.rain_amount is distinct from new.rain_amount
    or old.rain_min_mm is distinct from new.rain_min_mm
    or old.rain_hold_minutes is distinct from new.rain_hold_minutes
    or old.enabled is distinct from new.enabled
  )
  -- The key is named here so it never reaches `admin_actions`. This is the
  -- reason the helper above grew a second argument.
  execute function public.record_admin_action('id', 'weather_api_key');

drop trigger if exists payment_settings_audit on public.payment_settings;
create trigger payment_settings_audit
  after update on public.payment_settings
  for each row execute function public.record_admin_action('id');
