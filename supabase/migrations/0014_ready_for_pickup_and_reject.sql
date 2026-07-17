-- Step 11, migration 14: the kitchen gets two words it did not have.
--
-- Phase 2 of the vendor build-out. Two new order statuses, and the reason a
-- kitchen gives when it turns an order away:
--
--   * `ready_for_pickup` — the food is packed and waiting for the rider. It sits
--     between `preparing` and `out_for_delivery`, a step the kitchen owns and the
--     customer can see. Until now the kitchen went straight from "preparing" to
--     "handed to rider", which is two facts pretending to be one.
--
--   * `rejected` — a *new* order the restaurant declined before ever accepting it.
--     Different from `cancelled`, which is an order called off *after* it was
--     accepted. Same outcome for the customer — no food — but a different sentence,
--     and a different moment, and the two should not be the same word.
--
-- Both apps already know these values: the customer app shipped its reader first
-- (its `OrderStatus.fromWire` would otherwise throw on a status the database is
-- about to start emitting). This migration is the half that makes them real.

-- ---------------------------------------------------------------------------
-- 1. The check constraint learns the two new values.
-- ---------------------------------------------------------------------------
-- The inline check from 0003 is named `orders_status_check`. Drop and re-add
-- rather than alter — a check constraint has no in-place widen.
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in (
    'placed', 'accepted', 'preparing', 'ready_for_pickup',
    'out_for_delivery', 'delivered', 'rejected', 'cancelled'
  ));

-- ---------------------------------------------------------------------------
-- 2. Why an order was turned away.
-- ---------------------------------------------------------------------------
-- Nullable, and null for every order that simply went well: a reason exists only
-- when a kitchen rejects or cancels. The customer read does not select it (it is
-- the kitchen's note, not the customer's receipt), so adding the column changes
-- nothing about what the customer app fetches.
alter table public.orders
  add column if not exists status_reason text;

-- ---------------------------------------------------------------------------
-- 3. set_order_status: the new steps, and the reason.
-- ---------------------------------------------------------------------------
-- Gains a third argument, so the two-argument function from 0009 is dropped and
-- replaced. `p_reason` defaults to null, so a caller that omits it — the way
-- every forward step does — still binds by name against this one function.
drop function if exists public.set_order_status(text, text);

create or replace function public.set_order_status(
  p_order_id text,
  p_status   text,
  p_reason   text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  text;
  v_current     text;
  v_allowed     text[];
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  -- Locked, because two tablets in one kitchen is the normal case. Without this,
  -- both can read the same status and race to write different next ones.
  select o.status into v_current
    from public.orders o
   where o.id = p_order_id
     and o.restaurant_id = v_restaurant
   for update;

  if not found then
    raise exception 'That order is not one of yours.' using errcode = 'P0001';
  end if;

  -- The kitchen may move an order to the next step, decline a *new* one, or call
  -- off one it already accepted while the food is still in the building. It may
  -- not skip ahead and it may not go back — a customer told their food is on its
  -- way must not watch it return to the kitchen.
  --
  --   placed           → accept, or reject outright
  --   accepted         → prepare, or cancel
  --   preparing        → ready for pickup, or cancel
  --   ready_for_pickup → hand to rider, or cancel
  --   out_for_delivery → deliver (no cancel: the food has left)
  v_allowed := case v_current
    when 'placed'           then array['accepted', 'rejected']
    when 'accepted'         then array['preparing', 'cancelled']
    when 'preparing'        then array['ready_for_pickup', 'cancelled']
    when 'ready_for_pickup' then array['out_for_delivery', 'cancelled']
    when 'out_for_delivery' then array['delivered']
    else array[]::text[]
  end;

  if not (p_status = any (v_allowed)) then
    raise exception 'An order that is % cannot become %.', v_current, p_status
      using errcode = 'P0001';
  end if;

  -- The reason is kept only for the two statuses that have one. A forward step
  -- leaves any earlier note untouched rather than blanking it.
  update public.orders
     set status = p_status,
         status_reason = case
           when p_status in ('rejected', 'cancelled')
             then nullif(trim(coalesce(p_reason, '')), '')
           else status_reason
         end
   where id = p_order_id;

  return p_status;
end;
$$;

grant execute on function public.set_order_status(text, text, text) to authenticated;
