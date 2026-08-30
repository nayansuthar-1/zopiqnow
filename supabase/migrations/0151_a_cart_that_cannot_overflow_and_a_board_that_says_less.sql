-- ---------------------------------------------------------------------------
-- 0151 — a cart that cannot overflow, and a board that says less.
-- ---------------------------------------------------------------------------
-- Five of the eight smaller findings in P10. The three that are not here are
-- the rider app's countdown and its snackbar, and the customer router's missing
-- `errorBuilder` — all three are Dart, and they ship in the same commit.
--
-- The eighth, three hero slides advertising coupon codes that are not rows in
-- `coupons`, is **deliberately left open**: the slides are being replaced before
-- production, so issuing `TRYNEW`, `ZOPIQ150` and `SAVE30` to match copy that is
-- about to be rewritten would be inventing three live discounts nobody asked
-- for.
--
-- ## 1. `place_order` could be made to raise Postgres's own error
--
-- `v_qty < 1` was refused and nothing capped the other end. Two ways through:
--
--   * a quantity past 2^31 fails at `(v_line ->> 'quantity')::integer` with
--     `value out of range for type integer`, *before* any check of ours;
--   * a quantity inside integer range but large — 10,000,000 — overflows at
--     `v_unit * v_qty` with `integer out of range`.
--
-- Either way the customer is shown a Postgres error, from a function whose every
-- other refusal is a sentence in English. Parsing as `numeric` first fixes the
-- first, a cap of 50 per line fixes the second, and a cap of 50 lines closes the
-- same hole one level up — without it, enough lines overflow `v_subtotal`
-- whatever the per-line cap says.
--
-- ## 2. `p_user_phone` was whatever the caller said
--
-- Unvalidated, and it is the number the rider calls. The live table has
-- `+911918739985` on a real order: the sheet checks that ten digits were typed
-- and nothing checks that they are a mobile number.
--
-- **A format check, not an identity check.** There is nothing to check against —
-- `auth.users.phone` is empty for all 55 accounts and the app reads its number
-- from `user_metadata.delivery_phone`, which the client writes and can therefore
-- set to anything. Binding the number to the account needs phone auth (UX-002).
-- Recorded here so the gap is a known one rather than an assumed fix.
--
-- ## 3. `announce_open_delivery` announced once, forever
--
-- Its guard was "does any `job_available` notification exist for this order",
-- which is true from the moment the first rider is told and never becomes false.
-- Every rider who came online afterwards was never told about the job sitting on
-- the board — the exact rider a stale order is waiting for.
--
-- Per-rider now. Which introduces a way to pester somebody the old guard
-- accidentally protected: a rider who was *offered* this job and declined it.
-- They are excluded — a decline is an answer.
--
-- ## 4. The open board named what the order was worth
--
-- `available_deliveries` returned `total` for every dispatchable order to every
-- verified rider. On a cash job that is the money they will be carrying and they
-- need it. On a prepaid job it is what a stranger spent on dinner, and it is not
-- a number they can act on — `rider_pay`, beside it, is the one they are
-- deciding on.
--
-- The finding also said `delivery_to` leaks, and that half is **not changed**,
-- on the evidence: `delivery_to` is the customer's `line1, city` from a
-- reverse-geocode — "Mutha Nagar, Sadri" — a locality and a town, never a house
-- number, and `available_deliveries` returns no coordinates at all. The door
-- itself lives in `delivery_notes` and the lat/lng, and neither is on the board.
-- Stripping the locality would make the board unreadable to protect a town name
-- the rider is standing in.
--
-- ## 5. The countdown trusted the phone's clock
--
-- `OfferSheet` draws `remaining(DateTime.now())` against a server `expires_at`,
-- and `offersProvider` filters expired rows the same way. A phone a minute fast
-- therefore does not merely mis-draw the ring: **the offer is discarded before
-- the sheet opens**, silently, and that rider is never offered anything again
-- for as long as the clock is wrong.
--
-- `my_offers` now returns `now()` beside the row it applies to. The app measures
-- the skew once per fetch and counts against a corrected clock. Sending the
-- server's time with the deadline it belongs to is the smallest thing that
-- works; the alternative, sending "seconds left", loses the ring's start.
-- ---------------------------------------------------------------------------


