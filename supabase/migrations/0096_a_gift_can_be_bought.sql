-- ---------------------------------------------------------------------------
-- 0096 — a gift can be bought
-- ---------------------------------------------------------------------------
-- The Gifts tab has been a catalogue since 0022: two world-readable tables, a
-- shop page, an item sheet whose only button closes it. Everything to *look* and
-- nothing to *buy*. This is the buying half.
--
-- ## Why this is not the food pipeline
--
-- A gift shop is not a restaurant and cannot be made into one cheaply.
-- `gift_shops` has no owner, no staff row, no address and no coordinates — and
-- every part of the food machinery depends on all four. `staff_restaurant_id()`
-- is what lets a kitchen see an order; `restaurants.lat/lng` is what dispatch
-- routes from; the rider board offers runs between two points. A gift shop has
-- none of that and giving it all of it is a different project.
--
-- So gift orders are **fulfilled by Zopiqnow, and couriered by Zopiqnow**. There
-- is no vendor app in this story and no rider. An order lands in a queue in the
-- admin console; somebody there accepts it, packs it, hands it to a courier, and
-- records who and what the tracking number is. The customer sees each of those
-- as it happens.
--
-- That is a deliberate v1, not a shortcut around a hard part: a curated
-- catalogue of a few dozen items does not need a seller-facing app, and building
-- one before there is a seller to use it is how a product grows screens nobody
-- opens. When gift sellers do exist, they get rows in these same tables.
--
-- ## Prices are exclusive of GST, like food
--
-- `menu_items.price` is exclusive and `place_order` adds the tax; gifts follow
-- exactly. `gift_items` gains `gst_rate_bps` (default 1800 — 18%, the commonest
-- non-food slab) so a 12% handicraft or a 28% luxury item is one UPDATE away
-- rather than a migration.
--
-- The rounding is 0082's, copied deliberately rather than simplified: **once per
-- slab**, then handed down to the lines of that slab by largest remainder.
-- Rounding each line alone and summing gives a different number, and the
-- rate-wise total is the figure a GST invoice states.
--
-- ## No coupons, no fees, no discounts in v1
--
-- Every one of those is a real thing with a real ledger on the food side, and
-- none of them has a gift equivalent yet. `gift_settings.delivery_fee` exists,
-- defaults to 0, and is one UPDATE from being charged — so the courier can be
-- billed for the day somebody decides it should be, without a schema change.
-- Until then a gift costs its price plus its tax, and the receipt says so.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The rate a gift is taxed at.
-- ---------------------------------------------------------------------------
alter table public.gift_items
  add column if not exists gst_rate_bps integer not null default 1800;

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'gift_items_gst_rate_bps_check'
  ) then
    alter table public.gift_items add constraint gift_items_gst_rate_bps_check
      check (gst_rate_bps >= 0 and gst_rate_bps <= 10000);
  end if;
end $$;

comment on column public.gift_items.gst_rate_bps is
  'GST in basis points, exclusive of the listed price. 1800 = 18%, the default non-food slab; 1200 and 2800 are the other two a gift is likely to be.';

-- ---------------------------------------------------------------------------
-- 2. One knob, so a courier fee never needs a migration.
-- ---------------------------------------------------------------------------
create table if not exists public.gift_settings (
  id           boolean primary key default true check (id),
  delivery_fee integer not null default 0 check (delivery_fee >= 0),
  updated_at   timestamptz not null default now()
);

insert into public.gift_settings (id) values (true) on conflict (id) do nothing;

alter table public.gift_settings enable row level security;
revoke all on public.gift_settings from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. The order.
-- ---------------------------------------------------------------------------
-- `ZPG-`, not `ZPQ-`, and its own sequence. A gift order and a food order are
-- different things with different lifecycles, and an id that says which one it
-- is saves every future reader a lookup.
create sequence if not exists public.gift_order_seq start 1001;

