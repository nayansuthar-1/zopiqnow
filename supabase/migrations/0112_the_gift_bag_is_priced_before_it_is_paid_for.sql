-- ---------------------------------------------------------------------------
-- 0112 — the gift bag is priced before it is paid for
-- ---------------------------------------------------------------------------
-- Found by the B8 edge-case sweep over the phases since 0093.
--
-- ## What was wrong
--
-- `gift_checkout_page.dart` asked the gateway for `bag.subtotal` — the bag's own
-- arithmetic, which 0096 deliberately made *items only*, because tax is the
-- server's to add. The server then priced the same bag at `subtotal + GST` and
-- wrote that on the order. So the customer was charged the pre-tax figure, the
-- order recorded the tax-inclusive one, and the difference — 18% of every gift
-- sold — was booked as collected and never was.
--
-- The screen was not even quietly wrong: the button read **"Pay ₹500 + GST"**
-- and then charged ₹500. The food side has never had this problem because
-- `bill.total` is tax-inclusive and the cart mirrors `place_order` line for line
-- (0082). Gifts had no mirror on purpose, and no quote either, which left the
-- client with nothing to pay *but* the subtotal.
--
-- ## Why a quote and not a mirror
--
-- The obvious fix is to teach the Dart cart the tax arithmetic. That is the one
-- thing 0096 refused to do, and for a reason that has not changed: the rounding
-- is once per slab and then down to the lines of that slab by largest remainder,
-- and two implementations of that are two implementations that will disagree the
-- first time a bag holds an 18% mug and a 12% scarf. The disagreement would show
-- up as a receipt that does not match the amount charged — the same bug in a
-- smaller size.
--
-- So the price is quoted by the same code that charges it. `gift_bag_quote` is
-- the pricing block lifted out of `place_gift_order`, and `place_gift_order` now
-- calls it rather than keeping a second copy. One implementation, called twice:
-- once to show the customer what they are about to pay, once to write it down.
--
-- ## The temp table is gone with it
--
-- 0096's `_lines` was `drop table if exists` + `create temp table … on commit
-- drop`, carrying a comment about how sensitive that shape is to being called
-- twice in one transaction. A quote *is* a second call, so the arithmetic is
-- expressed as CTEs instead and the question stops existing. The largest-
-- remainder distribution is unchanged, statement for statement.
--
-- ## What this does not do
--
-- It does not verify the payment. `place_gift_order` still takes `p_payment_id`
-- on trust, exactly as it did — `orders_require_verified_payment` (0085) is a
-- trigger on `orders` and there is no equivalent on `gift_orders`. That gap is
-- real and it is B4's, not this migration's: arming the food gate will leave
-- gifts ungated, and it is written down in ZOMATO_PARITY.md so it is armed with
-- the rest rather than discovered afterwards. Charging the right amount and
-- proving the amount was charged are two different jobs; this is the first one.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. What a bag costs.
-- ---------------------------------------------------------------------------
-- Takes ids and quantities, never a price — the client cannot quote itself a
-- total any more than it could before. Returns the lines it priced so that
-- `place_gift_order` has something to write into `gift_order_items` without
-- pricing them a second time.
create or replace function public.gift_bag_quote(
  p_shop_id text,
  p_items   jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop     text;
  v_fee      integer;
  v_lines    jsonb;
  v_subtotal integer;
  v_taxes    integer;
  v_cgst     integer;
  v_sgst     integer;
begin
  select s.name into v_shop
    from public.gift_shops s
   where s.id = p_shop_id and s.is_active;
  if not found then
    raise exception 'That gift shop is not open right now.' using errcode = 'P0001';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Your gift bag is empty.' using errcode = 'P0001';
  end if;

  -- Checked before the join, so a missing or absent quantity gets this sentence
  -- rather than reading as an unavailable item. 0096 cast the field straight to
  -- integer, which left a null quantity to fall through the range check (null is
  -- not `<= 0`) and die on a not-null violation three statements later.
  if exists (
    select 1 from jsonb_array_elements(p_items) as i
     where coalesce((i ->> 'quantity')::integer, 0) not between 1 and 20
  ) then
    raise exception 'Choose between 1 and 20 of each item.' using errcode = 'P0001';
  end if;

  -- 0082's rounding, unchanged in shape: once per slab, then down to the lines
  -- of that slab by largest remainder. Rounding each line alone and summing
  -- gives a different number, and the rate-wise total is what a GST invoice
  -- states.
  with req as (
    select row_number() over ()                as seq,
           i ->> 'gift_item_id'                as gift_item_id,
           (i ->> 'quantity')::integer         as quantity
      from jsonb_array_elements(p_items) as i
  ),
  lines as (
    select r.seq,
           g.id                        as gift_item_id,
           g.name,
           g.price                     as unit_price,
           r.quantity,
           g.price * r.quantity        as line_total,
           g.gst_rate_bps
      from req r
      join public.gift_items g
        on g.id = r.gift_item_id
       and g.shop_id = p_shop_id
       and g.is_available
  ),
  slab as (
    select gst_rate_bps,
           sum(line_total)                                          as base,
           round(sum(line_total) * gst_rate_bps / 10000.0)::integer as tax
      from lines
     group by gst_rate_bps
  ),
  spread as (
    select l.*,
           s.tax as slab_tax,
           case when s.base = 0 then 0
                else (s.tax::bigint * l.line_total) / s.base end as floor_tax,
           case when s.base = 0 then 0
                else (s.tax::bigint * l.line_total) % s.base end as rem
      from lines l
      join slab s on s.gst_rate_bps = l.gst_rate_bps
  ),
  ranked as (
    select sp.*,
           sum(floor_tax) over (partition by gst_rate_bps)                      as total_floor,
           row_number() over (partition by gst_rate_bps order by rem desc, seq) as rn
      from spread sp
  ),
  priced as (
    select seq, gift_item_id, name, unit_price, quantity, line_total, gst_rate_bps,
           (floor_tax + case when rn <= slab_tax - total_floor then 1 else 0 end)::integer
             as tax_amount
      from ranked
  )
  select jsonb_agg(to_jsonb(p) order by p.seq),
         coalesce(sum(p.line_total), 0)::integer,
         coalesce(sum(p.tax_amount), 0)::integer
    into v_lines, v_subtotal, v_taxes
    from priced p;

  if v_lines is null
     or jsonb_array_length(v_lines) <> jsonb_array_length(p_items) then
    raise exception 'Something in your gift bag is no longer available.'
      using errcode = 'P0001';
  end if;

  select delivery_fee into v_fee from public.gift_settings where id;
  v_fee := coalesce(v_fee, 0);

  -- Same split as food, and for the same reason: nothing here crosses a state
  -- line that this schema can see, so IGST stays 0 rather than being guessed.
  v_cgst := round(v_taxes / 2.0)::integer;
  v_sgst := v_taxes - v_cgst;

  return jsonb_build_object(
    'shop_id',      p_shop_id,
    'shop_name',    v_shop,
    'subtotal',     v_subtotal,
    'delivery_fee', v_fee,
    'taxes',        v_taxes,
    'cgst',         v_cgst,
    'sgst',         v_sgst,
    'total',        v_subtotal + v_fee + v_taxes,
    'lines',        v_lines
  );
end;
$$;

comment on function public.gift_bag_quote(text, jsonb) is
  'What a gift bag costs, priced from the catalogue. The only pricing implementation gifts have — place_gift_order calls it too, so the amount shown and the amount charged cannot drift.';

revoke all on function public.gift_bag_quote(text, jsonb) from public, anon;
grant execute on function public.gift_bag_quote(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Buying one, priced by the function above.
-- ---------------------------------------------------------------------------
-- The argument list is unchanged, so this is a genuine replacement and no
-- overload is created (0051). Every check outside the pricing block is where it
-- was: sign-in, ban, idempotent retry, ten an hour, payment present, address.
create or replace function public.place_gift_order(
  p_user_phone      text,
  p_shop_id         text,
  p_items           jsonb,
  p_delivery_to     text,
  p_delivery_notes  text default null,
  p_payment_id      text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     text;
  v_quote    jsonb;
  v_id       text;
  v_notes    text;
  v_existing text;
begin
  v_user := auth.uid()::text;
  if v_user is null then
    raise exception 'Sign in to place an order.' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from auth.users u
     where u.id::text = v_user
       and u.banned_until is not null
       and u.banned_until > now()
  ) then
    raise exception 'This account has been blocked. Contact support@zopiqnow.com.'
      using errcode = 'P0001';
  end if;

  -- The retry answer, before anything else is done. Same key, same order.
  if p_idempotency_key is not null then
    select id into v_existing
      from public.gift_orders
     where user_id = v_user and idempotency_key = p_idempotency_key;
    if found then
      return (
        select jsonb_build_object(
          'id', o.id, 'total', o.total, 'shop_name', o.shop_name,
          'payment_id', o.payment_id, 'delivery_to', o.delivery_to,
          'status', o.status
        ) from public.gift_orders o where o.id = v_existing
      );
    end if;
  end if;

  -- Ten an hour, matching the food ceiling (0090). Free to call and expensive to
  -- answer: every one of these becomes a job for a human being.
  if (
    select count(*) from public.gift_orders g
     where g.user_id = v_user and g.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'That is a lot of orders at once. Try again shortly.'
      using errcode = 'P0001';
  end if;

  -- Nothing is paid in cash (0084). A gift is prepaid or it is not placed.
  if nullif(trim(coalesce(p_payment_id, '')), '') is null then
    raise exception 'This order has not been paid for.' using errcode = 'P0001';
  end if;

  -- Priced here, from the catalogue, at this instant — by the same function the
  -- checkout screen showed the customer a moment ago. It raises the shop-closed,
  -- empty-bag, quantity and availability sentences on the way.
  v_quote := public.gift_bag_quote(p_shop_id, p_items);

  if nullif(trim(coalesce(p_delivery_to, '')), '') is null then
    raise exception 'We need an address to send this to.' using errcode = 'P0001';
  end if;

  v_notes := nullif(trim(coalesce(p_delivery_notes, '')), '');

  insert into public.gift_orders (
    user_id, user_phone, shop_id, shop_name,
    subtotal, delivery_fee, taxes, cgst, sgst, total,
    payment_method, payment_id, delivery_to, delivery_notes, idempotency_key
  ) values (
    v_user, p_user_phone, p_shop_id, v_quote ->> 'shop_name',
    (v_quote ->> 'subtotal')::integer,
    (v_quote ->> 'delivery_fee')::integer,
    (v_quote ->> 'taxes')::integer,
    (v_quote ->> 'cgst')::integer,
    (v_quote ->> 'sgst')::integer,
    (v_quote ->> 'total')::integer,
    'upi', p_payment_id, p_delivery_to, v_notes, p_idempotency_key
  ) returning id into v_id;

  insert into public.gift_order_items
    (order_id, gift_item_id, name, unit_price, quantity, line_total,
     gst_rate_bps, tax_amount)
  select v_id, l.gift_item_id, l.name, l.unit_price, l.quantity, l.line_total,
         l.gst_rate_bps, l.tax_amount
    from jsonb_to_recordset(v_quote -> 'lines') as l(
      gift_item_id text,
      name         text,
      unit_price   integer,
      quantity     integer,
      line_total   integer,
      gst_rate_bps integer,
      tax_amount   integer
    );

  return jsonb_build_object(
    'id', v_id,
    'total', (v_quote ->> 'total')::integer,
    'shop_name', v_quote ->> 'shop_name',
    'payment_id', p_payment_id,
    'delivery_to', p_delivery_to,
    'status', 'placed'
  );
end;
$$;

revoke all on function public.place_gift_order(
  text, text, jsonb, text, text, text, text) from public, anon;
grant execute on function public.place_gift_order(
  text, text, jsonb, text, text, text, text) to authenticated;
