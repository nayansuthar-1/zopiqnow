-- ---------------------------------------------------------------------------
-- 0068 — a dish keeps its own hours. (Phase 3, closing the menu slices)
-- ---------------------------------------------------------------------------
-- Four things a menu row could not say until now, and one a restaurant row
-- could not:
--
--   * `original_price` — a struck-through number beside the live one. **Display
--     only. Never charged.** See the warning below.
--   * `unavailable_reason` — why a dish is off. Kitchen-facing; the customer
--     never reads it, because RLS has already removed the dish they would have
--     read it on.
--   * `prep_minutes` — how long *this* dish takes, so the prep-time sheet on
--     accept (0015) can propose a number instead of guessing one.
--   * `serve_from` / `serve_to` — breakfast is not sold at 9pm.
--   * `restaurants.pause_reason` — the sentence that goes with a pause (0011),
--     so a customer is told "Kitchen closed — power cut" rather than the
--     generic refusal the platform writes on the vendor's behalf.
--
-- **On `original_price`, plainly.** This column is never read by `place_order`
-- and can never change what anyone is charged; the charged price is `price` and
-- stays `price`. It exists so a vendor can show a former price beside the
-- current one. A number that was never actually charged, presented as if it
-- were, is a misleading price claim under the CCPA's 2022 guidelines on
-- misleading advertisements and is separately exposed under Legal Metrology
-- where it reads as an MRP. Nothing in this schema fabricates the number and
-- nothing infers it from `price` — a vendor types it, and a vendor owns it.

-- ===========================================================================
-- A. The columns.
-- ===========================================================================
alter table public.menu_items
  add column if not exists original_price     integer,
  add column if not exists unavailable_reason text not null default '',
  add column if not exists prep_minutes       integer,
  add column if not exists serve_from         time,
  add column if not exists serve_to           time;

-- A struck-through price below the live one is not a discount, it is a typo.
-- Equal is refused too: a strike-through showing the same number is noise.
alter table public.menu_items
  drop constraint if exists menu_item_original_price_is_higher;
alter table public.menu_items
  add constraint menu_item_original_price_is_higher
  check (original_price is null or original_price > price);

-- A sane upper bound rather than none: four hours is already an outlier, and an
-- unbounded integer here reaches the customer's ETA as nonsense.
alter table public.menu_items
  drop constraint if exists menu_item_prep_minutes_is_sane;
alter table public.menu_items
  add constraint menu_item_prep_minutes_is_sane
  check (prep_minutes is null or (prep_minutes > 0 and prep_minutes <= 240));

-- A window is both ends or neither — a `serve_from` with no `serve_to` is a
-- half-stated rule, and there is no defensible way to read it. Zero length is
-- refused for the reason 0036 gives on `restaurant_hours`: it would be
-- ambiguous between "never" and "always", and neither is what a null means.
alter table public.menu_items
  drop constraint if exists menu_item_window_is_whole;
alter table public.menu_items
  add constraint menu_item_window_is_whole
  check (
    (serve_from is null) = (serve_to is null)
    and (serve_from is null or serve_from <> serve_to)
  );

-- ===========================================================================
-- B. Is this dish being served right now?
-- ===========================================================================
-- Takes the two times, not a dish id — so the RLS policy below can call it on
-- the row it is already looking at, without a second lookup per row, and so the
-- function itself has nothing to leak: it is arithmetic on two values the
-- caller already holds.
--
-- The midnight-crossing case is 0036's, in miniature. A window with
-- `serve_to < serve_from` (a 22:00–02:00 late-night menu) is open from
-- `serve_from` to the end of the day *and* from the start of the day to
-- `serve_to`. Half-open at both ends, `>= from` and `< to`, matching 0036: a
-- breakfast that ends at 11:00 is over at 11:00.
--
-- Not `security definer`: it reads nothing. Not `immutable` either — it reads
-- the clock, which is what `stable` is for.
create or replace function public.menu_item_is_servable_now(
  p_from time,
  p_to   time
)
returns boolean
language sql
stable
set search_path = public
as $$
  select case
    -- No window is the overwhelmingly common case and means all day, which is
    -- what every row predating this migration already is.
    when p_from is null or p_to is null then true
    when p_to > p_from then
      (now() at time zone 'Asia/Kolkata')::time >= p_from
      and (now() at time zone 'Asia/Kolkata')::time <  p_to
    else
      (now() at time zone 'Asia/Kolkata')::time >= p_from
      or  (now() at time zone 'Asia/Kolkata')::time <  p_to
  end
$$;

-- 0065's lesson: a new function is executable by PUBLIC the moment it exists,
-- so the grant that matters is the revoke before it. The RLS policy below runs
-- as the querying role, so both browsing roles need it.
revoke all on function public.menu_item_is_servable_now(time, time)
  from public, anon, authenticated;
grant execute on function public.menu_item_is_servable_now(time, time)
  to anon, authenticated;

-- ===========================================================================
-- C. The customer's menu respects the window.
-- ===========================================================================
-- 0032's policy with one clause added. The same shape the whole menu surface
-- has used since 0016: the customer app is not asked to filter anything, it
-- simply cannot see a dish outside its hours, and no customer-app release is
-- required for a serving window to start working.
--
-- The vendor's own read policy (0009, `restaurant_id = staff_restaurant_id()`)
-- is untouched: a kitchen must see its breakfast menu at 4pm to edit it, which
-- is exactly when it would otherwise vanish from its own app.
drop policy if exists "available menu items are world-readable" on public.menu_items;
create policy "available menu items are world-readable"
  on public.menu_items
  for select
  to anon, authenticated
  using (
    is_available
    and category_available
    and public.menu_item_is_servable_now(serve_from, serve_to)
    and exists (
      select 1 from public.restaurants r
       where r.id = menu_items.restaurant_id
         and r.is_active
    )
  );