-- ===========================================================================
-- 1. place_order: a quantity that cannot overflow, a phone that is a phone.
-- ===========================================================================
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
  -- Read as numeric before it is trusted as an integer. See section 1.
  v_qty_raw       numeric;
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

  -- 0151. Normalised once, here, so every later reader — the order row, the
  -- rider's call button, WhatsApp — gets the same string.
  p_user_phone := trim(p_user_phone);

  -- An Indian mobile in E.164, which is the only kind the app can produce:
  -- `toE164` fixes the +91 and the sheet takes ten digits. What it did *not*
  -- check is the leading digit, and the live table shows why that matters —
  -- `+911918739985` is on a real order and can never be answered.
  --
  -- **This is a format check and not an identity check**, and the difference is
  -- worth being plain about. There is nothing to check against: sign-in is email
  -- or Google, `auth.users.phone` is empty for all 55 accounts, and the number
  -- the app sends comes from `user_metadata.delivery_phone` — which the client
  -- writes and can therefore say anything. Binding the number a rider calls to
  -- the account that placed the order needs phone auth (UX-002), not a regex.
  -- Until then this stops a typo and a fat-fingered API call, and no more.
  if p_user_phone !~ '^\+91[6-9][0-9]{9}$' then
    raise exception
      'That phone number does not look right. We need a 10-digit Indian mobile.'
      using errcode = 'P0001';
  end if;

  -- A cart is a screenful of dishes. The bound is here because the arithmetic
  -- below is `integer`: without it a caller can hand us enough lines to push
  -- `v_subtotal` past 2^31 whatever the per-line cap says, and the customer is
  -- shown `integer out of range` instead of a sentence.
  if jsonb_array_length(p_items) > 50 then
    raise exception 'That is too many different items for one order.'
      using errcode = 'P0001';
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
  -- New in 0143. `on commit drop` removes this at commit, which is too late for
  -- a second call in the same transaction. See the header.
  --
  -- `to_regclass` rather than `drop table if exists`, which raises a NOTICE
  -- every time it skips — that is once per order placed, forever, in the logs
  -- and on the wire to PostgREST. Asking the catalogue first is silent.
  if to_regclass('pg_temp._lines') is not null then
    drop table _lines;
  end if;

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
    -- ---------------------------------------------------------------------
    -- The quantity, read as numeric before it is trusted as an integer.
    -- ---------------------------------------------------------------------
    -- `::integer` on a value past 2^31 raises `value out of range for type
    -- integer` *at the cast*, before any check of ours can run, so the customer
    -- was shown Postgres's sentence rather than one of ours. numeric parses it,
    -- and a non-numeric string lands in the same refusal as a missing one.
    begin
      v_qty_raw := (v_line ->> 'quantity')::numeric;
    exception when others then
      v_qty_raw := null;
    end;

    if v_qty_raw is null or v_qty_raw <> floor(v_qty_raw) or v_qty_raw < 1 then
      raise exception 'Your cart has an invalid quantity.' using errcode = 'P0001';
    end if;

    -- Fifty of one dish is a party order and the app's stepper will not reach
    -- it. Past that the answer is a phone call, not a bigger integer:
    -- `v_unit * v_qty` is integer arithmetic, and `10000000 * 300` is not a
    -- cart, it is a crash with a customer watching.
    if v_qty_raw > 50 then
      raise exception 'You can order at most 50 of one item.'
        using errcode = 'P0001';
    end if;

    v_qty := v_qty_raw::integer;

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
  v_delivery_fee  := 40;
  v_platform_fee  := 0;
  v_packaging_fee := 0;
  v_surge_fee     := (public.delivery_surcharge_now(p_restaurant_id) ->> 'total')::integer;

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
$function$;

-- ===========================================================================
-- 3. A job on the board is announced to whoever is on it, not to whoever was.
-- ===========================================================================
create or replace function public.announce_open_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_name text;
begin
  select restaurant_name into v_name from public.orders where id = p_order_id;
  if v_name is null then
    return;
  end if;

  begin
    insert into public.notifications
      (audience, partner_email, kind, title, body, order_id)
    select 'rider', p.email, 'job_available',
           'Delivery on the board',
           'A delivery from ' || v_name || ' is waiting to be claimed',
           p_order_id
      from public.delivery_partners p
     where p.is_active
       and p.is_online
       -- Once each, not once ever. This is the whole change: the guard used to
       -- be "does any job_available row exist for this order", which is true
       -- the instant the first rider is told and stays true forever after.
       and not exists (
         select 1 from public.notifications n
          where n.kind = 'job_available'
            and n.order_id = p_order_id
            and n.partner_email = p.email
       )
       -- Somebody who was offered this job and said no. Under the old guard
       -- they were never pestered, because nobody was; per-rider, they would
       -- be. A decline is an answer, and this does not ask again.
       and not exists (
         select 1 from public.delivery_offers off
          where off.order_id = p_order_id
            and off.partner_email = p.email
            and off.state = 'declined'
       );
  exception when others then
    -- 0021's rule. The board is the event; the buzz is a courtesy on top of it.
    null;
  end;
