-- ---------------------------------------------------------------------------
-- 0115 — a gift is refunded too
-- ---------------------------------------------------------------------------
-- The last of the four gaps the gift path inherited by being built beside the
-- food path instead of through it, and the only one that is about money leaving
-- the platform without a record of it.
--
-- `refunds.order_id` is `not null references orders (id)`. `gift_orders` ids are
-- `ZPG-…` and are not in that table, so **a gift cannot be refunded through this
-- ledger at all** — not partially, not automatically, not by an admin. Today one
-- is refunded by hand in Razorpay's dashboard and written down nowhere: no
-- amount, no reason, no promised date, no notification, and nothing in
-- `admin_actions` (0092) saying who sent it.
--
-- Two places already promise the money back and cannot keep the promise:
--
--   * `gift_order_detail_page.dart` — "We'll stop preparing it and refund what
--     you paid", the confirm dialog behind the Cancel button.
--   * 0114's own header, which named this gap and deferred it on the grounds
--     that "two ledgers changing shape in one migration" is one too many.
--
-- 0113 was the first half of the same sentence: a gift *takes* money through
-- `payment_intents` now. This is the half that gives it back.
--
-- ## Shape
--
-- The one 0113 and 0114 both chose, for the third time and the same reasons:
-- `order_id` goes nullable, a `gift_order_id` joins it, and
-- `num_nonnulls(...) = 1` says exactly one — never both, and never neither.
-- **One ledger, not two.** Over-refund protection, the approve/decline/paid
-- state machine, and the console's work queue are all one implementation each;
-- a second table would be a second copy of every one of them, and the copy that
-- drifts is the one that pays twice.
--
-- ## What a gift refund is never
--
-- **Never restaurant-funded, and never on a settlement.** Gifts are fulfilled by
-- Zopiqnow itself (0096) — a gift shop is a catalogue, not a counterparty with a
-- weekly statement, and `settlements.restaurant_id` references `restaurants`,
-- which no gift order has. `run_settlement_batch` is already safe twice over (it
-- inner joins `orders` *and* filters `funded_by = 'restaurant'`), but "the batch
-- happens not to reach it" is a fact about one function and this is a property of
-- the row, so it is a check constraint. That is 0077's own argument for
-- `refund_on_a_statement_is_the_vendors`, applied one step further out.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The ledger learns about the other kind of order.
-- ---------------------------------------------------------------------------
alter table public.refunds
  alter column order_id drop not null;

alter table public.refunds
  add column if not exists gift_order_id text
    references public.gift_orders (id) on delete cascade;

comment on column public.refunds.gift_order_id is
  'Set when the money is owed on a gift order, as order_id is for a food order. Exactly one of the two is non-null.';

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.refunds'::regclass
       and conname  = 'refunds_one_order_check'
  ) then
    alter table public.refunds
      add constraint refunds_one_order_check
      check (num_nonnulls(order_id, gift_order_id) = 1);
  end if;
end
$$;

-- A gift refund is the platform's, always, and can never be charged to a vendor
-- statement. See the header: this is a property of the row, not a consequence of
-- how the batch happens to be written today.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.refunds'::regclass
       and conname  = 'refund_on_a_gift_is_the_platforms'
  ) then
    alter table public.refunds
      add constraint refund_on_a_gift_is_the_platforms
      check (
        gift_order_id is null
        or (funded_by = 'platform' and settlement_id is null)
      );
  end if;
end
$$;

-- The sibling of `refund_one_automatic_per_order`. The food index is on a column
-- that is now nullable, and nulls do not conflict in a unique index — so without
-- this, a gift order could collect an automatic refund per cancellation while a
-- food order still could not.
create unique index if not exists refund_one_automatic_per_gift_order
  on public.refunds (gift_order_id)
  where requested_by = 'system';

