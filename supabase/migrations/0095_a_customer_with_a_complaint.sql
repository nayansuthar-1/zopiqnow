-- ---------------------------------------------------------------------------
-- 0095 — a customer with a complaint
-- ---------------------------------------------------------------------------
-- Until now a customer whose order arrived wrong had no route back into this
-- system at all. Not a bad route — none. The cancel sheet covers an order they
-- want to stop; there was nothing for an order that already happened and was
-- not what they paid for. The only thing the app offered was a support email
-- address on the Account screen, which is a different company's inbox as far as
-- this database is concerned.
--
-- This is ZOMATO_PARITY B2's last open line: "customer order issue / report
-- screen, feeding a support queue".
--
-- ## What it is, and what it deliberately is not
--
-- A ticket is a *statement*, not a transaction. Raising one moves no money,
-- changes no order status, and refunds nothing. That is the whole design: the
-- refund path already exists (`refunds`, 0077) and it is an admin act with an
-- audit trail behind it. A complaint that refunded itself would be a complaint
-- worth making up.
--
-- So the flow is: customer says what went wrong → it lands in a queue → an
-- admin reads it, looks at the three photographs 0094 attached to that order,
-- and *then* decides whether to issue a refund through the function that
-- already does that.
--
-- ## Bounds
--
-- Free to call, and answering costs a human being's attention — SHIP_PLAN's
-- third standard. Two caps, both cheap to check:
--
--   • three per order. Somebody with two genuine problems on one dinner is
--     real; somebody with four is not describing a dinner.
--   • ten per hour per account, across every order.
--
-- Neither is a security control on its own. Together they mean the queue cannot
-- be buried by one signed-in account with a loop.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The table.
-- ---------------------------------------------------------------------------
create table if not exists public.support_tickets (
  id          bigint generated always as identity primary key,

  -- Cascade, like `reviews`: a deleted order takes its complaints with it.
  -- An admin deleting an order already destroys the review and the messages
  -- (0069), and a ticket pointing at nothing is worse than no ticket.
  order_id    text not null references public.orders (id) on delete cascade,

  -- Denormalised from the order at write time, and never read from the JWT on
  -- the way out. The order is the source and it cannot change owner.
  user_id     text not null,

  -- A closed set, because a queue somebody has to work is a queue that has to
  -- be sortable. The app's labels are friendlier than these; these are the
  -- values, and they are what the console filters on.
  category    text not null check (category in (
    'missing_item',
    'wrong_item',
    'quality',
    'damaged',
    'late',
    'never_arrived',
    'rider',
    'payment',
    'other'
  )),

  -- What they typed. Optional: a category alone is a complete complaint, and a
  -- mandatory text box in front of an angry customer is a way of not hearing
  -- from them. Capped so the column cannot be used as storage.
  body        text check (body is null or length(body) <= 1000),

  status      text not null default 'open'
                check (status in ('open', 'resolved')),

  created_at  timestamptz not null default now(),

  -- Set together, by the one function that resolves a ticket.
  resolved_at timestamptz,
  resolved_by text,
  admin_note  text check (admin_note is null or length(admin_note) <= 1000)
);

-- The queue is read newest-first and filtered by status; the customer's own
-- read is by order. Two indexes, one per reader.
create index if not exists support_tickets_queue_idx
  on public.support_tickets (status, created_at desc);
create index if not exists support_tickets_order_idx
  on public.support_tickets (order_id, created_at desc);

alter table public.support_tickets enable row level security;

