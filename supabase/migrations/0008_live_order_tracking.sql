-- Step 8, migration 8: live order tracking.
--
-- Two things, and they are deliberately independent:
--
--   1. The client may *watch* its own order row. Realtime, over the select policy
--      0005 already wrote — a customer who may read a receipt may watch it change.
--   2. Something has to *move* an order past 'placed'. In production that is the
--      vendor app: the kitchen accepts, the kitchen cooks, the rider picks up.
--      We do not have a vendor app, so until we do, a cron job walks open orders
--      through the same statuses on a schedule derived from the ETA the customer
--      was quoted.
--
-- Part 2 is a stand-in and is written to be deleted: it touches nothing but the
-- `status` column, it is invisible to the client (no grant, no API surface), and
-- the app cannot tell a status written by this job from one written by a kitchen.
-- The day the vendor app lands, `select cron.unschedule('advance-open-orders')`
-- and drop the function — no Flutter changes.

-- ---------------------------------------------------------------------------
-- 1. Realtime on `orders`.
-- ---------------------------------------------------------------------------
-- Realtime applies RLS per subscriber, so this publishes nothing that a
-- `select` would not already return: the policy from 0005 is
-- `user_id = auth.uid()::text`, and a customer subscribed to someone else's
-- order receives nothing. Adding the table to the publication is what makes the
-- row's changes *available* to be filtered — not what decides who sees them.
--
-- `order_items` is deliberately left out. Lines never change after `place_order`
-- writes them, and a subscription to a table that cannot change is a socket that
-- will never speak.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. The kitchen we do not have yet.
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron;

-- Status as a function of how long ago the order was placed, against the ETA the
-- customer was actually quoted. That last part is the whole point: a simulator
-- that delivers in four minutes flat would contradict the "arriving in about 30
-- min" the confirmation screen promised, and the customer would be watching a
-- screen that lies twice.
--
-- Monotonic by construction — the thresholds only increase with time — so a
-- status never runs backwards, and `is distinct from` means a row is written
-- only when it actually moves. An order already 'delivered' or 'cancelled' is
-- done and is never touched again.
create or replace function public.advance_open_orders() returns void
language sql
security definer
set search_path = public
as $$
  with progressed as (
    select
      o.id,
      case
        when now() >= o.created_at + make_interval(mins => o.eta_minutes)
          then 'delivered'
        -- Out for delivery for the last ~45% of the wait: the rider is the
        -- longest leg, and it is the leg the customer stares at.
        when now() >= o.created_at
                    + make_interval(mins => greatest(2, round(o.eta_minutes * 0.55)::int))
          then 'out_for_delivery'
        when now() >= o.created_at
                    + make_interval(mins => greatest(1, round(o.eta_minutes * 0.20)::int))
          then 'preparing'
        when now() >= o.created_at + interval '1 minute'
          then 'accepted'
        else 'placed'
      end as status
    from public.orders o
    where o.status not in ('delivered', 'cancelled')
  )
  update public.orders o
     set status = p.status
    from progressed p
   where o.id = p.id
     and o.status is distinct from p.status;
$$;

-- No grant. Nothing outside this database calls it — least of all the client,
-- which must not be able to tell the world its dinner has arrived.
revoke all on function public.advance_open_orders() from public;

-- Every minute. The finest granularity that matters: the customer's first
-- transition ('accepted', at +1 min) is the one that proves the stream is live,
-- and the rest are minutes apart anyway.
select cron.unschedule('advance-open-orders')
 where exists (select 1 from cron.job where jobname = 'advance-open-orders');

select cron.schedule(
  'advance-open-orders',
  '* * * * *',
  $$select public.advance_open_orders();$$
);
