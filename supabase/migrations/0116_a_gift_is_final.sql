-- ---------------------------------------------------------------------------
-- 0116 — a gift is final
-- ---------------------------------------------------------------------------
-- A product decision, taken 2026-08-11: **a gift order cannot be cancelled by
-- the customer, and there is no refund path for one.** Once it is bought, it is
-- bought.
--
-- This reverses 0115 in full and closes the customer's cancel door that 0096
-- opened. It is deliberately a migration rather than an edit to 0115 or 0096:
-- both have been applied to the live database, and a migration that rewrites an
-- applied one is a file that no longer describes what happened.
--
-- ## What stays, and why
--
-- **The admin's cancel stays.** `admin_set_gift_order_status` can still move a
-- `placed` or `accepted` gift order to `cancelled`. The rule is about the
-- customer changing their mind, not about Zopiqnow being unable to fulfil — an
-- order for a thing that turns out not to exist has to be able to end, or it
-- sits open for ever. Where money has to go back in that case it goes back in
-- Razorpay's dashboard, by hand, which is exactly where it went before 0115 and
-- is now the whole of the arrangement rather than half of it.
--
-- **`support_tickets` stays** (0114), and this migration is the reason it
-- matters more than it did yesterday: raising an issue is now the *only* route a
-- customer has back into this system on a gift. A ticket is a statement rather
-- than a transaction (0095's rule), so nothing here contradicts it.
--
-- ## What goes
--
-- Everything 0115 added, down to the column. It was applied hours ago and never
-- wrote a row — `select count(*) from refunds where gift_order_id is not null`
-- reads 0 on the live database — so there is no data to preserve and no reason
-- to leave a dead nullable column behind for a future reader to wonder about.
-- `refunds.order_id` goes back to `not null`, which is the honest statement
-- again: every row in that ledger is against a food order.
--
-- Nothing is done to existing `gift_orders`. There is exactly one row in the
-- table and it is `delivered`; no gift order has ever been cancelled. A
-- migration that rewrote order history to match a rule made today would be
-- rewriting what happened, which is 0063's argument about receipts.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The customer's cancel door closes.
-- ---------------------------------------------------------------------------
-- The function is kept and made to refuse, rather than dropped. Dropping it
-- would refuse too — but as a missing-function error, which the gift datasource
-- maps to its generic apology. An installed build still has the Cancel button
-- and will still press it, and what that customer should read is a sentence
-- explaining the rule, not "Something went wrong." The button goes from the app
-- in the same commit; the sentence is for every phone that has not updated yet.
--
-- Signature unchanged, so this is a genuine replacement and creates no overload
-- (0051).
create or replace function public.cancel_my_gift_order(
  p_order_id text,
  p_reason   text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
begin
  -- Their own order or nothing, even to be refused: answering "not yours"
  -- differently from "no such order" tells a stranger which ids are real, which
  -- is 0095's rule and holds whatever the answer turns out to be.
  select exists (
    select 1 from public.gift_orders
     where id = p_order_id and user_id = auth.uid()::text
  ) into v_exists;

  if not v_exists then
    raise exception 'We couldn''t find that order on your account.'
      using errcode = 'P0001';
  end if;

  raise exception 'Gift orders can''t be cancelled once they''re placed. If something is wrong with it, report a problem and we''ll sort it out.'
    using errcode = 'P0001';
end;
$$;

revoke all on function public.cancel_my_gift_order(text, text) from public, anon;
grant execute on function public.cancel_my_gift_order(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The automatic gift refund goes.
-- ---------------------------------------------------------------------------
drop trigger if exists gift_orders_refund_on_termination on public.gift_orders;
drop function if exists public.gift_orders_refund_on_termination();

-- ---------------------------------------------------------------------------
-- 3. The gift-shaped refund surfaces go.
-- ---------------------------------------------------------------------------
drop function if exists public.my_gift_order_refund(text);
drop function if exists public.admin_issue_gift_refund(text, integer, text);

-- ---------------------------------------------------------------------------
-- 4. The three functions 0115 widened go back to 0077's shape.
-- ---------------------------------------------------------------------------
-- Restored to what they were, not left tolerant of a column that is about to
-- stop existing. The grants are restated in the tighter `from public, anon`
-- form the project settled on in 0093 rather than 0077's original — restoring a
-- weaker grant to match an old file would be a regression dressed as a revert.

-- 4a. The over-refund check. Back to reading `orders` alone.
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
  select o.total into v_total from public.orders o where o.id = new.order_id;
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

revoke all on function public.refund_within_the_order()
  from public, anon, authenticated;

-- 4b. The queue. The return type changes back, so `drop` and `create` again —
-- `create or replace` cannot change OUT columns.
drop function if exists public.admin_list_refunds(text);

create function public.admin_list_refunds(p_status text default null)
returns table (
  id              bigint,
  order_id        text,
  restaurant_id   text,
  restaurant_name text,
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
    select r.id, r.order_id, o.restaurant_id, o.restaurant_name, o.user_phone,
           o.total, o.payment_method,
           r.amount, r.status, r.reason, r.funded_by, r.requested_by,
           r.approved_by, r.gateway_refund_id, r.failure_reason, r.expected_by,
           r.settlement_id, r.created_at, r.paid_at
      from public.refunds r
      join public.orders o on o.id = r.order_id
     where p_status is null or r.status = p_status
     -- Oldest first. This is a work queue and the thing that has been waiting
     -- longest is the thing somebody is chasing.
     order by r.created_at;
end;
$$;

revoke all on function public.admin_list_refunds(text) from public, anon;
grant execute on function public.admin_list_refunds(text) to authenticated;

-- 4c. Approval. The gift branch goes with the thing it was guarding.
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
begin
  perform public.assert_admin();

  select r.status, r.settlement_id into v_status, v_settled
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

-- 4d. Marking one paid. Back to looking the customer up in `orders` alone,
-- which is correct again the moment a refund can only be against one.
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
  v_amount integer;
  v_user   text;
begin
  perform public.assert_admin();

  v_ref := nullif(trim(coalesce(p_reference, '')), '');
  if v_ref is null then
    raise exception 'A paid refund needs the reference it can be traced by.'
      using errcode = 'P0001';
  end if;

  select r.status, r.order_id, r.amount into v_status, v_order, v_amount
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

  select o.user_id into v_user from public.orders o where o.id = v_order;

  begin
    insert into public.notifications
      (audience, user_id, kind, title, body, order_id)
    values (
      'customer', v_user, 'refund',
      'Refund sent',
      '₹' || v_amount || ' for order ' || v_order ||
        ' has been sent back to your original payment method.',
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

-- ---------------------------------------------------------------------------
-- 5. The ledger forgets gifts entirely.
-- ---------------------------------------------------------------------------
-- Last, and only after every function above has stopped naming the column: a
-- function body is not dependency-tracked by Postgres, so dropping the column
-- first would have succeeded and left `admin_list_refunds` erroring at runtime
-- instead of at migration time.
drop index if exists public.refund_one_automatic_per_gift_order;
drop index if exists public.refunds_by_gift_order_idx;

alter table public.refunds
  drop constraint if exists refunds_one_order_check;
alter table public.refunds
  drop constraint if exists refund_on_a_gift_is_the_platforms;

alter table public.refunds
  drop column if exists gift_order_id;

-- Back to what it always said. Safe unconditionally: the column it would have
-- to contradict is gone, and no row was ever written without an `order_id`.
alter table public.refunds
  alter column order_id set not null;
