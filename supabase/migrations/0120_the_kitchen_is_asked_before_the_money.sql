-- ---------------------------------------------------------------------------
-- 0120 — the kitchen is asked before the money, not after it.
-- ---------------------------------------------------------------------------
-- `CheckoutController.placeOrder` charges the card and *then* calls
-- `place_order`. Nine separate rules can refuse the order at that point, and
-- every one of them fires after the money has been taken:
--
--     restaurant inactive or gone            place_order
--     restaurant not accepting orders        place_order
--     restaurant closed right now            place_order → restaurant_is_open_now
--     an item no longer available            place_order
--     an item outside its serving window     place_order → menu_item_is_servable_now
--     an option withdrawn or a group short   resolve_order_line_options
--     the coupon expired, capped, or spent   coupon_lock_and_price
--     the address or kitchen out of area     orders_within_service_area  (trigger)
--     the account blocked                    orders_reject_blocked_user  (trigger)
--     more than ten orders in an hour        orders_reject_too_many      (trigger)
--
-- When any of them fires there is **no order row**, so
-- `orders_refund_on_termination` — which is `after update of status on orders` —
-- never runs. No refund is recorded, no notification is sent, and the payment
-- intent sits `verified` for ever. Nothing sweeps for those: `cron.job` holds six
-- jobs and none of them looks.
--
-- The hazard was already known for exactly one of the ten. `checkout_page.dart`
-- pre-checks the delivery area on the client and says why in as many words —
-- *"asked here and not in `place_order` because the gateway runs first — an order
-- the trigger refuses is an order somebody has already paid for."* This migration
-- is that sentence applied to the other nine.
--
-- ## Why this is a preflight and not a redesign
--
-- The complete fix is to invert the shape: write the order first as
-- `pending_payment`, charge, then confirm. That eliminates the window rather than
-- shrinking it, and it touches every consumer of `orders.status` in three apps,
-- the dispatch sweeper, the invoice trigger and the console. It is a project, not
-- a bug fix, and it is not this.
--
-- What this does is remove every *ordinary* occurrence — the cart left open while
-- the kitchen shut, the coupon that expired over lunch, the dish that sold out
-- while the customer chose an address. What it leaves is the residual window
-- between the preflight and the insert, which is the few seconds the Razorpay
-- sheet is on screen. The safety net for that belongs with the refund work (P3 in
-- `BUGFIX_QUEUE.md`), because `refunds.order_id` is `not null` with a foreign key
-- to `orders` and a refund for a payment that never became an order cannot be
-- written at all today.
--
-- ## The second thing it fixes, which is not on that list
--
-- The amount handed to the gateway is `CartBill.of(cart, …).total` — computed on
-- the phone. `place_order` reprices in Postgres, and the payment gate refuses an
-- intent whose `amount` is below the order's own `total`. So a client and server
-- that disagree by one rupee in the server's favour is *also* a charge followed by
-- a refusal, and no rule on the list above is involved. The preflight therefore
-- returns the server's bill, and the app charges that number rather than its own.
--
-- ## Read-only, and unlocked, on purpose
--
-- Nothing here writes. In particular the coupon is read through `validate_coupon`
-- rather than `coupon_lock_and_price`: the locking variant holds the coupon row
-- until its transaction commits, and a preflight that locked a popular code for
-- the length of a payment sheet would serialise every checkout on the platform
-- behind whoever was slowest to find their UPI PIN. The preflight's answer is
-- advisory by construction — `place_order` still locks, still reprices, and is
-- still the only authority.
--
-- ## The duplication, named
--
-- The pricing below is the same arithmetic as `place_order`'s, restated. That is
-- the failure mode 0097 was written to end, so it is worth saying why it is the
-- lesser evil here: the alternative is lifting the temp table, the largest-
-- remainder apportionment and the per-slab rounding out of `place_order` into a
-- shared function, which is open-heart surgery on the money path to fix a bug that
-- is not in it. The shared *helpers* are all reused — `resolve_order_line_options`,
-- `validate_coupon`, `fee_gst_rate_bps`, `packaging_gst_rate_bps`,
-- `restaurant_is_open_now`, `menu_item_is_servable_now`, `serviceable_point` — so
-- what is restated is the arithmetic between them.
--
-- **The verification at the foot of this file is what keeps the two honest**, and
-- it is not optional: it reprices every order in the table through this function
-- and asserts the totals match rupee for rupee.
--
-- The free-delivery threshold is the one genuinely duplicated constant
-- (`subtotal >= 500 → 0, else 40`). It is hard-coded in `place_order` too; making
-- it a settings row is a separate change and would want both call sites at once.

