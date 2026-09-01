-- ---------------------------------------------------------------------------
-- 0152 — the tax inside a gift's delivery fee.
-- ---------------------------------------------------------------------------
-- P13. `gift_bag_quote` returns `total = subtotal + delivery_fee + taxes` and
-- splits `cgst`/`sgst` over `taxes` alone. Every fee on the food path is stored
-- *gross* — the customer pays what the line says — and `orders.tax_on_fees`
-- records the GST already sitting inside it, which is part of the split and
-- part of what the platform owes. The gift path has the same gross fee and no
-- such column, so the GST inside it would be collected and never declared.
--
-- ## Nothing has been under-declared yet, which is the whole reason to fix it now
--
-- `gift_settings.delivery_fee` is ₹0 and all three live gift orders were placed
-- at ₹0, so there has never been anything inside the fee to extract. It becomes
-- a real under-declaration the first time somebody sets a fee, which
-- `admin_set_gift_delivery_fee` (0118) does in one call from the console, with
-- nothing on that screen to suggest a tax half is missing. The cheapest moment
-- to close it is while the arithmetic is still all zeroes.
--
-- ## Nobody pays a rupee more
--
-- `tax_on_fees` is extracted from the fee, not added to it: `f * r / (10000 +
-- r)`, the same inclusive formula the food path uses, at the same 18% —
-- `fee_gst_rate_bps()` — because a delivery is a delivery. The fee, the total
-- and every line are unchanged. What moves is `cgst`/`sgst`, which now sum to
-- the whole liability, and neither is a number any screen shows: both
-- `my_gift_orders` and `admin_gift_orders` return `taxes` and stop there.
--
-- ## The constraint, and what it does not do
--
-- `orders` has carried `order_tax_split_is_consistent` — `cgst + sgst + igst =
-- taxes + tax_on_fees` — since the money model was set, and `gift_orders` never
-- got it. The same check is added here. The three existing rows already satisfy
-- it (90 + 90 + 0 = 180), so it goes on valid and nothing is backfilled.
--
-- **It would not have caught this bug, and it is worth being exact about that.**
-- The old shape wrote `tax_on_fees = 0` and split `cgst`/`sgst` over `taxes`
-- alone, which adds up perfectly — under-declared and internally consistent at
-- the same time. What the check catches is the *next* mistake, which is the more
-- likely one: extracting the fee's tax and forgetting to widen the split, or
-- widening the split and forgetting to record what it covers. Either half alone
-- now fails the insert.
--
-- Nothing at the schema level ties `tax_on_fees` to `delivery_fee` — a check
-- would have to hardcode the rate and would then refuse its own history the day
-- the rate moved. `orders` does not do it either. What guarantees the extraction
-- is that there is one pricing implementation and `place_gift_order` calls it.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Somewhere to record it.
-- ---------------------------------------------------------------------------
alter table public.gift_orders
  add column if not exists tax_on_fees integer not null default 0
    check (tax_on_fees >= 0);

comment on column public.gift_orders.tax_on_fees is
  'The GST already inside delivery_fee, which is stored gross. Part of cgst/sgst/igst, never part of taxes, and never added to total.';

alter table public.gift_orders
  drop constraint if exists gift_order_tax_split_is_consistent;
alter table public.gift_orders
  add constraint gift_order_tax_split_is_consistent
    check (cgst + sgst + igst = taxes + tax_on_fees);

-- ---------------------------------------------------------------------------
-- 2. What a bag costs — the fee's own tax, extracted.
-- ---------------------------------------------------------------------------
-- Replaced whole rather than patched, because there is one pricing
-- implementation and `place_gift_order` calls this one (0112). The argument
-- list is unchanged, so no overload is created (0051).
create or replace function public.gift_bag_quote(
  p_shop_id text,
  p_items   jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop        text;
  v_fee         integer;
  v_lines       jsonb;
  v_subtotal    integer;
  v_taxes       integer;
  v_tax_on_fees integer;
  v_liability   integer;
  v_cgst        integer;
  v_sgst        integer;
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

  -- The tax already inside the gross fee. `f * r / (10000 + r)` and not
  -- `f * r / 10000` — extracting a tax from an inclusive amount, not adding one
  -- to an exclusive one. A gift delivery is a service at 18%, read from the same
  -- function the food path reads so the two rates cannot drift apart.
  v_tax_on_fees := round(v_fee * public.fee_gst_rate_bps()::numeric
                           / (10000 + public.fee_gst_rate_bps()))::integer;

  -- Same split as food, and for the same reason: nothing here crosses a state
  -- line that this schema can see, so IGST stays 0 rather than being guessed.
  -- Over the whole liability now — splitting `taxes` alone left the GST inside
  -- the fee out of the only number that says what is owed.
  v_liability := v_taxes + v_tax_on_fees;
  v_cgst := round(v_liability / 2.0)::integer;
  v_sgst := v_liability - v_cgst;

  -- `tax_on_fees` is not in `taxes` and not in `total`: the fee is gross, so its
  -- tax was charged inside it. Adding it here would bill it twice.
  return jsonb_build_object(
    'shop_id',      p_shop_id,
    'shop_name',    v_shop,
    'subtotal',     v_subtotal,
    'delivery_fee', v_fee,
    'taxes',        v_taxes,
    'tax_on_fees',  v_tax_on_fees,
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
-- 3. Writing it down.
-- ---------------------------------------------------------------------------
-- One column added to the insert. Every check around it is where 0112 left it:
-- sign-in, ban, idempotent retry, ten an hour, payment present, address. The
-- argument list is unchanged, so this too is a replacement and not an overload.
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
    subtotal, delivery_fee, taxes, tax_on_fees, cgst, sgst, total,
    payment_method, payment_id, delivery_to, delivery_notes, idempotency_key
  ) values (
    v_user, p_user_phone, p_shop_id, v_quote ->> 'shop_name',
    (v_quote ->> 'subtotal')::integer,
    (v_quote ->> 'delivery_fee')::integer,
    (v_quote ->> 'taxes')::integer,
    (v_quote ->> 'tax_on_fees')::integer,
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

revoke all on function public.place_gift_order(text, text, jsonb, text, text, text, text)
  from public, anon;
grant execute on function public.place_gift_order(text, text, jsonb, text, text, text, text)
  to authenticated;