-- ===========================================================================
-- D. A pause can say why.
-- ===========================================================================
-- Empty string, not null, for the reason `unavailable_reason` above is: "no
-- reason given" and "reason not yet asked for" are the same fact here, and one
-- of them being null would make every reader write the same coalesce.
alter table public.restaurants
  add column if not exists pause_reason text not null default '';

-- The signature changes, so the old one is dropped rather than replaced. Left
-- in place it would become an *overload*, and `set_accepting_orders(true)` from
-- an un-updated client would bind to whichever Postgres preferred — the exact
-- failure this project has hit before. The vendor app is updated in the same
-- commit, and there is no other caller.
drop function if exists public.set_accepting_orders(boolean);

-- Reopening clears the reason. It has to: a stale "power cut" surviving the
-- power coming back would be shown to customers by a kitchen that thinks it
-- said nothing, and nobody would go looking for a field they only ever see
-- while closed.
create or replace function public.set_accepting_orders(
  p_accepting boolean,
  p_reason    text default ''
)
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
     set accepting_orders = p_accepting,
         pause_reason = case
           when p_accepting then ''
           -- Truncated rather than refused, the same call 0064 makes on a
           -- delivery note: a kitchen pausing mid-rush must not be stopped by a
           -- character count.
           else left(trim(coalesce(p_reason, '')), 120)
         end
   where id = v_restaurant;

  return p_accepting;
end;
$$;

revoke all on function public.set_accepting_orders(boolean, text)
  from public, anon, authenticated;
grant execute on function public.set_accepting_orders(boolean, text)
  to authenticated;

-- ===========================================================================
-- E. place_order enforces both.
-- ===========================================================================
-- The whole of 0064's function, unchanged but for two places:
--
--   1. the pause refusal now carries the kitchen's own sentence when there is
--      one, so "we've stopped taking orders" becomes "we've stopped taking
--      orders: fryer is down";
--   2. every line is checked against its dish's serving window.
--
-- The second is the point. RLS (C, above) hides an out-of-hours dish from the
-- menu, but RLS is bypassed inside a `security definer` function and, more to
-- the point, a cart assembled at 10:55 is still a cart at 11:05. The pause and
-- hours gates have lived here since 0011 and 0018 for exactly this reason, and
-- a per-dish window is the same fact at a smaller scale.
--
-- Signature unchanged, so this is a replace and no app has to ship for
-- checkout to keep working. `create or replace` preserves 0065's grants.
--
-- **Known gap, deliberately left alone:** this function has never checked
-- `category_available`, so a stale cart can still order a dish from a section
-- the vendor switched off (0016). Same class of hole as the one being closed
-- here; out of scope for this change and flagged rather than fixed.
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
  v_pause_reason text;
  v_notes        text;
  v_line         jsonb;
  v_seq          integer;
  v_mi_id        text;
  v_mi_name      text;
  v_base         integer;
  v_serve_from   time;
  v_serve_to     time;
  v_qty          integer;
  v_opt_ids      text[];
  v_opts         jsonb;
  v_addons       integer;
  v_unit         integer;
  v_line_total   integer;
  v_line_id      bigint;
  v_row          record;
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

  select name, eta_minutes, accepting_orders, pause_reason
    into v_name, v_eta, v_accepting, v_pause_reason
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
    seq          integer,
    menu_item_id text,
    name         text,
    unit_price   integer,
    quantity     integer,
    line_total   integer,
    options      jsonb
  ) on commit drop;

  for v_line, v_seq in
    select value, ordinality from jsonb_array_elements(p_items) with ordinality
  loop
    v_qty := (v_line ->> 'quantity')::integer;
    if v_qty is null or v_qty < 1 then
      raise exception 'Your cart has an invalid quantity.' using errcode = 'P0001';
    end if;

    select id, name, price, serve_from, serve_to
      into v_mi_id, v_mi_name, v_base, v_serve_from, v_serve_to
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

    insert into _lines
      values (v_seq, v_mi_id, v_mi_name, v_unit, v_qty, v_line_total, v_opts);
  end loop;

  v_delivery_fee := case when v_subtotal >= 500 then 0 else 40 end;
  v_taxes := round(v_subtotal * 0.05)::integer;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);
  end if;

  v_total := v_subtotal + v_delivery_fee + v_taxes - v_discount;

  insert into public.orders (
    user_id, user_phone, restaurant_id, restaurant_name,
    subtotal, delivery_fee, taxes, discount, total,
    coupon_code, payment_method, payment_id,
    delivery_to, delivery_lat, delivery_lng, delivery_notes, eta_minutes
  ) values (
    v_user_id, p_user_phone, p_restaurant_id, v_name,
    v_subtotal, v_delivery_fee, v_taxes, v_discount, v_total,
    nullif(upper(trim(coalesce(p_coupon_code, ''))), ''), p_payment_method, p_payment_id,
    p_delivery_to, p_delivery_lat, p_delivery_lng, v_notes, v_eta
  ) returning id into v_order_id;

  -- Pass two: the lines, in order, each with its frozen options.
  for v_row in select * from _lines order by seq
  loop
    insert into public.order_items
      (order_id, menu_item_id, name, unit_price, quantity, line_total)
    values (v_order_id, v_row.menu_item_id, v_row.name, v_row.unit_price,
            v_row.quantity, v_row.line_total)
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
