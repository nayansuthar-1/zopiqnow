-- Step, migration 18: the hours a kitchen keeps.
--
-- Phase 3, the availability half. 0011 gave the vendor a *pause* — a live "we've
-- stopped for now" switch the customer sees in real time. This adds the other
-- kind of closed: a *schedule*. A restaurant that serves breakfast only, or shuts
-- on Mondays, should not have to remember to flip the pause every morning and
-- night. It declares its week once, and the week enforces itself.
--
-- Two closednesses, and they stack. The pause (`accepting_orders`) is the
-- kitchen saying "not right now" on top of whatever the schedule says; the
-- schedule is "not at this hour" underneath it. An order has to clear both.
--
-- The rule, as everywhere a vendor touches its own row: no `update` grant on the
-- hours a customer reads. The vendor writes them through one function that
-- replaces its own week and no one else's, and `place_order` — the trust
-- boundary — is the thing that actually refuses an order placed after close.

-- ---------------------------------------------------------------------------
-- The week, one row per day the kitchen is open.
-- ---------------------------------------------------------------------------
-- A day the restaurant is closed is the *absence* of a row, not a row with a
-- flag: "closed Monday" is "no Monday hours", which is also the default state of
-- every restaurant that has never set an hour — so an empty schedule means
-- "always open" (see restaurant_is_open_now), and nothing existing changes the
-- day this lands.
--
-- `day_of_week` is ISO (1 = Monday … 7 = Sunday), to line up with Dart's
-- `DateTime.weekday` and Postgres `isodow` without either side doing modular
-- arithmetic. Same-day windows only for now: `closes > opens`, so a kitchen open
-- until 2am is a limitation this migration names rather than a bug it hides.
create table if not exists public.restaurant_hours (
  restaurant_id text     not null references public.restaurants (id) on delete cascade,
  day_of_week   smallint not null check (day_of_week between 1 and 7),
  opens         time     not null,
  closes        time     not null,

  primary key (restaurant_id, day_of_week),
  constraint hours_open_before_close check (closes > opens)
);

-- Readable by anyone, for an active restaurant — the customer app shows "open
-- until 11 PM" and needs the same rows the vendor edits. Tied to `is_active` like
-- the restaurants policy (0001), so a delisted restaurant's hours go dark with
-- the restaurant itself. The vendor's own restaurant is active, so this same
-- policy is how their editor reads them back.
alter table public.restaurant_hours enable row level security;

drop policy if exists "hours of active restaurants are world-readable" on public.restaurant_hours;
create policy "hours of active restaurants are world-readable"
  on public.restaurant_hours for select to anon, authenticated
  using (
    exists (
      select 1 from public.restaurants r
       where r.id = restaurant_hours.restaurant_id and r.is_active
    )
  );

