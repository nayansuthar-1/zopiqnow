-- The ring is sent by the function that is actually wired up.
--
-- 0128 taught a kitchen's phone to ring like a call until an order is answered,
-- and it worked on the device: the channel, the flags, the alarm-stream
-- ringtone and the Accept/Reject actions are all in the vendor app, and a new
-- order rings an app that is *open* off the realtime stream. The whole point,
-- though, is the app that is **not** open — and that half has never fired once.
--
-- Ringing a closed app needs a **data-only** message: Android draws any message
-- carrying a `notification` block itself and will not attach `FLAG_INSISTENT`,
-- so the app has to be woken to draw its own. 0128 put that branch in
-- `send-order-push` — and `send-order-push` has not been called since **0058**,
-- which dropped the `orders`-INSERT webhook because it was ringing the kitchen
-- twice alongside 0047's `notifications`-INSERT webhook. So the ring branch was
-- written into a function nothing invokes. The live sender, `send-notification`,
-- has gone on sending `new_order` with a notification block, Android has gone on
-- drawing it itself, and the kitchen has gone on getting one polite ping.
--
-- The send side moves to `send-notification` in the same commit. This migration
-- is the one thing that move needs from the database: the deadline.
--
-- **Why the deadline has to ride along.** `OrderRing` bounds the ring by the
-- time actually left on `orders.accept_deadline` (0051, five minutes), because a
-- phone still ringing for an order the database has already auto-expired is
-- noise with nothing behind it. The device cannot read that column — the ring is
-- drawn in the FCM background isolate, where there is no session and no
-- Supabase client — so the sender has to put it in the message, and the sender
-- only ever sees the notification row. `notify_new_order` writes the row without
-- `data`, so every ring would fall back to a fresh five minutes: an order
-- delayed four minutes in a Doze queue would ring for five more, four of them
-- past the point where it was already gone.
--
-- `notifications.data` (0052) is exactly the channel for this — `send-notification`
-- already flattens it one level into the FCM data map, and `PushService` already
-- reads `accept_deadline` from there. Nothing else about the row changes.

create or replace function public.notify_new_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    insert into public.notifications
      (restaurant_id, kind, title, body, order_id, data)
    values (
      new.restaurant_id,
      'new_order',
      'New order',
      'Order ' || new.id || ' · ₹' || new.total,
      new.id,
      -- How long the kitchen has left to answer. `accept_deadline` is defaulted
      -- and not null (0051), so this is always a real instant, and `to_jsonb`
      -- renders it as the ISO-8601 text `DateTime.tryParse` expects.
      jsonb_build_object('accept_deadline', new.accept_deadline)
    );
  exception when others then
    -- Placement is sacred; a notification is not. Never let this abort the order.
    null;
  end;
  return new;
end;
$$;

-- ---------------------------------------------------------------- verification
--   -- The row a new order writes now carries the deadline:
--   begin;
--     insert into public.orders (…) values (…);   -- any placed order
--     select kind, data from public.notifications order by id desc limit 1;
--     -- data must be {"accept_deadline": "2026-..T..:..:..+00:00"}
--   rollback;
--
-- And end to end, which is the claim worth proving: with the vendor app killed,
-- place an order and the phone must ring — the device ringtone, on the alarm
-- stream, repeating, with Accept and Reject on the notification — and it must
-- stop ringing when the order is answered on any device.
--
-- ⚠️ A device only gets the data-only message if `device_tokens.rings_new_orders`
-- is true for it, which is the build's own claim (0128) and false for every
-- install that predates the ring. Check before blaming the sender:
--   select restaurant_id, platform, rings_new_orders, updated_at
--     from public.device_tokens where audience = 'restaurant';
