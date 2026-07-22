-- Migration 41: two things the 8b-4 review found. (Phase 8b-4)
--
-- Neither is a hole anyone can walk through today. Both are the kind of thing
-- that becomes one later, quietly, when a feature nobody has written yet makes
-- the unreachable reachable.

-- ---------------------------------------------------------------------------
-- 1. `confirm_delivered` never looked at the order.
-- ---------------------------------------------------------------------------
-- It checked that the caller is the rider holding a `picked_up` row — and then
-- wrote `status = 'delivered'` over whatever the order said. Its twin
-- `confirm_pickup` has always checked the status (`ready_for_pickup`); this one
-- simply never did.
--
-- Reachable today? No. The only thing that can move an order out of
-- `out_for_delivery` is this function, because 0014 gives the kitchen no
-- transition out of it and the 0008 demo cron has been unscheduled. So the
-- edge matrix had to fabricate the state by hand to prove the gap — a rider
-- marking a *cancelled* order delivered.
--
-- Which is exactly why it is worth closing now rather than later: the day
-- someone adds customer-side cancellation, or an ops "cancel this order"
-- button, this stops being hypothetical and starts being a cancelled order that
-- reports itself delivered, settles, and is charged for.
create or replace function public.confirm_delivered(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider  text;
  v_status text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- Locked with the delivery row, for the reason `confirm_pickup` locks: the
  -- read and the write must not straddle somebody else's write.
  select o.status into v_status
    from public.deliveries d
    join public.orders o on o.id = d.order_id
   where d.order_id = p_order_id
     and d.partner_email = v_rider
     and d.state = 'picked_up'
   for update of d;

  if not found then
    raise exception 'You aren''t carrying that order.' using errcode = 'P0001';
  end if;

  -- The new check. An order that is not out for delivery cannot arrive.
  if v_status <> 'out_for_delivery' then
    raise exception 'That order is %, so it can''t be marked delivered.', v_status
      using errcode = 'P0001';
  end if;

  update public.deliveries
     set state = 'delivered', delivered_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'picked_up';

  update public.orders set status = 'delivered' where id = p_order_id;
end;
$$;

grant execute on function public.confirm_delivered(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The customer's phone number outlived the delivery.
-- ---------------------------------------------------------------------------
-- `my_deliveries` returns every job a rider has ever held that was not dropped,
-- and it handed back `o.user_phone` on all of them. A rider a year in had a
-- contact list of everyone whose dinner they ever carried, readable any time
-- they opened the app.
--
-- The number is given for one reason — "I'm outside and can't find the gate" —
-- and that reason ends when the food is handed over. So it ends with the job.
-- This is the same rule 0039 applied in the other direction: the customer sees
-- their rider's number only while the order is actually in transit.
-- *(User decision, 2026-07-22.)*
--
-- The address stays. It is how a rider recognises a past job at all, and unlike
-- a phone number it is not a way to reach anybody.
--
-- No app change: the rider app renders only the live job (`state.isLive`), so
-- the delivered rows this touches are fetched and never drawn. The client
-- already parses this column as nullable.
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
           o.delivery_to, o.delivery_lat, o.delivery_lng,
           case when d.state = 'delivered' then null else o.user_phone end,
           o.total, o.payment_method,
           d.claimed_at, d.picked_up_at, d.delivered_at
      from public.deliveries d
      join public.orders o on o.id = d.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where d.partner_email = v_rider
       and d.state <> 'cancelled'
     order by (d.state = 'delivered'), d.claimed_at desc;
end;
$$;

grant execute on function public.my_deliveries() to authenticated;

-- ---------------------------------------------------------------------------
-- Reviewed and deliberately left alone
-- ---------------------------------------------------------------------------
-- * **A rider may hold any number of jobs at once.** No cap, and that is not an
--   oversight — carrying three orders from the same street is how delivery
--   actually works. The abuse case (one rider claiming the whole board to
--   starve the others) is real but is answered by riders being hand-onboarded
--   by an admin and switchable off, not by a number in a function.
--
-- * **`available_deliveries` shows the delivery address before claiming.** Every
--   active rider can see where every unclaimed order is going. Narrowing it to
--   an area would be a genuine improvement and a bigger change than this
--   migration: the board is how a rider decides whether a job is worth taking,
--   and "somewhere in Banjara Hills" is a different decision from an address.
--   Noted in DELIVERY_PLAN.md rather than half-done here.
--
-- * **A rider deactivated *while carrying* still strands the order.** 0040
--   refuses it through the console, which is the only route ops has. Direct SQL
--   bypasses that, as direct SQL bypasses everything. The fix that would make it
--   structural is `abandon_delivery` accepting a picked-up job for an admin —
--   which is a support flow that does not exist yet, and inventing one here
--   would be guessing at its shape.
