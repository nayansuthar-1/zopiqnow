-- ---------------------------------------------------------------------------
-- 0086 — placing the same order twice places it once. (launch C4, audit CUS-005)
-- ---------------------------------------------------------------------------
-- `place_order` has no idempotency. A double-tap, or a retry after a response
-- was lost on a bad connection, is two orders: the RPC ran, the row exists, the
-- phone never heard back, and the customer presses the button again.
--
-- **What that costs has changed since the audit was written, and it is worth
-- being precise about.** With 0085's payment gate armed, the second attempt does
-- not double-charge — the intent is already `consumed`, so the trigger refuses
-- it. But it refuses it with "We couldn't confirm your payment", which is the
-- single most alarming thing to show somebody whose payment worked perfectly.
-- With the gate still off, as it is today, the second attempt simply creates a
-- second order against the same payment. Neither is acceptable and both have the
-- same fix.
--
-- **The fix is a key the client chooses, not a shape the server guesses.** Two
-- genuinely separate orders of the same food, to the same address, minutes
-- apart, are a thing people really do — a natural key over the contents would
-- refuse the second one and be wrong. Only the caller knows whether this is a
-- retry or a new intent, so the caller names it: one UUID per checkout attempt,
-- reused verbatim on every retry of that attempt and never again after it
-- succeeds.
--
-- Three parts:
--
--   1. `orders.idempotency_key`, and a unique index over (user_id, key). Scoped
--      to the customer because a key is only ever unique within the client that
--      made it up, and a global unique index would let one customer's UUID
--      collide with another's.
--   2. A pre-check at the top of `place_order`: a key that already has an order
--      returns *that order's receipt*, byte for byte what the first call
--      returned, and does nothing else. No second row, no second redemption, no
--      second notification.
--   3. The insert wrapped so a lost race reads back the winner's row instead of
--      failing. The pre-check alone is not enough — two retries that arrive
--      together both find nothing — and the unique index is what actually
--      decides. Losing that race must not cost the customer an order they have
--      already paid for.
--
-- **The whole function is restated, and that is deliberate.** Adding a parameter
-- makes a new signature rather than replacing the old one, so the old one is
-- dropped explicitly below — leaving both would let PostgREST bind a call to
-- whichever it liked, which is exactly how this repo has been bitten before.
-- The body below was taken from `pg_get_functiondef` against the live database
-- rather than from the repo's own migration history, because the two have
-- drifted four times and the database is the one that is true.
--
-- Reversing this: drop the new signature, restore the old one from 0082, drop
-- the column. The key is additive and nothing reads it but this function.
-- ---------------------------------------------------------------------------

alter table public.orders
  add column if not exists idempotency_key text;

comment on column public.orders.idempotency_key is
  'Launch C4 / audit CUS-005: caller-chosen key, one per checkout attempt. Null for orders placed before 0086 and for any caller that omits it.';

-- Partial, so the thousands of existing rows with a null key do not collide with
-- each other. Unique per customer, not globally — see the header.
create unique index if not exists orders_idempotency_key_unique
  on public.orders (user_id, idempotency_key)
  where idempotency_key is not null;

-- Used by `place_order` twice: once before inserting and once when it loses the
-- race. Kept as its own function so the two callers cannot drift apart, and so
-- the shape of a receipt is written down in exactly one place.
create or replace function public.order_receipt_by_key(
  p_user_id text,
  p_key     text
)
returns jsonb
language sql
security definer
set search_path to 'public'
stable
as $$
  select jsonb_build_object(
    'id', o.id,
    'restaurant_name', o.restaurant_name,
    'delivery_to', o.delivery_to,
    'total', o.total,
    'payment_method', o.payment_method,
    'payment_id', o.payment_id,
    'eta_minutes', o.eta_minutes
  )
  from public.orders o
  where o.user_id = p_user_id
    and o.idempotency_key = p_key
  limit 1;
$$;

revoke all on function public.order_receipt_by_key(text, text) from anon, authenticated;

-- The old ten-argument signature. Dropped *after* the new one is created would
-- be safer still, but a drop of a function PostgREST may be mid-call on is
-- momentary and this runs in one transaction.
drop function if exists public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text, text
);