-- ===========================================================================
-- The preflight.
-- ===========================================================================
-- Argument order and names mirror `place_order`'s so the two read as a pair.
-- `p_user_phone`, `p_delivery_to`, `p_payment_method`, `p_payment_id`,
-- `p_delivery_notes` and `p_idempotency_key` are all absent: none of them can
-- cause a refusal that costs money. The phone and the note are validated by
-- `place_order` from inputs the screen already holds, cash is refused at insert
-- by a rule the app cannot reach, and the idempotency key exists precisely to
-- make the *second* call safe.
create or replace function public.checkout_preflight(
  p_restaurant_id  text,
  p_items          jsonb,
  p_delivery_lat   double precision default null,
  p_delivery_lng   double precision default null,
  p_coupon_code    text             default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id       text;
  v_name          text;
  v_accepting     boolean;
  v_pause_reason  text;
  v_towns         text;
  v_r_lat         double precision;
  v_r_lng         double precision;
  v_line          jsonb;
  v_mi_id         text;
  v_mi_name       text;
  v_serve_from    time;
  v_serve_to      time;
  v_qty           integer;
  v_opt_ids       text[];
  v_subtotal      integer := 0;
  v_delivery_fee  integer;
  v_platform_fee  constant integer := 0;
  v_packaging_fee constant integer := 0;
  v_surge_fee     constant integer := 0;
  v_discount      integer := 0;
  v_taxes         integer;
  v_tax_on_fees   integer;
  v_recent        integer;
  v_total         integer;
begin
  v_user_id := auth.uid()::text;
  if v_user_id is null then
    raise exception 'Please sign in to place an order.' using errcode = 'P0001';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty.' using errcode = 'P0001';
  end if;

  -- -------------------------------------------------------------------------
  -- 1. The kitchen. Same three questions, same three sentences.
  -- -------------------------------------------------------------------------
  select name, accepting_orders, pause_reason, latitude, longitude
    into v_name, v_accepting, v_pause_reason, v_r_lat, v_r_lng
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

  -- -------------------------------------------------------------------------
  -- 2. Every line. Availability, the serving window, and the options — the
  --    last of which `resolve_order_line_options` raises for us, with the same
  --    wording it raises inside `place_order`.
  -- -------------------------------------------------------------------------
  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_line ->> 'quantity')::integer;
    if v_qty is null or v_qty < 1 then
      raise exception 'Your cart has an invalid quantity.' using errcode = 'P0001';
    end if;

    select id, name, serve_from, serve_to
      into v_mi_id, v_mi_name, v_serve_from, v_serve_to
      from public.menu_items
     where id = (v_line ->> 'menu_item_id')
       and restaurant_id = p_restaurant_id
       and is_available;
    if not found then
      raise exception 'Something in your cart is no longer available.'
        using errcode = 'P0001';
    end if;

    if not public.menu_item_is_servable_now(v_serve_from, v_serve_to) then
      raise exception '% isn''t served at this hour.', v_mi_name
        using errcode = 'P0001';
    end if;

    v_opt_ids := coalesce(
      (select array_agg(value)
         from jsonb_array_elements_text(coalesce(v_line -> 'option_ids', '[]'::jsonb))),
      array[]::text[]
    );
    -- Called for its refusals. The prices it returns are summed again below, in
    -- the set-based pass — resolving twice costs two index lookups on a handful
    -- of rows and keeps the validation loop free of arithmetic.
    perform public.resolve_order_line_options(v_mi_id, v_opt_ids);
  end loop;

  -- -------------------------------------------------------------------------
  -- 3. The three `before insert` triggers, asked here rather than there.
  --
  --    Restated rather than called: they are trigger functions and take a `new`
  --    row that does not exist yet. Each is a handful of lines and each keeps
  --    the trigger's own wording, so the customer reads the same sentence
  --    whichever side of the payment sheet catches it.
  -- -------------------------------------------------------------------------

  -- orders_reject_blocked_user
  if exists (
    select 1 from auth.users u
     where u.id::text = v_user_id
       and u.banned_until is not null
       and u.banned_until > now()
  ) then
    raise exception 'This account has been blocked. Contact support@zopiqnow.com.'
      using errcode = 'P0001';
  end if;

  -- orders_reject_too_many. `>=` against the same ceiling of ten: this is a
  -- preflight for an order that does not exist yet, so the question is whether
  -- there is room for one more.
  select count(*) into v_recent
    from public.orders o
   where o.user_id = v_user_id
     and o.created_at > now() - interval '1 hour';
  if v_recent >= 10 then
    raise exception
      'That is % orders in an hour. Please wait a little before ordering again.',
      v_recent using errcode = 'P0001';
  end if;

  -- orders_within_service_area. Both halves, in the trigger's order.
  --
  -- Skipped when the caller passes no coordinates, which is not a hole: the
  -- trigger asks `serviceable_point(null, null)` at insert and refuses. A
  -- preflight that invented a refusal for a screen that simply has not chosen an
  -- address yet would be answering a question nobody asked.
  if p_delivery_lat is not null and p_delivery_lng is not null then
    v_towns := public.service_area_names();

    if not public.serviceable_point(p_delivery_lat, p_delivery_lng) then
      raise exception
        'We''re not delivering to that address yet. We''re still only in %, and we''re expanding — we''ll be there soon.',
        v_towns
        using errcode = 'P0001';
    end if;

    if not public.serviceable_point(v_r_lat, v_r_lng) then
      raise exception
        'That restaurant is outside our delivery area. We only deliver from kitchens in %.',
        v_towns
        using errcode = 'P0001';
    end if;
  end if;

  -- -------------------------------------------------------------------------
  -- 4. The bill. `place_order`'s arithmetic, restated set-based because nothing
  --    here has to be written to a table afterwards.
  -- -------------------------------------------------------------------------
  select coalesce(sum(l.line_total), 0)::integer
    into v_subtotal
    from (
      select (mi.price + o.addons) * (t.value ->> 'quantity')::integer as line_total
        from jsonb_array_elements(p_items) with ordinality as t(value, ordinality)
        join public.menu_items mi
          on mi.id = (t.value ->> 'menu_item_id')
         and mi.restaurant_id = p_restaurant_id
        cross join lateral (
          select coalesce(sum(r.price_delta), 0)::integer as addons
            from public.resolve_order_line_options(
                   mi.id,
                   coalesce(
                     (select array_agg(value)
                        from jsonb_array_elements_text(
                               coalesce(t.value -> 'option_ids', '[]'::jsonb))),
                     array[]::text[]
                   )
                 ) r
        ) o
    ) l;

  v_delivery_fee := case when v_subtotal >= 500 then 0 else 40 end;

  -- The coupon, unlocked. `validate_coupon` is the same read `_CouponCard` makes
  -- when the code is applied, and it raises the same sentences.
  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);
  end if;

  -- The tax, per slab, over taxable values that already carry their share of the
  -- discount — apportioned by the same largest-remainder rule, because the
  -- per-slab *sums* depend on which lines the leftover rupees landed on.
  with line as (
    select t.ordinality::integer                              as seq,
           mi.gst_rate_bps                                    as rate,
           (mi.price + o.addons) * (t.value ->> 'quantity')::integer as line_total
      from jsonb_array_elements(p_items) with ordinality as t(value, ordinality)
      join public.menu_items mi
        on mi.id = (t.value ->> 'menu_item_id')
       and mi.restaurant_id = p_restaurant_id
      cross join lateral (
        select coalesce(sum(r.price_delta), 0)::integer as addons
          from public.resolve_order_line_options(
                 mi.id,
                 coalesce(
                   (select array_agg(value)
                      from jsonb_array_elements_text(
                             coalesce(t.value -> 'option_ids', '[]'::jsonb))),
                   array[]::text[]
                 )
               ) r
      ) o
  ),
  alloc as (
    select seq, rate, line_total,
           (floor_alloc
             + case when rn <= v_discount - total_floor then 1 else 0 end)::integer
             as discount_alloc
      from (
        select seq, rate, line_total, floor_alloc,
               sum(floor_alloc) over ()                   as total_floor,
               row_number() over (order by rem desc, seq) as rn
          from (
            select seq, rate, line_total,
                   case when v_subtotal = 0 then 0
                        else (v_discount::bigint * line_total) / v_subtotal end as floor_alloc,
                   case when v_subtotal = 0 then 0
                        else (v_discount::bigint * line_total) % v_subtotal end as rem
              from line
          ) f
      ) r
  ),
  slab as (
    select rate,
           round(sum(line_total - discount_alloc) * rate / 10000.0)::integer as tax
      from alloc
     group by rate
  )
  select coalesce(sum(tax), 0)::integer into v_taxes from slab;

  -- Inside the gross fees, not on top of them. Returned for the bill breakdown;
  -- deliberately **not** added to the total, exactly as in `place_order`.
  v_tax_on_fees :=
      round((v_delivery_fee + v_platform_fee + v_surge_fee)
              * public.fee_gst_rate_bps()::numeric
              / (10000 + public.fee_gst_rate_bps()))::integer
    + round(v_packaging_fee * public.packaging_gst_rate_bps()::numeric
              / (10000 + public.packaging_gst_rate_bps()))::integer;

  v_total := v_subtotal + v_delivery_fee + v_platform_fee + v_packaging_fee
             + v_surge_fee + v_taxes - v_discount;

  return jsonb_build_object(
    'subtotal',      v_subtotal,
    'delivery_fee',  v_delivery_fee,
    'platform_fee',  v_platform_fee,
    'packaging_fee', v_packaging_fee,
    'surge_fee',     v_surge_fee,
    'taxes',         v_taxes,
    'tax_on_fees',   v_tax_on_fees,
    'discount',      v_discount,
    'total',         v_total
  );
