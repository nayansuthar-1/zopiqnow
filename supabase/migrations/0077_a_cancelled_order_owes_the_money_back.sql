-- ---------------------------------------------------------------------------
-- 0077 — a cancelled order owes the money back. (Audit BIZ-004)
-- ---------------------------------------------------------------------------
-- Three paths end an order without delivering it. A customer may cancel while
-- it is still 'placed' or 'accepted' (`cancel_my_order`, 0051). A vendor may
-- decline it, or cancel it mid-prep (`set_order_status`, 0049). An order nobody
-- accepts inside five minutes is declined by a batch nobody watches
-- (`expire_unaccepted_orders`, 0051). Support has a fourth (`admin_cancel_order`,
-- 0066). All four move the row to a terminal state, release the rider and tell
-- somebody. None of them records that money is owed, because until now there
-- was no table to record it in: searching all 76 migrations for a refund, a
-- credit or a reversal finds the word once, in a comment in 0066 promising this
-- migration.
--
-- Today that is survivable only because online payment is a mock (PAY-001).
-- The instant a real gateway is wired in, every one of those four paths becomes
-- a finance ticket — and the five-minute expiry generates them *automatically,
-- without a human deciding to*. Under the RBI's rules for a failed prepaid
-- transaction an unrefunded auto-cancellation is a compliance exposure on top
-- of a support one.
--
-- THE OBLIGATION IS A ROW, NOT A CONSEQUENCE OF A STATUS. The alternative shape
-- — "an order that is cancelled and prepaid is owed its total" as a view — was
-- rejected for the reason 0076 rejected a `cash_held` column, inverted: a
-- refund has a life of its own after the order stops changing. It gets approved,
-- sent, confirmed, or refused, and each of those is a fact about the refund and
-- not about the order. A view cannot be marked paid.
--
-- WHO WRITES IT. A trigger on `orders`, not four edits to four functions. The
-- rule being encoded is "an order that ends without being delivered owes the
-- money back", which is a statement about the data and not about the four call
-- sites that happen to produce it today — and a fifth path added next year gets
-- the refund for free rather than getting it in a follow-up migration. This is
-- the same argument 0076 made for putting the one-collection-per-order rule in
-- an index rather than in `confirm_delivered`.
--
-- ONLY WHERE MONEY WENT IN. The automatic refund fires for `payment_method =
-- 'upi'` alone. A cancelled cash order collected nothing — the customer never
-- handed anything over, and after 0076 there is a ledger that says so. A
-- delivered cash order that went wrong is a different question and it has a
-- different answer below: an admin may issue a refund against any order,
-- whatever it was paid with.
--
-- WHAT AN ADMIN DOES AND DOES NOT DECIDE. A full refund on an order that never
-- happened needs no approval and does not get to wait for one: it is inserted
-- already approved, by `system`. A *partial* refund is a judgement about food
-- somebody ate, so it cannot exist without an admin's name on it — issued in
-- `requested` and approved as a second, separate act, both recorded.
--
-- WHAT THIS IS NOT. It is not PAY-001. No gateway is called here, because there
-- is no gateway: `processing` and `gateway_refund_id` are the seam the Razorpay
-- edge function fills, and until it exists an admin marks a refund paid by hand
-- against a bank reference, exactly as they already mark a settlement and a
-- rider payout paid (0045, 0066). The ledger is right from today; what changes
-- when PAY-001 lands is who moves the money, not who owes it.
--
-- Nor is it BIZ-007. A refund raised after its week has already been settled
-- lands on the *next* statement, because there is still no hold period to claw
-- back from. That is the finding's whole point and it stays open.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The ledger.
-- ---------------------------------------------------------------------------
create table if not exists public.refunds (
  id                bigserial primary key,
  order_id          text not null references public.orders (id) on delete cascade,

  -- The capture being reversed. Copied off the order rather than joined to it
  -- for the reason `order_items` copies a dish's name: what the gateway is told
  -- to reverse must not change when the order row does.
  payment_id        text,

  -- Whole rupees, like every money column in this schema. Positive always —
  -- there is no such thing as a negative refund, and a signed column here would
  -- invite one.
  amount            integer not null check (amount > 0),

  -- Shown to the customer verbatim. Defaulted from the order's own
  -- `status_reason` on the automatic path, so the sentence the customer already
  -- read on the tracking screen is the sentence on the refund.
  reason            text not null,

  --   requested  — owed, not yet cleared to send. Where a partial waits.
  --   approved   — cleared. Automatic full refunds are born here.
  --   processing — handed to the gateway. PAY-001 owns this state; nothing
  --                writes it today.
  --   paid       — confirmed. From a webhook once there is one; from an admin
  --                and a bank reference until then.
  --   failed     — the gateway refused. Needs a person.
  --   declined   — an admin decided it should not have been raised. The way out
  --                of a mistyped partial, and the reason 'failed' is not made to
  --                mean two things.
  status            text not null default 'requested'
                    check (status in ('requested', 'approved', 'processing',
                                      'paid', 'failed', 'declined')),

  -- Who bears it, in the vocabulary 0074 gave `orders.discount_funded_by`.
  -- Derived on the automatic path and correctable by an admin until a
  -- settlement claims it; see section 6.
  funded_by         text not null check (funded_by in ('platform', 'restaurant')),

  -- 'system' for the automatic path, an admin's email otherwise.
  requested_by      text not null,
  approved_by       text,
  gateway_refund_id text,

  -- Why it failed, or why an admin declined it. Both are sentences somebody has
  -- to read later.
  failure_reason    text,

  -- The date the customer is promised, frozen at insert. Recomputing it on read
  -- means a promise that slides one day further away every day the refund sits
  -- unpaid, which is the single most reliable way to turn one support contact
  -- into four.
  expected_by       date not null,

  -- The vendor statement that absorbed it. Only ever set on a restaurant-funded
  -- refund; see the constraint below and section 6.
  settlement_id     bigint references public.settlements (id),

  created_at        timestamptz not null default now(),
  approved_at       timestamptz,
  paid_at           timestamptz,

  -- A refund that is on its way to a gateway has a person behind it, always.
  constraint refund_approved_has_an_approver check (
    status not in ('approved', 'processing', 'paid')
    or (approved_by is not null and approved_at is not null)
  ),

  -- The same rule 0045 put on a payout and 0076 put on a cash deposit: money
  -- recorded as moved, with nothing to look up on a statement, is not a record
  -- of anything.
  constraint refund_paid_has_a_reference check (
    status <> 'paid' or (gateway_refund_id is not null and paid_at is not null)
  ),

  constraint refund_failure_is_explained check (
    status not in ('failed', 'declined') or failure_reason is not null
  ),

  -- A platform-funded refund has no business on a vendor's statement. Enforced
  -- here rather than trusted to the batch, because the batch is one function and
  -- this is a property of the row.
  constraint refund_on_a_statement_is_the_vendors check (
    settlement_id is null or funded_by = 'restaurant'
  )
);

