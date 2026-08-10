-- ---------------------------------------------------------------------------
-- 0110 — the live card waits for the kitchen to actually start.
-- ---------------------------------------------------------------------------
-- The live card has been going up the moment an order was placed, and again
-- when the restaurant accepted it. Both are too early, and the second one is
-- worse than too early: 'accepted' already sends an ordinary `order_update`
-- push ("Order confirmed"), so a customer got a notification *and* a countdown
-- card for one event — two things on the lock screen saying the same thing, one
-- of which had started counting down to a prep time nobody had committed to yet.
--
-- A countdown is a promise. The kitchen makes it when it taps Start Preparing,
-- which is the moment `ready_by` becomes real; before that the card was counting
-- down to `created_at + 55% of the ETA`, a number invented so the bar would have
-- somewhere to go.
--
-- So the card now begins at 'preparing'. Everything before it is narrated by
-- `order_update` alone, which is what that kind is for:
--
--   placed     → no card. (No `order_update` either — placing it is not news to
--                the person who placed it.)
--   accepted   → no card, ordinary "Order confirmed" push. Unchanged.
--   preparing  → the card goes up, counting down to `ready_by`.
--   packed →    … and onwards, exactly as before.
--
-- Nothing about the payload changes: `order_live_payload` (0058) still computes
-- the same window, the same phase and the same title. This only decides *when*
-- the first tick is allowed out. That keeps the change to one function, and
-- keeps the two cards' handover (prep → delivery) untouched.

create or replace function public.post_order_live(
  p_order_id text,
  p_user_id  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v      jsonb;
  v_last jsonb;
begin
  v := public.order_live_payload(p_order_id);
  if v is null then
    return;
  end if;

  -- Before the kitchen starts, there is nothing to count down to. Checked on
  -- `stage` rather than `orders.status` deliberately: `stage` is the reconciled
  -- answer that already folds in the delivery row, so an order whose status
  -- still reads 'accepted' while a rider is somehow ahead of it cannot be held
  -- back by this. `order_live_payload` computes it; this only reads it.
  --
  -- 'delivered' and 'ended' are *not* filtered here. They carry no card either,
  -- but the device needs them: they are the instruction to take down the cards
  -- that are already up (`OrderLiveCard._terminal`). Dropping them would strand
  -- a prep card on the lock screen of a cancelled order.
  if v->>'stage' in ('placed', 'accepted') then
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

-- 0089/0091: a function is born PUBLIC-executable and additionally granted to
-- `authenticated`. This one is called only by triggers running as the definer,
-- so both doors are shut — the same revoke 0052 issued, restated because
-- `create or replace` on an existing function keeps its ACL but a fresh one
-- would not, and this file must be safe to run against either.
revoke all on function public.post_order_live(text, text) from public, anon, authenticated;
