-- ---------------------------------------------------------------------------
-- 0078 — the tax follows what was actually paid. (audit BIZ-005)
-- ---------------------------------------------------------------------------
-- Since 0003 this platform has charged 5% on the *pre-discount* subtotal. A
-- customer who paid ₹800 on a ₹1,000 cart was taxed ₹50, not ₹40. Under GST the
-- taxable value is the transaction value — what changed hands — so every one of
-- those ₹10 was both an overcharge to the customer and a misstatement of the
-- liability. 0063 turned that arithmetic into a *numbered tax invoice*, which is
-- what raises it from an accounting nit to a document defect. This file fixes
-- the base.
--
-- Four things, all of them BIZ-005's:
--
--   1. **A rate per dish, not one rate for the platform.** `menu_items` gains
--      `gst_rate_bps` and `hsn_code`. Restaurant food is 5%; packaged goods and
--      beverages are 12% or 18%. Everything defaults to 500 bps, so nothing on
--      any menu today changes price — but the pricing path now reads the dish's
--      rate rather than a constant, which is the part that could not be fixed
--      later without re-pricing every order.
--
--   2. **The tax is computed on the discounted value, rate by rate.** The order
--      discount is apportioned across the lines by value (largest remainder, so
--      the parts sum to the whole to the rupee), the taxable values are totalled
--      per slab, the tax is rounded once per slab, and the frozen `order_items`
--      row carries each line's share. A rate-wise summary is a legal requirement
--      on a tax invoice and you cannot assemble one from an order-level total.
--
--   3. **The fee stack exists.** `platform_fee`, `packaging_fee`, `surge_fee`
--      beside the delivery fee, and the GST that sits inside all four. Every one
--      of them defaults to 0: this migration models the lines, it does not turn
--      them on. Turning one on is a pricing decision and belongs to whoever
--      makes pricing decisions, not to a schema change.
--
--   4. **The tax splits into CGST/SGST/IGST**, stored on the order rather than
--      halved on the way out to a screen, so the split an invoice prints is the
--      split that was charged.
--
-- **What the customer pays changes in exactly one direction: down.** The food
-- tax now sits on the discounted base, so a coupon takes its 5% with it. Nothing
-- else moves.
--
-- **The fees are tax-inclusive and the food is not.** A ₹40 delivery fee stays a
-- ₹40 delivery fee, of which ₹6 is the 18% service GST inside it; menu prices
-- keep having 5% added on top, which is how a restaurant bill has always read in
-- this country. The alternative — charging 18% on top of the ₹40 — is a price
-- rise for every customer under the free-delivery threshold, and a compliance
-- migration is not the place to put one through. Reversing that choice later is
-- one line here and a re-priced fee, not a schema change.
--
-- **No receipt is rewritten.** Orders placed before this file keep every figure
-- they were charged, carry `pricing_version = 1`, and their invoices render on
-- the basis 0063 stated. The CGST/SGST backfill below reproduces 0063's halves
-- exactly, so an invoice printed yesterday and the same invoice printed
-- tomorrow are the same piece of paper.
--
-- **Still owed, and deliberately not here:** BIZ-005 also asks for a chartered
-- accountant's review of the invoice template and the settlement statement, and
-- for the TCS (GST §52) and TDS (IT §194-O) position on vendor payouts. Both are
-- somebody's judgement, not a function. There is also no console lever for
-- `gst_rate_bps` yet — a non-food catalogue (Gifts) will need one before it can
-- be sold, and Gifts does not go through `place_order` today.

-- ===========================================================================
-- A. The rates, as facts rather than literals.
-- ===========================================================================
-- Basis points, not percent: 12.5% is a rate somebody will want one day and
-- `numeric` in a pricing loop is how a total stops being reproducible.
create or replace function public.fee_gst_rate_bps()
returns integer language sql immutable as $$ select 1800 $$;

comment on function public.fee_gst_rate_bps() is
  'GST on a platform service charge — delivery, platform fee, surge. 18%. The '
  'fee amounts stored on an order are inclusive of it (0078).';

create or replace function public.packaging_gst_rate_bps()
returns integer language sql immutable as $$ select 500 $$;

