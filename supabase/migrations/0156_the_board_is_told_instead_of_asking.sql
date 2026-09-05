-- ---------------------------------------------------------------------------
-- 0156 — the board is told instead of asking.
-- ---------------------------------------------------------------------------
-- The live board polls every fifteen seconds and its own header says why:
-- Realtime would mean an admin read policy on `orders`, and the console's one
-- structural guarantee is that it reaches this database through named
-- `security definer` functions and nothing else. That guarantee is worth more
-- than a socket, so the board has been a quarter-minute stale on purpose.
--
-- Both halves can be kept, because a broadcast does not have to carry a row.
--
-- ## What crosses the socket
--
-- Nothing. `{}`, on the event `changed`, on the topic `ops:orders`. The console
-- hears it and refetches through `admin_orders` exactly as it does today — same
-- function, same `assert_admin()`, same breach arithmetic. The socket is a
-- doorbell, not a delivery.
--
-- That is not squeamishness about a small payload. An order id on the wire is an
-- invitation for a later change to patch a row into the board client-side, and
-- the moment that happens there are two definitions of what is on the board and
-- one of them skips `admin_orders`. A doorbell cannot be misused that way.
--
-- ## Who can hear it
--
-- `realtime.messages` has RLS enabled and, on this database, **no policies at
-- all** — which is why `private => true` currently denies everyone. This adds
-- exactly one, for `select`, for one topic, gated on `is_admin()`. So the
-- channel is admin-only for the same reason and by the same function as every
-- RPC in the console.
--
-- Deliberately no `insert` policy. Reading this channel is subscribing to it;
-- writing to it would be a signed-in customer able to fake ops traffic, and
-- nothing needs that. The database is the only speaker here.
--
-- ## Why the triggers are per statement
--
-- `dispatch_deliveries` updates the whole board in one statement. Per row, that
-- is one broadcast per order and a console that refetches twenty times for one
-- sweep. Per statement it is one.
--
-- And per statement **with a transition table**, so a statement that changed
-- nothing says nothing. This is the part that matters: the dispatcher runs on a
-- schedule and its updates frequently match no rows, and a broadcast on every
-- one of those would be the fifteen-second poll again wearing a socket.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- The doorbell.
-- ---------------------------------------------------------------------------
-- Every trigger below names its transition table `changed` — `NEW TABLE` for
-- insert and update, `OLD TABLE` for delete — so one function serves all of
-- them and the `exists` below is the same question every time: did this
-- statement actually touch anything?
create or replace function public.notify_ops_board()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if exists (select 1 from changed) then
    perform realtime.send(
      '{}'::jsonb,   -- no row data, ever. See the header.
      'changed',
      'ops:orders',
      true           -- private: the policy below decides who hears it.
    );
  end if;
  return null;
end;
$fn$;

comment on function public.notify_ops_board() is
  '0156: rings the console''s ops channel when a statement changed something. Carries no data — the console refetches through admin_orders.';

revoke all on function public.notify_ops_board() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Where it rings from.
-- ---------------------------------------------------------------------------
-- The three tables the live board draws from. `delivery_offers` is included
-- because a ring in flight is on the board — "offered to Ravi, 22 seconds left"
-- — and without it the one thing that moves fastest would be the one thing the
-- board could not see move.
--
-- Deletes: only `orders` has one (0069's admin delete). A delivery is cancelled
-- rather than removed, and an offer is never deleted at all.

drop trigger if exists orders_notify_ops_insert on public.orders;
create trigger orders_notify_ops_insert
  after insert on public.orders
  referencing new table as changed
  for each statement execute function public.notify_ops_board();

drop trigger if exists orders_notify_ops_update on public.orders;
create trigger orders_notify_ops_update
  after update on public.orders
  referencing new table as changed
  for each statement execute function public.notify_ops_board();

drop trigger if exists orders_notify_ops_delete on public.orders;
create trigger orders_notify_ops_delete
  after delete on public.orders
  referencing old table as changed
  for each statement execute function public.notify_ops_board();

drop trigger if exists deliveries_notify_ops_insert on public.deliveries;
create trigger deliveries_notify_ops_insert
  after insert on public.deliveries
  referencing new table as changed
  for each statement execute function public.notify_ops_board();

drop trigger if exists deliveries_notify_ops_update on public.deliveries;
create trigger deliveries_notify_ops_update
  after update on public.deliveries
  referencing new table as changed
  for each statement execute function public.notify_ops_board();

drop trigger if exists offers_notify_ops_insert on public.delivery_offers;
create trigger offers_notify_ops_insert
  after insert on public.delivery_offers
  referencing new table as changed
  for each statement execute function public.notify_ops_board();

drop trigger if exists offers_notify_ops_update on public.delivery_offers;
create trigger offers_notify_ops_update
  after update on public.delivery_offers
  referencing new table as changed
  for each statement execute function public.notify_ops_board();

-- ---------------------------------------------------------------------------
-- Who is allowed to listen.
-- ---------------------------------------------------------------------------
-- The first policy this database has ever had on `realtime.messages`. Adding
-- one does not open the others: every topic that is not named here stays denied,
-- because the table's RLS is on and this is the only thing that permits.
--
-- **It reads the topic being joined, not the topic on the row.**
-- `realtime.topic()` is a session setting Realtime sets before it asks whether
-- this subscriber may join this channel — so the predicate answers "may you
-- listen here", which is the question being asked, and is deliberately
-- row-independent. Outside Realtime's own check that setting is null and the
-- policy is false for everyone; the `realtime` schema is not exposed through
-- PostgREST either, so there is no second door to try it at.
--
-- Verified as Realtime evaluates it — role `authenticated`, claims set, topic
-- set: an admin on `ops:orders` passes; a signed-in customer on `ops:orders`,
-- an admin on any other topic, and `anon` with no session all see nothing. An
-- `insert` is refused for everyone, including admins, because no policy permits
-- one and RLS denies by default.
drop policy if exists "admins hear the ops channel" on realtime.messages;
create policy "admins hear the ops channel"
  on realtime.messages
  for select
  to authenticated
  using (
    realtime.topic() = 'ops:orders'
    and public.is_admin()
  );