create table if not exists public.gift_orders (
  id            text primary key default 'ZPG-' || nextval('public.gift_order_seq'),

  user_id       text not null,
  user_phone    text not null,

  shop_id       text not null references public.gift_shops (id),
  -- Frozen at write time, like `orders.restaurant_name`. A shop that renames
  -- itself must not rewrite what somebody bought last month.
  shop_name     text not null,

  subtotal      integer not null check (subtotal >= 0),
  delivery_fee  integer not null default 0 check (delivery_fee >= 0),
  taxes         integer not null check (taxes >= 0),
  cgst          integer not null default 0,
  sgst          integer not null default 0,
  igst          integer not null default 0,
  total         integer not null check (total >= 0),

  -- UPI only, for 0084's reason: nothing new is paid in cash.
  payment_method text not null default 'upi' check (payment_method = 'upi'),
  payment_id     text,

  delivery_to    text not null,
  delivery_notes text,

  -- The whole life of a couriered gift. No `packed`: the customer cannot act on
  -- it and it is one more state for somebody to forget to set.
  status         text not null default 'placed' check (status in (
    'placed', 'accepted', 'dispatched', 'delivered', 'cancelled'
  )),
  status_reason  text,

  -- Written when it goes out. Both null until then, and both shown to the
  -- customer — a tracking number they cannot see is a tracking number for us.
  courier_name   text,
  tracking_ref   text,

  accepted_at    timestamptz,
  dispatched_at  timestamptz,
  delivered_at   timestamptz,

  -- One per checkout attempt, reused on retry — 0086's rule, same reason: a
  -- lost response must be safe to retry without buying the gift twice.
  idempotency_key text,

  created_at     timestamptz not null default now()
);

create unique index if not exists gift_orders_idempotency_idx
  on public.gift_orders (user_id, idempotency_key)
  where idempotency_key is not null;

create index if not exists gift_orders_mine_idx
  on public.gift_orders (user_id, created_at desc);
create index if not exists gift_orders_queue_idx
  on public.gift_orders (status, created_at asc);

create table if not exists public.gift_order_items (
  id           bigint generated always as identity primary key,
  order_id     text not null references public.gift_orders (id) on delete cascade,

  -- Not a foreign key on purpose. A receipt has to survive the shop deleting the
  -- item, and every field needed to read the line is copied beside it.
  gift_item_id text not null,
  name         text not null,
  unit_price   integer not null check (unit_price > 0),
  quantity     integer not null check (quantity > 0),
  line_total   integer not null check (line_total > 0),
  gst_rate_bps integer not null,
  tax_amount   integer not null check (tax_amount >= 0)
);

create index if not exists gift_order_items_order_idx
  on public.gift_order_items (order_id);

alter table public.gift_orders enable row level security;
alter table public.gift_order_items enable row level security;

