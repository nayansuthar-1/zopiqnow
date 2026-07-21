-- Phase 8b, slice 1: the third kind of person.
--
-- 0009 introduced the second — someone who works at a restaurant — and was
-- careful to say what that meant. This introduces the third, and owes the same
-- precision: a **delivery partner**, who belongs to Zopiqnow rather than to any
-- one kitchen, and who may carry an order from any of them.
--
-- What a rider is allowed to touch, exactly:
--   * see the orders that are ready and unclaimed — id, where from, where to;
--   * claim one, which is the first-come race this migration has to win cleanly;
--   * see the orders they are themselves carrying;
--   * move such an order to `out_for_delivery` (proving they are at the counter)
--     and then to `delivered`.
--
-- And what they may not:
--   * any order they have not claimed, including its existence;
--   * any figure on any order. Same rule as the vendor's, same reason.
--   * any other rider's row, or any restaurant's staff, menu or settlements.
--
-- ---------------------------------------------------------------------------
-- The decision that shaped this file: `orders` gains NO new policy.
-- ---------------------------------------------------------------------------
-- Every read a rider makes goes through a `security definer` function below,
-- and there is deliberately no `create policy … on public.orders` anywhere in
-- this migration. That table's policies currently encode "customers see their
-- own, staff see their restaurant's", and a third clause bolted on is a third
-- way for the first two to be widened by a future edit. A function that returns
-- three named columns cannot leak a fourth.
--
-- ---------------------------------------------------------------------------
-- And the constraint that shaped it more: `orders.status` does not change.
-- ---------------------------------------------------------------------------
-- Not one new value. The customer app throws on a status it does not recognise
-- (a deliberate choice — see `OrderStatus.fromWire`), so a new one breaks the
-- tracking screen on every build already on a phone. The existing statuses
-- already describe delivery: `ready_for_pickup` is a bag on a counter,
-- `out_for_delivery` is that bag on a bike. The rider's own lifecycle — claimed,
-- picked up, dropped — lives in `deliveries.state`, which no customer build has
-- ever read and none will be broken by.

-- ---------------------------------------------------------------------------
-- Who rides.
-- ---------------------------------------------------------------------------
-- Keyed by email, for the reason `restaurant_staff` is (0009 at length): ops
-- onboards a person days before that person first opens an app and is issued a
-- uid, and a table keyed by uid can only be filled in after that first sign-in —
-- which would mean whoever signs in first gets to be the rider.
--
-- No `restaurant_id`, and that is the platform-fleet decision made concrete: a
-- rider is not staff at a kitchen, they are a Zopiqnow rider who can take a job
-- from any kitchen. Nothing here is scoped by restaurant.
create table if not exists public.delivery_partners (
  email      text primary key,
  name       text not null,
  phone      text not null,
  vehicle    text not null default 'bike'
             check (vehicle in ('bike', 'scooter', 'bicycle')),

  -- Ops' switch, not the rider's. A deactivated partner keeps their history and
  -- their claimed jobs; they simply stop being offered new ones.
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),

  constraint delivery_partners_email_is_lowercase check (email = lower(email))
);

alter table public.delivery_partners enable row level security;

-- A rider may read their own row and no other. Unlike `restaurant_staff` — which
-- is readable by nobody at all — a self-only policy is safe here, because it
-- answers nothing about anyone else: 0009's fear was that a readable table would
-- let anyone map addresses to restaurants, and `email = my own email` maps
-- exactly one address to the person already holding it.
drop policy if exists "riders read their own partner row" on public.delivery_partners;
create policy "riders read their own partner row"
  on public.delivery_partners for select to authenticated
  using (email = lower(auth.jwt() ->> 'email'));

-- The kitchen's read of a rider is declared after `deliveries` exists, since it
-- is that table it has to consult.

grant select on public.delivery_partners to authenticated;

-- ---------------------------------------------------------------------------
-- The job.
-- ---------------------------------------------------------------------------
-- One row per order a rider has taken on. Created at the moment of claiming —
-- there is no `offered` state, because with riders claiming for themselves an
-- unclaimed job is simply an order with no row here. The board is a `left join`,
-- not a status.
create table if not exists public.deliveries (
  id            bigint generated always as identity primary key,
  order_id      text not null references public.orders (id) on delete cascade,
  partner_email text not null references public.delivery_partners (email),

  state         text not null default 'claimed'
                check (state in ('claimed', 'picked_up', 'delivered', 'cancelled')),

  -- Four digits, shown to the *vendor* and typed by the *rider*. That direction
  -- is the whole point: a rider who can produce this code is standing at the
  -- counter that was shown it. A code the rider displayed and the vendor typed
  -- would prove only that the rider can read their own screen.
  pickup_otp    text not null check (pickup_otp ~ '^[0-9]{4}$'),

  claimed_at    timestamptz not null default now(),
  picked_up_at  timestamptz,
  delivered_at  timestamptz
);

