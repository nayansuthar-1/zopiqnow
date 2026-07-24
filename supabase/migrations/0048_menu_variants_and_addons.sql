-- Migration 48: a dish can ask a question before it is ordered.
--
-- Phase 3, the big menu slice: variants and add-ons. Until now a menu item was a
-- single name at a single price. A real menu is not: a biryani comes Half or
-- Full, a pizza takes extra cheese, a thali lets you pick two of four sides.
-- This adds that, with one pricing rule for all of it.
--
-- **One idea, not two.** A "variant" (Half/Full, a size) and an "add-on" (extra
-- cheese) are the same thing wearing different rules. Both are a *group* of
-- *options*, each option carrying a price. The only difference is how many you
-- must pick: a variant group is "exactly one" (min 1, max 1); an add-on group is
-- "any of these" (min 0, max N). So there is no `type` column deciding behaviour
-- — the min/max *is* the behaviour, and the app reads a required-single group as
-- a variant and everything else as add-ons.
--
-- **The pricing rule, stated once and true everywhere:**
--
--     unit price = menu_items.price + Σ(price_delta of chosen options)
--
-- `menu_items.price` is the dish at its cheapest configuration; every option is a
-- delta on top (₹0 or more). Half is the base, Full is "+₹80". Extra cheese is
-- "+₹30". The order service computes this, never the client — the same reason
-- pricing has lived server-side since 0002.
--
-- **Nothing forces a customer release.** `place_order`'s signature is unchanged
-- (the chosen options ride inside each line's existing jsonb), and a line that
-- names no option for a required group is *filled with that group's default*
-- (its cheapest available option) rather than refused. So a customer build that
-- knows nothing about options still orders successfully — it just gets the
-- default variant. The customer UI that lets people choose ships on top of this,
-- not before it.

-- ---------------------------------------------------------------------------
-- The groups: a question a dish asks.
-- ---------------------------------------------------------------------------
create table if not exists public.menu_option_groups (
  id            text primary key default gen_random_uuid()::text,
  menu_item_id  text not null references public.menu_items (id) on delete cascade,

  -- "Choose a size", "Extra toppings" — the heading the customer reads.
  name          text not null,

  -- How many of this group's options must and may be chosen. A variant is
  -- (1, 1); an add-on group is (0, N). The check keeps the pair sane; the app
  -- reads (1,1) as a variant and renders radios, everything else as checkboxes.
  min_select    integer not null default 0 check (min_select >= 0),
  max_select    integer not null default 1 check (max_select >= 1),

  rank          integer not null default 0,
  created_at    timestamptz not null default now(),

  constraint option_group_max_ge_min check (max_select >= min_select)
);

create index if not exists menu_option_groups_item_idx
  on public.menu_option_groups (menu_item_id, rank);

-- ---------------------------------------------------------------------------
-- The options: the answers, each with its price.
-- ---------------------------------------------------------------------------
create table if not exists public.menu_options (
  id            text primary key default gen_random_uuid()::text,
  group_id      text not null references public.menu_option_groups (id) on delete cascade,

  name          text not null,

  -- Whole rupees added to the dish's base price. `>= 0` because the base price
  -- is defined as the cheapest configuration — a cheaper option would mean the
  -- base was set wrong, not that an option subtracts.
  price_delta   integer not null default 0 check (price_delta >= 0),

  -- A single option can sell out (no more paneer) without deleting it or the
  -- group. An unavailable option is unreadable to customers and refused by the
  -- order service, exactly like an unavailable dish.
  is_available  boolean not null default true,

  rank          integer not null default 0,
  created_at    timestamptz not null default now()
);

create index if not exists menu_options_group_idx
  on public.menu_options (group_id, rank);

-- ---------------------------------------------------------------------------
-- Who may read the menu's questions.
-- ---------------------------------------------------------------------------
-- Two readers, the same split the rest of the menu already has. The customer
-- reads the options of a *visible* dish (its `is_available`), and only the
-- *available* options — the menu_items policy (0002) is `using (is_available)`,
-- and these line up with it so a hidden dish's options are hidden too. The
-- vendor reads *its own* dishes' options whatever their state, so the editor can
-- show a sold-out option to turn it back on — the same `staff_restaurant_id()`
-- path order_items uses (0009).
alter table public.menu_option_groups enable row level security;
alter table public.menu_options enable row level security;

drop policy if exists "groups of visible dishes are world-readable" on public.menu_option_groups;
create policy "groups of visible dishes are world-readable"
  on public.menu_option_groups for select to anon, authenticated
  using (
    exists (
      select 1 from public.menu_items m
       where m.id = menu_option_groups.menu_item_id and m.is_available
    )
  );

drop policy if exists "staff read their restaurant's option groups" on public.menu_option_groups;
create policy "staff read their restaurant's option groups"
  on public.menu_option_groups for select to authenticated
  using (
    exists (
      select 1 from public.menu_items m
       where m.id = menu_option_groups.menu_item_id
         and m.restaurant_id = public.staff_restaurant_id()
    )
  );

drop policy if exists "available options of visible dishes are world-readable" on public.menu_options;
create policy "available options of visible dishes are world-readable"
  on public.menu_options for select to anon, authenticated
  using (
    is_available and exists (
      select 1
        from public.menu_option_groups g
        join public.menu_items m on m.id = g.menu_item_id
       where g.id = menu_options.group_id and m.is_available
    )
  );

drop policy if exists "staff read their restaurant's options" on public.menu_options;
create policy "staff read their restaurant's options"
  on public.menu_options for select to authenticated
  using (
    exists (
      select 1
        from public.menu_option_groups g
        join public.menu_items m on m.id = g.menu_item_id
       where g.id = menu_options.group_id
         and m.restaurant_id = public.staff_restaurant_id()
    )
  );

grant select on public.menu_option_groups to anon, authenticated;
grant select on public.menu_options to anon, authenticated;

-- ---------------------------------------------------------------------------
-- The write: a vendor sets a dish's whole customisation at once.
-- ---------------------------------------------------------------------------
-- One intent — "this is how this dish is customised now" — so one wholesale
-- swap, the same shape as set_restaurant_hours (0018): delete the dish's groups
-- (options cascade) and insert the new ones in a single transaction. No update
-- grant on either table; this is the only door, and it opens only for a dish the
-- caller's own restaurant owns.
--
-- Ids are generated here, not sent by the client — an option is identified by
-- what it is, not by a handle the client made up, and a wholesale replace means
-- yesterday's ids are gone anyway. Past orders are unaffected: order lines record
-- the option's *name and price* (below), never a foreign key into this table.
--
-- p_groups shape:
--   [{ "name": "...", "min_select": 1, "max_select": 1, "rank": 0,
--      "options": [{ "name": "...", "price_delta": 0, "is_available": true, "rank": 0 }, …] }, …]
create or replace function public.set_menu_item_options(
  p_menu_item_id text,
  p_groups       jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_group      jsonb;
  v_group_id   text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  -- The dish must be one of ours. A vendor cannot attach options to another
  -- restaurant's menu.
  if not exists (
    select 1 from public.menu_items
     where id = p_menu_item_id and restaurant_id = v_restaurant
  ) then
    raise exception 'That dish is not on your menu.' using errcode = 'P0001';
  end if;

  -- Out with the old — options cascade with their group.
  delete from public.menu_option_groups where menu_item_id = p_menu_item_id;

  -- In with the new.
  for v_group in select * from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb))
  loop
    insert into public.menu_option_groups
      (menu_item_id, name, min_select, max_select, rank)
    values (
      p_menu_item_id,
      v_group ->> 'name',
      coalesce((v_group ->> 'min_select')::integer, 0),
      coalesce((v_group ->> 'max_select')::integer, 1),
      coalesce((v_group ->> 'rank')::integer, 0)
    )
    returning id into v_group_id;

    insert into public.menu_options
      (group_id, name, price_delta, is_available, rank)
    select
      v_group_id,
      o ->> 'name',
      coalesce((o ->> 'price_delta')::integer, 0),
      coalesce((o ->> 'is_available')::boolean, true),
      coalesce((o ->> 'rank')::integer, 0)
    from jsonb_array_elements(coalesce(v_group -> 'options', '[]'::jsonb)) as o;
  end loop;
