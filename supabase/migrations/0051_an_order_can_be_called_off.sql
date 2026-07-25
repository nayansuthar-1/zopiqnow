-- ---------------------------------------------------------------------------
-- 0051 — an order can be called off
-- ---------------------------------------------------------------------------
-- Until now an order could only end one way once it existed: the kitchen ended
-- it. A customer who ordered by mistake had no button at all, and an order the
-- kitchen simply never looked at sat on 'placed' forever — the customer watching
-- a spinner that would never move, the restaurant unaware, nothing in the system
-- that would ever notice.
--
-- Three holes, one migration, because they are the same hole from three sides:
--
--   1. **The customer cannot call off their own order.** Now they can, until the
--      kitchen starts cooking. After that it is a refund conversation, and a
--      refund is B4's problem (there is no real money in the system yet — the
--      payment gateway is still a mock), so this migration deliberately stops at
--      the state change and does not pretend to move money.
--
--   2. **An unaccepted order never times out.** Now it auto-declines five minutes
--      after it was placed, in Postgres, on pg_cron. Not in an app: the reason a
--      kitchen misses an order is that nobody is looking at the tablet, and a
--      timeout that needs the tablet awake is a timeout that fires exactly when
--      it is not needed.
--
--   3. **A cancelled order left its rider holding a job.** `set_order_status`
--      wrote one column and told nobody: the `deliveries` row stayed 'claimed',
--      the rider's screen kept showing a pickup for an order that no longer
--      existed, and the pickup code stayed live. Every path that ends an order
--      now goes through one release.
--
-- **And a fourth, found on the way — 0050 did not do what it says.** 0015 had
-- widened `set_order_status` to four arguments (`p_prep_minutes`); 0050 wrote a
-- *three*-argument function to close the vendor's back door into the rider's
-- half of the story. Postgres does not replace a function across a different
-- argument list — it overloads it. So both existed, and the vendor app, which
-- passes `p_prep_minutes` on every call, bound to the four-argument one: the
-- 0015 body, with `ready_for_pickup → out_for_delivery` and
-- `out_for_delivery → delivered` still on its ladder. The wall 0050 describes
-- was built beside the door, not across it. Nothing exploited it — the app
-- stopped offering the buttons in the same commit — but "the app does not ask"
-- is precisely the kind of guarantee 0050 was written to stop relying on.
--
-- This migration collapses the two back into **one** function: 0050's ladder,
-- 0015's prep-time stamp, and the release from (3). The three-argument overload
-- is dropped, so there is one `set_order_status` and no way to pick the wrong one.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. How long a kitchen has to look up.
-- ---------------------------------------------------------------------------
-- A column and not a constant inside the sweeper, because the vendor's ticket
-- counts down to it: the deadline the kitchen sees and the deadline the database
-- enforces have to be the same value, or the tablet will show "0:04 left" over
-- an order that was declined a minute ago.
--
-- Not a generated column, though that is what this wants to be:
-- `timestamptz + interval` is STABLE, not IMMUTABLE (it reads the session's
-- timezone), and Postgres refuses it in a generation expression. A default does
-- the same job — it is evaluated once, at insert, which is exactly when the
-- clock should start.
alter table public.orders
  add column if not exists accept_deadline timestamptz;

-- Existing rows get the deadline they would have had. Almost all of them are
-- long finished; the arithmetic is what matters, not the outcome.
update public.orders
   set accept_deadline = created_at + interval '5 minutes'
 where accept_deadline is null;

alter table public.orders
  alter column accept_deadline set default (now() + interval '5 minutes'),
  alter column accept_deadline set not null;

-- The sweeper's whole query, once a minute, forever. Partial: only 'placed' rows
-- are ever scanned, and a busy restaurant has a handful of those at a time.
create index if not exists orders_awaiting_accept_idx
  on public.orders (accept_deadline)
  where status = 'placed';