-- One *live* delivery per order — but any number of dead ones. A rider who
-- claims a job and thinks better of it leaves a `cancelled` row behind and the
-- order returns to the board; a plain `unique (order_id)` would have made that
-- abandonment permanent, and made "who dropped this and when" unanswerable.
create unique index if not exists deliveries_one_live_per_order
  on public.deliveries (order_id) where state <> 'cancelled';

create index if not exists deliveries_partner_idx
  on public.deliveries (partner_email, state);

alter table public.deliveries enable row level security;

-- The rider's own jobs. (Their *contents* still come from the functions below —
-- this policy is what lets the rider app watch its own row change.)
drop policy if exists "riders read their own deliveries" on public.deliveries;
create policy "riders read their own deliveries"
  on public.deliveries for select to authenticated
  using (partner_email = lower(auth.jwt() ->> 'email'));

-- The kitchen's view of who has its order. No write grant: a vendor does not
-- claim, pick up or drop anything.
drop policy if exists "staff read deliveries of their orders" on public.deliveries;
create policy "staff read deliveries of their orders"
  on public.deliveries for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = deliveries.order_id
         and o.restaurant_id = public.staff_restaurant_id()
    )
  );

grant select on public.deliveries to authenticated;

-- A kitchen may read the rider who is carrying one of *its* orders, and only
-- while they are carrying it. This is what puts a name and a phone number on the
-- vendor's ticket — the number a manager rings when a bag has been sitting on
-- the counter for ten minutes. (Declared here rather than with the other
-- `delivery_partners` policies because it reads `deliveries`, created above.)
drop policy if exists "staff read the rider carrying their order" on public.delivery_partners;
create policy "staff read the rider carrying their order"
  on public.delivery_partners for select to authenticated
  using (
    exists (
      select 1
        from public.deliveries d
        join public.orders o on o.id = d.order_id
       where d.partner_email = delivery_partners.email
         and o.restaurant_id = public.staff_restaurant_id()
         and d.state in ('claimed', 'picked_up')
    )
  );

-- ---------------------------------------------------------------------------
-- The question every rider function opens with.
-- ---------------------------------------------------------------------------
-- The rider's twin of `staff_restaurant_id()`, and the same shape for the same
-- reasons: `security definer` to read a table the caller cannot enumerate,
-- `stable` so it is evaluated once per statement.
--
-- Null for a customer, for a vendor, and for a deactivated rider — that last one
-- deliberately, so that switching `is_active` off takes someone off the board
-- without any function needing to know that is why.
create or replace function public.delivery_partner_email() returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.email
    from public.delivery_partners p
   where p.email = lower(auth.jwt() ->> 'email')
     and p.is_active
$$;

grant execute on function public.delivery_partner_email() to authenticated;

-- ---------------------------------------------------------------------------
-- The board: what is going begging.
-- ---------------------------------------------------------------------------
-- Orders that are cooked, or nearly, and that nobody has claimed. `preparing` is
-- included on purpose — a rider who can only see a job the instant it is bagged
-- is a rider who always arrives ten minutes late. Seeing it while it cooks is
-- what lets them ride over.
--
-- Note what is returned and what is not: where to collect, where to take it, and
-- what it is worth to know (the bill, for a cash order). Not the customer's
-- phone number — that is in `my_deliveries` below, after they have committed to
-- the job. A board that hands out phone numbers to anyone who opens the app is a
-- list of everyone who ordered dinner tonight.
create or replace function public.available_deliveries()
returns table (
  order_id        text,
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  total           integer,
  payment_method  text,
  status          text,
  ready_by        timestamptz,
  placed_at       timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if public.delivery_partner_email() is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status, o.ready_by, o.created_at
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
     where o.status in ('preparing', 'ready_for_pickup')
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = o.id and d.state <> 'cancelled'
       )
     -- Ready ones first, then the longest-waiting: the bag already on the
     -- counter is the one somebody should be collecting.
     order by (o.status = 'ready_for_pickup') desc, o.created_at;
end;
$$;

grant execute on function public.available_deliveries() to authenticated;

-- ---------------------------------------------------------------------------
-- Claiming, which is a race.
-- ---------------------------------------------------------------------------
-- Two riders tapping the same job in the same second is the normal case in a
-- busy hour, not an edge case. The partial unique index is what actually decides
-- it — one insert wins, the other violates, and the loser is told plainly rather
-- than shown a database error. The `on conflict do nothing` turns that violation
-- into zero rows inserted, which is a thing we can check.
create or replace function public.claim_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider  text;
  v_status text;
  v_id     bigint;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select o.status into v_status
    from public.orders o where o.id = p_order_id;

  if not found then
    raise exception 'That order no longer exists.' using errcode = 'P0001';
  end if;

  if v_status not in ('preparing', 'ready_for_pickup') then
    raise exception 'That order is no longer available.' using errcode = 'P0001';
  end if;

  insert into public.deliveries (order_id, partner_email, pickup_otp)
  values (
    p_order_id,
    v_rider,
    -- Four digits, zero-padded. `random()` is not a cryptographic source and
    -- does not need to be: the code is checked against one specific order, by
    -- one specific rider, standing in one specific shop, within minutes.
    lpad((floor(random() * 10000))::integer::text, 4, '0')
  )
  on conflict do nothing
  returning id into v_id;

  if v_id is null then
    raise exception 'Another partner just took that one.' using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.claim_delivery(text) to authenticated;

