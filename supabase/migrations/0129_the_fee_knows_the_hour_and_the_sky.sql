-- 0129 — the fee knows the hour and the sky.
--
-- Two surcharges on delivery, ₹20 each, and they stack:
--
--   * **night** — an order placed between 20:00 and 06:00, Asia/Kolkata;
--   * **rain**  — an order placed while it is raining on the town the kitchen
--                 is in.
--
-- ---------------------------------------------------------------------------
-- Where the money goes, and why not into `delivery_fee`.
-- ---------------------------------------------------------------------------
-- The ask was "add ₹20 to the delivery charge". It is added to the total the
-- customer pays for delivery either way; the question is only which column
-- carries it, and `surge_fee` — declared, stored, taxed and returned since
-- 0078, and zero on every order ever placed — is the column that already means
-- exactly this. Putting it there buys three things that folding it into
-- `delivery_fee` does not:
--
--   1. **`sum(surge_fee)` is the answer to "what did the weather earn us".**
--      Inside `delivery_fee` the surcharge is indistinguishable from the base
--      ₹40 a week later, and the only way back to it is re-deriving the
--      weather and the clock for every historical order — which is not
--      possible for rain, because the sky is not kept.
--   2. **The tax is already right.** `tax_on_fees` computes the GST inside
--      `delivery_fee + platform_fee + surge_fee` as one gross bucket at the
--      services rate, so a rupee moved between those three is taxed
--      identically. Nothing in the tax arithmetic below is touched.
--   3. **The edit to the two money functions is one line each.** `v_total`
--      already adds `v_surge_fee`, the `insert` already stores it, and
--      `checkout_preflight` already returns it. See section D on why that
--      matters more here than anywhere else in this schema.
--
-- The customer's bill still reads it as part of the cost of delivery — the
-- cart draws it as its own line under "Delivery fee", named for the reason it
-- was charged, which is more honest than a silently larger ₹60.
--
-- ---------------------------------------------------------------------------
-- On the weather, and on a fee that flickers.
-- ---------------------------------------------------------------------------
-- Rain is polled from Open-Meteo (section E) — no API key, no signup, and the
-- three towns cost ~864 calls a day against a 10,000/day allowance. **Its free
-- tier is licensed for non-commercial use**; `weather_api_key` in the settings
-- table exists so that buying their commercial plan is an `update`, not a
-- migration. Read the note in section E before leaving this in production.
--
-- A surcharge that switches on and off with each poll is worse than no
-- surcharge: a customer quoted ₹60 in the cart and charged ₹40 at the door —
-- or the reverse — reads it as the app inventing numbers. So rain does not
-- track the feed minute by minute. A rainy reading sets `raining_until` an
-- hour out and each further rainy reading pushes it out again; the flag falls
-- only after a full hour with no rain in it. That also means a poller that
-- dies stops charging within the hour on its own, rather than leaving the
-- surcharge stuck on until somebody notices.
--
-- The night window is a clock and cannot flicker, but it can be crossed: a cart
-- quoted at 19:59 is charged the surcharge if the order lands at 20:00. That
-- race is seconds wide and already survivable — the payment intent is built
-- from `checkout_preflight`'s total (0120), not from the cart's quote, so the
-- money follows the server both times.

