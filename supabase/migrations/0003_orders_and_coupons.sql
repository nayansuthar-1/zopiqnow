-- Step 7, migration 3: coupons, orders, and the two functions that own money.
--
-- The rule this migration exists to enforce: **the client never decides what
-- anything costs.** It sends what the customer picked — restaurant, dish ids,
-- quantities, a coupon code — and the database prices it. If the app claims a
-- ₹320 biryani costs ₹1, `place_order` charges ₹320, because it reads the price
-- from `menu_items` and ignores whatever arrived.
--
-- That is the whole reason this project is on Postgres rather than Firestore:
-- pricing and coupon validation are a transaction, not application code that
-- happens to run somewhere trusted.

-- ---------------------------------------------------------------------------
-- Coupons: the promotions service's rules, as data with constraints.
-- ---------------------------------------------------------------------------
create table if not exists public.coupons (
  code          text primary key,
  min_subtotal  integer not null default 0 check (min_subtotal >= 0),

  -- A rule is flat XOR capped-percent. The same assertion the Dart CouponRule
  -- carried, except here it is the database refusing to store a rule that means
  -- two things at once.
  flat_off      integer check (flat_off > 0),
  percent_off   integer check (percent_off > 0 and percent_off <= 100),
  max_off       integer check (max_off > 0),

  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),

  constraint coupon_is_flat_xor_capped_percent check (
    (flat_off is not null and percent_off is null and max_off is null)
    or
    (flat_off is null and percent_off is not null and max_off is not null)
  )
);

alter table public.coupons enable row level security;

-- Readable so the checkout screen can *advertise* codes. Advertising a coupon
-- and honouring one are different things: honouring happens in validate_coupon.
drop policy if exists "active coupons are world-readable" on public.coupons;
create policy "active coupons are world-readable"
  on public.coupons for select to anon, authenticated using (is_active);

-- ---------------------------------------------------------------------------
-- Orders.
-- ---------------------------------------------------------------------------
create sequence if not exists public.order_seq start 1001;

create table if not exists public.orders (
  id             text primary key default 'ZPQ-' || nextval('public.order_seq'),

  -- The app's auth id today (mock), the Firebase UID once phone auth lands.
  -- Text, not a uuid FK, precisely so that swap does not require a migration.
  user_id        text not null,
  user_phone     text not null,

  restaurant_id  text not null references public.restaurants (id),

  -- Priced by place_order from menu_items — never from the client's numbers.
  subtotal       integer not null check (subtotal >= 0),
  delivery_fee   integer not null check (delivery_fee >= 0),
  taxes          integer not null check (taxes >= 0),
  discount       integer not null default 0 check (discount >= 0),
  total          integer not null check (total >= 0),
  coupon_code    text references public.coupons (code),

  payment_method text not null check (payment_method in ('cod', 'upi')),

  -- The gateway's reference for a prepaid order. Required for 'upi' (see the
  -- check below) and null for cash: nothing has been charged yet.
  payment_id     text,

  -- The address as it was at the time of the order. Denormalized on purpose —
  -- an order must still show where it went after the customer edits or deletes
  -- that address.
  delivery_to    text not null,
  delivery_lat   double precision,
  delivery_lng   double precision,

  eta_minutes    integer not null check (eta_minutes > 0),
  status         text not null default 'placed'
                 check (status in ('placed','accepted','preparing','out_for_delivery','delivered','cancelled')),
  created_at     timestamptz not null default now(),

  -- The total must equal its parts. A bug that mis-sums a bill gets rejected by
  -- the database rather than quietly charging the wrong amount.
  constraint order_total_is_consistent
    check (total = subtotal + delivery_fee + taxes - discount),

  -- A prepaid order without a payment reference is an order nobody paid for.
  constraint prepaid_order_has_a_payment_id
    check (payment_method <> 'upi' or payment_id is not null)
);

create index if not exists orders_user_idx on public.orders (user_id, created_at desc);

create table if not exists public.order_items (
  id            bigserial primary key,
  order_id      text not null references public.orders (id) on delete cascade,
  menu_item_id  text not null references public.menu_items (id),

  -- The name and price *as charged*. A receipt must not change when the vendor
  -- renames a dish or raises its price tomorrow.
  name          text    not null,
  unit_price    integer not null check (unit_price > 0),
  quantity      integer not null check (quantity > 0 and quantity <= 50),
  line_total    integer not null check (line_total > 0),

  constraint line_total_is_consistent check (line_total = unit_price * quantity)
);