-- Thinking better of it. Allowed right up until pickup and not after — once the
-- food is on the bike, walking away is a support conversation, not a button.
-- The row is kept as `cancelled` rather than deleted, so the order can go back
-- on the board (the partial index only constrains live rows) while "who dropped
-- this, and when" stays answerable.
create or replace function public.abandon_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  update public.deliveries
     set state = 'cancelled'
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'claimed';

  if not found then
    raise exception 'You can only drop a job you haven''t picked up yet.'
      using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.abandon_delivery(text) to authenticated;

-- ---------------------------------------------------------------------------
-- The rider's own jobs, in full.
-- ---------------------------------------------------------------------------
-- Everything the board withheld — the customer's phone number, chiefly — plus
-- the state of the job itself. Only for deliveries this caller actually holds.
--
-- Deliberately *not* the pickup code: the rider types that in, they do not read
-- it out. Returning it here would make the whole handover theatre.
create or replace function public.my_deliveries()
returns table (
  order_id        text,
  state           text,
  order_status    text,
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  deliver_lat     double precision,
  deliver_lng     double precision,
  customer_phone  text,
  total           integer,
  payment_method  text,
  claimed_at      timestamptz,
  picked_up_at    timestamptz,
  delivered_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  return query
    select o.id, d.state, o.status, r.name, r.latitude, r.longitude,
           o.delivery_to, o.delivery_lat, o.delivery_lng, o.user_phone,
           o.total, o.payment_method,
           d.claimed_at, d.picked_up_at, d.delivered_at
      from public.deliveries d
      join public.orders o on o.id = d.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where d.partner_email = v_rider
       and d.state <> 'cancelled'
     -- Live jobs first, then most recent.
     order by (d.state = 'delivered'), d.claimed_at desc;
end;
$$;

grant execute on function public.my_deliveries() to authenticated;

-- ---------------------------------------------------------------------------
-- Pickup: the one place a code is checked.
-- ---------------------------------------------------------------------------
-- Moves `orders.status` to `out_for_delivery` — the same transition the vendor's
-- "Hand to rider" button already makes, written here for the other party to the
-- same handshake. Both paths survive: a restaurant with no rider claimed still
-- hands the bag to a cousin with a scooter and presses its own button, exactly
-- as it did yesterday.
--
-- The food must actually be ready. A rider cannot talk a kitchen into "out for
-- delivery" while it is still frying.
create or replace function public.confirm_pickup(
  p_order_id text,
  p_otp      text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider  text;
  v_otp    text;
  v_status text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- Locked: the vendor may be pressing its own hand-off button at this instant.
  select d.pickup_otp, o.status into v_otp, v_status
    from public.deliveries d
    join public.orders o on o.id = d.order_id
   where d.order_id = p_order_id
     and d.partner_email = v_rider
     and d.state = 'claimed'
   for update of d;

  if not found then
    raise exception 'You have no job waiting to be picked up on that order.'
      using errcode = 'P0001';
  end if;

  if v_status <> 'ready_for_pickup' then
    raise exception 'That order isn''t packed yet.' using errcode = 'P0001';
  end if;

  if p_otp is distinct from v_otp then
    raise exception 'That code doesn''t match. Ask the restaurant to read it again.'
      using errcode = 'P0001';
  end if;

  -- Scoped to the *live* row, not just the order. An order that was claimed,
  -- dropped and claimed again has a `cancelled` row sitting beside this one, and
  -- an update keyed on `order_id` alone would drag that corpse to `picked_up`
  -- too — straight into the partial unique index, which permits only one row per
  -- order that is not cancelled.
  update public.deliveries
     set state = 'picked_up', picked_up_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'claimed';

  update public.orders set status = 'out_for_delivery' where id = p_order_id;
end;
$$;

grant execute on function public.confirm_pickup(text, text) to authenticated;

-- Dropped off. The end of the rider's involvement and of the order.
create or replace function public.confirm_delivered(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  update public.deliveries
     set state = 'delivered', delivered_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'picked_up';

  if not found then
    raise exception 'You aren''t carrying that order.' using errcode = 'P0001';
  end if;

  update public.orders set status = 'delivered' where id = p_order_id;
end;
$$;

grant execute on function public.confirm_delivered(text) to authenticated;