CREATE OR REPLACE FUNCTION public.place_order(p_user_phone text, p_restaurant_id text, p_items jsonb, p_delivery_to text, p_payment_method text, p_delivery_lat double precision DEFAULT NULL::double precision, p_delivery_lng double precision DEFAULT NULL::double precision, p_coupon_code text DEFAULT NULL::text, p_payment_id text DEFAULT NULL::text, p_delivery_notes text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_existing      jsonb;
  v_user_id       text;
  v_order_id      text;
  v_subtotal      integer := 0;
  v_delivery_fee  integer;
  v_platform_fee  integer := 0;
  v_packaging_fee integer := 0;
  v_surge_fee     integer := 0;
  v_taxes         integer;
  v_tax_on_fees   integer;
  v_liability     integer;
  v_cgst          integer;
  v_sgst          integer;
  v_igst          integer := 0;
  v_discount      integer := 0;
  v_funded_by     text;
  v_max_per_user  integer;
  v_total         integer;
  v_eta           integer;
  v_name          text;
  v_state         text;
  v_accepting     boolean;
  v_pause_reason  text;
  v_notes         text;
  v_line          jsonb;
  v_seq           integer;
  v_mi_id         text;
  v_mi_name       text;
  v_base          integer;
  v_rate_bps      integer;
  v_hsn           text;
  v_serve_from    time;
  v_serve_to      time;
  v_qty           integer;
  v_opt_ids       text[];
  v_opts          jsonb;
  v_addons        integer;
  v_unit          integer;
  v_line_total    integer;
  v_line_id       bigint;
  v_row           record;
begin
  v_user_id := auth.uid()::text;
  if v_user_id is null then
    raise exception 'Please sign in to place an order.' using errcode = 'P0001';
  end if;

  -- Already done? A retry names the same key, and the honest answer to "place
  -- this order" when it is already placed is the order, not a second one.
  if p_idempotency_key is not null then
    v_existing := public.order_receipt_by_key(v_user_id, p_idempotency_key);
    if v_existing is not null then
      return v_existing;
    end if;
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

  -- Trimmed and truncated rather than refused. A note is a courtesy the customer
  -- typed on the way past; failing an order over its length would be absurd.
  v_notes := nullif(trim(coalesce(p_delivery_notes, '')), '');
  v_notes := left(v_notes, 160);

  select name, eta_minutes, accepting_orders, pause_reason, nullif(state, '')
    into v_name, v_eta, v_accepting, v_pause_reason, v_state
    from public.restaurants where id = p_restaurant_id and is_active;
  if not found then
    raise exception 'This restaurant isn''t available right now.'
      using errcode = 'P0001';
  end if;

  if not v_accepting then
    if coalesce(v_pause_reason, '') <> '' then
      raise exception 'This restaurant has stopped taking orders: %', v_pause_reason
        using errcode = 'P0001';
    end if;
    raise exception 'This restaurant has stopped taking orders for now.'
      using errcode = 'P0001';
  end if;

  if not public.restaurant_is_open_now(p_restaurant_id) then
    raise exception 'This restaurant is closed right now. Please check its hours before ordering.'
      using errcode = 'P0001';
  end if;

  -- Pass one: price every line into a scratch table, options and all, and total
  -- the subtotal — without touching `orders` yet, so an invalid coupon below is
  -- still answered with a sentence rather than a foreign-key violation.
  create temp table _lines (
    seq            integer,
    menu_item_id   text,
    name           text,
    unit_price     integer,
    quantity       integer,
    line_total     integer,
    options        jsonb,
    gst_rate_bps   integer,
    hsn_code       text,
    discount_alloc integer default 0,
    taxable_value  integer,
    tax_amount     integer
  ) on commit drop;

  for v_line, v_seq in
    select value, ordinality from jsonb_array_elements(p_items) with ordinality
  loop
    v_qty := (v_line ->> 'quantity')::integer;
    if v_qty is null or v_qty < 1 then
      raise exception 'Your cart has an invalid quantity.' using errcode = 'P0001';
    end if;

    select id, name, price, serve_from, serve_to, gst_rate_bps, hsn_code
      into v_mi_id, v_mi_name, v_base, v_serve_from, v_serve_to, v_rate_bps, v_hsn
      from public.menu_items
     where id = (v_line ->> 'menu_item_id')
       and restaurant_id = p_restaurant_id
       and is_available;
    if not found then
      raise exception 'Something in your cart is no longer available.'
        using errcode = 'P0001';
    end if;

    -- New in 0068. Its own sentence rather than the generic one above, because
    -- "sold out" and "not served at this hour" send the customer to different
    -- places: one is a different dish, the other is a different time.
    if not public.menu_item_is_servable_now(v_serve_from, v_serve_to) then
      raise exception '% isn''t served at this hour.', v_mi_name
        using errcode = 'P0001';
    end if;

    -- The claimed options for this line (absent → empty → all defaults filled).
    v_opt_ids := coalesce(
      (select array_agg(value)
         from jsonb_array_elements_text(coalesce(v_line -> 'option_ids', '[]'::jsonb))),
      array[]::text[]
    );

    -- Resolve once into what is actually charged (name + delta, frozen), then
    -- price off that so the sum and the stored choices can never disagree.
    select coalesce(
             jsonb_agg(jsonb_build_object('name', option_name, 'price_delta', price_delta)),
             '[]'::jsonb
           )
      into v_opts
      from public.resolve_order_line_options(v_mi_id, v_opt_ids);

    v_addons := coalesce(
      (select sum((e ->> 'price_delta')::integer)
         from jsonb_array_elements(v_opts) as e),
      0
    );

    -- `price`, not `original_price`. Said here because this is the line where
    -- the display-only column would do damage if it ever crept in.
    v_unit := v_base + v_addons;
    v_line_total := v_unit * v_qty;
    v_subtotal := v_subtotal + v_line_total;

    -- An option's price delta is taxed at the dish's rate. An add-on is part of
    -- the same supply, not a second one.
    insert into _lines
      (seq, menu_item_id, name, unit_price, quantity, line_total, options,
       gst_rate_bps, hsn_code, discount_alloc)
    values (v_seq, v_mi_id, v_mi_name, v_unit, v_qty, v_line_total, v_opts,
            v_rate_bps, v_hsn, 0);
  end loop;

  -- -------------------------------------------------------------------------
  -- The fee stack (0078). Gross figures — what the customer sees on each line
  -- and pays — with the GST sitting inside them, not added on top.
  -- -------------------------------------------------------------------------
  v_delivery_fee  := case when v_subtotal >= 500 then 0 else 40 end;
  v_platform_fee  := 0;
  v_packaging_fee := 0;
  v_surge_fee     := 0;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    -- Locks the coupon row, applies every cap, and returns the discount, the
    -- funder (0074) and the per-user cap in force (0075). The lock is held
    -- until this transaction commits, so the redemption written below cannot
    -- race another order placing the same code.
    select p.discount, p.funded_by, p.max_per_user
      into v_discount, v_funded_by, v_max_per_user
      from public.coupon_lock_and_price(
             p_coupon_code, v_subtotal, p_restaurant_id, v_user_id) p;
  end if;

  -- -------------------------------------------------------------------------
  -- The discount, apportioned across the lines by value (0078). Largest
  -- remainder: every line takes its floor share, then the rupees left over go
  -- one each to the lines with the biggest fractional claim, ties broken by
  -- position. The allocations therefore sum to `v_discount` exactly, which is
  -- what makes the per-line taxable values sum back to the order's.
  -- -------------------------------------------------------------------------
  if v_discount > 0 and v_subtotal > 0 then
    update _lines l
       set discount_alloc = a.alloc
      from (
        select seq,
               (floor_alloc
                 + case when rn <= v_discount - total_floor then 1 else 0 end)::integer
                 as alloc
          from (
            select seq,
                   floor_alloc,
                   sum(floor_alloc) over ()                   as total_floor,
                   row_number() over (order by rem desc, seq) as rn
              from (
                select seq,
                       (v_discount::bigint * line_total) / v_subtotal as floor_alloc,
                       (v_discount::bigint * line_total) % v_subtotal as rem
                  from _lines
              ) f
          ) r
      ) a
     where a.seq = l.seq;
  end if;

  -- Every line, deliberately -- and `where true` is how you say so out loud.
  --
  -- Without it this is an `update` with no `where` clause, which Postgres runs
  -- happily and Supabase refuses: pg_safeupdate is loaded for the roles
  -- PostgREST switches into, so the statement dies with SQLSTATE 21000 for
  -- every real customer and for nobody testing it through psql. See the
  -- header -- this one line stopped the entire product taking orders.
  update _lines set taxable_value = line_total - discount_alloc where true;

  -- The tax, rounded **once per slab** and then handed back down to the lines of
  -- that slab by the same largest-remainder rule. Rounding each line on its own
  -- and adding those up would be a different number — ₹250 and ₹150 both round
  -- their 5% up half a rupee, and the customer pays ₹21 on a ₹400 cart that owes
  -- ₹20. The rate-wise total is the figure a GST invoice states, so it is the
  -- figure to compute and the lines are what is derived from it.
  update _lines l
     set tax_amount = (
           r.floor_tax
             + case when r.rn <= r.slab_tax - r.total_floor then 1 else 0 end
         )::integer
    from (
      select seq,
             floor_tax,
             slab_tax,
             sum(floor_tax) over (partition by gst_rate_bps)                  as total_floor,
             row_number() over (partition by gst_rate_bps order by rem desc, seq) as rn
        from (
          select l2.seq,
                 l2.gst_rate_bps,
                 s.tax as slab_tax,
                 case when s.base = 0 then 0
                      else (s.tax::bigint * l2.taxable_value) / s.base end as floor_tax,
                 case when s.base = 0 then 0
                      else (s.tax::bigint * l2.taxable_value) % s.base end as rem
            from _lines l2
            join (
              select gst_rate_bps,
                     sum(taxable_value)                                    as base,
                     round(sum(taxable_value) * gst_rate_bps / 10000.0)::integer as tax
                from _lines
               group by gst_rate_bps
            ) s on s.gst_rate_bps = l2.gst_rate_bps
        ) f
    ) r
   where r.seq = l.seq;

  select coalesce(sum(tax_amount), 0)::integer into v_taxes from _lines;

  -- The tax already inside the gross fees. `f * r / (10000 + r)` and not
  -- `f * r / 10000` — extracting a tax from an inclusive amount, not adding one
  -- to an exclusive one. Delivery, platform and surge are services at 18%;
  -- packaging follows the food it wraps.
  v_tax_on_fees :=
      round((v_delivery_fee + v_platform_fee + v_surge_fee)
              * public.fee_gst_rate_bps()::numeric
              / (10000 + public.fee_gst_rate_bps()))::integer
    + round(v_packaging_fee * public.packaging_gst_rate_bps()::numeric
              / (10000 + public.packaging_gst_rate_bps()))::integer;

  -- CGST and SGST, because the rider carries the food to an address in the
  -- state the kitchen cooked it in. IGST stays 0 and is not guesswork waiting to
  -- happen: `addresses` stores a city and no state (0006), so there is nothing
  -- to compare the seller's state against. The column and the constraint are
  -- here so that the day an address carries a state, this is one condition.
  v_liability := v_taxes + v_tax_on_fees;
  v_cgst := round(v_liability / 2.0)::integer;
  v_sgst := v_liability - v_cgst;

  v_total := v_subtotal + v_delivery_fee + v_platform_fee + v_packaging_fee
             + v_surge_fee + v_taxes - v_discount;

  -- Wrapped, because the pre-check above can be lost to a race: two retries
  -- that arrive together both find nothing and both try to insert. The unique
  -- index is the arbiter, and the loser reads back what the winner wrote
  -- rather than failing an order the customer has already paid for.
  begin
  insert into public.orders (
    user_id, user_phone, restaurant_id, restaurant_name,
    subtotal, delivery_fee, platform_fee, packaging_fee, surge_fee,
    taxes, tax_on_fees, cgst, sgst, igst, place_of_supply, pricing_version,
    discount, total,
    coupon_code, discount_funded_by, payment_method, payment_id,
    delivery_to, delivery_lat, delivery_lng, delivery_notes, eta_minutes,
    idempotency_key
  ) values (
    v_user_id, p_user_phone, p_restaurant_id, v_name,
    v_subtotal, v_delivery_fee, v_platform_fee, v_packaging_fee, v_surge_fee,
    v_taxes, v_tax_on_fees, v_cgst, v_sgst, v_igst, v_state, 2,
    v_discount, v_total,
    nullif(upper(trim(coalesce(p_coupon_code, ''))), ''),
    case when v_discount > 0 then v_funded_by end, p_payment_method, p_payment_id,
    p_delivery_to, p_delivery_lat, p_delivery_lng, v_notes, v_eta,
    p_idempotency_key
  ) returning id into v_order_id;
  exception when unique_violation then
    if p_idempotency_key is not null then
      v_existing := public.order_receipt_by_key(v_user_id, p_idempotency_key);
      if v_existing is not null then
        return v_existing;
      end if;
    end if;
    -- Some other uniqueness broke. Not ours to swallow.
    raise;
  end;

  -- The redemption, in the same transaction as the order (0075). Before the
  -- lines rather than after, so a cap breach fails as early as it can.
  if v_discount > 0 then
    insert into public.coupon_redemptions
      (coupon_code, user_id, order_id, discount, max_per_user_at_redemption)
    values (upper(trim(p_coupon_code)), v_user_id, v_order_id, v_discount,
            v_max_per_user);
  end if;

  -- Pass two: the lines, in order, each with its frozen options and its frozen
  -- tax. A rate change on the menu tomorrow cannot re-price this receipt.
  for v_row in select * from _lines order by seq
  loop
    insert into public.order_items
      (order_id, menu_item_id, name, unit_price, quantity, line_total,
       gst_rate_bps, hsn_code, discount_alloc, taxable_value, tax_amount)
    values (v_order_id, v_row.menu_item_id, v_row.name, v_row.unit_price,
            v_row.quantity, v_row.line_total,
            v_row.gst_rate_bps, v_row.hsn_code, v_row.discount_alloc,
            v_row.taxable_value, v_row.tax_amount)
    returning id into v_line_id;

    insert into public.order_item_options (order_item_id, name, price_delta)
    select v_line_id, e ->> 'name', (e ->> 'price_delta')::integer
      from jsonb_array_elements(v_row.options) as e;
  end loop;

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
$function$

;