-- One automatic refund per order. `orders_refund_on_termination` checks before
-- it inserts and cannot fire twice on the same transition anyway, but "cannot
-- happen" is a statement about today's triggers and this is a statement about
-- the data — the same reason 0076 indexed its one-collection-per-order rule
-- instead of arguing that `confirm_delivered` could not reach it twice.
create unique index if not exists refund_one_automatic_per_order
  on public.refunds (order_id)
  where requested_by = 'system';

create index if not exists refunds_by_order_idx
  on public.refunds (order_id, created_at desc);

-- The console's queue: everything a person still has to do, newest last.
create index if not exists refunds_open_idx
  on public.refunds (status, created_at)
  where status in ('requested', 'approved', 'processing', 'failed');

-- Unsettled vendor money, for the batch in section 6.
create index if not exists refunds_unsettled_vendor_idx
  on public.refunds (order_id)
  where settlement_id is null and funded_by = 'restaurant';

-- RLS on, no policies, no grants — the shape 0045 gave the bank accounts and
-- 0076 gave the cash ledger. Every read below goes through a `security definer`
-- function that decides what the caller may see: a customer gets their own
-- order's refunds, an admin gets the queue. Supabase grants insert, update and
-- delete on a new table to `anon` and `authenticated` by default, which is how
-- `coupons` spent 61 migrations writable by the anon key (0064). Revoked before
-- it can happen again.
alter table public.refunds enable row level security;
revoke all on public.refunds from anon, authenticated;
revoke all on sequence public.refunds_id_seq from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. An order cannot be refunded for more than it cost.
-- ---------------------------------------------------------------------------
-- Over-refunding is the failure mode of this table that costs money, and it is
-- reachable from a single mistyped amount in the console. Checked against the
-- order's total, counting every refund that is still alive — a declined or
-- failed one has released its claim and must not keep blocking a correct
-- retry.
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

drop trigger if exists refunds_within_the_order on public.refunds;
create trigger refunds_within_the_order
  before insert or update of amount, status on public.refunds
  for each row execute function public.refund_within_the_order();

