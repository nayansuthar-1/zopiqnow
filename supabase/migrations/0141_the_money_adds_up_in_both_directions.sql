-- ---------------------------------------------------------------------------
-- 0141 — the money adds up in both directions.
-- ---------------------------------------------------------------------------
-- A sweep of the whole money path — customer, vendor, rider, admin console,
-- gifts — looking for places where a rupee enters the system and does not come
-- out the other side, or comes out twice. Seven findings, six of them fixed
-- here and the seventh (the payment gate) armed at the bottom.
--
-- The healthy majority is worth saying first, because it is what made the
-- exceptions findable: every money table is `select`-only to `authenticated`
-- and written exclusively through `security definer` functions; every one of
-- the 106 `admin_*` RPCs calls `assert_admin()`; every amount in the schema is
-- whole rupees with the paise conversion happening in exactly three places
-- (`razorpay-order`, the checkout sheet, `pay_approved_refunds`); and the
-- cart, `checkout_preflight` and `place_order` compute the same total by the
-- same largest-remainder rule. None of that is touched.
--
-- ===========================================================================
-- 1. An order with any earlier refund could never be cancelled.
-- ===========================================================================
-- `orders_refund_on_termination` (0077) refunds `new.total` — the whole order —
-- and `refund_within_the_order` (0076) refuses any refund that would take the
-- order past its own total. Put a ₹50 goodwill refund on a ₹292 order and the
-- two rules collide:
--
--     update orders set status = 'cancelled' where id = 'ZPQ-1166';
--     ERROR:  That would refund ₹342 on an order of ₹292 — ₹50 of it is
--             already refunded.
--
-- The cancel does not half-happen; the whole statement aborts. So an order that
-- has been partly refunded — which is *precisely* the order most likely to be
-- heading for a cancellation — cannot be cancelled by the customer, by the
-- kitchen, or by an admin. The customer is stuck watching an order nobody can
-- call off, and the sentence they are shown is about refund arithmetic.
--
-- The fix is the obvious one: refund what is still owed, not what was owed at
-- the start. If earlier refunds already cover the order there is nothing left
-- to send and the trigger stands down rather than raising.
-- ---------------------------------------------------------------------------

create or replace function public.orders_refund_on_termination()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  -- What the customer is promised. Five days is the gateway's own working
  -- window for a UPI reversal; it is deliberately not a settings row, because a
  -- promise that an admin can shorten is a promise the platform will break.
  v_days constant integer := 5;
  v_reason text;
  v_owed   integer;
  v_id     bigint;
