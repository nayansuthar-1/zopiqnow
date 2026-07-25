-- ---------------------------------------------------------------------------
-- 0052 — the order narrates itself.
-- ---------------------------------------------------------------------------
-- P1 Tier 1 of `presentation-tasks.md`: the live order card on the lock screen.
-- The card is drawn on the device by `flutter_local_notifications`; this
-- migration is the other half — the stream of events it redraws from.
--
-- **Why a second kind and not more `order_update` rows.** 0047 deliberately
-- narrates five moments to the customer and stays quiet about the rest, because
-- every one of those rows buzzes a phone. A live card needs the opposite: an
-- event on *every* step, including the kitchen mechanics 0047 skips, and none of
-- them may make a sound. So there are now two streams over one table —
-- `order_update`, which alerts and lands in the inbox exactly as it always has,
-- and `order_live`, which is silent, pre-read, and exists only to move a
-- progress bar. Six status changes, one buzz.
--
-- **Why the payload is computed from both tables, not from the row that fired.**
-- An order's progress lives in two places: `orders.status` (the kitchen) and
-- `deliveries.state` (the road). They advance independently — a rider can reach
-- the counter before the bag is packed — so a bar driven by whichever one moved
-- last would walk backwards on screen. `order_live_payload` reads both and takes
-- the furthest point either has reached, which is monotonic as long as neither
-- table reverses. Rule 3 of the slice ("the ETA must never move backwards")
-- is enforced here, in one function, rather than trusted to the device.
--
-- Nothing 0047 built changes. Its trigger, its rows, its channel and the
-- webhook that turns a row into a push all keep working untouched; this adds a
-- quieter second voice beside them.

-- ---------------------------------------------------------------------------
-- A. A notification can carry a payload.
-- ---------------------------------------------------------------------------
-- `title` and `body` are what a person reads. A live card also needs numbers —
-- which step, how far along, when the food is due — and it needs them without a
-- round trip, because it is drawn on a phone that may be asleep with the app
-- killed. One nullable jsonb, null for every row written before today and for
-- every row that is only prose.
alter table public.notifications
  add column if not exists data jsonb;

alter table public.notifications
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check
    check (kind in (
      'new_order',      -- vendor: a customer placed an order (0021)
      'system',         -- anyone: a catch-all notice
      'order_update',   -- customer: their order changed status (0047)
      'order_live',     -- customer: silent tick for the live card (0052)
      'job_available',  -- rider: a delivery is on the board to claim
      'job_cancelled',  -- rider: a job they were holding was called off (0051)
      'payout',         -- rider: a payout was paid
      'account',        -- rider: their partner account was activated/deactivated
      'settlement'      -- vendor: a weekly settlement was paid
    ));