-- Born writable to `anon` (0089). Revoked outright, no policy, no grant: every
-- read and write goes through a security-definer function below.
revoke all on public.gift_orders from public, anon, authenticated;
revoke all on public.gift_order_items from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Buying one.
-- ---------------------------------------------------------------------------
-- Takes no prices. The client sends ids and quantities and this function prices
-- them out of `gift_items` — the same rule `place_order` follows, and the reason
-- is the same: a client that can quote a total can get one wrong on purpose.
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
  v_user      text;
  v_shop      text;
  v_subtotal  integer;
  v_fee       integer;
  v_taxes     integer;
  v_liability integer;
  v_cgst      integer;
  v_sgst      integer;
  v_total     integer;
  v_id        text;
  v_notes     text;
  v_existing  text;
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

  select s.name into v_shop
    from public.gift_shops s
   where s.id = p_shop_id and s.is_active;
  if not found then
    raise exception 'That gift shop is not open right now.'
      using errcode = 'P0001';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Your gift bag is empty.' using errcode = 'P0001';
  end if;

  if nullif(trim(coalesce(p_delivery_to, '')), '') is null then
    raise exception 'We need an address to send this to.' using errcode = 'P0001';
  end if;

  v_notes := nullif(trim(coalesce(p_delivery_notes, '')), '');

  -- Priced here, from the catalogue, at this instant.
  --
  -- Dropped first, not just `on commit drop`. Over HTTP every RPC is its own
  -- transaction so the question never arises — but `on commit drop` alone means
  -- a second call inside one transaction dies on "relation _lines already
  -- exists", which is a trap for anything that batches (a test, a backfill, a
  -- future function that places two). One line, and the shape stops being
  -- sensitive to how it is called.
  drop table if exists _lines;
  create temp table _lines on commit drop as
  select row_number() over ()                      as seq,
         g.id                                      as gift_item_id,
         g.name,
         g.price                                   as unit_price,
         (i ->> 'quantity')::integer               as quantity,
         g.price * (i ->> 'quantity')::integer     as line_total,
         g.gst_rate_bps,
         0::integer                                as tax_amount
    from jsonb_array_elements(p_items) as i
    join public.gift_items g
      on g.id = (i ->> 'gift_item_id')
     and g.shop_id = p_shop_id
     and g.is_available;

  if (select count(*) from _lines) <> jsonb_array_length(p_items) then
    raise exception 'Something in your gift bag is no longer available.'
      using errcode = 'P0001';
  end if;

  if exists (select 1 from _lines where quantity <= 0 or quantity > 20) then
    raise exception 'Choose between 1 and 20 of each item.'
      using errcode = 'P0001';
  end if;

  select coalesce(sum(line_total), 0) into v_subtotal from _lines;

  -- 0082's rounding, verbatim in shape: once per slab, then down to the lines of
  -- that slab by largest remainder. There are no discounts on a gift, so the
  -- taxable value of a line *is* its total — but the slab arithmetic still
  -- matters the moment a bag holds an 18% mug and a 12% scarf.
  update _lines l
     set tax_amount = (
           r.floor_tax
             + case when r.rn <= r.slab_tax - r.total_floor then 1 else 0 end
         )::integer
    from (
      select seq,
             floor_tax,
             slab_tax,
             sum(floor_tax) over (partition by gst_rate_bps)                     as total_floor,
             row_number() over (partition by gst_rate_bps order by rem desc, seq) as rn
        from (
          select l2.seq,
                 l2.gst_rate_bps,
                 s.tax as slab_tax,
                 case when s.base = 0 then 0
                      else (s.tax::bigint * l2.line_total) / s.base end as floor_tax,
                 case when s.base = 0 then 0
                      else (s.tax::bigint * l2.line_total) % s.base end as rem
            from _lines l2
            join (
              select gst_rate_bps,
                     sum(line_total)                                          as base,
                     round(sum(line_total) * gst_rate_bps / 10000.0)::integer as tax
                from _lines
               group by gst_rate_bps
            ) s on s.gst_rate_bps = l2.gst_rate_bps
        ) f
    ) r
   where r.seq = l.seq;

  select coalesce(sum(tax_amount), 0)::integer into v_taxes from _lines;

  select delivery_fee into v_fee from public.gift_settings where id;
  v_fee := coalesce(v_fee, 0);

  -- Same split as food, and for the same reason: nothing here crosses a state
  -- line that this schema can see, so IGST stays 0 rather than being guessed.
  v_liability := v_taxes;
  v_cgst := round(v_liability / 2.0)::integer;
  v_sgst := v_liability - v_cgst;

  v_total := v_subtotal + v_fee + v_taxes;

  insert into public.gift_orders (
    user_id, user_phone, shop_id, shop_name,
    subtotal, delivery_fee, taxes, cgst, sgst, total,
    payment_method, payment_id, delivery_to, delivery_notes, idempotency_key
  ) values (
    v_user, p_user_phone, p_shop_id, v_shop,
    v_subtotal, v_fee, v_taxes, v_cgst, v_sgst, v_total,
    'upi', p_payment_id, p_delivery_to, v_notes, p_idempotency_key
  ) returning id into v_id;

  insert into public.gift_order_items
    (order_id, gift_item_id, name, unit_price, quantity, line_total,
     gst_rate_bps, tax_amount)
  select v_id, gift_item_id, name, unit_price, quantity, line_total,
         gst_rate_bps, tax_amount
    from _lines;

  return jsonb_build_object(
    'id', v_id, 'total', v_total, 'shop_name', v_shop,
    'payment_id', p_payment_id, 'delivery_to', p_delivery_to,
    'status', 'placed'
  );
end;
$$;

revoke all on function public.place_gift_order(
  text, text, jsonb, text, text, text, text) from public, anon;