-- What `my_gift_order_refund` reads, matching `refunds_by_order_idx`.
create index if not exists refunds_by_gift_order_idx
  on public.refunds (gift_order_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2. An order still cannot be refunded for more than it cost.
-- ---------------------------------------------------------------------------
-- This trigger read the total out of `orders` and raised "We couldn't find that
-- order." when it found nothing — so left alone it would have refused every gift
-- refund the rest of this migration creates, including the automatic one, from
-- inside a trigger with no way to tell the difference between a gift and a
-- deleted order.
--
-- The argument list is unchanged (a trigger function has none), so this is a
-- genuine replacement and creates no overload — 0051's lesson.
create or replace function public.refund_within_the_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total  integer;
  v_others integer;
begin
  if new.order_id is not null then
    select o.total into v_total from public.orders o where o.id = new.order_id;
  else
    select g.total into v_total
      from public.gift_orders g where g.id = new.gift_order_id;
  end if;

  if v_total is null then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  -- Siblings on *this* order, whichever kind it is. `is not distinct from`
  -- rather than `=`: for a gift row `new.order_id` is null, and `r.order_id =
  -- null` is null rather than true, which would have made every gift refund
  -- count zero siblings and the over-refund check a no-op on half the ledger.
  select coalesce(sum(r.amount), 0) into v_others
    from public.refunds r
   where r.order_id      is not distinct from new.order_id
     and r.gift_order_id is not distinct from new.gift_order_id
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

-- ---------------------------------------------------------------------------
-- 3. The automatic path.
-- ---------------------------------------------------------------------------
-- 0077's trigger, in the shape a gift order takes.
--
-- Only `cancelled`: a gift order has no `rejected` — there is no kitchen to turn
-- it down — and the ladder (0096) allows a cancel only from `placed` or
-- `accepted`, by the customer or by an admin. A parcel that was dispatched and
-- never arrived cannot be cancelled at all, which is why `admin_issue_gift_refund`
-- below exists and is not a nicety.
--
-- `funded_by` is `'platform'` unconditionally, and there is no `payment_method`
-- branch, because `gift_orders.payment_method` is pinned to `'upi'` by a check
-- constraint (0096) — 0113's reasoning, and the safe direction: if that
-- constraint is ever widened, the refund applies to the new method until somebody
-- decides otherwise rather than silently skipping it.
create or replace function public.gift_orders_refund_on_termination()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- The same five working days the food path promises. One number, so a customer
  -- who has had both kinds of order refunded is told the same thing twice.
  v_days constant integer := 5;
  v_reason text;
begin
  -- Nothing was captured, so nothing goes back. `payment_id` is null on every
  -- gift order placed while 0113's gate is off, and inventing a refund for money
  -- that never moved is worse than not recording one.
  if new.payment_id is null then
    return new;
  end if;

  if exists (
    select 1 from public.refunds r
     where r.gift_order_id = new.id and r.requested_by = 'system'
  ) then
    return new;
  end if;

  v_reason := coalesce(
    nullif(trim(coalesce(new.status_reason, '')), ''),
    'This gift order was cancelled'
  );

  insert into public.refunds (
    gift_order_id, payment_id, amount, reason, status, funded_by,
    requested_by, approved_by, approved_at, expected_by
  ) values (
    new.id, new.payment_id, new.total, v_reason, 'approved', 'platform',
    'system', 'system', now(), (current_date + v_days)
  );

  -- **No `order_id` on the notification**, unlike the food path's. That column is
  -- read as a food order id by everything that touches it: the inbox taps through
  -- to `/orders/:id` and the push handler routes to the same place, so a `ZPG-…`
  -- there would send somebody who tapped "Refund initiated" to a screen telling
  -- them the order they are asking about does not exist.
  --
  -- Standing rule 2 in the parity checklist, one column over: a wire value the
  -- installed build cannot read is not widened until a build that can read it is
  -- on people's phones. Filling this in — so the alert opens `/gift-orders/:id` —
  -- is a later migration's, after the customer app has shipped the prefix branch.
  -- Until then a notification with nothing to tap is the honest version: the
  -- sentence carries the order id, the amount and the date, which is the whole
  -- reason the row exists.
  begin
    insert into public.notifications
      (audience, user_id, kind, title, body)
    values (
      'customer', new.user_id, 'refund',
      'Refund initiated',
      '₹' || new.total || ' for gift order ' || new.id ||
        ' is on its way back to you, in your account by ' ||
        to_char(current_date + v_days, 'DD Mon') || '.'
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists gift_orders_refund_on_termination on public.gift_orders;
create trigger gift_orders_refund_on_termination
  after update of status on public.gift_orders
  for each row
  when (new.status = 'cancelled' and old.status is distinct from new.status)
  execute function public.gift_orders_refund_on_termination();

-- 0093's rule: a trigger body is not an application surface.
revoke all on function public.gift_orders_refund_on_termination()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. What the customer sees.
-- ---------------------------------------------------------------------------
-- `my_order_refund`'s sibling, and deliberately not a widening of it: the two
-- differ in the table they join for ownership and for the total, and a single
-- function taking "an id of one of two kinds" would have to guess which table to
-- look in. 0114's argument, unchanged.
create or replace function public.my_gift_order_refund(p_gift_order_id text)
returns table (
  id          bigint,
  amount      integer,
  status      text,
  reason      text,
  expected_by date,
  paid_at     timestamptz,
  is_partial  boolean,
  created_at  timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.amount, r.status, r.reason, r.expected_by, r.paid_at,
         r.amount < g.total as is_partial,
         r.created_at
    from public.refunds r
    join public.gift_orders g on g.id = r.gift_order_id
   where r.gift_order_id = p_gift_order_id
     and g.user_id = auth.uid()::text
     -- A refund an admin declined was never owed. 0077's rule.
     and r.status <> 'declined'
   order by r.created_at;
$$;

revoke all on function public.my_gift_order_refund(text) from public, anon;
grant execute on function public.my_gift_order_refund(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The queue, which must not be blind to half of it.
-- ---------------------------------------------------------------------------
-- `admin_list_refunds` **inner joins `orders`**. A gift refund has a null
-- `order_id`, so without this every one of them — including the automatic one
-- section 3 raises without a human involved — would sit in the ledger invisible
-- to the people whose job is to send the money. That is worse than not recording
-- it: the customer has been told a refund is on its way.
--
-- Exactly the blindness 0114 found in `admin_support_tickets`, one table over.
--
-- The return type changes, so this is a `drop` and a `create`. `restaurant_id`
-- and `restaurant_name` become `seller_id` and `seller_name` for 0114's reason:
-- filling a column called `restaurant_name` with a gift shop is how a report
-- comes to say a thing that is not true.
drop function if exists public.admin_list_refunds(text);

create function public.admin_list_refunds(p_status text default null)
returns table (
  id              bigint,
  -- 'food' or 'gift'. The console needs it before the rest of the row means
  -- anything: a gift has no restaurant to charge and no settlement to charge it
  -- to, so the "Funded by" control is not offered on one.
  kind            text,
  -- Whichever id this refund is against. One column, because this is one
  -- worklist and the row reads as "the order this is about"; `kind` says which
  -- table it lives in, and the id prefixes (`ZPQ-` / `ZPG-`) agree with it.
  order_id        text,
  seller_id       text,
  seller_name     text,
  user_phone      text,
  order_total     integer,
  payment_method  text,
  amount          integer,
  status          text,
  reason          text,
  funded_by       text,
  requested_by    text,
  approved_by     text,
  gateway_refund_id text,
  failure_reason  text,
  expected_by     date,
  settlement_id   bigint,
  created_at      timestamptz,
  paid_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    -- Left joins, not inner ones. Exactly one side is present per row by the
    -- check constraint, so `coalesce` picks the one that is.
    select r.id,
           case when r.gift_order_id is not null then 'gift' else 'food' end,
           coalesce(r.order_id, r.gift_order_id),
           coalesce(o.restaurant_id, g.shop_id),
           coalesce(o.restaurant_name, g.shop_name),
           coalesce(o.user_phone, g.user_phone),
           coalesce(o.total, g.total),
           coalesce(o.payment_method, g.payment_method),
           r.amount, r.status, r.reason, r.funded_by, r.requested_by,
           r.approved_by, r.gateway_refund_id, r.failure_reason, r.expected_by,
           r.settlement_id, r.created_at, r.paid_at
      from public.refunds r
      left join public.orders      o on o.id = r.order_id
      left join public.gift_orders g on g.id = r.gift_order_id
     where p_status is null or r.status = p_status
     -- Oldest first. This is a work queue and the thing that has been waiting
     -- longest is the thing somebody is chasing.
     order by r.created_at;
end;
$$;

revoke all on function public.admin_list_refunds(text) from public, anon;
grant execute on function public.admin_list_refunds(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Refunding a gift by hand.
-- ---------------------------------------------------------------------------
-- The important one. A gift that was dispatched and never arrived cannot be
-- cancelled (0096) and therefore never reaches section 3 — so the automatic path
-- covers the easy case and this covers the case that actually generates the
-- complaint 0114 built the door for.
--
-- No `p_funded_by`, unlike `admin_issue_refund`. There is nobody else to charge,
-- and an argument whose only legal value is the default is an argument somebody
-- eventually passes the other value to.
create or replace function public.admin_issue_gift_refund(
  p_gift_order_id text,
  p_amount        integer,
  p_reason        text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  record;
  v_reason text;
  v_id     bigint;
begin
  perform public.assert_admin();

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception 'Say why this is being refunded — the customer is shown this sentence.'
      using errcode = 'P0001';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'A refund needs an amount.' using errcode = 'P0001';
  end if;

  select g.id, g.payment_id into v_order
    from public.gift_orders g where g.id = p_gift_order_id;

  if not found then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  -- The amount is checked against everything already owed on this order by
  -- `refunds_within_the_order`, which is where that rule lives for every writer
  -- and both kinds.
  insert into public.refunds (
    gift_order_id, payment_id, amount, reason, status, funded_by,
    requested_by, expected_by
  ) values (
    v_order.id, v_order.payment_id, p_amount, v_reason, 'requested', 'platform',
    lower(auth.jwt() ->> 'email'), (current_date + 5)
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.admin_issue_gift_refund(text, integer, text)
  from public, anon;
grant execute on function public.admin_issue_gift_refund(text, integer, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Approving one.
-- ---------------------------------------------------------------------------
-- Argument list unchanged, so a genuine replacement. One thing added: moving a
-- gift refund onto a restaurant is refused with a sentence rather than left to
-- the check constraint added in section 1, which would have surfaced in the
-- console as a raw `23514` nobody can act on.
create or replace function public.admin_approve_refund(
  p_id        bigint,
  p_funded_by text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status  text;
  v_settled bigint;
  v_gift    text;
begin
  perform public.assert_admin();

  select r.status, r.settlement_id, r.gift_order_id
    into v_status, v_settled, v_gift
    from public.refunds r where r.id = p_id for update;

  if not found then
    raise exception 'We couldn''t find that refund.' using errcode = 'P0001';
  end if;

  if v_status not in ('requested', 'failed') then
    raise exception '%', case v_status
      when 'approved'  then 'That refund is already approved.'
      when 'processing' then 'That refund is already with the gateway.'
      when 'paid'      then 'That refund has already been paid.'
      else 'That refund was declined. Raise a new one.'
    end using errcode = 'P0001';
  end if;

  if p_funded_by is not null then
    if p_funded_by not in ('platform', 'restaurant') then
      raise exception 'A refund is funded by the platform or by the restaurant.'
        using errcode = 'P0001';
    end if;
    if v_gift is not null and p_funded_by = 'restaurant' then
      raise exception 'A gift order has no restaurant behind it — Zopiqnow funds this one.'
        using errcode = 'P0001';
    end if;
    -- Once a statement has absorbed it, moving the funder would silently change
    -- a number a vendor has already been shown and possibly already been paid.
    if v_settled is not null then
      raise exception 'That refund is already on a settlement. Adjust the settlement instead.'
        using errcode = 'P0001';
    end if;
  end if;

  update public.refunds
     set status         = 'approved',
         funded_by      = coalesce(p_funded_by, funded_by),
         approved_by    = lower(auth.jwt() ->> 'email'),
         approved_at    = now(),
         failure_reason = null
   where id = p_id;
end;
$$;

revoke all on function public.admin_approve_refund(bigint, text)
  from public, anon;
grant execute on function public.admin_approve_refund(bigint, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Recording that it went.
-- ---------------------------------------------------------------------------
-- Argument list unchanged; a genuine replacement. The bug being fixed is 0114's
-- exactly: this function read `r.order_id`, looked the customer up in `orders`,
-- and on a gift refund would have found nothing. `notifications.user_id` is
-- nullable, so nothing would have raised and the `exception when others` below
-- would have had nothing to swallow — the row would simply have been written
-- addressed to **nobody**, and the inbox reads by `user_id`. A refund sent and
-- the customer never told, with no error anywhere to say so, on the one message
-- in this whole flow they are actually waiting for.
create or replace function public.admin_mark_refund_paid(p_id bigint, p_reference text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_ref    text;
  v_order  text;
  v_gift   text;
  v_amount integer;
  v_user   text;
begin
  perform public.assert_admin();

  v_ref := nullif(trim(coalesce(p_reference, '')), '');
  if v_ref is null then
    raise exception 'A paid refund needs the reference it can be traced by.'
      using errcode = 'P0001';
  end if;

  select r.status, r.order_id, r.gift_order_id, r.amount
    into v_status, v_order, v_gift, v_amount
    from public.refunds r where r.id = p_id for update;

  if not found then
    raise exception 'We couldn''t find that refund.' using errcode = 'P0001';
  end if;

  if v_status not in ('approved', 'processing') then
    raise exception '%', case v_status
      when 'requested' then 'Approve that refund before paying it.'
      when 'paid'      then 'That refund has already been paid.'
      else 'That refund was declined.'
    end using errcode = 'P0001';
  end if;

  update public.refunds
     set status = 'paid', gateway_refund_id = v_ref, paid_at = now()
   where id = p_id;

  if v_gift is null then
    select o.user_id into v_user from public.orders o where o.id = v_order;
  else
    select g.user_id into v_user from public.gift_orders g where g.id = v_gift;
  end if;

  begin
    insert into public.notifications
      (audience, user_id, kind, title, body, order_id)
    values (
      'customer', v_user, 'refund',
      'Refund sent',
      '₹' || v_amount || ' for ' ||
        case when v_gift is null then 'order ' || v_order
             else 'gift order ' || v_gift end ||
        ' has been sent back to your original payment method.',
      -- Null on a gift, for section 3's reason: this column routes a tap to
      -- `/orders/:id` and a `ZPG-…` there is a dead end.
      v_order
    );
  exception when others then
    null;
  end;
end;
$$;

revoke all on function public.admin_mark_refund_paid(bigint, text)
  from public, anon;
grant execute on function public.admin_mark_refund_paid(bigint, text)
  to authenticated;