-- ===========================================================================
-- A. The knobs.
-- ===========================================================================
-- Every number a business decision rather than an engineering one, in a row, so
-- that "make it ₹30 in monsoon" is an `update` and not a deploy — the shape
-- `dispatch_settings` (0099) and `rider_pay_rates` (0043) established.
create table if not exists public.delivery_surcharge_settings (
  id                integer primary key default 1 check (id = 1),

  -- The night band, in Asia/Kolkata. `night_to` earlier than `night_from` is
  -- the normal case and means the band wraps midnight.
  night_from        time         not null default '20:00',
  night_to          time         not null default '06:00',
  night_amount      integer      not null default 20 check (night_amount >= 0),

  rain_amount       integer      not null default 20 check (rain_amount >= 0),

  -- How long one rainy reading keeps the surcharge on. The anti-flicker hold
  -- described above; also the blast radius of a dead poller.
  rain_hold_minutes integer      not null default 60 check (rain_hold_minutes > 0),

  -- Millimetres in the reading before we call it rain. A trace of 0.05 is a
  -- damp windscreen, not a reason to charge somebody.
  rain_min_mm       numeric(4,2) not null default 0.20 check (rain_min_mm >= 0),

  -- Null: Open-Meteo's free host. Set: their commercial host, and the key is
  -- sent with every call. Nothing else changes.
  weather_api_key   text,

  -- The kill switch. One `update` turns both surcharges off everywhere —
  -- the cart, the quote and the charge — if the feed or the rule goes wrong.
  enabled           boolean      not null default true,

  updated_at        timestamptz  not null default now()
);

insert into public.delivery_surcharge_settings (id) values (1)
  on conflict (id) do nothing;

-- Read only by the definer functions below; written only by a person at a psql
-- prompt. 0093's rule: a new table arrives with write grants to `anon` that RLS
-- hides rather than removes, so they come off by hand.
alter table public.delivery_surcharge_settings enable row level security;
revoke all on public.delivery_surcharge_settings from anon, authenticated;

-- ===========================================================================
-- B. Where the sky is written down.
-- ===========================================================================
-- On `service_areas` rather than in a table of its own, because there is
-- exactly one current weather per town and it is a property of the town. A
-- history of readings would be a nice thing to have and is not needed by
-- anything here; when something needs it, that is a table, not these columns.
--
-- `service_areas` is world-readable (0098) and these columns go public with it.
-- That is the right side to err on: "why is delivery ₹60" deserves an answer
-- the app can give without asking permission.
alter table public.service_areas
  add column if not exists raining_until      timestamptz,
  add column if not exists weather_checked_at timestamptz,
  add column if not exists last_precip_mm     numeric(5,2),
  add column if not exists weather_request_id bigint;

comment on column public.service_areas.raining_until is
  'Rain surcharge applies while this is in the future. Extended by each rainy '
  'reading; expires on its own, so a dead poller stops charging within the hour.';

comment on column public.service_areas.weather_request_id is
  'In-flight pg_net request, null when nothing is outstanding.';

