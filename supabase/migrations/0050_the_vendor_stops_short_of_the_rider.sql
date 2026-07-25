-- ---------------------------------------------------------------------------
-- 0050 — the vendor stops short of the rider
-- ---------------------------------------------------------------------------
-- 0049 built the whole delivery handshake — arrivals, a pickup code the rider
-- cannot read, a delivery code the customer reads out — and made
-- `confirm_pickup` and `confirm_delivered` the only honest way across the last
-- two transitions of an order's life:
--
--   ready_for_pickup → out_for_delivery   only via confirm_pickup   (rider at
--                                          the counter + the kitchen's code)
--   out_for_delivery → delivered          only via confirm_delivered (rider at
--                                          the door + the customer's code)
--
-- But it left the back door wide open. `set_order_status` (0014) still listed
-- both of those as moves the *kitchen* could make on its own:
--
--   ready_for_pickup → out_for_delivery   ("Hand to rider")
--   out_for_delivery → delivered          ("Mark delivered")
--
-- So a vendor could accept an order, mark it ready, then tap "Hand to rider"
-- and "Mark delivered" in sequence — no rider, no pickup, no code read to
-- anyone, no food moved — and the order would settle as delivered and be
-- charged for. The two apps disagreed about who owns the handover, and the
-- looser one won.
--
-- This closes it at the source. The kitchen's authority now *ends* at
-- `ready_for_pickup`: it packs the food and it may still call the order off
-- while it sits on the counter, but it cannot declare the food collected or
-- delivered. Those two sentences are the rider's to say, with proof, or nobody's.
--
-- The vendor app is changed in lockstep to stop offering the two buttons, but
-- the app change is a courtesy — this function is the wall. A hand-rolled RPC
-- call to `set_order_status(id, 'delivered')` now raises like any other illegal
-- move.
-- ---------------------------------------------------------------------------

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

  -- The kitchen's ladder now stops at `ready_for_pickup`. It may move an order
  -- to the next step it owns, decline a *new* one, or call off one it already
  -- accepted while the food is still on its counter. It may not skip ahead, it
  -- may not go back, and — the change in this migration — it may not cross into
  -- the rider's half of the story:
  --
  --   placed           → accept, or reject outright
  --   accepted         → prepare, or cancel
  --   preparing        → ready for pickup, or cancel
  --   ready_for_pickup → cancel only        (the rider collects; confirm_pickup)
  --   out_for_delivery → nothing            (the rider delivers; confirm_delivered)
  --
  -- `out_for_delivery` is a state the kitchen can now only *watch*: it is put
  -- there by `confirm_pickup` and taken out of by `confirm_delivered`, both of
  -- which demand a rider and a code. The vendor's screen still shows the rider's
  -- progress across it — it just has no button under it.
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