create index if not exists order_items_order_idx on public.order_items (order_id);

-- Orders carry a phone number and an address. Nothing reads them directly with
-- the publishable key: RLS is on with no select policy, so the tables are
-- invisible to the client, and the functions below (security definer) are the
-- only way in.
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- ---------------------------------------------------------------------------
-- validate_coupon: the only thing allowed to say what a discount is worth.
-- ---------------------------------------------------------------------------
create or replace function public.validate_coupon(
  p_code     text,
  p_subtotal integer
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.coupons;
  v_discount integer;
begin
  select * into c from public.coupons
    where code = upper(trim(p_code)) and is_active;

  if not found then
    raise exception 'This code isn''t valid.' using errcode = 'P0001';
  end if;

  if p_subtotal < c.min_subtotal then
    raise exception 'Add items worth ₹% more to use %.',
      c.min_subtotal - p_subtotal, c.code using errcode = 'P0001';
  end if;

  v_discount := coalesce(
    c.flat_off,
    least(round(p_subtotal * c.percent_off / 100.0)::integer, c.max_off)
  );

  -- A discount may never exceed the subtotal: no coupon turns an order into a
  -- payout. Cheap to state, catastrophic to omit.
  return least(v_discount, p_subtotal);
end;
$$;

-- ---------------------------------------------------------------------------
-- place_order: prices the cart, re-validates the coupon, writes the order.
-- ---------------------------------------------------------------------------
create or replace function public.place_order(
  p_user_id          text,
  p_user_phone       text,
  p_restaurant_id    text,
  p_items            jsonb,   -- [{"menu_item_id": "r1-m1", "quantity": 2}, …]
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
  v_order_id     text;
  v_subtotal     integer := 0;
  v_delivery_fee integer;
  v_taxes        integer;
  v_discount     integer := 0;
  v_total        integer;
  v_eta          integer;
  v_name         text;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty.' using errcode = 'P0001';
  end if;

  -- Checked here so the customer gets a sentence, not a constraint violation.
  -- The `prepaid_order_has_a_payment_id` constraint still exists and still
  -- refuses the row — a check the client can read is a check, not a guard.
  if p_payment_method = 'upi'
     and (p_payment_id is null or length(trim(p_payment_id)) = 0) then
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  select name, eta_minutes into v_name, v_eta
    from public.restaurants where id = p_restaurant_id and is_active;
  if not found then
    raise exception 'This restaurant isn''t taking orders right now.'
      using errcode = 'P0001';
  end if;

  -- Price every line from menu_items. The join is the enforcement: a dish id
  -- that is unavailable, or belongs to another restaurant, simply does not
  -- match, and the count check below catches it.
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

  -- The pricing rules, server-side. They were placeholders in the client
  -- (flat ₹40, free over ₹500, 5% tax) and they are placeholders here too —
  -- but now there is exactly one copy of them, and it is the one that charges.
  v_delivery_fee := case when v_subtotal >= 500 then 0 else 40 end;
  v_taxes := round(v_subtotal * 0.05)::integer;

  -- Re-validated against the subtotal *we* computed, not the one the client
  -- was shown. A coupon approved for a ₹400 cart cannot ride along on a ₹40 one.
  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_discount := public.validate_coupon(p_coupon_code, v_subtotal);
  end if;

  v_total := v_subtotal + v_delivery_fee + v_taxes - v_discount;

  insert into public.orders (
    user_id, user_phone, restaurant_id,
    subtotal, delivery_fee, taxes, discount, total,
    coupon_code, payment_method, payment_id,
    delivery_to, delivery_lat, delivery_lng, eta_minutes
  ) values (
    p_user_id, p_user_phone, p_restaurant_id,
    v_subtotal, v_delivery_fee, v_taxes, v_discount, v_total,
    nullif(upper(trim(coalesce(p_coupon_code, ''))), ''), p_payment_method, p_payment_id,
    p_delivery_to, p_delivery_lat, p_delivery_lng, v_eta
  ) returning id into v_order_id;

  insert into public.order_items
    (order_id, menu_item_id, name, unit_price, quantity, line_total)
  select v_order_id, menu_item_id, name, unit_price, quantity, line_total
  from _lines;

  -- The receipt. Everything the confirmation screen shows, priced by us.
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

-- The client may call these; it may not touch the tables underneath.
grant execute on function public.validate_coupon(text, integer) to anon, authenticated;
grant execute on function public.place_order(
  text, text, text, jsonb, text, text, double precision, double precision, text, text
) to anon, authenticated;
