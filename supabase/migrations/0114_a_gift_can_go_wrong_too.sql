-- ---------------------------------------------------------------------------
-- 0114 — a gift can go wrong too
-- ---------------------------------------------------------------------------
-- 0095 gave a customer whose dinner arrived wrong a route back into this system.
-- It gave a customer whose *gift* arrived wrong nothing at all:
-- `support_tickets.order_id` is `not null references orders (id)`, so a gift
-- order could not have a ticket even in principle — `raise_order_issue` looks
-- the id up in `orders`, a `ZPG-…` is not there, and the customer is told
-- "We couldn't find that order on your account." about an order they are
-- looking at.
--
-- The gift order detail screen has a Cancel button and nothing else. Once a
-- parcel is dispatched, cancelling is refused (0096) and there is no other
-- door: the entire in-app recourse for a gift that never arrived is the support
-- email address on the Account screen, which is the exact state 0095 opened by
-- calling "a different company's inbox as far as this database is concerned".
--
-- This is the third gift gap in a row and the same sentence explains all three:
-- gifts were built as a parallel path and inherited none of the hardening the
-- food path had already been given. 0112 taught them to be priced by the code
-- that charges them, 0113 taught them to prove a payment, and this one gives
-- them somewhere to complain.
--
-- ## What this is not
--
-- Not the support *queue* deferred as ADM-002. That deferral is about a general
-- inbox — "phone and WhatsApp at launch volume, feel the pain first". The
-- per-order complaint path is built, worked and in the console already; this
-- only stops it being blind to half the orders the platform takes.
--
-- Not a refund either, for 0095's reason: a ticket is a statement, not a
-- transaction. Raising one moves no money and changes no status.
-- **`refunds.order_id` is also a not-null FK to `orders`**, so a gift cannot yet
-- be refunded through the ledger — an admin refunds one in Razorpay's dashboard
-- and it is not written down here. That is a real gap and it is deliberately not
-- this migration's: teaching `refunds` about `gift_orders` is the same schema
-- question 0113 answered for `payment_intents`, and doing it in the same breath
-- as this would mean two ledgers changing shape in one migration. Written down
-- so it is found rather than discovered.
--
-- ## Shape
--
-- The same one 0113 chose for `payment_intents`, for the same reasons and
-- deliberately not a second table: one queue is what support works, one set of
-- caps is what protects it, and `admin_resolve_ticket` should not have to know
-- which kind of thing it is closing. So `order_id` goes nullable, a
-- `gift_order_id` joins it, and a check constraint says exactly one is set —
-- never both, and never neither, which is the failure a nullable column added
-- without a constraint always eventually allows.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. A ticket can point at either kind of order.
-- ---------------------------------------------------------------------------
alter table public.support_tickets
  alter column order_id drop not null;

alter table public.support_tickets
  add column if not exists gift_order_id text
    references public.gift_orders (id) on delete cascade;

comment on column public.support_tickets.gift_order_id is
  'Set when the complaint is about a gift order, as order_id is for a food order. Exactly one of the two is non-null.';

-- Exactly one. `num_nonnulls` says that in one expression rather than as two
-- half-rules that can be satisfied together.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.support_tickets'::regclass
       and conname  = 'support_tickets_one_order_check'
  ) then
    alter table public.support_tickets
      add constraint support_tickets_one_order_check
      check (num_nonnulls(order_id, gift_order_id) = 1);
  end if;
end
$$;