-- ---------------------------------------------------------------------------
-- The write: a vendor replaces its own week, wholesale.
-- ---------------------------------------------------------------------------
-- Takes the whole week as an array and swaps it in — delete-then-insert in one
-- transaction — because "these are my hours now" is one intent, not seven edits,
-- and a partial write that left Tuesday from last week and Wednesday from this
-- one is a schedule nobody meant. Scoped to `staff_restaurant_id()`; there is no
-- update/insert/delete grant on the table for a vendor, only this.
--
-- The table's own checks (day 1–7, closes > opens) are the guard behind the
-- editor's validation — a check the client can read is a check, not a guard.
create or replace function public.set_restaurant_hours(p_hours jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  delete from public.restaurant_hours where restaurant_id = v_restaurant;

  insert into public.restaurant_hours (restaurant_id, day_of_week, opens, closes)
  select
    v_restaurant,
    (e ->> 'day')::smallint,
    (e ->> 'opens')::time,
    (e ->> 'closes')::time
  from jsonb_array_elements(coalesce(p_hours, '[]'::jsonb)) as e;
end;
$$;

grant execute on function public.set_restaurant_hours(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Is the kitchen open, right now, by its schedule?
-- ---------------------------------------------------------------------------
-- True when there is no schedule at all (an unset week means always open, so
-- every restaurant predating this migration is unaffected), or when the current
-- moment — in India, where the kitchens are — falls inside today's window.
-- `security definer` so `place_order` can ask it about any restaurant; the answer
-- is a boolean about opening hours, which is not a secret.
create or replace function public.restaurant_is_open_now(p_restaurant_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not exists (
      select 1 from public.restaurant_hours
       where restaurant_id = p_restaurant_id
    ) then true
    else exists (
      select 1 from public.restaurant_hours h
       where h.restaurant_id = p_restaurant_id
         and h.day_of_week =
             extract(isodow from (now() at time zone 'Asia/Kolkata'))::int
         and (now() at time zone 'Asia/Kolkata')::time between h.opens and h.closes
    )
  end
$$;

grant execute on function public.restaurant_is_open_now(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- place_order refuses an order placed outside opening hours.
-- ---------------------------------------------------------------------------
-- The whole of 0011's place_order, re-created with one added gate: after the
-- pause check, the schedule check. A cart assembled before close, or a request
-- forged past a client that greyed its button, is stopped here — the same reason
-- the pause check lives here and not only in the app.
create or replace function public.place_order(
  p_user_phone       text,
  p_restaurant_id    text,
  p_items            jsonb,
  p_delivery_to      text,
  p_payment_method   text,
  p_delivery_lat     double precision default null,
  p_delivery_lng     double precision default null,
  p_coupon_code      text default null,
  p_payment_id       text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      text;
  v_order_id     text;
  v_subtotal     integer := 0;
  v_delivery_fee integer;
  v_taxes        integer;
  v_discount     integer := 0;
  v_total        integer;
  v_eta          integer;
  v_name         text;
  v_accepting    boolean;
begin
  v_user_id := auth.uid()::text;
  if v_user_id is null then
    raise exception 'Please sign in to place an order.' using errcode = 'P0001';
  end if;

  if p_user_phone is null or length(trim(p_user_phone)) = 0 then
    raise exception 'We need a phone number for your rider.' using errcode = 'P0001';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty.' using errcode = 'P0001';
  end if;

  if p_payment_method = 'upi'
     and (p_payment_id is null or length(trim(p_payment_id)) = 0) then
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  select name, eta_minutes, accepting_orders
    into v_name, v_eta, v_accepting
    from public.restaurants where id = p_restaurant_id and is_active;
  if not found then
    raise exception 'This restaurant isn''t available right now.'
      using errcode = 'P0001';
  end if;

  if not v_accepting then
    raise exception 'This restaurant has stopped taking orders for now.'
      using errcode = 'P0001';
  end if;

  -- New in 0018: closed by the clock, not the switch. Its own sentence, because
  -- "paused" and "shut for the night" are different facts the customer app says
  -- different things about.
  if not public.restaurant_is_open_now(p_restaurant_id) then
    raise exception 'This restaurant is closed right now. Please check its hours before ordering.'
      using errcode = 'P0001';
  end if;

  create temp table _lines on commit drop as
  select
    m.id           as menu_item_id,
    m.name         as name,
    m.price        as unit_price,
    (i ->> 'quantity')::integer as quantity,
    m.price * (i ->> 'quantity')::integer as line_total
  from jsonb_array_elements(p_items) as i
  join public.menu_items m
    on m.id = (i ->> 'menu_item_id')
   and m.restaurant_id = p_restaurant_id
   and m.is_available;

  if (select count(*) from _lines) <> jsonb_array_length(p_items) then
    raise exception 'Something in your cart is no longer available.'
      using errcode = 'P0001';
  end if;

  select coalesce(sum(line_total), 0) into v_subtotal from _lines;

  v_delivery_fee := case when v_subtotal >= 500 then 0 else 40 end;
  v_taxes := round(v_subtotal * 0.05)::integer;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_discount := public.validate_coupon(p_coupon_code, v_subtotal);
  end if;

  v_total := v_subtotal + v_delivery_fee + v_taxes - v_discount;

  insert into public.orders (
    user_id, user_phone, restaurant_id, restaurant_name,
    subtotal, delivery_fee, taxes, discount, total,
    coupon_code, payment_method, payment_id,
    delivery_to, delivery_lat, delivery_lng, eta_minutes
  ) values (
    v_user_id, p_user_phone, p_restaurant_id, v_name,
    v_subtotal, v_delivery_fee, v_taxes, v_discount, v_total,
    nullif(upper(trim(coalesce(p_coupon_code, ''))), ''), p_payment_method, p_payment_id,
    p_delivery_to, p_delivery_lat, p_delivery_lng, v_eta
  ) returning id into v_order_id;

  insert into public.order_items
    (order_id, menu_item_id, name, unit_price, quantity, line_total)
  select v_order_id, menu_item_id, name, unit_price, quantity, line_total
  from _lines;

  return jsonb_build_object(
    'id', v_order_id,
    'restaurant_name', v_name,
    'delivery_to', p_delivery_to,
    'total', v_total,
    'payment_method', p_payment_method,
    'payment_id', p_payment_id,
    'eta_minutes', v_eta
  );
end;
$$;

grant execute on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text
) to authenticated;