-- ===========================================================================
-- C. What the surcharge is, right now.
-- ===========================================================================
-- One function, one answer, three callers: the charge (`place_order`), the
-- quote (`checkout_preflight`) and the cart. 0123 is the reason it is one
-- function and not three copies of a rule — a one-rupee disagreement between
-- the quote and the charge is not a rounding bug here, it is a refused payment.
--
-- Returns the parts and not just the total, because the cart names the line it
-- draws: "Night fee", "Rain fee", or both.
--
-- `stable`, and every reader inside a transaction sees the same `now()`, so the
-- fee a row is charged matches the `created_at` stamped on it in the same
-- statement.
create or replace function public.delivery_surcharge_now(p_restaurant_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  s        record;
  v_local  time;
  v_night  integer := 0;
  v_rain   integer := 0;
begin
  select * into s from public.delivery_surcharge_settings where id = 1;

  if not found or not s.enabled then
    return jsonb_build_object('total', 0, 'night', 0, 'rain', 0);
  end if;

  -- The clock the customer is standing in, not the server's UTC.
  v_local := (now() at time zone 'Asia/Kolkata')::time;

  -- A band that wraps midnight is two ranges; one that does not is an
  -- intersection. Written as an `or`/`and` pair rather than a `between` so the
  -- wrap is visible rather than implied.
  if s.night_from > s.night_to then
    if v_local >= s.night_from or v_local < s.night_to then
      v_night := s.night_amount;
    end if;
  else
    if v_local >= s.night_from and v_local < s.night_to then
      v_night := s.night_amount;
    end if;
  end if;

  -- The kitchen's town. Null `service_area_id` — a restaurant whose
  -- coordinates 0127's trigger could not place — is never rained on, which is
  -- the cheap answer and therefore the safe one.
  select case when a.raining_until > now() then s.rain_amount else 0 end
    into v_rain
    from public.restaurants r
    join public.service_areas a on a.id = r.service_area_id
   where r.id = p_restaurant_id;

  v_rain := coalesce(v_rain, 0);

  return jsonb_build_object(
    'total', v_night + v_rain,
    'night', v_night,
    'rain',  v_rain
  );
end;
$$;

-- Born executable by PUBLIC *and* granted to `authenticated` by default —
-- 0087's lesson, and 0089's. Both routes off, then the one that is wanted back
-- on: the cart calls this to draw its bill.
revoke all on function public.delivery_surcharge_now(text)
  from public, anon, authenticated;
grant execute on function public.delivery_surcharge_now(text) to authenticated;

-- ===========================================================================
-- D. The charge and the quote learn about it.
-- ===========================================================================
-- **This section edits the live definitions instead of restating them**, for
-- the reason 0123 spelled out and this migration inherits: `place_order` and
-- `checkout_preflight` are ~300 lines of money arithmetic each, and pasting 600
-- lines into a migration to change one assignment is 600 lines of opportunity
-- to mistranscribe a tax line. This repo has been bitten four times by the file
-- and the database disagreeing.
--
-- Three edits, and every one of them raises if its target is not found, so a
-- future rewrite of either function cannot let this quietly no-op:
--
--   1. `place_order`         — `v_surge_fee := 0;`          becomes the call.
--   2. `checkout_preflight`  — `v_surge_fee` stops being `constant`, which is
--                              what it has been since 0078 (nothing ever
--                              assigned it), so that it can be assigned.
--   3. `checkout_preflight`  — the call, right after the delivery fee.
--
-- Matched by regex rather than by literal text: the two functions space that
-- assignment differently (`v_surge_fee     := 0;` against `v_surge_fee := 0;`),
-- and a literal `replace` that silently matched neither would have shipped a
-- surcharge that is quoted and never charged.
--
-- `create or replace` preserves the ACLs, so 0087's revokes survive.
do $$
declare
  v_def   text;
  v_new   text;
  v_oid   oid;
begin
  -- ---- 1. place_order charges it. -----------------------------------------
  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order';

  v_def := pg_get_functiondef(v_oid);

  if v_def !~ 'v_surge_fee\s*:=\s*0;' then
    raise exception
      'place_order has no `v_surge_fee := 0;` to replace. It was either already '
      'changed or the function was rewritten; read it before re-running this.';
  end if;

  v_new := regexp_replace(
    v_def,
    'v_surge_fee(\s*):=\s*0;',
    'v_surge_fee\1:= (public.delivery_surcharge_now(p_restaurant_id) ->> ''total'')::integer;'
  );
  execute v_new;

  -- ---- 2 & 3. checkout_preflight quotes the same number. -------------------
  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'checkout_preflight';

  v_def := pg_get_functiondef(v_oid);

  if v_def !~ 'v_surge_fee\s+constant integer := 0;' then
    raise exception
      'checkout_preflight does not declare `v_surge_fee` as a constant. Read it '
      'before re-running this.';
  end if;

  if v_def !~ 'v_delivery_fee\s*:=\s*40;' then
    raise exception
      'checkout_preflight has no flat delivery fee to hang the surcharge on. '
      '0123 put it there; read the function before re-running this.';
  end if;

  v_new := regexp_replace(
    v_def,
    'v_surge_fee(\s+)constant integer := 0;',
    'v_surge_fee\1integer := 0;'
  );

  -- Beside the delivery fee, so the next person to read this finds the whole
  -- cost of delivery in one place rather than two hundred lines apart.
  v_new := regexp_replace(
    v_new,
    'v_delivery_fee(\s*):=\s*40;',
    'v_delivery_fee\1:= 40;' || chr(10) ||
    '  v_surge_fee := (public.delivery_surcharge_now(p_restaurant_id) ->> ''total'')::integer;'
  );

  execute v_new;
end $$;

-- ===========================================================================
-- E. The sky, polled.
-- ===========================================================================
-- The 0046 shape exactly: `pg_net` fires, `pg_cron` drives, and there is no
-- Edge Function and therefore no deploy — deliberate, because the deployed
-- functions in this project have gone weeks between pushes and a fee must not
-- wait on one.
--
-- `pg_net` is asynchronous: a call fired on one tick lands in
-- `net._http_response` and is read on a later one. So this collects first and
-- fires second, and rain is known within one tick of falling.
--
-- **On the provider.** Open-Meteo needs no key and no account, which is why it
-- is here — a surcharge that waits on somebody signing up for a weather API is
-- a surcharge that never ships. Their free endpoint is licensed CC-BY 4.0 for
-- *non-commercial* use. Zopiqnow is commercial. The fix is their paid plan:
--
--     update public.delivery_surcharge_settings
--        set weather_api_key = '…' where id = 1;
--
-- which switches the host below to `customer-api.open-meteo.com` and sends the
-- key. Until that is done this is running on the wrong tier — a licence
-- problem, not a technical one, and it is written here rather than left for
-- somebody to discover in a terms-of-service page.
--
-- What counts as rain: millimetres over the threshold, **or** a WMO weather
-- code in the drizzle/rain/shower/thunderstorm bands. Two signals because
-- either alone misses a case — light drizzle can report 0.0 mm, and a code can
-- lag a downpour that the accumulation already shows.
create or replace function public.poll_weather()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s          record;
  a          record;
  v_status   integer;
  v_body     jsonb;
  v_mm       numeric;
  v_code     integer;
  v_wet      boolean;
  v_req      bigint;
  -- 51-57 drizzle, 61-67 rain, 80-82 rain showers, 95-99 thunderstorm.
  v_rain_codes constant integer[] :=
    array[51,53,55,56,57,61,63,65,66,67,80,81,82,95,96,99];
begin
  select * into s from public.delivery_surcharge_settings where id = 1;
  if not found or not s.enabled then
    return;
  end if;

  -- ---- 1. Collect what has come back. -------------------------------------
  for a in
    select id, weather_request_id, weather_checked_at
      from public.service_areas
     where weather_request_id is not null
  loop
    select status_code, content::jsonb into v_status, v_body
      from net._http_response
     where id = a.weather_request_id;

    if not found then
      -- Still in flight, or pruned before we read it. A reading that has been
      -- outstanding for far longer than any call takes is the latter: clear it
      -- so the town is polled again rather than stranded holding a request id
      -- whose answer will never arrive.
      if a.weather_checked_at is null
         or a.weather_checked_at < now() - interval '30 minutes' then
        update public.service_areas
           set weather_request_id = null
         where id = a.id;
      end if;
      continue;
    end if;

    if v_status = 200 then
      v_mm   := (v_body #>> '{current,precipitation}')::numeric;
      v_code := (v_body #>> '{current,weather_code}')::integer;
      v_wet  := coalesce(v_mm, 0) >= s.rain_min_mm
                or coalesce(v_code, -1) = any(v_rain_codes);

      update public.service_areas
         set last_precip_mm     = coalesce(v_mm, 0),
             weather_checked_at = now(),
             weather_request_id = null,
             -- Only ever pushed forward. A dry reading does not clear the
             -- flag — it lets it run out, which is the hour of hysteresis
             -- that keeps the fee from blinking between two page loads.
             raining_until      = case
               when v_wet then now() + make_interval(mins => s.rain_hold_minutes)
               else raining_until
             end
       where id = a.id;
    else
      -- A non-200 says nothing about the weather. Record that we looked, drop
      -- the request, and leave `raining_until` to expire if the feed stays
      -- broken. An outage must not invent rain, and must not cancel it either.
      update public.service_areas
         set weather_checked_at = now(),
             weather_request_id = null
       where id = a.id;
    end if;
  end loop;

  -- ---- 2. Fire for the towns that are due. --------------------------------
  for a in
    select id, centre_lat, centre_lng
      from public.service_areas
     where is_active
       and weather_request_id is null
       and (weather_checked_at is null
            or weather_checked_at < now() - interval '10 minutes')
  loop
    v_req := net.http_get(
      url := case
        when s.weather_api_key is null
          then 'https://api.open-meteo.com/v1/forecast'
          else 'https://customer-api.open-meteo.com/v1/forecast'
      end,
      params := jsonb_strip_nulls(jsonb_build_object(
        'latitude',  a.centre_lat::text,
        'longitude', a.centre_lng::text,
        'current',   'precipitation,weather_code',
        'apikey',    s.weather_api_key
      )),
      timeout_milliseconds := 8000
    );

    update public.service_areas
       set weather_request_id = v_req
     where id = a.id;
  end loop;
end;
$$;

-- Spends an outbound quota and is driven by cron alone. `revoke from public` is
-- not enough on Supabase — the default privileges grant execute to the named
-- roles directly — so all three come off (0087, 0089).
revoke all on function public.poll_weather()
  from public, anon, authenticated;

-- Every five minutes: the collect half of one tick reads what the fire half of
-- the previous one sent, so rain is known within ten minutes of starting and
-- the towns are re-read every ten. 3 towns × 288 ticks is ~864 calls a day.
select cron.unschedule('poll-weather')
 where exists (select 1 from cron.job where jobname = 'poll-weather');

select cron.schedule(
  'poll-weather',
  '*/5 * * * *',
  $$ select public.poll_weather(); $$
);

-- ---------------------------------------------------------------- verification
-- 1. The rule, from the outside. Both must show the surcharge in `surge_fee`
--    and in `total`, and they must agree to the rupee:
--
--      select public.delivery_surcharge_now('<restaurant_id>');
--
-- 2. The night band, without waiting for 8pm — move the band onto the current
--    hour, read it, and put it back:
--
--      update public.delivery_surcharge_settings
--         set night_from = '00:00', night_to = '23:59' where id = 1;
--      select public.delivery_surcharge_now('<restaurant_id>');   -- night: 20
--      update public.delivery_surcharge_settings
--         set night_from = '20:00', night_to = '06:00' where id = 1;
--
-- 3. Rain, without waiting for rain:
--
--      update public.service_areas
--         set raining_until = now() + interval '5 minutes' where id = 'falna';
--      select public.delivery_surcharge_now('<a falna restaurant>');  -- rain: 20
--      update public.service_areas set raining_until = null where id = 'falna';
--
-- 4. The poller, end to end. Run it twice — the first tick fires, the second
--    collects — and every active town must come back with a timestamp:
--
--      select public.poll_weather();
--      select public.poll_weather();
--      select id, last_precip_mm, weather_checked_at, raining_until
--        from public.service_areas order by id;
--
-- 5. The surgery landed in both functions and nowhere else:
--
--      select p.proname,
--             pg_get_functiondef(p.oid) like '%delivery_surcharge_now%' as wired
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('place_order', 'checkout_preflight');
--
-- 6. The grants, per 0087: `delivery_surcharge_now` executable by
--    `authenticated` and by nobody else; `poll_weather` by nobody at all.
--
--      select has_function_privilege('anon',          'public.poll_weather()', 'execute'),
--             has_function_privilege('authenticated', 'public.poll_weather()', 'execute'),
--             has_function_privilege('anon',          'public.delivery_surcharge_now(text)', 'execute'),
--             has_function_privilege('authenticated', 'public.delivery_surcharge_now(text)', 'execute');