-- The customer's own read is by order, and there are now two kinds of it.
create index if not exists support_tickets_gift_order_idx
  on public.support_tickets (gift_order_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2. Raising one against a gift.
-- ---------------------------------------------------------------------------
-- A sibling of `raise_order_issue` rather than a widening of it. The two differ
-- in the table they check ownership against and in which categories mean
-- anything, and a single function taking "an id of one of two kinds" would have
-- to guess which table to look in — a guess that silently picks the wrong answer
-- the first time the two id formats stop being distinguishable.
create or replace function public.raise_gift_issue(
  p_gift_order_id text,
  p_category      text,
  p_body          text default null
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user text;
  v_body text;
  v_id   bigint;
begin
  v_user := auth.uid()::text;
  if v_user is null then
    raise exception 'Sign in to report a problem with an order.'
      using errcode = 'P0001';
  end if;

  -- Theirs, or it does not exist as far as this function is concerned — 0095's
  -- rule, and the ownership and existence checks are deliberately the same
  -- statement so that "not yours" and "no such order" cannot be told apart.
  if not exists (
    select 1 from public.gift_orders g
     where g.id = p_gift_order_id and g.user_id = v_user
  ) then
    raise exception 'We couldn''t find that order on your account.'
      using errcode = 'P0001';
  end if;

  v_body := nullif(trim(coalesce(p_body, '')), '');
  if v_body is not null and length(v_body) > 1000 then
    raise exception 'Please keep it under 1000 characters.'
      using errcode = 'P0001';
  end if;

  -- Three per order, as food has.
  if (
    select count(*) from public.support_tickets t
     where t.gift_order_id = p_gift_order_id and t.user_id = v_user
  ) >= 3 then
    raise exception
      'You have already reported this order. We are looking at it.'
      using errcode = 'P0001';
  end if;

  -- Ten an hour per account, counted across **both** kinds. The cap exists to
  -- stop one signed-in account burying the queue, and the queue is one queue —
  -- counting gifts separately would hand anybody who wanted to bury it twice
  -- the budget for doing so.
  if (
    select count(*) from public.support_tickets t
     where t.user_id = v_user
       and t.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'That is a lot of reports at once. Try again shortly.'
      using errcode = 'P0001';
  end if;

  -- The food set minus `rider`. Nobody rides a gift — Zopiqnow couriers them
  -- (0096), there is no `deliveries` row and no delivery partner to complain
  -- about, and a category that can never be true is a filter in the console
  -- that always returns nothing. Refused in the database and not merely absent
  -- from the app's chip list, because the app is not where this is decided.
  if p_category not in (
    'missing_item', 'wrong_item', 'quality', 'damaged', 'late',
    'never_arrived', 'payment', 'other'
  ) then
    raise exception 'That is not a problem we know how to file.'
      using errcode = 'P0001';
  end if;

  insert into public.support_tickets (gift_order_id, user_id, category, body)
  values (p_gift_order_id, v_user, p_category, v_body)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.raise_gift_issue(text, text, text)
  from public, anon;
grant execute on function public.raise_gift_issue(text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Reading their own.
-- ---------------------------------------------------------------------------
create or replace function public.my_gift_order_issues(p_gift_order_id text)
returns table (
  id          bigint,
  category    text,
  body        text,
  status      text,
  created_at  timestamptz,
  resolved_at timestamptz,
  admin_note  text
)
language sql
stable
security definer
set search_path = public
as $$
  select t.id, t.category, t.body, t.status,
         t.created_at, t.resolved_at, t.admin_note
    from public.support_tickets t
   where t.gift_order_id = p_gift_order_id
     and t.user_id = auth.uid()::text
   order by t.created_at desc;
$$;

revoke all on function public.my_gift_order_issues(text) from public, anon;
grant execute on function public.my_gift_order_issues(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The queue, which must not be blind to half of it.
-- ---------------------------------------------------------------------------
-- `admin_support_tickets` **inner joins `orders`**. A gift ticket has a null
-- `order_id`, so without this every gift complaint would land in the table and
-- be invisible to the people whose job is to answer it — which is worse than
-- not accepting it, because the customer is told it was filed.
--
-- The return type changes, so this is a `drop` and a `create` rather than a
-- `create or replace`: Postgres refuses to replace a function whose OUT columns
-- differ, and 0051's lesson is that a changed signature makes a *new* function.
-- Dropping also drops the grants, so they are stated again below.
drop function if exists public.admin_support_tickets(text, integer, integer);

create function public.admin_support_tickets(
  p_status text    default 'open',
  p_limit  integer default 50,
  p_offset integer default 0
)
returns table (
  id              bigint,
  -- 'food' or 'gift'. The console needs it before it can decide what the rest
  -- of the row means: a gift has no restaurant, no rider and no photographs,
  -- and its status values are its own set.
  kind            text,
  -- Whichever id this ticket points at. One column because it is one worklist
  -- and the row is read as "the order this is about"; `kind` says which table
  -- it lives in, and the id formats (`ZPQ-` / `ZPG-`) agree with it.
  order_id        text,
  category        text,
  body            text,
  status          text,
  created_at      timestamptz,
  resolved_at     timestamptz,
  resolved_by     text,
  admin_note      text,
  -- The restaurant, or the gift shop. Renamed from `restaurant_name`, because
  -- filling a column called `restaurant_name` with a gift shop is how a report
  -- comes to say a thing that is not true.
  seller_name     text,
  order_status    text,
  order_total     integer,
  customer_phone  text,
  total_count     bigint
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
    -- Left joins, not inner ones. Exactly one side is present per row by the
    -- check constraint, so `coalesce` picks the one that is — and a ticket whose
    -- order was deleted underneath it cannot vanish from the queue, which is
    -- what an inner join would do.
    select t.id,
           case when t.gift_order_id is not null then 'gift' else 'food' end
             as kind,
           coalesce(t.order_id, t.gift_order_id)            as order_id,
           t.category, t.body, t.status,
           t.created_at, t.resolved_at, t.resolved_by, t.admin_note,
           coalesce(o.restaurant_name, g.shop_name)         as seller_name,
           coalesce(o.status, g.status)                     as order_status,
           coalesce(o.total, g.total)                       as order_total,
           coalesce(o.user_phone, g.user_phone)             as customer_phone
      from public.support_tickets t
      left join public.orders      o on o.id = t.order_id
      left join public.gift_orders g on g.id = t.gift_order_id
     where p_status is null or t.status = p_status
  )
  select m.id, m.kind, m.order_id, m.category, m.body, m.status,
         m.created_at, m.resolved_at, m.resolved_by, m.admin_note,
         m.seller_name, m.order_status, m.order_total, m.customer_phone,
         count(*) over () as total_count
    from matched m
   -- Oldest first. This is a worklist, and a worklist is worked from the
   -- bottom: the complaint that has been waiting longest is the one that has
   -- been waiting longest.
   order by m.created_at asc
   limit v_limit offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.admin_support_tickets(text, integer, integer)
  from public, anon;
grant execute on function public.admin_support_tickets(text, integer, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Closing one, whichever kind it is.
-- ---------------------------------------------------------------------------
-- The argument list is unchanged, so this is a genuine replacement and creates
-- no overload. Only the sentence it hands back changes: the old one read
-- `'Ticket 12 on order ' || v_order`, and for a gift ticket `v_order` is null,
-- which would have concatenated to **null** — the console showing an empty
-- toast for an action that in fact succeeded.
create or replace function public.admin_resolve_ticket(
  p_id   bigint,
  p_note text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor  text;
  v_note   text;
  v_order  text;
  v_status text;
begin
  perform public.assert_admin();

  v_actor := lower(nullif(trim(coalesce(auth.jwt() ->> 'email', '')), ''));
  v_note  := nullif(trim(coalesce(p_note, '')), '');

  if v_note is not null and length(v_note) > 1000 then
    raise exception 'Keep the note under 1000 characters.'
      using errcode = 'P0001';
  end if;

  select coalesce(t.order_id, t.gift_order_id), t.status
    into v_order, v_status
    from public.support_tickets t
   where t.id = p_id
   for update;

  if not found then
    raise exception 'No such ticket.' using errcode = 'P0001';
  end if;

  if v_status = 'resolved' then
    raise exception 'That one is already closed.' using errcode = 'P0001';
  end if;

  update public.support_tickets
     set status      = 'resolved',
         resolved_at = now(),
         resolved_by = v_actor,
         admin_note  = v_note
   where id = p_id;

  return 'Ticket ' || p_id || ' on order ' || v_order || ' is closed.';
end;
$$;

revoke all on function public.admin_resolve_ticket(bigint, text)
  from public, anon;
grant execute on function public.admin_resolve_ticket(bigint, text)
  to authenticated;