comment on function public.packaging_gst_rate_bps() is
  'GST on a packaging charge. Ancillary to the supply of the food it wraps, so '
  'it follows the food rate rather than the service rate (0078).';

-- ===========================================================================
-- B. A rate on the dish.
-- ===========================================================================
alter table public.menu_items
  add column if not exists gst_rate_bps integer not null default 500,
  add column if not exists hsn_code     text;

alter table public.menu_items
  drop constraint if exists menu_items_gst_rate_is_a_real_slab;
alter table public.menu_items
  add constraint menu_items_gst_rate_is_a_real_slab
  check (gst_rate_bps in (0, 500, 1200, 1800));

comment on column public.menu_items.gst_rate_bps is
  'The GST slab this dish is taxed at, in basis points. 500 (5%) for restaurant '
  'food without ITC, which is every row today. 1200/1800 exist for packaged '
  'goods and beverages. Frozen onto the order line at checkout, so changing it '
  'never re-prices an order already placed (0078, audit BIZ-005).';

comment on column public.menu_items.hsn_code is
  'HSN/SAC for this dish, printed on the tax invoice. Null until somebody '
  'classifies the menu; the document omits the column rather than guessing.';

-- ===========================================================================
-- C. The taxable value on the frozen line.
-- ===========================================================================
-- Nullable and *not* backfilled. A pre-0078 order was taxed once, at the order
-- level, on a base that no longer exists — inventing a per-line split for it
-- would mean printing figures nobody was charged. Null here reads as "this
-- order predates per-line tax", and `order_invoice` says so by rendering it the
-- way 0063 did.
alter table public.order_items
  add column if not exists gst_rate_bps   integer,
  add column if not exists hsn_code       text,
  add column if not exists discount_alloc integer,
  add column if not exists taxable_value  integer,
  add column if not exists tax_amount     integer;

alter table public.order_items
  drop constraint if exists order_item_tax_is_all_or_nothing;
alter table public.order_items
  add constraint order_item_tax_is_all_or_nothing
  check (
    (gst_rate_bps is null and discount_alloc is null
       and taxable_value is null and tax_amount is null)
    or
    (gst_rate_bps is not null and discount_alloc is not null
       and taxable_value is not null and tax_amount is not null)
  );

-- The apportionment cannot exceed the line it is apportioned to, and the
-- taxable value is the one number the other two are derived from.
alter table public.order_items
  drop constraint if exists order_item_taxable_value_is_consistent;
alter table public.order_items
  add constraint order_item_taxable_value_is_consistent
  check (
    taxable_value is null
    or (discount_alloc between 0 and line_total
        and taxable_value = line_total - discount_alloc
        and tax_amount >= 0)
  );

comment on column public.order_items.discount_alloc is
  'This line''s share of the order discount, apportioned by value. Sums to '
  '`orders.discount` across the order exactly — the remainder rupees go to the '
  'lines with the largest fractional claim (0078).';

comment on column public.order_items.taxable_value is
  'line_total − discount_alloc. What GST was actually charged on. Null on an '
  'order placed before 0078, which was taxed at the order level.';

-- ===========================================================================
-- D. The fee stack and the split, on the order.
-- ===========================================================================
alter table public.orders
  add column if not exists platform_fee    integer  not null default 0,
  add column if not exists packaging_fee   integer  not null default 0,
  add column if not exists surge_fee       integer  not null default 0,
  add column if not exists tax_on_fees     integer  not null default 0,
  add column if not exists cgst            integer  not null default 0,
  add column if not exists sgst            integer  not null default 0,
  add column if not exists igst            integer  not null default 0,
  add column if not exists place_of_supply text,
  add column if not exists pricing_version smallint not null default 1;

comment on column public.orders.tax_on_fees is
  'The GST already inside delivery_fee + platform_fee + packaging_fee + '
  'surge_fee. Part of the liability, and therefore part of cgst/sgst/igst — but '
  'NOT part of `taxes` and NOT added to `total`, because the customer was shown '
  'a gross fee and paid it (0078).';

comment on column public.orders.taxes is
  'GST charged on top of the food, on the post-discount taxable value. Since '
  '0078 this is the sum of order_items.tax_amount; before it, 5% of the '
  'pre-discount subtotal.';

