-- Step, migration 21: the kitchen's inbox.
--
-- Phase 7, the in-app half. The push side (0020) reaches a device that isn't
-- looking; this is the record it comes back to — a list of what happened while
-- it was away, each row read or unread, kept per restaurant.
--
-- The vendor reads its own notifications and marks them read; it never writes
-- their content. A row is written by the database itself, on the one event that
-- matters at this phase — a new order landing — through a trigger that can never
-- harm the placement it rides on.

-- ---------------------------------------------------------------------------
-- One row per thing worth telling a kitchen about.
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id             bigserial primary key,
  restaurant_id  text not null references public.restaurants (id) on delete cascade,

  -- What sort of alert this is. Only 'new_order' is written today; 'system' is
  -- here so the next source (a settlement paid, an ops notice) has a home
  -- without a migration.
  kind           text not null default 'new_order'
                 check (kind in ('new_order', 'system')),

  title          text not null,
  body           text,

  -- The order this is about, for a tap that opens the queue. Plain text, no FK:
  -- a notification outlives the order it points at, and a deleted order should
  -- not take the record of its having arrived with it.
  order_id       text,

  -- Null until the kitchen has seen it. The unread badge is `count(read_at is null)`.
  read_at        timestamptz,
  created_at     timestamptz not null default now()
);

create index if not exists notifications_restaurant_idx
  on public.notifications (restaurant_id, created_at desc);

-- RLS on. A vendor reads only its own restaurant's notifications — the same
-- shape as every other vendor read (0009) — and never writes the table directly;
-- the two functions below move `read_at` and nothing else.
alter table public.notifications enable row level security;

drop policy if exists "staff read their restaurant's notifications" on public.notifications;
create policy "staff read their restaurant's notifications"
  on public.notifications for select to authenticated
  using (restaurant_id = public.staff_restaurant_id());

grant select on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- Marking read: a status, and only read_at.
-- ---------------------------------------------------------------------------
-- No update grant, for the same reason `set_order_status` is a function and not
-- a policy: RLS chooses rows, not columns, and an update that lets a vendor set
-- `read_at` is one typo from letting them set `title`. These write `read_at`
-- and nothing else, scoped to the caller's own restaurant.
create or replace function public.mark_notification_read(p_id bigint)
returns void
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

  update public.notifications
     set read_at = now()
   where id = p_id
     and restaurant_id = v_restaurant
     and read_at is null;
end;
$$;

grant execute on function public.mark_notification_read(bigint) to authenticated;

create or replace function public.mark_all_notifications_read()
returns void
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

  update public.notifications
     set read_at = now()
   where restaurant_id = v_restaurant
     and read_at is null;
end;
$$;

grant execute on function public.mark_all_notifications_read() to authenticated;

-- ---------------------------------------------------------------------------
-- The source: a new order writes an inbox row.
-- ---------------------------------------------------------------------------
-- Rides `orders` INSERT, but is a guest there. The row being inserted is the
-- customer's placed order; an inbox entry is a courtesy on top of it, and a
-- courtesy must never be able to refuse the thing itself. So the insert is
-- wrapped: any failure is swallowed, the order commits regardless, and the
-- kitchen simply doesn't get this one line.
create or replace function public.notify_new_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    insert into public.notifications (restaurant_id, kind, title, body, order_id)
    values (
      new.restaurant_id,
      'new_order',
      'New order',
      'Order ' || new.id || ' · ₹' || new.total,
      new.id
    );
  exception when others then
    -- Placement is sacred; a notification is not. Never let this abort the order.
    null;
  end;
  return new;
end;
$$;

drop trigger if exists orders_notify_new on public.orders;
create trigger orders_notify_new
  after insert on public.orders
  for each row
  when (new.status = 'placed')
  execute function public.notify_new_order();

-- ---------------------------------------------------------------------------
-- Realtime, so the bell lights without a refresh.
-- ---------------------------------------------------------------------------
-- Same as orders (0008): adding the table to the publication makes its changes
-- *available* to subscribers; the RLS policy above still decides who sees them,
-- so a kitchen's socket carries only its own rows.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