-- ---------------------------------------------------------------------------
-- 3. The automatic path.
-- ---------------------------------------------------------------------------
-- Fires on the transition, not on the function that caused it. 'rejected' is
-- both the vendor declining and the five-minute expiry giving up on them, and
-- both are the restaurant's to fund; 'cancelled' is the customer, support, or a
-- kitchen that took the order and then could not cook it, and those are not
-- separable from the row — so it defaults to the platform and an admin can move
-- it while it is still unsettled (section 5).
create or replace function public.orders_refund_on_termination()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- What the customer is promised. Five days is the gateway's own working
  -- window for a UPI reversal; it is deliberately not a settings row, because a
  -- promise that an admin can shorten is a promise the platform will break.
  v_days constant integer := 5;
  v_reason text;
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
    new.id, new.payment_id, new.total, v_reason, 'approved',
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
      '₹' || new.total || ' for order ' || new.id ||
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

-- 'refund' is new. The check on `notifications.kind` has been deliberately
-- tolerant since 0047 and all three apps degrade an unrecognised kind to a
-- plain system notice, so an older build installed today shows this row as an
-- ordinary alert rather than crashing on it.
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('new_order', 'system', 'order_update', 'order_live',
                  'job_offer', 'job_available', 'job_cancelled', 'payout',
                  'account', 'settlement', 'message', 'review', 'refund'));

drop trigger if exists orders_refund_on_termination on public.orders;
create trigger orders_refund_on_termination
  after update of status on public.orders
  for each row
  when (new.status in ('cancelled', 'rejected')
        and old.status is distinct from new.status)
  execute function public.orders_refund_on_termination();

-- ---------------------------------------------------------------------------
-- 4. What the customer sees.
-- ---------------------------------------------------------------------------
-- Returns rows, not a row: an order can carry the automatic full refund and
-- later a partial one, and a screen that shows only the newest would tell a
-- customer their ₹80 goodwill credit is the whole story.
create or replace function public.my_order_refund(p_order_id text)
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
         r.amount < o.total as is_partial,
         r.created_at
    from public.refunds r
    join public.orders o on o.id = r.order_id
   where r.order_id = p_order_id
     and o.user_id = auth.uid()::text
     -- A refund an admin declined was never owed. Showing it would announce an
     -- internal decision to somebody who never asked for the money.
     and r.status <> 'declined'
   order by r.created_at;
$$;

