-- Step 7, migration 5: order history — a customer may read their own orders.
--
-- 0003 left `orders` and `order_items` with RLS on and *no* select policy, so
-- the tables were invisible to the client and `place_order` was the only way
-- in. That was right for writes and wrong for reads. The reason money moves
-- through a `security definer` function is that **the client must not decide
-- what anything costs** — an argument about pricing, not about visibility. It
-- says nothing about a customer reading a receipt they already paid for.
--
-- So the read is a policy, not another function: `auth.uid()` is the truth here
-- exactly as it is in `place_order`, RLS is the mechanism Postgres has for
-- "your own rows", and PostgREST gives us ordering, pagination, and the items
-- embedded in one round trip instead of a hand-rolled jsonb builder.
--
-- Nothing here grants insert, update, or delete. An order is written by
-- `place_order` and is thereafter immutable to the customer: a client that can
-- edit an order's total is a client that can decide what it pays.

-- ---------------------------------------------------------------------------
-- A receipt must not depend on the catalog still listing the restaurant.
-- ---------------------------------------------------------------------------
-- `orders` carries `restaurant_id` and nothing else about the vendor, while the
-- restaurants policy is `using (is_active)` — so a delisted restaurant becomes
-- unreadable and every past order of theirs would render with a blank name.
-- `order_items` already denormalizes `name` and `unit_price` for this exact
-- reason ("a receipt must not change when the vendor renames a dish"). The
-- restaurant's name is no different, and `delivery_to` is the same idea again.
--
-- The image is deliberately *not* copied: it is decoration, it 404s on its own
-- schedule, and the UI already falls back to a gradient when it is missing. A
-- name is what makes the row mean anything.
alter table public.orders
  add column if not exists restaurant_name text;

update public.orders o
   set restaurant_name = r.name
  from public.restaurants r
 where r.id = o.restaurant_id
   and o.restaurant_name is null;

-- Safe: every order references a restaurant (FK), so the backfill above leaves
-- no nulls behind.
alter table public.orders
  alter column restaurant_name set not null;

-- ---------------------------------------------------------------------------
-- place_order writes the name it already looked up.
-- ---------------------------------------------------------------------------
-- Identical to 0004 but for the two lines that persist `v_name`, which the
-- function has always had in hand — it returns it in the receipt.
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

-- ---------------------------------------------------------------------------
-- The read policies.
-- ---------------------------------------------------------------------------
-- `auth.uid()` is a uuid and `user_id` is text (0003 kept it text so the auth
-- swap needed no migration), hence the cast. It is on the *left* of nothing:
-- the comparison stays sargable against `orders_user_idx (user_id, created_at)`
-- because the cast is on the constant side.
--
-- `to authenticated` and not `anon`: a signed-out caller has no uid, so the
-- predicate would be null-false anyway, but a policy that says who it is for is
-- a policy the next person can read.
drop policy if exists "customers read their own orders" on public.orders;
create policy "customers read their own orders"
  on public.orders for select to authenticated
  using (user_id = auth.uid()::text);

-- The items of an order the caller is allowed to see. The subquery is evaluated
-- with the caller's own privileges, so the policy above applies to it too —
-- which is the point: there is exactly one definition of "my order", and this
-- one defers to it rather than restating `user_id = auth.uid()` and drifting.
drop policy if exists "customers read their own order items" on public.order_items;
create policy "customers read their own order items"
  on public.order_items for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = order_items.order_id
         and o.user_id = auth.uid()::text
    )
  );

-- Select only. Insert/update/delete stay unreachable: `place_order` owns writes.
grant select on public.orders to authenticated;
grant select on public.order_items to authenticated;