-- ---------------------------------------------------------------------------
-- B. Where the order actually is, as one answer.
-- ---------------------------------------------------------------------------
-- The single source of the card's contents. Given an order id it returns
-- everything the device needs to redraw: the stage, the progress percentage, the
-- two lines of copy, and when the food is due.
--
-- `eta_at` is an absolute instant, not "minutes remaining", and that is the
-- whole trick behind Rule 3. Minutes remaining computed on the server would be
-- stale the moment it was sent and would jump around between events; a fixed
-- deadline lets the device count down against its own clock and can never move
-- backwards, because it never moves at all. It is `created_at + eta_minutes` —
-- the same promise the confirmation screen already made.
--
-- `stable`, and it reads only rows the caller has no other way to combine, so it
-- is `security definer` with the grant revoked: the triggers below call it in
-- their own definer context and nobody else calls it at all (the 0045 lesson).
create or replace function public.order_live_payload(p_order_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with o as (
    select id, status, restaurant_name, created_at, eta_minutes
      from public.orders
     where id = p_order_id
  ),
  d as (
    -- The live delivery, if there is one. A dropped job leaves a 'cancelled'
    -- row beside the real one (the 0025 abandon→reclaim shape), and letting a
    -- corpse into this join is how the bar would jump back to the counter.
    select state
      from public.deliveries
     where order_id = p_order_id
       and state <> 'cancelled'
     order by claimed_at desc
     limit 1
  ),
  stage as (
    select case
      when o.status in ('cancelled', 'rejected')            then 'ended'
      when o.status = 'delivered'
        or coalesce(d.state, '') = 'delivered'              then 'delivered'
      when coalesce(d.state, '') = 'arrived_at_customer'    then 'at_door'
      when coalesce(d.state, '') = 'picked_up'
        or o.status = 'out_for_delivery'                    then 'on_the_way'
      when coalesce(d.state, '') = 'arrived_at_restaurant'  then 'rider_at_restaurant'
      when o.status = 'ready_for_pickup'                    then 'packed'
      when o.status = 'preparing'                           then 'preparing'
      when o.status = 'accepted'                            then 'accepted'
      else 'placed'
    end as name,
    -- The furthest point either ladder has reached. `greatest` is what makes it
    -- monotonic: an arrival at the restaurant (65) survives the kitchen
    -- afterwards marking the bag packed (55).
    greatest(
      case o.status
        when 'placed'           then 5
        when 'accepted'         then 15
        when 'preparing'        then 35
        when 'ready_for_pickup' then 55
        when 'out_for_delivery' then 75
        when 'delivered'        then 100
        else 0
      end,
      case coalesce(d.state, '')
        when 'claimed'               then 20
        when 'arrived_at_restaurant' then 65
        when 'picked_up'             then 75
        when 'arrived_at_customer'   then 95
        when 'delivered'             then 100
        else 0
      end
    ) as progress
    from o left join d on true
  )
  select jsonb_build_object(
    'order_id',   o.id,
    -- `stage`, and deliberately not `orders.status` beside it. The raw status
    -- is a half-truth here — it reads 'preparing' while the rider is already
    -- standing at the counter — and a second field that disagrees with the
    -- first is a field somebody will eventually believe. `stage` is the one
    -- answer, computed from both ladders, and it is also what makes two
    -- consecutive payloads comparable in `post_order_live`.
    'stage',      s.name,
    'progress',   s.progress,
    'restaurant', o.restaurant_name,
    'eta_at',     to_char(
                    (o.created_at + make_interval(mins => o.eta_minutes))
                      at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                  ),
    'title', case s.name
      when 'accepted'            then 'Order confirmed'
      when 'preparing'           then 'Preparing your order'
      when 'packed'              then 'Order packed'
      when 'rider_at_restaurant' then 'Delivery partner is at the restaurant'
      when 'on_the_way'          then 'On the way'
      when 'at_door'             then 'Your delivery partner is outside'
      when 'delivered'           then 'Delivered'
      when 'ended'               then 'Order ended'
      else 'Order placed'
    end,
    'body', case s.name
      when 'accepted'            then o.restaurant_name || ' is getting started'
      when 'preparing'           then o.restaurant_name || ' is cooking your food'
      when 'packed'              then 'Waiting for a delivery partner to collect it'
      when 'rider_at_restaurant' then 'Collecting your order from ' || o.restaurant_name
      when 'on_the_way'          then 'Your order from ' || o.restaurant_name || ' is on its way'
      when 'at_door'             then 'Have your delivery code ready'
      when 'delivered'           then 'Your order from ' || o.restaurant_name || ' has arrived'
      when 'ended'               then 'This order is no longer running'
      else 'Waiting for ' || o.restaurant_name || ' to confirm'
    end
  )
  from o cross join stage s;
$$;

revoke all on function public.order_live_payload(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- C. Posting a tick.
-- ---------------------------------------------------------------------------
-- One writer, called by both triggers, so the two sources cannot drift apart.
--
-- `read_at` is stamped at insert. These rows are transport, not correspondence:
-- they must not appear in the inbox and must not touch the unread badge. The
-- customer app filters them out of the list as well, but a row that arrives
-- already-read cannot inflate a count even on a build that has not been updated.
--
-- **It refuses to repeat itself.** Because progress is the furthest point either
-- ladder has reached, an event can leave the card exactly as it was — a kitchen
-- marking the bag packed after the rider already reached the counter is the
-- ordinary case. The payload is then byte-identical to the last one, and sending
-- it would wake every one of that customer's devices to redraw nothing. So the
-- previous tick is compared and a duplicate is dropped.
create or replace function public.post_order_live(
  p_order_id text,
  p_user_id  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v    jsonb;
  v_last jsonb;
begin
  v := public.order_live_payload(p_order_id);
  if v is null then
    return;
  end if;

  select data into v_last
    from public.notifications
   where kind = 'order_live'
     and order_id = p_order_id
   order by id desc
   limit 1;

  if v_last is not null and v_last = v then
    return;
  end if;

  insert into public.notifications
    (audience, user_id, kind, title, body, order_id, data, read_at)
  values
    ('customer', p_user_id, 'order_live',
     v->>'title', v->>'body', p_order_id, v, now());
end;
$$;

revoke all on function public.post_order_live(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- D. The two sources that make it tick.
-- ---------------------------------------------------------------------------
-- Both are wrapped so they can never abort the write they ride on — the rule
-- 0021 stated and 0047 kept: the event is the thing that matters, the
-- notification is a courtesy on top of it.

-- The kitchen half: every status change, including the two 0047 stays quiet
-- about, and the terminal ones — a card that survives a delivered order is worse
-- than never having shown one, so the end of the order is itself an event.
create or replace function public.notify_customer_order_live()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  begin
    perform public.post_order_live(new.id, new.user_id);
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists orders_notify_customer_live on public.orders;
create trigger orders_notify_customer_live
  after update of status on public.orders
  for each row execute function public.notify_customer_order_live();

-- The road half: the two arrivals 0049 records and nothing tells the phone
-- about. "Delivery partner is at the restaurant" is exactly this row.
--
-- Only those two states. `picked_up` and `delivered` already move
-- `orders.status` (`confirm_pickup`, `confirm_delivered`), so narrating them
-- here as well would post the same card twice; `claimed` is not a moment the
-- customer is told about, because a rider who has taken a job may still drop it
-- (the reason 0039 waits for `picked_up` before naming them).
create or replace function public.notify_customer_delivery_live()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user text;
begin
  if new.state is not distinct from old.state then
    return new;
  end if;

  if new.state not in ('arrived_at_restaurant', 'arrived_at_customer') then
    return new;
  end if;

  begin
    select user_id into v_user from public.orders where id = new.order_id;
    if v_user is null then
      return new;
    end if;
    perform public.post_order_live(new.order_id, v_user);
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists deliveries_notify_customer_live on public.deliveries;
create trigger deliveries_notify_customer_live
  after update of state on public.deliveries
  for each row execute function public.notify_customer_delivery_live();