revoke all on function public.my_order_refund(text) from public;
grant execute on function public.my_order_refund(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. What support does.
-- ---------------------------------------------------------------------------
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

-- A refund an admin raises by hand: the partial the finding asks for, and the
-- only way to refund a cash order that was actually delivered. Born
-- 'requested' — issuing and approving are two acts and both get a name.
create or replace function public.admin_issue_refund(
  p_order_id  text,
  p_amount    integer,
  p_reason    text,
  p_funded_by text default 'platform'
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

  if p_funded_by not in ('platform', 'restaurant') then
    raise exception 'A refund is funded by the platform or by the restaurant.'
      using errcode = 'P0001';
  end if;

  select o.id, o.total, o.payment_id into v_order
    from public.orders o where o.id = p_order_id;

  if not found then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  -- The amount is checked against everything already owed on this order by
  -- `refunds_within_the_order`, which is where that rule lives for every writer.
  insert into public.refunds (
    order_id, payment_id, amount, reason, status, funded_by,
    requested_by, expected_by
  ) values (
    v_order.id, v_order.payment_id, p_amount, v_reason, 'requested', p_funded_by,
    lower(auth.jwt() ->> 'email'), (current_date + 5)
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- Approval, and the one chance to move who pays. Attribution is offered here
-- rather than as a fifth button because this is the moment a person is already
-- looking at the refund and deciding about it; a separate screen for it is a
-- screen nobody opens.
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
  v_status text;
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

create or replace function public.admin_decline_refund(p_id bigint, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_reason text;
begin
  perform public.assert_admin();

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception 'Say why this refund is being declined.' using errcode = 'P0001';
  end if;

  select r.status into v_status from public.refunds r where r.id = p_id for update;

  if not found then
    raise exception 'We couldn''t find that refund.' using errcode = 'P0001';
  end if;

  -- An automatic refund is the platform's own obligation on an order that never
  -- happened. Support does not get to decide it is not owed.
  if exists (select 1 from public.refunds r
              where r.id = p_id and r.requested_by = 'system') then
    raise exception 'That refund is owed automatically on a cancelled order and cannot be declined.'
      using errcode = 'P0001';
  end if;

  if v_status not in ('requested', 'failed') then
    raise exception 'Only a refund that has not been sent can be declined.'
      using errcode = 'P0001';
  end if;

  update public.refunds
     set status = 'declined', failure_reason = v_reason
   where id = p_id;
end;
$$;

-- Paid, by hand, against a bank reference. This is what a refund settlement is
-- today and it is not a placeholder: PAY-001's webhook will write exactly these
-- three columns, from a gateway id instead of a typed one, and the row will not
-- know the difference.
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

revoke all on function public.admin_list_refunds(text) from public;
revoke all on function public.admin_issue_refund(text, integer, text, text) from public;
revoke all on function public.admin_approve_refund(bigint, text) from public;
revoke all on function public.admin_decline_refund(bigint, text) from public;
revoke all on function public.admin_mark_refund_paid(bigint, text) from public;

grant execute on function public.admin_list_refunds(text) to authenticated;
grant execute on function public.admin_issue_refund(text, integer, text, text) to authenticated;
grant execute on function public.admin_approve_refund(bigint, text) to authenticated;
grant execute on function public.admin_decline_refund(bigint, text) to authenticated;
grant execute on function public.admin_mark_refund_paid(bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. A refund the vendor caused comes off the vendor's statement.
-- ---------------------------------------------------------------------------
-- Until now `run_settlement_batch` summed delivered orders and nothing else, so
-- a restaurant that rejected forty prepaid orders in a week was paid in full for
-- the ones it did cook while the platform ate forty reversals.
alter table public.settlements
  add column if not exists refunds integer not null default 0 check (refunds >= 0);

alter table public.settlements drop constraint if exists settlement_net_is_consistent;
alter table public.settlements add constraint settlement_net_is_consistent
  check (net_payable = gross_sales - vendor_funded_discount - commission - refunds);

-- Refunds are claimed by restaurant, not by week. A refund raised in week three
-- for a week-one order belongs on the week-three statement, because week one has
-- already been paid — there is no hold period to claw back from and pretending
-- otherwise is BIZ-007's job, not this one.
create or replace function public.run_settlement_batch()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  b            record;
  v_settlement bigint;
  v_commission integer;
  v_net_sales  integer;
  v_refunds    integer;
  v_created    integer := 0;
begin
  for b in
    select
      o.restaurant_id                                          as restaurant_id,
      (date_trunc('week', o.created_at))::date                 as period_start,
      (date_trunc('week', o.created_at) + interval '6 days')::date as period_end,
      count(*)::integer                                        as order_count,
      sum(o.subtotal)::integer                                 as gross_sales,
      -- The whole of BIZ-001, in one clause. `discount_funded_by` is frozen on
      -- the order, so this reads what was true when the customer paid.
      coalesce(sum(o.discount) filter (
        where o.discount_funded_by = 'restaurant'
      ), 0)::integer                                           as vendor_funded_discount,
      r.commission_bps                                         as bps
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
    where o.status = 'delivered'
      and o.settlement_id is null
    group by o.restaurant_id, date_trunc('week', o.created_at), r.commission_bps
  loop
    -- Commission is charged on what the kitchen earned, not on the menu price
    -- of food it discounted away.
    v_net_sales  := b.gross_sales - b.vendor_funded_discount;
    v_commission := round(v_net_sales * b.bps / 10000.0)::integer;

    -- Everything this restaurant owes back and has not yet been charged for.
    -- 'approved' counts as well as 'paid': the platform has committed to the
    -- customer by then, and waiting for the gateway to confirm before charging
    -- the vendor means a refund can slip a whole statement.
    select coalesce(sum(r.amount), 0)::integer into v_refunds
      from public.refunds r
      join public.orders o2 on o2.id = r.order_id
     where o2.restaurant_id = b.restaurant_id
       and r.funded_by = 'restaurant'
       and r.settlement_id is null
       and r.status in ('approved', 'processing', 'paid');

    insert into public.settlements (
      restaurant_id, period_start, period_end,
      order_count, gross_sales, vendor_funded_discount, commission, refunds,
      net_payable
    ) values (
      b.restaurant_id, b.period_start, b.period_end,
      b.order_count, b.gross_sales, b.vendor_funded_discount, v_commission,
      v_refunds,
      -- Deliberately not floored at zero. A week of rejections that costs more
      -- than the week's cooking earned is a real number and a vendor conversation
      -- worth having; clamping it would hide the thing worth seeing and quietly
      -- forgive the balance.
      v_net_sales - v_commission - v_refunds
    ) returning id into v_settlement;

    update public.orders o
       set settlement_id = v_settlement
     where o.restaurant_id = b.restaurant_id
       and o.status = 'delivered'
       and o.settlement_id is null
       and (date_trunc('week', o.created_at))::date = b.period_start;

    -- Claim exactly what was summed a moment ago, on the same predicate. A
    -- refund approved between the two statements is left for the next batch
    -- rather than being charged without being counted.
    update public.refunds r
       set settlement_id = v_settlement
      from public.orders o2
     where o2.id = r.order_id
       and o2.restaurant_id = b.restaurant_id
       and r.funded_by = 'restaurant'
       and r.settlement_id is null
       and r.status in ('approved', 'processing', 'paid');

    v_created := v_created + 1;
  end loop;

  return v_created;
end;
$$;

-- `admin_list_settlements` returns an explicit column list and has to be told
-- about the new one, or the console shows a net that does not equal its parts.
-- Dropped first, not replaced: `create or replace` cannot change a function's
-- OUT columns, and replacing it under the same argument list would otherwise
-- have produced the overload trap this project has hit before (0065).
drop function if exists public.admin_list_settlements(text);
create function public.admin_list_settlements(p_status text default null)
returns table (
  id                     bigint,
  restaurant_id          text,
  restaurant_name        text,
  period_start           date,
  period_end             date,
  order_count            integer,
  gross_sales            integer,
  vendor_funded_discount integer,
  commission             integer,
  refunds                integer,
  net_payable            integer,
  status                 text,
  reference              text,
  has_bank               boolean,
  paid_at                timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select s.id, s.restaurant_id, r.name, s.period_start, s.period_end,
           s.order_count, s.gross_sales, s.vendor_funded_discount,
           s.commission, s.refunds, s.net_payable,
           s.status, s.reference,
           (a.account_number is not null),
           s.paid_at
      from public.settlements s
      join public.restaurants r on r.id = s.restaurant_id
      left join public.restaurant_bank_accounts a on a.restaurant_id = s.restaurant_id
     where p_status is null or s.status = p_status
     order by s.status = 'paid', s.period_end desc, r.name;
end;
$$;

revoke all on function public.admin_list_settlements(text) from public;
grant execute on function public.admin_list_settlements(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. An order that still owes money cannot be erased.
-- ---------------------------------------------------------------------------
-- `refunds.order_id` cascades, like every other child of `orders` — 0069's
-- delete is deliberately a delete and it keeps a snapshot. But a cascade that
-- silently discharges a debt is a different thing from one that removes a line
-- item, so the one case is closed here: while a refund is owed and unpaid, the
-- order is not deletable. A paid one goes with the order, as the invoice does.
create or replace function public.admin_delete_order(p_order_id text, p_reason text default '')
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order   public.orders%rowtype;
  v_items   integer;
  v_admin   text;
  v_owed    integer;
begin
  perform public.assert_admin();

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'No order carries the id %.', p_order_id using errcode = 'P0001';
  end if;

  select coalesce(sum(r.amount), 0)::integer into v_owed
    from public.refunds r
   where r.order_id = p_order_id
     and r.status in ('requested', 'approved', 'processing');

  if v_owed > 0 then
    raise exception
      '₹% is still owed back on %. Pay or decline the refund before deleting the order.',
      v_owed, p_order_id
      using errcode = 'P0001';
  end if;

  v_admin := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'unknown');
  select count(*)::integer into v_items
    from public.order_items where order_id = p_order_id;

  insert into public.admin_order_deletions (
    order_id, restaurant_id, deleted_by, reason,
    order_status, invoice_no, total, order_snapshot
  ) values (
    v_order.id, v_order.restaurant_id, v_admin,
    left(trim(coalesce(p_reason, '')), 200),
    v_order.status, v_order.invoice_no, v_order.total, to_jsonb(v_order)
  );

  -- The cascades do the rest: items and their options, the delivery, the codes,
  -- any offer, the messages, the route job, the review, and any settled refund.
  delete from public.orders where id = p_order_id;

  return case
    when v_order.invoice_no is not null then
      format(
        '%s is deleted — %s items, ₹%s, and tax invoice %s. The invoice series now has a gap.',
        v_order.id, v_items, v_order.total, v_order.invoice_no
      )
    else
      format('%s is deleted — %s items, ₹%s.', v_order.id, v_items, v_order.total)
  end;
end;
$$;
