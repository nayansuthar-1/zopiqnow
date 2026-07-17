-- Step 12, migration 15: how long the kitchen says it needs.
--
-- Accepting an order is also a promise about *when*. Until now the kitchen
-- accepted and that was that; the customer's "arriving by" came from the
-- delivery ETA quoted at checkout, a number the kitchen never touched. This lets
-- the cook commit to a prep time at the moment of accepting — "twenty minutes" —
-- and turns that into a `ready_by` the ticket can count down to.
--
-- Vendor-only. The column is nullable and the customer read does not select it,
-- so this changes nothing about what the customer app fetches or shows — the
-- countdown is the kitchen's own clock, not a second promise to the customer.

-- ---------------------------------------------------------------------------
-- 1. When the food should be ready.
-- ---------------------------------------------------------------------------
-- Null until the kitchen accepts with a prep time, and null forever for an order
-- that is rejected before it is ever accepted.
alter table public.orders
  add column if not exists ready_by timestamptz;

-- ---------------------------------------------------------------------------
-- 2. set_order_status stamps ready_by on accept.
-- ---------------------------------------------------------------------------
-- A fourth argument, so the three-argument function from 0014 is dropped and
-- replaced. `p_prep_minutes` defaults to null; a caller that omits it — every
-- transition that is not an accept — binds by name against this one function and
-- leaves `ready_by` alone.
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
  v_restaurant  text;
  v_current     text;
  v_allowed     text[];
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  select o.status into v_current
    from public.orders o
   where o.id = p_order_id
     and o.restaurant_id = v_restaurant
   for update;

  if not found then
    raise exception 'That order is not one of yours.' using errcode = 'P0001';
  end if;

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

  update public.orders
     set status = p_status,
         status_reason = case
           when p_status in ('rejected', 'cancelled')
             then nullif(trim(coalesce(p_reason, '')), '')
           else status_reason
         end,
         -- A prep time is meaningful only at the moment of accepting. Stamped
         -- from the server's clock, not the client's, so the countdown cannot be
         -- skewed by a tablet whose time is wrong.
         ready_by = case
           when p_status = 'accepted'
                and p_prep_minutes is not null
                and p_prep_minutes > 0
             then now() + make_interval(mins => p_prep_minutes)
           else ready_by
         end
   where id = p_order_id;

  return p_status;
end;
$$;

grant execute on function public.set_order_status(text, text, text, integer)
  to authenticated;