begin
  -- Nothing was captured, so nothing goes back. A cancelled cash order is not a
  -- refund — after 0076 there is a ledger that says the rider never collected.
  if new.payment_method <> 'upi' or new.payment_id is null then
    return new;
  end if;

  if exists (
    select 1 from public.refunds r
     where r.order_id = new.id and r.requested_by = 'system'
  ) then
    return new;
  end if;

  -- New in 0141. Everything already owed on this order, on the same predicate
  -- `refund_within_the_order` uses to decide what is owed — a `failed` or
  -- `declined` refund sent nothing, so it leaves the balance untouched.
  select new.total - coalesce(sum(r.amount), 0)::integer
    into v_owed
    from public.refunds r
   where r.order_id = new.id
     and r.status not in ('failed', 'declined');

  -- Already made whole. Not an error and not a warning: an order refunded in
  -- full and then cancelled is an ordinary support sequence, and the only
  -- correct amount to send is nothing.
  if coalesce(v_owed, new.total) <= 0 then
    return new;
  end if;

  v_reason := coalesce(
    nullif(trim(coalesce(new.status_reason, '')), ''),
    case new.status
      when 'rejected' then 'The restaurant couldn''t take this order'
      else 'This order was cancelled'
    end
  );

  -- Approved in the same statement that requests it. The audit's point is that
  -- an expiry nobody watched must not create a queue nobody works: a refund
  -- that needs a human is a refund that waits for one.
  insert into public.refunds (
    order_id, payment_id, amount, reason, status, funded_by,
    requested_by, approved_by, approved_at, expected_by
  ) values (
    new.id, new.payment_id, v_owed, v_reason, 'approved',
    case when new.status = 'rejected' then 'restaurant' else 'platform' end,
    'system', 'system', now(), (current_date + v_days)
  )
  returning id into v_id;

  -- The customer is already being told the order ended, by `orders_notify_
  -- customer` (0047). This is the second sentence, and it is the one that stops
  -- the phone call: the amount, and the date.
  begin
    insert into public.notifications
      (audience, user_id, kind, title, body, order_id)
    values (
      'customer', new.user_id, 'refund',
      'Refund initiated',
      '₹' || v_owed || ' for order ' || new.id ||
        ' is on its way back to you, in your account by ' ||
        to_char(current_date + v_days, 'DD Mon') || '.',
      new.id
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

-- ===========================================================================
-- 2. A refund that failed left the restaurant paying for it anyway.
-- ===========================================================================
-- `refunds_charge_to_open_statement` (0077) charges a restaurant-funded refund
-- to the vendor's open statement the moment it is approved — deliberately, so
-- a refund cannot slip a whole week waiting for the gateway. It then never
-- looks again. When Razorpay refuses the refund and `pay_approved_refunds`
-- moves it to `failed`, the trigger fires on that status change, sees
-- `settlement_id is not null`, and returns early.
--
-- Proven against the live schema:
--
--     settlement 20 before          refunds 250   net_payable  −58
--     insert a ₹100 vendor refund   refunds 350   net_payable −158
--     gateway refuses it → failed   refunds 350   net_payable −158   ← unchanged
--
-- The customer never got their ₹100 and the restaurant is still short it. The
-- platform keeps the difference, silently, with the arithmetic on both sides
-- looking internally consistent. `declined` does the same thing by the same
-- route (`admin_decline_refund` accepts a `failed` refund).
--
-- So the trigger now reverses as well as charges. Two cases, because they are
-- genuinely different:
--
--   * the statement is still `pending` — un-charge it in place and release the
--     `settlement_id`, which is also what lets a re-approval charge it again;
--   * the statement has been `paid` — the vendor was underpaid and money has
--     already left the bank, so nothing here can put it right. It raises an
--     admin alert asking for a credit adjustment on the next statement, and
--     leaves `settlement_id` alone because that is the statement it really was
--     charged to.
-- ---------------------------------------------------------------------------

create or replace function public.refunds_charge_to_open_statement()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_settlement bigint;
  v_status     text;
  v_rest       text;
begin
  -- ---------------------------------------------------------------------
  -- Reverse. New in 0141, and first, because a refund that has stopped being
  -- payable must give the money back before anything else is considered.
  -- ---------------------------------------------------------------------
  if tg_op = 'UPDATE'
     and old.settlement_id is not null
     and new.status in ('requested', 'failed', 'declined')
     and old.status in ('approved', 'processing', 'paid')
  then
    select s.status, s.restaurant_id into v_status, v_rest
      from public.settlements s
     where s.id = old.settlement_id
     for update;

    if v_status = 'pending' then
      update public.settlements
         set refunds     = refunds - old.amount,
             net_payable = net_payable + old.amount
       where id = old.settlement_id;

      -- Released, so a later re-approval charges it again rather than being
      -- read as already-charged by the early return below.
      new.settlement_id := null;
    else
      -- Paid out already. Say so where somebody works a queue, once — the
      -- partial index on (kind, subject) keeps a retry from stacking alerts.
      begin
        insert into public.admin_alerts (kind, subject, title, body, order_id)
        values (
          'refund_reversal_owed',
          'refund:' || new.id,
          'A failed refund is still charged to a paid statement',
          'Refund #' || new.id || ' (₹' || old.amount || ', order ' ||
            new.order_id || ') was charged to settlement #' || old.settlement_id ||
            ', which has since been paid. The refund is now ' || new.status ||
            ', so the restaurant is short ₹' || old.amount ||
            '. Put a credit adjustment of +₹' || old.amount ||
            ' on their next statement.',
          new.order_id
        )
        on conflict do nothing;
      exception when others then
        null;
      end;
    end if;

    return new;
  end if;

  -- ---------------------------------------------------------------------
  -- Charge. 0077, unchanged.
  -- ---------------------------------------------------------------------
  if new.funded_by <> 'restaurant'
     or new.settlement_id is not null
     or new.status not in ('approved', 'processing', 'paid') then
    return new;
  end if;

  -- The statement this order's week was rolled into, and only while it is still
  -- open. A paid one is history; the batch will charge this to the next.
  select s.id into v_settlement
    from public.orders o
    join public.settlements s on s.id = o.settlement_id
   where o.id = new.order_id
     and s.status = 'pending'
     for update of s;

  if v_settlement is null then
    return new;
  end if;

  new.settlement_id := v_settlement;

  update public.settlements
     set refunds     = refunds + new.amount,
         net_payable = net_payable - new.amount
   where id = v_settlement;

  return new;
end;
$$;

-- ===========================================================================
-- 3. Two refunds at once could jointly exceed the order.
-- ===========================================================================
-- `refund_within_the_order` reads the order's total and the sum of its existing
-- refunds without holding a lock on anything. Two admins issuing goodwill
-- refunds on the same order in the same second both read the same "already
-- refunded" figure, both pass, and together they take the order past its total.
-- Narrow, but it is the one check standing between a support screen and paying
-- out more than was ever collected, so it should not depend on nobody clicking
-- twice.
--
-- One `for update` on the order row serialises them. The order is the natural
-- thing to lock: it is what the ceiling is measured against, and every writer of
-- `refunds` names one.
-- ---------------------------------------------------------------------------

create or replace function public.refund_within_the_order()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_total  integer;
  v_others integer;
begin
  -- `for update`, new in 0141. Held to the end of the transaction, so the
  -- second writer reads the first one's row rather than racing it.
  select o.total into v_total
    from public.orders o
   where o.id = new.order_id
   for update;

  if v_total is null then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  select coalesce(sum(r.amount), 0) into v_others
    from public.refunds r
   where r.order_id = new.order_id
     and r.status not in ('failed', 'declined')
     and r.id is distinct from new.id;

  if v_others + new.amount > v_total then
    raise exception
      'That would refund ₹% on an order of ₹% — ₹% of it is already refunded.',
      v_others + new.amount, v_total, v_others
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

-- ===========================================================================
-- 4. Cancelling a paid gift order kept the money and said nothing.
-- ===========================================================================
-- A gift order is prepaid — `gift_orders_payment_method_check` allows nothing
-- but `upi` and `place_gift_order` refuses an empty `payment_id`. An admin can
-- move one from `placed` or `accepted` to `cancelled`, and until now that was
-- the end of it: no refund row (there cannot be one — `refunds.order_id` is
-- `not null` against `orders`, and 0116 removed the gift ledger on purpose), no
-- notification, no record anywhere that money is owed. The customer's payment
-- simply stayed with the platform.
--
-- "Gifts are final" (0116) is a rule about what the *customer* may call off. It
-- was never a licence for the platform to cancel and keep the money.
--
-- The ledger stays torn out. What this adds is the smallest thing that makes
-- the obligation impossible to lose: an admin alert naming the amount and the
-- order, and the sentence to the customer that a refund is coming. A person
-- sends it from the Razorpay dashboard — which is what already happens for
-- every gift issue today.
-- ---------------------------------------------------------------------------

create or replace function public.admin_set_gift_order_status(
  p_order_id     text,
  p_status       text,
  p_courier_name text default null,
  p_tracking_ref text default null,
  p_reason       text default null
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_current text;
  v_allowed text[];
  v_courier text;
  v_reason  text;
  v_total   integer;
  v_user    text;
  v_pay     text;
begin
  perform public.assert_admin();

  select status, total, user_id, payment_id
    into v_current, v_total, v_user, v_pay
    from public.gift_orders where id = p_order_id for update;
  if not found then
    raise exception 'No such gift order.' using errcode = 'P0001';
  end if;

  v_allowed := case v_current
    when 'placed'     then array['accepted', 'cancelled']
    when 'accepted'   then array['dispatched', 'cancelled']
    when 'dispatched' then array['delivered']
    else array[]::text[]
  end;

  if not (p_status = any (v_allowed)) then
    raise exception 'A gift order that is % cannot become %.', v_current, p_status
      using errcode = 'P0001';
  end if;

  v_courier := nullif(trim(coalesce(p_courier_name, '')), '');
  if p_status = 'dispatched' and v_courier is null then
    raise exception 'Name the courier before marking this dispatched.'
      using errcode = 'P0001';
  end if;

  -- New in 0141. A cancellation is the platform withdrawing from an order the
  -- customer has already paid for, and the customer is shown this sentence.
  -- Required for the same reason `admin_issue_refund` requires one.
  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  if p_status = 'cancelled' and v_reason is null then
    raise exception 'Say why this gift order is being cancelled — the customer is shown this sentence and is owed their money back.'
      using errcode = 'P0001';
  end if;

  update public.gift_orders
     set status = p_status,
         status_reason = case
           when p_status = 'cancelled' then v_reason
           else status_reason
         end,
         courier_name = case
           when p_status = 'dispatched' then v_courier else courier_name
         end,
         tracking_ref = case
           when p_status = 'dispatched'
             then nullif(trim(coalesce(p_tracking_ref, '')), '')
           else tracking_ref
         end,
         accepted_at   = case when p_status = 'accepted'   then now() else accepted_at   end,
         dispatched_at = case when p_status = 'dispatched' then now() else dispatched_at end,
         delivered_at  = case when p_status = 'delivered'  then now() else delivered_at  end
   where id = p_order_id;

  -- The obligation, written down twice: once where somebody works a queue, once
  -- where the customer can read it. Both swallowed on failure — an inbox row is
  -- not worth failing a status change over — but the alert is the one that
  -- matters, and its unique index means a re-run cannot stack duplicates.
  if p_status = 'cancelled' and coalesce(v_total, 0) > 0 then
    begin
      insert into public.admin_alerts (kind, subject, title, body)
      values (
        'gift_refund_owed',
        'gift:' || p_order_id,
        'A paid gift order was cancelled',
        'Gift order ' || p_order_id || ' was cancelled for ₹' || v_total ||
          ' — "' || v_reason || '". It was paid by ' || coalesce(v_pay, '(unknown)') ||
          '. Gifts have no refund ledger (0116), so refund this from the Razorpay ' ||
          'dashboard and resolve this alert with the refund reference.'
      )
      on conflict do nothing;
    exception when others then
      null;
    end;

    begin
      insert into public.notifications
        (audience, user_id, kind, title, body)
      values (
        'customer', v_user, 'refund',
        'Gift order cancelled',
        'We couldn''t complete gift order ' || p_order_id || ' — ' || v_reason ||
          '. ₹' || v_total || ' is being returned to your original payment method.'
      );
    exception when others then
      null;
    end;
  end if;

  return p_status;
end;
$$;

-- ===========================================================================
-- 5. A payment with no order was nobody's problem.
-- ===========================================================================
-- Checkout is pay-then-order: `razorpay-verify` moves a `payment_intents` row
-- to `verified`, and the trigger on `orders` marks it `consumed` when the order
-- lands. Between those two the money is captured and the order does not exist,
-- and everything that can go wrong there — the app killed, the kitchen closing
-- in the seconds the sheet was open, a price edited under the cart — leaves a
-- `verified` intent with no `order_id` and no `gift_order_id`.
--
-- Nothing looked for those. `refunds.order_id` is `not null` against `orders`,
-- so a payment that never became an order has nowhere in the schema to be
-- written down; the customer is shown "don't pay again, contact support" and
-- support has no queue to find them in. That is P3 in `BUGFIX_QUEUE.md` and the
-- `_paidId` field in `checkout_providers.dart` names it as the case it cannot
-- cover.
--
-- This does not invert checkout — writing the order first as `pending_payment`
-- is the real answer and is a bigger change than an audit should make. It makes
-- the money visible: every verified intent still unspent after half an hour
-- becomes one open alert, with the amount and the Razorpay id a person needs to
-- refund it by hand.
--
-- Half an hour rather than five minutes because a customer who backgrounds the
-- app mid-checkout and comes back is a normal thing that resolves itself, and an
-- alert raised for that is an alert somebody learns to ignore.
-- ---------------------------------------------------------------------------

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
       -- Not already on somebody's desk. The partial unique index below would
       -- refuse the insert anyway; asking first keeps the loop honest about
       -- what it counted.
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

revoke all on function public.flag_orphaned_payments() from public;
revoke all on function public.flag_orphaned_payments() from anon, authenticated;

-- Unscheduled first so a re-run of this file replaces the job rather than
-- raising on the duplicate name.
select cron.unschedule('flag-orphaned-payments')
 where exists (select 1 from cron.job where jobname = 'flag-orphaned-payments');

select cron.schedule(
  'flag-orphaned-payments',
  '*/15 * * * *',
  $$ select public.flag_orphaned_payments(); $$
);

-- ===========================================================================
-- 6. The console's commission tile disagreed with the money it describes.
-- ===========================================================================
-- `admin_platform_stats` says, in its own comment, that its commission figure is
-- "the same arithmetic `run_settlement_batch` uses". It was not: the batch
-- charges commission on `subtotal - vendor_funded_discount`, because the
-- platform does not take a cut of a discount the kitchen paid for itself, and
-- the tile charged it on the full `subtotal`. So the dashboard has been
-- reporting more commission than the platform will ever invoice, by exactly the
-- vendor-funded discount, and the gap grows with every restaurant offer.
--
-- The per-order-versus-per-week rounding still differs by a rupee or two over a
-- month, which is a dashboard and not a ledger. The base is the part that was
-- wrong.
-- ---------------------------------------------------------------------------

create or replace function public.admin_platform_stats(p_days integer default 30)
returns table(
  days integer, orders_placed integer, orders_delivered integer,
  orders_cancelled integer, orders_rejected integer, gmv integer,
  commission integer, discount_given integer, avg_order integer,
  live_orders integer, restaurants_live integer, riders_active integer,
  riders_carrying integer, customers_ordering integer
)
language plpgsql
stable security definer
set search_path to 'public'
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from timestamptz;
begin
  perform public.assert_admin();

  v_from := now() - make_interval(days => v_days);

  return query
  with w as (
    select o.*, r.commission_bps
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
     where o.created_at >= v_from
  )
  select
    v_days,
    (select count(*)::integer from w),
    (select count(*)::integer from w where w.status = 'delivered'),
    (select count(*)::integer from w where w.status = 'cancelled'),
    (select count(*)::integer from w where w.status = 'rejected'),
    -- GMV is delivered orders only. An order that was placed and cancelled is
    -- not revenue, and counting it would make a bad week look like a good one.
    (select coalesce(sum(w.total), 0)::integer from w where w.status = 'delivered'),
    -- The same base `run_settlement_batch` charges on: the subtotal less
    -- whatever of the discount the restaurant funded itself (0074). Corrected in
    -- 0141 — this read the full subtotal and so overstated the platform's cut by
    -- the whole of every vendor-funded offer.
    (select coalesce(sum(round(
              (w.subtotal - case when w.discount_funded_by = 'restaurant'
                                 then w.discount else 0 end)
              * w.commission_bps / 10000.0)), 0)::integer
       from w where w.status = 'delivered'),
    (select coalesce(sum(w.discount), 0)::integer from w where w.status = 'delivered'),
    (select coalesce(round(avg(w.total)), 0)::integer from w where w.status = 'delivered'),
    (select count(*)::integer from public.orders o
      where o.status not in ('delivered', 'cancelled', 'rejected')),
    (select count(*)::integer from public.restaurants r
      where r.is_active and r.accepting_orders),
    (select count(*)::integer from public.delivery_partners p where p.is_active),
    -- Joined to the order for the reason section G gives: a `deliveries` row
    -- that never closed under an order that did is not a rider on the road, and
    -- counting it would put a permanent 1 on this tile.
    (select count(distinct d.partner_email)::integer
       from public.deliveries d
       join public.orders o2 on o2.id = d.order_id
      where d.state not in ('delivered', 'cancelled')
        and o2.status not in ('delivered', 'cancelled', 'rejected')),
    (select count(distinct w.user_id)::integer from w);
end;
$$;

-- ===========================================================================
-- 7. Three trigger functions were still executable by the world.
-- ===========================================================================
-- 0087/0089/0091 revoked the default `PUBLIC` grant from every function that
-- takes arguments. These three take none and were missed. Calling a trigger
-- function directly raises "can only be called as a trigger", so nothing was
-- reachable through them — but "unreachable today" is how the next one gets
-- missed, and the rule is that nothing in this schema is executable by default.
-- ---------------------------------------------------------------------------

revoke all on function public.stamp_order_ready_at()        from public, anon, authenticated;
revoke all on function public.whatsapp_order_confirmed()    from public, anon, authenticated;
revoke all on function public.admin_actions_are_append_only() from public, anon, authenticated;

-- ===========================================================================
-- 8. The payment gate, armed.
-- ===========================================================================
-- `orders_require_verified_payment` (0085) and its gift counterpart (0113) have
-- shipped disarmed since the day they were written, because there was no
-- gateway behind them: `payment_settings.require_verified_payment = false`
-- makes both triggers return immediately, and `place_order` then accepts any
-- non-empty string as `p_payment_id`. That was correct while every payment on
-- the platform was a `pay_mock_…` from the fallback gateway.
--
-- **It stopped being correct on 25 August**, when the Razorpay keys were set.
-- `razorpay-order` now answers `configured: true`, so `RazorpayPaymentGateway`
-- never reaches its fallback and the gateway is genuinely in the path — orders
-- ZPQ-1185 through ZPQ-1189 went through it and had their intents verified.
--
-- The keys are `rzp_test_…`, so **no real money has moved yet** and this was not
-- costing anything today. It is armed now rather than on the day live keys go in
-- for the reason P4 in `BUGFIX_QUEUE.md` gives: arming is a separate manual
-- statement that nothing fails loudly about, and the four days between the test
-- keys landing and this file are the demonstration that it gets forgotten. Doing
-- it now means the switch to live keys is one step and not two.
--
-- With the gate down, anyone signed in can call `place_order` over PostgREST
-- with `p_payment_id: 'anything'` and get the food for nothing. The app is not
-- the attack surface; the RPC is, and it is `authenticated`-executable by
-- design.
--
-- Verified in a rolled-back transaction against this schema before arming:
--
--   a fabricated id                → payment gate: no intent for payment_id …
--   a real intent, order priced up → payment gate: intent 39 paid 9930 for an
--                                    order of 10975
--
-- and a matching intent passes and is marked `consumed`, which is what stops one
-- payment buying two dinners.
--
-- The 25 historical `pay_mock_…` orders are untouched: this gate is `before
-- insert` and says nothing about rows that already exist.
--
-- To disarm, if checkout misbehaves:
--     update public.payment_settings set require_verified_payment = false;
-- ---------------------------------------------------------------------------

update public.payment_settings set require_verified_payment = true, updated_at = now();
