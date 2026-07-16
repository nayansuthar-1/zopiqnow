-- Step 10, migration 11: the kitchen can stop the queue.
--
-- A restaurant is either taking orders or it is not — the lunch rush is over, the
-- fryer is down, the one cook went home. Until now the only "off" switch was
-- `is_active`, and that is ops delisting a vendor, not a vendor pausing itself for
-- an hour. They are different powers held by different people: `is_active` is not
-- the kitchen's to touch (a restaurant that could delist itself could vanish from
-- the catalog by accident), and this new switch is not ops' to babysit.
--
-- So this is the vendor's own flag, on the vendor's own row, and — like every
-- other thing a vendor may change — it is reached through a function that can
-- write exactly one column, never an `update` policy that RLS cannot stop from
-- reaching `total` or `is_active` the day someone widens it.

-- The column. Default true: a restaurant that has never touched the switch is
-- open, which is what every seeded row and every row written before this
-- migration already means.
alter table public.restaurants
  add column if not exists accepting_orders boolean not null default true;

-- ---------------------------------------------------------------------------
-- The switch: one column, the caller's own restaurant, nothing else.
-- ---------------------------------------------------------------------------
-- Same shape as `set_order_status` (0009), and for the same reason. A vendor
-- pausing orders must not be one `using` clause away from editing their rating or
-- un-delisting themselves, so there is no update grant on `restaurants` for a
-- vendor at all — there is this, which takes a boolean and writes `accepting_orders`.
create or replace function public.set_accepting_orders(p_accepting boolean)
returns boolean
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

  update public.restaurants
     set accepting_orders = p_accepting
   where id = v_restaurant;

  return p_accepting;
end;
$$;

grant execute on function public.set_accepting_orders(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- place_order refuses a closed kitchen.
-- ---------------------------------------------------------------------------
-- Identical to 0005 but for the restaurant lookup, which now reads
-- `accepting_orders` and rejects a paused kitchen with its own sentence. The
-- customer app disables its ADD buttons and greys the card when a restaurant is
-- closed, but that is the client being honest, not the client being trusted: a
-- cart assembled before the kitchen closed, or a request forged past the UI, is
-- stopped here, where the order is actually written.
create or replace function public.place_order(
  p_user_phone       text,   -- the delivery contact, not an identity
  p_restaurant_id    text,
  p_items            jsonb,  -- [{"menu_item_id": "r1-m1", "quantity": 2}, …]
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
  -- Null for the anon key. `security definer` means this function runs as its
  -- owner and RLS would not stop an unauthenticated write, so the check is here.
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

  -- Checked here so the customer gets a sentence, not a constraint violation.
  -- The `prepaid_order_has_a_payment_id` constraint still exists and still
  -- refuses the row — a check the client can read is a check, not a guard.
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

  -- The kitchen has paused. Its own sentence, because "unavailable" (delisted)
  -- and "closed for now" are different facts and the customer app says different
  -- things about them.
  if not v_accepting then
    raise exception 'This restaurant has stopped taking orders for now.'
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

grant execute on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text
) to authenticated;