-- Born writable to `anon` (0089, and the note in ENGINEERING_RULES). RLS does
-- not cover TRUNCATE and a PostgREST 204 is not a refusal, so the grant is
-- removed outright rather than policed. No policy and no grant: every read and
-- every write below goes through a security-definer function, which is the only
-- shape that cannot be widened by accident later.
revoke all on public.support_tickets from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Raising one.
-- ---------------------------------------------------------------------------
create or replace function public.raise_order_issue(
  p_order_id text,
  p_category text,
  p_body     text default null
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

  -- Theirs, or it does not exist as far as this function is concerned. Note the
  -- ownership check and the existence check are the same statement on purpose:
  -- answering "that order isn't yours" differently from "no such order" tells a
  -- stranger which order ids are real.
  if not exists (
    select 1 from public.orders o
     where o.id = p_order_id and o.user_id = v_user
  ) then
    raise exception 'We couldn''t find that order on your account.'
      using errcode = 'P0001';
  end if;

  -- Trimmed to null, so a body of spaces is stored as "they said nothing"
  -- rather than as a string the console has to render.
  v_body := nullif(trim(coalesce(p_body, '')), '');
  if v_body is not null and length(v_body) > 1000 then
    raise exception 'Please keep it under 1000 characters.'
      using errcode = 'P0001';
  end if;

  if (
    select count(*) from public.support_tickets t
     where t.order_id = p_order_id and t.user_id = v_user
  ) >= 3 then
    raise exception
      'You have already reported this order. We are looking at it.'
      using errcode = 'P0001';
  end if;

  if (
    select count(*) from public.support_tickets t
     where t.user_id = v_user
       and t.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'That is a lot of reports at once. Try again shortly.'
      using errcode = 'P0001';
  end if;

  -- The category is checked by the constraint, but a bad one should read as a
  -- sentence rather than as a constraint violation the app has to translate.
  if p_category not in (
    'missing_item', 'wrong_item', 'quality', 'damaged', 'late',
    'never_arrived', 'rider', 'payment', 'other'
  ) then
    raise exception 'That is not a problem we know how to file.'
      using errcode = 'P0001';
  end if;

  insert into public.support_tickets (order_id, user_id, category, body)
  values (p_order_id, v_user, p_category, v_body)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.raise_order_issue(text, text, text)
  from public, anon;
grant execute on function public.raise_order_issue(text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Reading their own.
-- ---------------------------------------------------------------------------
-- So the order screen can say "reported" instead of offering to report it a
-- second time, and can show that somebody answered.
create or replace function public.my_order_issues(p_order_id text)
returns table (
  id          bigint,
  category    text,
  body        text,
  status      text,
  created_at  timestamptz,
  resolved_at timestamptz,
  -- The admin's note comes back to the customer. It is written knowing that —
  -- see the console's field hint.
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
   where t.order_id = p_order_id
     and t.user_id = auth.uid()::text
   order by t.created_at desc;
$$;

revoke all on function public.my_order_issues(text) from public, anon;
grant execute on function public.my_order_issues(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The queue.
-- ---------------------------------------------------------------------------
-- Everything support needs to triage without opening another screen: who, what
-- order, how much it was worth, and whether the order is even finished. The
-- photographs are deliberately *not* here — `admin_order_photos` (0094) already
-- returns them and support opens one ticket at a time.
create or replace function public.admin_support_tickets(
  p_status text    default 'open',
  p_limit  integer default 50,
  p_offset integer default 0
)
returns table (
  id              bigint,
  order_id        text,
  category        text,
  body            text,
  status          text,
  created_at      timestamptz,
  resolved_at     timestamptz,
  resolved_by     text,
  admin_note      text,
  restaurant_name text,
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
    select t.id, t.order_id, t.category, t.body, t.status,
           t.created_at, t.resolved_at, t.resolved_by, t.admin_note,
           o.restaurant_name, o.status as order_status,
           o.total as order_total, o.user_phone as customer_phone
      from public.support_tickets t
      join public.orders o on o.id = t.order_id
     where p_status is null or t.status = p_status
  )
  select m.id, m.order_id, m.category, m.body, m.status,
         m.created_at, m.resolved_at, m.resolved_by, m.admin_note,
         m.restaurant_name, m.order_status, m.order_total, m.customer_phone,
         count(*) over () as total_count
    from matched m
   -- Oldest first, unlike the order book. This is a worklist, and a worklist is
   -- worked from the bottom: the complaint that has been waiting longest is the
   -- one that has been waiting longest.
   order by m.created_at asc
   limit v_limit offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.admin_support_tickets(text, integer, integer)
  from public, anon;
grant execute on function public.admin_support_tickets(text, integer, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Answering one.
-- ---------------------------------------------------------------------------
-- Resolving is a one-way door and there is no reopen. A complaint that comes
-- back is a new complaint, which keeps the queue honest about how many times
-- somebody had to ask.
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

  select t.order_id, t.status into v_order, v_status
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

-- ---------------------------------------------------------------------------
-- 6. The trail.
-- ---------------------------------------------------------------------------
-- On the *status change* only, the same shape 0092 uses for refunds and
-- settlements. Not on insert: an insert here is a customer, not an admin, and
-- filling the admin trail with customers' own acts would bury the thing it
-- exists to show.
drop trigger if exists support_tickets_audit_status on public.support_tickets;
create trigger support_tickets_audit_status after update on public.support_tickets
  for each row when (old.status is distinct from new.status)
  execute function public.record_admin_action('id');