end;
$$;

grant execute on function public.set_menu_item_options(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- What an order line remembers about its choices.
-- ---------------------------------------------------------------------------
-- The name and price of each chosen option, denormalised onto the order line for
-- the same reason order_items denormalises the dish's name and price (0003): a
-- receipt must not change when the vendor renames "Extra cheese" or the option
-- is deleted next week. No foreign key into menu_options — the choice outlives
-- the option.
create table if not exists public.order_item_options (
  id             bigserial primary key,
  order_item_id  bigint not null references public.order_items (id) on delete cascade,

  name           text    not null,
  price_delta    integer not null check (price_delta >= 0)
);

create index if not exists order_item_options_line_idx
  on public.order_item_options (order_item_id);

-- Read paths mirror order_items exactly: the customer sees the options on their
-- own order; the vendor sees them on an order to their restaurant. Both hop
-- through order_items to the order, where the ownership actually lives.
alter table public.order_item_options enable row level security;

drop policy if exists "customers read their own order line options" on public.order_item_options;
create policy "customers read their own order line options"
  on public.order_item_options for select to authenticated
  using (
    exists (
      select 1
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
       where oi.id = order_item_options.order_item_id
         and o.user_id = auth.uid()::text
    )
  );

drop policy if exists "staff read their restaurant's order line options" on public.order_item_options;
create policy "staff read their restaurant's order line options"
  on public.order_item_options for select to authenticated
  using (
    exists (
      select 1
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
       where oi.id = order_item_options.order_item_id
         and o.restaurant_id = public.staff_restaurant_id()
    )
  );

grant select on public.order_item_options to authenticated;

-- ---------------------------------------------------------------------------
-- Resolving one line's options: validate, fill defaults, return what to charge.
-- ---------------------------------------------------------------------------
-- Given a dish and the option ids a line claims, this returns the *effective*
-- options — the ones actually charged — or raises if the claim is impossible.
-- Pulled out of place_order so the order service reads as a list of lines, not a
-- thicket of option arithmetic.
--
-- The rules it enforces:
--   * every claimed id must be an available option of *this* dish (no borrowing
--     another dish's options, no picking a sold-out one);
--   * no group may be over its max;
--   * a group under its min is *filled* with its cheapest available options up to
--     the min — this is the tolerance that lets an options-unaware client order a
--     Half/Full dish and get Half, rather than being refused.
-- A dish whose required group has too few available options to meet its own min
-- is treated as unorderable, the same as a sold-out dish.
create or replace function public.resolve_order_line_options(
  p_menu_item_id text,
  p_option_ids   text[]
)
returns table (option_name text, price_delta integer)
language plpgsql
stable
security definer
set search_path = public
as $$
-- The output columns above (`option_name`, `price_delta`) share names with the
-- table columns queried below; tell PL/pgSQL that a bare name means the column,
-- not the output variable, so `select ... price_delta` is unambiguous.
#variable_conflict use_column
begin
  p_option_ids := coalesce(p_option_ids, array[]::text[]);

  -- Every claimed option must be an available option of this dish.
  if exists (
    select 1 from unnest(p_option_ids) as oid
     where not exists (
       select 1
         from public.menu_options o
         join public.menu_option_groups g on g.id = o.group_id
        where o.id = oid and g.menu_item_id = p_menu_item_id and o.is_available
     )
  ) then
    raise exception 'Something in your cart is no longer available.'
      using errcode = 'P0001';
  end if;

  -- No group over its maximum, and none so short on available options it cannot
  -- meet its own minimum.
  if exists (
    select 1 from public.menu_option_groups g
     where g.menu_item_id = p_menu_item_id
       and (
         (select count(*) from public.menu_options o
           where o.group_id = g.id and o.id = any(p_option_ids)) > g.max_select
         or
         (select count(*) from public.menu_options o
           where o.group_id = g.id and o.is_available) < g.min_select
       )
  ) then
    raise exception 'Something in your cart is no longer available.'
      using errcode = 'P0001';
  end if;

  return query
  with grp as (
    select * from public.menu_option_groups where menu_item_id = p_menu_item_id
  ),
  chosen as (
    select o.id, o.group_id, o.name, o.price_delta
      from public.menu_options o
      join grp on grp.id = o.group_id
     where o.id = any(p_option_ids) and o.is_available
  ),
  fills as (
    -- For each group under its minimum, its cheapest-ranked available options
    -- that weren't already chosen, enough to reach the minimum.
    select f.name, f.price_delta
      from grp
      join lateral (
        select o.name, o.price_delta
          from public.menu_options o
         where o.group_id = grp.id
           and o.is_available
           and not (o.id = any(p_option_ids))
         order by o.rank, o.id
         limit greatest(
           grp.min_select - (select count(*) from chosen c where c.group_id = grp.id),
           0
         )
      ) f on true
  )
  select name, price_delta from chosen
  union all
  select name, price_delta from fills;
end;
$$;

grant execute on function public.resolve_order_line_options(text, text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- place_order, now priced per option.
-- ---------------------------------------------------------------------------
-- The whole of 0018's place_order, with the set-based line pricing replaced by a
-- loop — because options differ line by line, a single join can no longer price
-- them all at once. Everything else (the sign-in check, the phone check, the
-- pause and hours gates, the coupon, the receipt) is byte-for-byte 0018.
--
-- Signature unchanged, deliberately: the chosen options live in each line's
-- existing jsonb under "option_ids", so a client that sends none still calls the
-- same function and gets the default-filled order described at the top.
create or replace function public.place_order(
  p_user_phone       text,
  p_restaurant_id    text,
  p_items            jsonb,
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
  v_line         jsonb;
  v_seq          integer;
  v_mi_id        text;
  v_mi_name      text;
  v_base         integer;
  v_qty          integer;
  v_opt_ids      text[];
  v_opts         jsonb;
  v_addons       integer;
  v_unit         integer;
  v_line_total   integer;
  v_line_id      bigint;
  v_row          record;
  v_opt          jsonb;
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

  select name, eta_minutes, accepting_orders
    into v_name, v_eta, v_accepting
    from public.restaurants where id = p_restaurant_id and is_active;
  if not found then
    raise exception 'This restaurant isn''t available right now.'
      using errcode = 'P0001';
  end if;

  if not v_accepting then
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

    select id, name, price into v_mi_id, v_mi_name, v_base
      from public.menu_items
     where id = (v_line ->> 'menu_item_id')
       and restaurant_id = p_restaurant_id
       and is_available;
    if not found then
      raise exception 'Something in your cart is no longer available.'
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

    v_unit := v_base + v_addons;
    v_line_total := v_unit * v_qty;
    v_subtotal := v_subtotal + v_line_total;

    insert into _lines
      values (v_seq, v_mi_id, v_mi_name, v_unit, v_qty, v_line_total, v_opts);
  end loop;

  v_delivery_fee := case when v_subtotal >= 500 then 0 else 40 end;
  v_taxes := round(v_subtotal * 0.05)::integer;

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

grant execute on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text
) to authenticated;