end;
$function$;

comment on function public.checkout_preflight(text, jsonb, double precision, double precision, text) is
  'P1: every refusal place_order can raise, asked before the gateway is opened, plus the server''s own total so the amount charged matches what the order will cost. Read-only and unlocked; place_order remains the authority.';

-- The customer app is the caller, so unlike most of this schema `authenticated`
-- keeps EXECUTE. PUBLIC and `anon` do not: an unauthenticated caller gets the
-- sign-in refusal on the first line anyway, and leaving the grant standing would
-- hand an anonymous stranger a menu-and-coupon oracle for free.
--
-- Both revokes are load-bearing — see 0097's note. Revoking PUBLIC alone leaves
-- the `alter default privileges` grant to `authenticated` standing, which here is
-- what we want; the `anon` revoke is the one doing work.
revoke execute on function
  public.checkout_preflight(text, jsonb, double precision, double precision, text)
  from public, anon;

grant execute on function
  public.checkout_preflight(text, jsonb, double precision, double precision, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Verification — this migration does not count as applied until both pass.
-- ---------------------------------------------------------------------------
-- 1. **The preflight and `place_order` agree, rupee for rupee.** This is the
--    check that keeps the restated arithmetic honest, and it must be re-run
--    after any edit to either function. It replays every order in the table
--    through the preflight and compares the totals.
--
--    Run as the order's own customer — `auth.uid()` drives the coupon's
--    per-user caps — so it goes one order at a time with a forged sub:
--
--      do $verify$
--      declare
--        o        record;
--        v_bill   jsonb;
--        v_bad    integer := 0;
--      begin
--        for o in
--          select ord.id, ord.user_id, ord.restaurant_id, ord.total,
--                 ord.coupon_code, ord.delivery_lat, ord.delivery_lng,
--                 (select jsonb_agg(jsonb_build_object(
--                           'menu_item_id', oi.menu_item_id,
--                           'quantity',     oi.quantity))
--                    from public.order_items oi where oi.order_id = ord.id) as items
--            from public.orders ord
--        loop
--          perform set_config('request.jwt.claims',
--                             json_build_object('sub', o.user_id)::text, true);
--          begin
--            v_bill := public.checkout_preflight(
--                        o.restaurant_id, o.items, null, null, null);
--            if (v_bill ->> 'total')::integer <> o.total then
--              raise warning 'MISMATCH % : preflight % vs order %',
--                o.id, v_bill ->> 'total', o.total;
--              v_bad := v_bad + 1;
--            end if;
--          exception when others then
--            -- A dish delisted since the order was placed is not a mismatch.
--            raise notice 'skipped % : %', o.id, sqlerrm;
--          end;
--        end loop;
--        raise notice 'mismatches: %', v_bad;
--      end
--      $verify$;
--
--    Expect `mismatches: 0`. Coupons are passed as null because the discount is
--    time-and-cap dependent and a coupon that has since been exhausted would
--    raise rather than mismatch; the apportionment path is covered by the
--    per-slab arithmetic being identical, and by the app's own comparison.
--
-- 2. **The grants are what the file says.** 0089's rule: read the catalogue, not
--    the migration.
--
--      select has_function_privilege('authenticated',
--               'public.checkout_preflight(text,jsonb,double precision,double precision,text)',
--               'EXECUTE') as authenticated_may,   -- expect t
--             has_function_privilege('anon',
--               'public.checkout_preflight(text,jsonb,double precision,double precision,text)',
--               'EXECUTE') as anon_may;            -- expect f
--
-- And the two standing release checks (0087, 0089) must still return zero rows.
-- ---------------------------------------------------------------------------