comment on column public.orders.pricing_version is
  '1 = priced before 0078 (one flat rate, pre-discount base, untaxed fees). '
  '2 = priced by 0078. The invoice reads this to decide which document to '
  'render, so an old receipt keeps saying what it always said.';

comment on column public.orders.place_of_supply is
  'The state the supply was made in, frozen from the restaurant at checkout. '
  'Printed on the invoice. Null on pre-0078 orders and on any restaurant an '
  'admin has not finished — the document omits the line rather than guessing.';

-- Backfill the split for every existing order with the exact halves 0063
-- computed on the way out, so no printed document changes by a rupee.
update public.orders
   set cgst = round(taxes / 2.0)::integer,
       sgst = taxes - round(taxes / 2.0)::integer
 where cgst = 0 and sgst = 0 and igst = 0 and taxes > 0;

-- Old rows keep the state they were sold in, where the restaurant has one.
update public.orders o
   set place_of_supply = nullif(r.state, '')
  from public.restaurants r
 where r.id = o.restaurant_id
   and o.place_of_supply is null;

alter table public.orders
  drop constraint if exists orders_platform_fee_check;
alter table public.orders
  add constraint orders_platform_fee_check check (platform_fee >= 0);
alter table public.orders
  drop constraint if exists orders_packaging_fee_check;
alter table public.orders
  add constraint orders_packaging_fee_check check (packaging_fee >= 0);
alter table public.orders
  drop constraint if exists orders_surge_fee_check;
alter table public.orders
  add constraint orders_surge_fee_check check (surge_fee >= 0);
alter table public.orders
  drop constraint if exists orders_tax_on_fees_check;
alter table public.orders
  add constraint orders_tax_on_fees_check check (tax_on_fees >= 0);

-- The total now has four fee lines in it. Every existing row has 0 in three of
-- them, so this is the old constraint for old orders and a wider one for new.
alter table public.orders
  drop constraint if exists order_total_is_consistent;
alter table public.orders
  add constraint order_total_is_consistent
  check (total = subtotal + delivery_fee + platform_fee + packaging_fee
                 + surge_fee + taxes - discount);

-- The split has to add back up to the whole liability — the food tax charged on
-- top plus the fee tax charged inside. An invoice whose parts do not sum to its
-- total is a rejected invoice.
alter table public.orders
  drop constraint if exists order_tax_split_is_consistent;
alter table public.orders
  add constraint order_tax_split_is_consistent
  check (cgst + sgst + igst = taxes + tax_on_fees);

-- One supply is either intra-state or inter-state. It is never both, and a row
-- carrying CGST *and* IGST is a bug that should not reach an invoice.
alter table public.orders
  drop constraint if exists order_tax_is_one_kind_or_the_other;
alter table public.orders
  add constraint order_tax_is_one_kind_or_the_other
  check (igst = 0 or (cgst = 0 and sgst = 0));

-- ===========================================================================
-- E. place_order prices the bill in the right order.
-- ===========================================================================
-- Fees, then the discount, then the tax — because the taxable value is what the
-- customer actually pays for the food.
--
-- Re-pasted whole rather than string-patched the way 0074 and 0075 were. Those
-- moved two statements each; this moves the entire pricing section, adds four
-- columns to the scratch table and rewrites both inserts, and eight blind
-- replacements against a body nobody can read in the file is a worse trade than
-- one function you can review. The guard below is what 0074's idempotence check
-- was: it refuses to run against a body that is not the one this was written
-- from, so a later change cannot be silently clobbered.
do $$
declare
  v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order';

  if v_src is null then
    raise exception '0078: place_order not found — nothing to replace.';
  end if;

  if position('gst_rate_bps' in v_src) > 0 then
    raise notice '0078: place_order already prices tax per line; the replace below is the same text.';
  elsif position('coupon_lock_and_price' in v_src) = 0
     or position('menu_item_is_servable_now' in v_src) = 0
     or position('discount_funded_by' in v_src) = 0 then
    raise exception '0078: place_order is missing 0068/0074/0075. Reconcile it by hand before running this.';
  end if;
end $$;