-- ---------------------------------------------------------------------------
-- B. Letting go of a rider.
-- ---------------------------------------------------------------------------
-- One function, called by every path that ends an order early. Three things,
-- and they belong together — a release that does two of them is the bug this
-- fixes in a new shape:
--
--   * the delivery row is cancelled, so the job leaves `my_deliveries` and the
--     partial unique index (8b-4) frees the order for nobody;
--   * the codes are deleted, for 0049's reason: a rider who still holds a live
--     pickup code for a dead order can collect food nobody is paying for;
--   * the rider is told, because their job vanishing off the screen with no
--     sentence attached is how a delivery partner decides the app is broken.
--
-- Deliberately not `abandon_delivery`: that is the rider's own "I'm walking
-- away", scoped to their email and refused after pickup. This is the platform
-- taking a job back, for a reason the rider had nothing to do with.
--
-- `security definer` and revoked from every client role — nothing outside this
-- file may cancel a delivery on someone's behalf.
create or replace function public.release_order_delivery(
  p_order_id text,
  p_note     text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  update public.deliveries
     set state = 'cancelled'
   where order_id = p_order_id
     and state not in ('delivered', 'cancelled')
  returning partner_email into v_rider;

  -- Unconditional: an order that ended has no handover left, so neither code
  -- has anything to prove. `claim_delivery` writes fresh ones if this order
  -- somehow comes back, which it cannot.
  delete from public.delivery_codes where order_id = p_order_id;

  if v_rider is not null then
    -- Wrapped, per 0047: the notification is a courtesy on top of the release,
    -- and a courtesy must never be able to abort the thing it rides on.
    begin
      insert into public.notifications
        (audience, partner_email, kind, title, body, order_id)
      values
        ('rider', v_rider, 'job_cancelled', 'Delivery cancelled',
         p_note, p_order_id);
    exception when others then
      null;
    end;
  end if;
end;
$$;

revoke all on function public.release_order_delivery(text, text)
  from public, anon, authenticated;

-- A rider's job being taken back is its own kind of news — not a payout, not an
-- account change, and not a job appearing. 0047 kept `kind` a tolerant check
-- precisely so adding one is this line; every app maps a kind it does not know
-- to a plain row, so an older build meeting this one degrades and does not
-- crash. (The rider app's `fromWire` already falls through to `system`.)
alter table public.notifications
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check
    check (kind in (
      'new_order',      -- vendor: a customer placed an order (0021)
      'system',         -- anyone: a catch-all notice
      'order_update',   -- customer: their order changed status
      'job_available',  -- rider: a delivery is on the board to claim
      'job_cancelled',  -- rider: a job they were holding was called off (0051)
      'payout',         -- rider: a payout was paid
      'account',        -- rider: their partner account was activated/deactivated
      'settlement'      -- vendor: a weekly settlement was paid
    ));

-- ---------------------------------------------------------------------------
-- C. The kitchen's ladder — one function again.
-- ---------------------------------------------------------------------------
-- 0050's rules, 0015's prep stamp, B's release. Dropping the three-argument
-- overload is the point of the exercise: while both existed, which one ran
-- depended on how many arguments the caller happened to send, and the stricter
-- one was the one nobody called.
drop function if exists public.set_order_status(text, text, text);

create or replace function public.set_order_status(
  p_order_id     text,
  p_status       text,
  p_reason       text default null,
  p_prep_minutes integer default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_current    text;
  v_allowed    text[];
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  -- Locked, because two tablets in one kitchen is the normal case. Without this,
  -- both can read the same status and race to write different next ones. It is
  -- also what makes the auto-decline sweeper safe: it takes the same lock and
  -- skips a row a cook is mid-accept on.
  select o.status into v_current
    from public.orders o
   where o.id = p_order_id
     and o.restaurant_id = v_restaurant
   for update;

  if not found then
    raise exception 'That order is not one of yours.' using errcode = 'P0001';
  end if;

  -- The kitchen's authority ends at `ready_for_pickup` (0050). It may move an
  -- order to the next step it owns, decline a *new* one, or call off one it has
  -- accepted while the food is still on its counter. It may not skip ahead, it
  -- may not go back, and it may not cross into the rider's half of the story:
  --
  --   placed           → accept, or reject outright
  --   accepted         → prepare, or cancel
  --   preparing        → ready for pickup, or cancel
  --   ready_for_pickup → cancel only        (the rider collects; confirm_pickup)
  --   out_for_delivery → nothing            (the rider delivers; confirm_delivered)
  v_allowed := case v_current
    when 'placed'           then array['accepted', 'rejected']
    when 'accepted'         then array['preparing', 'cancelled']
    when 'preparing'        then array['ready_for_pickup', 'cancelled']
    when 'ready_for_pickup' then array['cancelled']
    else array[]::text[]
  end;

  if not (p_status = any (v_allowed)) then
    raise exception 'An order that is % cannot become %.', v_current, p_status
      using errcode = 'P0001';
  end if;

  update public.orders
     set status = p_status,
         -- The reason is kept only for the two statuses that have one. A forward
         -- step leaves any earlier note untouched rather than blanking it.
         status_reason = case
           when p_status in ('rejected', 'cancelled')
             then nullif(trim(coalesce(p_reason, '')), '')
           else status_reason
         end,
         -- A prep time is meaningful only at the moment of accepting. Stamped
         -- from the server's clock, not the client's, so the countdown cannot be
         -- skewed by a tablet whose time is wrong. (0015, kept verbatim — this is
         -- the half of the four-argument function that was worth keeping.)
         ready_by = case
           when p_status = 'accepted'
                and p_prep_minutes is not null
                and p_prep_minutes > 0
             then now() + make_interval(mins => p_prep_minutes)
           else ready_by
         end
   where id = p_order_id;

  -- A cancelled order must not leave a `deliveries` row pointing at a dead
  -- order. Only reachable from 'ready_for_pickup' backwards, so the rider is at
  -- most standing at the counter — but the release does not depend on that, and
  -- should not.
  if p_status in ('cancelled', 'rejected') then
    perform public.release_order_delivery(
      p_order_id,
      'The restaurant called off order ' || p_order_id || '.'
    );
  end if;

  return p_status;
end;
$$;

grant execute on function public.set_order_status(text, text, text, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- D. The customer calls it off.
-- ---------------------------------------------------------------------------
-- Allowed while the order is 'placed' or 'accepted' — that is, until somebody
-- starts cooking. The moment the kitchen taps "Start preparing", food is being
-- made and a cancellation stops being free; from there it is a refund, and a
-- refund needs a payment to reverse, which this platform does not have yet.
--
-- Every refusal is a **sentence about this order**, not a generic no. The screen
-- shows it verbatim, which is why 'preparing' and 'out_for_delivery' do not
-- share a message: "the kitchen has started" and "it is already on its way" are
-- different pieces of news, and a customer deciding whether to phone the
-- restaurant needs to know which one they are in.
--
-- The reason, when given, is stored third-person (`status_reason` has one
-- column and two readers). "Ordered by mistake" reads correctly on the kitchen's
-- history ticket *and* in the customer's own notification; "cancelled by you"
-- would read correctly in exactly one of them.
create or replace function public.cancel_my_order(
  p_order_id text,
  p_reason   text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    text;
  v_current text;
begin
  v_user := auth.uid()::text;
  if v_user is null then
    raise exception 'Sign in to manage your orders.' using errcode = 'P0001';
  end if;

  -- Locked against the kitchen accepting or starting this order in the same
  -- instant. Whichever of the two gets the lock first wins, and the other reads
  -- the status it actually produced — which is the whole point: a customer who
  -- taps Cancel a half-second after the cook taps Start must be told the food is
  -- already being made, not quietly allowed to stop it.
  select o.status into v_current
    from public.orders o
   where o.id = p_order_id
     and o.user_id = v_user
   for update;

  -- "Not yours" and "does not exist" are the same answer here, deliberately, and
  -- for the reason every other read of `orders` gives it: an id that says "this
  -- exists, but not for you" is an id worth guessing at.
  if not found then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  if v_current not in ('placed', 'accepted') then
    raise exception '%', case v_current
      when 'preparing'        then 'The kitchen has already started cooking this order.'
      when 'ready_for_pickup' then 'Your order is packed and waiting for a rider.'
      when 'out_for_delivery' then 'Your order is already on its way.'
      when 'delivered'        then 'This order has already been delivered.'
      else 'This order has already ended.'
    end using errcode = 'P0001';
  end if;

  update public.orders
     set status = 'cancelled',
         status_reason = coalesce(
           nullif(trim(coalesce(p_reason, '')), ''),
           'Cancelled by the customer'
         )
   where id = p_order_id;

  -- Belt and braces. No rider can hold a job on an order this early — a claim
  -- needs 'preparing' at the least (0049) — but the rule is "every path that
  -- ends an order releases the rider", and a rule with an exception written into
  -- it is the exception somebody relies on later.
  perform public.release_order_delivery(
    p_order_id,
    'The customer cancelled order ' || p_order_id || '.'
  );

  -- The kitchen may have accepted this and be about to start on it. The ticket
  -- will disappear from a live queue on its own; this is so it disappears with
  -- an explanation attached.
  begin
    insert into public.notifications
      (audience, restaurant_id, kind, title, body, order_id)
    select 'restaurant', o.restaurant_id, 'system',
           'Order cancelled',
           'The customer cancelled order ' || o.id || '.',
           o.id
      from public.orders o
     where o.id = p_order_id;
  exception when others then
    null;
  end;

  return 'cancelled';
end;
$$;

grant execute on function public.cancel_my_order(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- E. The order nobody looked at.
-- ---------------------------------------------------------------------------
-- Five minutes from placement, an order still sitting on 'placed' declines
-- itself. `rejected` and not `cancelled` deliberately: the two words already
-- mean different things in this schema (0014) — rejected is "never accepted",
-- cancelled is "called off after" — and an order the kitchen never touched is
-- the first of those. It also means the customer's notification trigger already
-- knows how to phrase it, and both apps already tolerate the status.
--
-- `skip locked` is the whole concurrency story: a row a kitchen tablet is
-- mid-accept on is locked by `set_order_status`, so the sweeper passes it by and
-- the accept wins. The alternative — waiting for the lock — would auto-decline
-- an order a cook accepted a half-second before the deadline.
--
-- No release call: a 'placed' order cannot have a rider (`claim_delivery`
-- refuses anything before 'preparing'), so there is nothing to let go of.
create or replace function public.expire_unaccepted_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_count integer := 0;
begin
  for v_order in
    select o.id, o.restaurant_id
      from public.orders o
     where o.status = 'placed'
       and o.accept_deadline <= now()
     order by o.accept_deadline
       for update skip locked
  loop
    update public.orders
       set status = 'rejected',
           status_reason = 'The restaurant didn''t respond in time'
     where id = v_order.id;

    begin
      insert into public.notifications
        (audience, restaurant_id, kind, title, body, order_id)
      values
        ('restaurant', v_order.restaurant_id, 'system',
         'Order missed',
         'Order ' || v_order.id ||
           ' was declined automatically — nobody accepted it in time.',
         v_order.id);
    exception when others then
      null;
    end;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- Ops-only, and revoked the 0045 way: `revoke ... from public` alone leaves the
-- Supabase client roles holding their own grants, and `anon` calling this over
-- PostgREST would be able to decline every open order on the platform.
revoke all on function public.expire_unaccepted_orders()
  from public, anon, authenticated;

select cron.unschedule('expire-unaccepted-orders')
 where exists (select 1 from cron.job where jobname = 'expire-unaccepted-orders');

-- Every minute. The deadline is five, so the worst case is a customer waiting
-- six — and a coarser tick would mean the vendor's countdown hitting zero with
-- the order still sitting there, which reads as a broken promise even though
-- nothing is wrong.
select cron.schedule(
  'expire-unaccepted-orders',
  '* * * * *',
  $$ select public.expire_unaccepted_orders(); $$
);
