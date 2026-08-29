-- ---------------------------------------------------------------------------
-- 0142 — a payment that was spent says so.
-- ---------------------------------------------------------------------------
-- Fallout from arming the gate in 0141, found by pointing the new orphan sweep
-- at the live database before trusting it.
--
-- ## Five payments that bought dinner and still look unspent
--
-- `orders_require_verified_payment` does two things: it refuses an order whose
-- payment cannot be proved, and it marks the proving intent `consumed` so the
-- same payment cannot buy a second one. While the gate was disarmed it did
-- *neither* — it returned on its first line. So every real payment taken since
-- the Razorpay keys went in on 25 August became an order and left its
-- `payment_intents` row sitting at `verified`:
--
--     intent 36  ₹292   → ZPQ-1185      intent 39  ₹9930  → ZPQ-1188
--     intent 37  ₹177   → ZPQ-1186      intent 46  ₹155   → ZPQ-1189
--     intent 38  ₹816   → ZPQ-1187
--
-- Every one of those is matched by `razorpay_payment_id` to an order of exactly
-- its own amount, so there is no ambiguity about what they paid for.
--
-- **Arming the gate turned each of them into a live voucher.** The gate lets an
-- order through when it finds a `verified` intent belonging to the caller worth
-- at least the order's total — and these five are verified, unconsumed, and
-- belong to real customers. Any one of them could have been spent a second time
-- on a fresh order (₹9930 of headroom on the largest), which is the precise
-- thing the `consumed` transition exists to prevent. Closing the front door in
-- 0141 is what made these five worth finding.
--
-- Backfilled rather than deleted: the row is the record that ₹9930 was taken
-- from a named customer, and `consumed_at` is set to the order's own timestamp
-- because that is when it was, in fact, spent.
--
-- Gift orders need no equivalent — all three on the platform carry
-- `pay_mock_…` ids from before the gateway existed and match no intent.
--
-- ## The sweep needed a second question
--
-- `flag_orphaned_payments` asked whether an intent had been *linked* to an
-- order. That is the right question for everything created from here on, and
-- the wrong one for anything created while the gate was down: all five above
-- would have been reported as money captured for nothing, at 15-minute
-- intervals, with the customer's food already eaten. An alert that is wrong
-- five times out of five on its first run is an alert nobody reads again.
--
-- So it now also asks whether anything on the platform is *carrying* the
-- payment id. Linked or carried, the money arrived somewhere. Belt and braces
-- after this backfill, and the brace that matters the day some other path
-- writes an order without going through the trigger.
--
-- The 19 `created` intents are left alone. An intent that never reached
-- `verified` is a checkout somebody abandoned at the Razorpay sheet: no
-- signature was ever presented, so no money was captured, and there is nothing
-- to refund or to alert about.
-- ---------------------------------------------------------------------------

update public.payment_intents pi
   set status      = 'consumed',
       order_id    = o.id,
       consumed_at = o.created_at
  from public.orders o
 where o.payment_id = pi.razorpay_payment_id
   and pi.status    = 'verified'
   and pi.order_id  is null
   and pi.gift_order_id is null;

update public.payment_intents pi
   set status        = 'consumed',
       gift_order_id = g.id,
       consumed_at   = g.created_at
  from public.gift_orders g
 where g.payment_id = pi.razorpay_payment_id
   and pi.status    = 'verified'
   and pi.order_id  is null
   and pi.gift_order_id is null;

create or replace function public.flag_orphaned_payments()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r       record;
  v_count integer := 0;
begin
  for r in
    select pi.id, pi.amount, pi.user_id, pi.razorpay_payment_id,
           pi.razorpay_order_id, pi.verified_at
      from public.payment_intents pi
     where pi.status = 'verified'
       and pi.order_id is null
       and pi.gift_order_id is null
       and pi.verified_at < now() - interval '30 minutes'
       -- New in 0142. `order_id` says the gate linked it; this says somebody is
       -- carrying the payment id anyway. Either answers "did this money arrive
       -- somewhere", and only the second one survives a period where the gate
       -- was not doing the linking.
       and not exists (
         select 1 from public.orders o
          where o.payment_id = pi.razorpay_payment_id
       )
       and not exists (
         select 1 from public.gift_orders g
          where g.payment_id = pi.razorpay_payment_id
       )
       -- Not already on somebody's desk. The partial unique index would refuse
       -- the insert anyway; asking first keeps the loop honest about what it
       -- counted.
       and not exists (
         select 1 from public.admin_alerts a
          where a.kind = 'orphan_payment'
            and a.subject = 'intent:' || pi.id
            and a.resolved_at is null
       )
     order by pi.verified_at
     limit 50
  loop
    begin
      insert into public.admin_alerts (kind, subject, title, body)
      values (
        'orphan_payment',
        'intent:' || r.id,
        'A payment was taken and no order exists',
        '₹' || r.amount || ' was captured from customer ' || r.user_id ||
          ' at ' || to_char(r.verified_at at time zone 'Asia/Kolkata', 'DD Mon HH24:MI') ||
          ' IST and never became an order. Razorpay payment ' ||
          coalesce(r.razorpay_payment_id, '(none)') || ', order ' ||
          r.razorpay_order_id || '. Refund it from the Razorpay dashboard and ' ||
          'resolve this alert with the refund reference.'
      )
      on conflict do nothing;
      v_count := v_count + 1;
    exception when others then
      -- One bad row must not stop the sweep finding the rest of the money.
      raise warning 'orphan sweep: intent % could not be flagged: %', r.id, sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.flag_orphaned_payments() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The five alerts the sweep had already raised before it learned the second
-- question. 0141 scheduled it every fifteen minutes and a tick landed between
-- the two files, so the console is holding five open alerts that say ₹11,370 of
-- customer money vanished. It did not — it bought ZPQ-1185 through ZPQ-1189,
-- which the backfill above has now recorded.
--
-- Resolved rather than deleted, with the body rewritten to say what actually
-- happened. A false alarm that is simply removed teaches nobody anything the
-- next time the sweep is doubted; one that is closed with its own correction
-- attached is the record of why it fired.
-- ---------------------------------------------------------------------------

update public.admin_alerts a
   set title       = 'Payment reconciled — this alert was a false positive',
       body        = 'Intent #' || split_part(a.subject, ':', 2) || ' was raised by the '
                     || 'first run of the orphan sweep, before migration 0142 taught it to '
                     || 'check whether an order was carrying the payment id. It was: this '
                     || 'payment bought order ' || coalesce(pi.order_id, '(unknown)')
                     || '. The intent has been marked consumed and no money is owed.',
       resolved_at = now(),
       resolved_by = 'migration 0142'
  from public.payment_intents pi
 where a.kind = 'orphan_payment'
   and a.subject = 'intent:' || pi.id
   and a.resolved_at is null
   and pi.status = 'consumed';