create or replace function public.place_order(
  p_user_phone       text,
  p_restaurant_id    text,
  p_items            jsonb,
  p_delivery_to      text,
  p_payment_method   text,
  p_delivery_lat     double precision default null,
  p_delivery_lng     double precision default null,
  p_coupon_code      text default null,
  p_payment_id       text default null,
  p_delivery_notes   text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
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

  update _lines set taxable_value = line_total - discount_alloc;

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

  insert into public.orders (
    user_id, user_phone, restaurant_id, restaurant_name,
    subtotal, delivery_fee, platform_fee, packaging_fee, surge_fee,
    taxes, tax_on_fees, cgst, sgst, igst, place_of_supply, pricing_version,
    discount, total,
    coupon_code, discount_funded_by, payment_method, payment_id,
    delivery_to, delivery_lat, delivery_lng, delivery_notes, eta_minutes
  ) values (
    v_user_id, p_user_phone, p_restaurant_id, v_name,
    v_subtotal, v_delivery_fee, v_platform_fee, v_packaging_fee, v_surge_fee,
    v_taxes, v_tax_on_fees, v_cgst, v_sgst, v_igst, v_state, 2,
    v_discount, v_total,
    nullif(upper(trim(coalesce(p_coupon_code, ''))), ''),
    case when v_discount > 0 then v_funded_by end, p_payment_method, p_payment_id,
    p_delivery_to, p_delivery_lat, p_delivery_lng, v_notes, v_eta
  ) returning id into v_order_id;

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
$$;

grant execute on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text, text
) to authenticated;