grant execute on function public.place_gift_order(
  text, text, jsonb, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. What the customer sees.
-- ---------------------------------------------------------------------------
create or replace function public.my_gift_orders()
returns table (
  id            text,
  shop_name     text,
  subtotal      integer,
  delivery_fee  integer,
  taxes         integer,
  total         integer,
  status        text,
  status_reason text,
  courier_name  text,
  tracking_ref  text,
  delivery_to   text,
  created_at    timestamptz,
  dispatched_at timestamptz,
  delivered_at  timestamptz,
  item_count    integer
)
language sql
stable
security definer
set search_path = public
as $$
  select o.id, o.shop_name, o.subtotal, o.delivery_fee, o.taxes, o.total,
         o.status, o.status_reason, o.courier_name, o.tracking_ref,
         o.delivery_to, o.created_at, o.dispatched_at, o.delivered_at,
         (select count(*)::integer from public.gift_order_items i
           where i.order_id = o.id)
    from public.gift_orders o
   where o.user_id = auth.uid()::text
   order by o.created_at desc;
$$;

revoke all on function public.my_gift_orders() from public, anon;
grant execute on function public.my_gift_orders() to authenticated;

-- The lines on one of their own orders. Separate from the header so the list
-- screen does not pull every line of every order it will never show.
create or replace function public.my_gift_order_items(p_order_id text)
returns table (
  name       text,
  unit_price integer,
  quantity   integer,
  line_total integer,
  tax_amount integer
)
language sql
stable
security definer
set search_path = public
as $$
  select i.name, i.unit_price, i.quantity, i.line_total, i.tax_amount
    from public.gift_order_items i
    join public.gift_orders o on o.id = i.order_id
   where i.order_id = p_order_id
     and o.user_id = auth.uid()::text
   order by i.id;
$$;

revoke all on function public.my_gift_order_items(text) from public, anon;
grant execute on function public.my_gift_order_items(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Calling it off.
-- ---------------------------------------------------------------------------
-- Only before it is handed to a courier. Once it is dispatched there is a parcel
-- in somebody's van, and a button that pretended to recall it would be a lie.
create or replace function public.cancel_my_gift_order(
  p_order_id text,
  p_reason   text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_says   text;
begin
  select status into v_status
    from public.gift_orders
   where id = p_order_id and user_id = auth.uid()::text
   for update;

  if not found then
    raise exception 'We couldn''t find that order on your account.'
      using errcode = 'P0001';
  end if;

  if v_status not in ('placed', 'accepted') then
    -- Built first and raised as a value: `raise` takes a format *literal*, not
    -- an expression, so a `case` inline here is a syntax error.
    v_says := case v_status
      when 'dispatched' then 'This one is already with the courier. Contact support and we''ll sort it out.'
      when 'delivered'  then 'This one has already arrived.'
      else 'This order has already been called off.'
    end;
    raise exception '%', v_says using errcode = 'P0001';
  end if;

  update public.gift_orders
     set status = 'cancelled',
         status_reason = nullif(trim(coalesce(p_reason, '')), '')
   where id = p_order_id;

  return 'cancelled';
end;
$$;

revoke all on function public.cancel_my_gift_order(text, text) from public, anon;
grant execute on function public.cancel_my_gift_order(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. The queue somebody works.
-- ---------------------------------------------------------------------------
create or replace function public.admin_gift_orders(
  p_status text    default null,
  p_limit  integer default 50,
  p_offset integer default 0
)
returns table (
  id             text,
  shop_id        text,
  shop_name      text,
  status         text,
  status_reason  text,
  subtotal       integer,
  delivery_fee   integer,
  taxes          integer,
  total          integer,
  payment_id     text,
  customer_phone text,
  delivery_to    text,
  delivery_notes text,
  courier_name   text,
  tracking_ref   text,
  created_at     timestamptz,
  dispatched_at  timestamptz,
  delivered_at   timestamptz,
  item_count     integer,
  total_count    bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit integer;
begin
  perform public.assert_admin();
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  with matched as (
    select o.*, (select count(*)::integer from public.gift_order_items i
                  where i.order_id = o.id) as n
      from public.gift_orders o
     where p_status is null or o.status = p_status
  )
  select m.id, m.shop_id, m.shop_name, m.status, m.status_reason,
         m.subtotal, m.delivery_fee, m.taxes, m.total, m.payment_id,
         m.user_phone, m.delivery_to, m.delivery_notes,
         m.courier_name, m.tracking_ref,
         m.created_at, m.dispatched_at, m.delivered_at,
         m.n, count(*) over () as total_count
    from matched m
   -- Oldest first. A worklist is worked from the bottom.
   order by m.created_at asc
   limit v_limit offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.admin_gift_orders(text, integer, integer)
  from public, anon;
grant execute on function public.admin_gift_orders(text, integer, integer)
  to authenticated;

create or replace function public.admin_gift_order_items(p_order_id text)
returns table (
  name       text,
  unit_price integer,
  quantity   integer,
  line_total integer,
  tax_amount integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();
  return query
  select i.name, i.unit_price, i.quantity, i.line_total, i.tax_amount
    from public.gift_order_items i
   where i.order_id = p_order_id
   order by i.id;
end;
$$;

revoke all on function public.admin_gift_order_items(text) from public, anon;
grant execute on function public.admin_gift_order_items(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Moving one along.
-- ---------------------------------------------------------------------------
-- The ladder, and it only goes one way:
--
--   placed     → accepted, cancelled
--   accepted   → dispatched, cancelled
--   dispatched → delivered
--   delivered  → nothing
--
-- `dispatched` is the one step that demands something: a courier name. A parcel
-- marked "on its way" with nobody named is a customer who cannot ask anybody
-- anything. The tracking number is optional — not every courier issues one — and
-- the customer sees whichever of the two exists.
create or replace function public.admin_set_gift_order_status(
  p_order_id     text,
  p_status       text,
  p_courier_name text default null,
  p_tracking_ref text default null,
  p_reason       text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current text;
  v_allowed text[];
  v_courier text;
begin
  perform public.assert_admin();

  select status into v_current
    from public.gift_orders where id = p_order_id for update;
  if not found then
    raise exception 'No such gift order.' using errcode = 'P0001';
  end if;

  v_allowed := case v_current
    when 'placed'     then array['accepted', 'cancelled']
    when 'accepted'   then array['dispatched', 'cancelled']
    when 'dispatched' then array['delivered']
    else array[]::text[]
  end;

  if not (p_status = any (v_allowed)) then
    raise exception 'A gift order that is % cannot become %.', v_current, p_status
      using errcode = 'P0001';
  end if;

  v_courier := nullif(trim(coalesce(p_courier_name, '')), '');
  if p_status = 'dispatched' and v_courier is null then
    raise exception 'Name the courier before marking this dispatched.'
      using errcode = 'P0001';
  end if;

  update public.gift_orders
     set status = p_status,
         status_reason = case
           when p_status = 'cancelled'
             then nullif(trim(coalesce(p_reason, '')), '')
           else status_reason
         end,
         courier_name = case
           when p_status = 'dispatched' then v_courier else courier_name
         end,
         tracking_ref = case
           when p_status = 'dispatched'
             then nullif(trim(coalesce(p_tracking_ref, '')), '')
           else tracking_ref
         end,
         accepted_at   = case when p_status = 'accepted'   then now() else accepted_at   end,
         dispatched_at = case when p_status = 'dispatched' then now() else dispatched_at end,
         delivered_at  = case when p_status = 'delivered'  then now() else delivered_at  end
   where id = p_order_id;

  return p_status;
end;
$$;

revoke all on function public.admin_set_gift_order_status(
  text, text, text, text, text) from public, anon;
grant execute on function public.admin_set_gift_order_status(
  text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. The trail.
-- ---------------------------------------------------------------------------
-- Status changes only, the shape 0092 uses for refunds and settlements. Not on
-- insert: an insert is a customer buying something, and the admin trail is for
-- what admins did.
drop trigger if exists gift_orders_audit_status on public.gift_orders;
create trigger gift_orders_audit_status after update on public.gift_orders
  for each row when (old.status is distinct from new.status)
  execute function public.record_admin_action('id');