end;
$fn$;

revoke all on function public.announce_open_delivery(text)
  from public, anon, authenticated;

-- ===========================================================================
-- 4. The open board stops naming what a stranger spent on dinner.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.available_deliveries()
 RETURNS TABLE(order_id text, restaurant_name text, restaurant_lat double precision, restaurant_lng double precision, deliver_to text, total integer, payment_method text, status text, route_km numeric, rider_pay integer, ready_by timestamp with time zone, placed_at timestamp with time zone, offered_to_other boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_email    text;
  v_headroom integer;
  v_block    text;
begin
  v_email := public.delivery_partner_email();
  if v_email is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- 0080. Raised rather than returning nothing: an empty board reads as "no
  -- work right now", which is a different and much worse thing to tell somebody
  -- whose documents are sitting unverified in a queue.
  v_block := public.rider_work_block(v_email);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  -- How much more cash this rider may be holding. Computed once here rather
  -- than per row: it does not change while the query runs.
  v_headroom := public.rider_cash_cap() - public.rider_cash_in_hand(v_email);

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to,
           -- 0151. What the order is worth is the rider's business only when
           -- they are the one who has to collect it. On a prepaid job the number
           -- told them nothing they could act on, and told them what a stranger
           -- spent on dinner; `rider_pay` beside it is the figure they are
           -- actually deciding on. Null, not zero — the board says "Prepaid
           -- online" and stops.
           case when o.payment_method = 'cod' then o.total end,
           o.payment_method, o.status,
           q.ride_km,
           q.rider_pay,
           o.ready_by, o.created_at,
           exists (
             select 1 from public.delivery_offers off
              where off.order_id = o.id
                and off.state = 'offered'
                and off.expires_at > now()
                and off.partner_email <> v_email
           )
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
      left join lateral public.rider_pay_quote(o.id) q on true
     where o.status in ('preparing', 'ready_for_pickup')
       and (o.payment_method <> 'cod' or o.total <= v_headroom)
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = o.id and d.state <> 'cancelled'
       )
       and (
         not exists (
           select 1 from public.delivery_offers off
            where off.order_id = o.id
              and off.state = 'offered'
              and off.expires_at > now()
         )
         or exists (
           select 1 from public.delivery_offers mine
            where mine.order_id = o.id
              and mine.partner_email = v_email
              and mine.state in ('offered', 'expired')
         )
       )
     order by (o.status = 'ready_for_pickup') desc, o.created_at;
end;
$function$;

-- ===========================================================================
-- 5. An offer carries the clock it is measured against.
-- ===========================================================================
-- `returns table` cannot gain a column through `create or replace`; the drop
-- and the grant below are that, and nothing more. The signature is unchanged,
-- so no overload is left behind for the app to bind to by accident (0110).
drop function if exists public.my_offers();

CREATE OR REPLACE FUNCTION public.my_offers()
 RETURNS TABLE(order_id text, restaurant_name text, restaurant_lat double precision, restaurant_lng double precision, deliver_to text, total integer, payment_method text, order_status text, route_km numeric, to_pickup_km numeric, rider_pay integer, offered_at timestamp with time zone, expires_at timestamp with time zone, server_now timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status,
           coalesce(off.ride_km,   q.ride_km),
           off.distance_km,
           coalesce(off.rider_pay, q.rider_pay),
           off.offered_at, off.expires_at,
           -- 0151. The database's clock, sent with the row that is measured
           -- against it. See the header: the countdown was drawn against the
           -- phone's.
           now()
      from public.delivery_offers off
      join public.orders o      on o.id = off.order_id
      join public.restaurants r on r.id = o.restaurant_id
      left join lateral public.rider_pay_quote(o.id) q on true
     where off.partner_email = v_rider
       and off.state = 'offered'
       and off.expires_at > now()
     order by off.expires_at;
end;
$function$;

revoke all on function public.my_offers() from public, anon;
grant execute on function public.my_offers() to authenticated;