-- ===========================================================================
-- F. The document says what was charged, on the basis it was charged on.
-- ===========================================================================
-- Two documents out of one function, chosen by `pricing_version`:
--
--   v1 — the taxable value is the subtotal, the discount is a deduction below
--        it, the delivery fee carries no tax, and CGST/SGST are the halves 0063
--        printed. Identical to 0063's output, field for field.
--
--   v2 — the taxable value is post-discount, there is a rate-wise tax table,
--        and each fee line states the tax inside it.
--
-- `tax_lines` is the rate-wise summary a compliant tax invoice requires. It is
-- empty on a v1 order because there is no honest way to produce one.
create or replace function public.order_invoice(p_order_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user      text;
  v_o         public.orders;
  v_r         record;
  v_legal     record;
  v_lines     jsonb;
  v_tax_lines jsonb;
  v_rate      numeric;
begin
  v_user := auth.uid()::text;
  if v_user is null then
    raise exception 'Please sign in to view this invoice.' using errcode = 'P0001';
  end if;

  select * into v_o from public.orders where id = p_order_id;
  if not found or v_o.user_id <> v_user then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  if v_o.invoice_no is null then
    raise exception 'An invoice is issued once your order has been delivered.'
      using errcode = 'P0001';
  end if;

  select r.name, r.address_line, r.city, r.state, r.pincode, r.contact_phone
    into v_r
    from public.restaurants r
   where r.id = v_o.restaurant_id;

  select l.gst_number, l.fssai_number
    into v_legal
    from public.restaurant_legal l
   where l.restaurant_id = v_o.restaurant_id;

  -- The frozen lines, options and all, in the order they were bought. The tax
  -- fields are null on a v1 line and the document simply has no column for them.
  select coalesce(jsonb_agg(line order by line_id), '[]'::jsonb)
    into v_lines
    from (
      select oi.id as line_id,
             jsonb_build_object(
               'name',       oi.name,
               'options',    coalesce(
                               (select jsonb_agg(o.name order by o.id)
                                  from public.order_item_options o
                                 where o.order_item_id = oi.id),
                               '[]'::jsonb
                             ),
               'quantity',      oi.quantity,
               'unit_price',    oi.unit_price,
               'line_total',    oi.line_total,
               'hsn',           oi.hsn_code,
               'gst_rate',      case when oi.gst_rate_bps is not null
                                     then oi.gst_rate_bps / 100.0 end,
               'discount',      oi.discount_alloc,
               'taxable_value', oi.taxable_value,
               'tax',           oi.tax_amount
             ) as line
        from public.order_items oi
       where oi.order_id = p_order_id
    ) s;

  -- The rate-wise table. Food only: the tax inside the fees is stated on the fee
  -- lines themselves, where the customer can see the number it was taken out of.
  if v_o.pricing_version >= 2 then
    select coalesce(jsonb_agg(t order by (t ->> 'rate_percent')::numeric), '[]'::jsonb)
      into v_tax_lines
      from (
        select jsonb_build_object(
                 'rate_percent', oi.gst_rate_bps / 100.0,
                 'taxable',      sum(oi.taxable_value),
                 'tax',          sum(oi.tax_amount)
               ) as t
          from public.order_items oi
         where oi.order_id = p_order_id
           and oi.gst_rate_bps is not null
         group by oi.gst_rate_bps
      ) g;
  else
    v_tax_lines := '[]'::jsonb;
  end if;

  -- The headline rate, for the "CGST @ 2.5%" line every single-rate invoice
  -- prints. Null when the order spans more than one slab — the rate-wise table
  -- is the truth then, and one averaged number on the face of a tax invoice
  -- would be a wrong one.
  if v_o.pricing_version >= 2 then
    select case when count(distinct oi.gst_rate_bps) = 1
                then min(oi.gst_rate_bps) / 100.0 end
      into v_rate
      from public.order_items oi
     where oi.order_id = p_order_id and oi.gst_rate_bps is not null;
  else
    v_rate := public.gst_rate_percent();
  end if;

  return jsonb_build_object(
    'invoice_no',      v_o.invoice_no,
    'invoiced_at',     v_o.invoiced_at,
    'order_id',        v_o.id,
    'placed_at',       v_o.created_at,
    'pricing_version', v_o.pricing_version,

    'seller', jsonb_build_object(
      'name',    v_o.restaurant_name,
      'address', nullif(concat_ws(', ',
                   nullif(v_r.address_line, ''), nullif(v_r.city, ''),
                   nullif(v_r.state, ''),        nullif(v_r.pincode, '')
                 ), ''),
      'phone',   v_r.contact_phone,
      'gstin',   v_legal.gst_number,
      'fssai',   v_legal.fssai_number
    ),

    'buyer', jsonb_build_object(
      'phone',   v_o.user_phone,
      'address', v_o.delivery_to
    ),

    -- Frozen on the order since 0078, and read off the restaurant for the ones
    -- placed before that. Null on a restaurant an admin has not finished, and
    -- the document omits the line rather than guessing.
    'place_of_supply', coalesce(v_o.place_of_supply, nullif(v_r.state, '')),

    'lines',          v_lines,

    -- v2: what the food was actually taxed on. v1: the subtotal, because that
    -- is the base the tax beside it was computed from and a document has to
    -- reproduce its own arithmetic.
    'taxable_value',  case when v_o.pricing_version >= 2
                           then v_o.subtotal - v_o.discount
                           else v_o.subtotal end,
    'discount',       v_o.discount,
    'coupon_code',    v_o.coupon_code,

    'fees', jsonb_build_object(
      'delivery',  v_o.delivery_fee,
      'platform',  v_o.platform_fee,
      'packaging', v_o.packaging_fee,
      'surge',     v_o.surge_fee
    ),
    -- Kept at the top level as well: every build of the app that predates 0078
    -- reads `delivery_fee` from here and would otherwise lose the line.
    'delivery_fee',   v_o.delivery_fee,
    'tax_on_fees',    v_o.tax_on_fees,

    'gst_rate',       v_rate,
    'tax_lines',      v_tax_lines,
    'cgst',           v_o.cgst,
    'sgst',           v_o.sgst,
    'igst',           v_o.igst,
    'taxes',          v_o.taxes + v_o.tax_on_fees,
    'total',          v_o.total,

    'payment_method', v_o.payment_method,
    'payment_id',     v_o.payment_id
  );
end;
$$;

grant execute on function public.order_invoice(text) to authenticated;

-- ===========================================================================
-- G. Grants on the new helpers.
-- ===========================================================================
-- Read by `place_order` (security definer) and by nothing a client can reach.
-- Both are constants, so this is hygiene rather than a secret — SEC-002's rule
-- is that a function is granted to the caller who needs it and to nobody else.
revoke all on function
  public.fee_gst_rate_bps(), public.packaging_gst_rate_bps()
  from public, anon, authenticated;
grant execute on function
  public.fee_gst_rate_bps(), public.packaging_gst_rate_bps()
  to service_role;
