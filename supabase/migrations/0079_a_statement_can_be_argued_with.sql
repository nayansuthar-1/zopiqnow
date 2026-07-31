-- ---------------------------------------------------------------------------
-- 0079 — a statement can be argued with. (audit BIZ-007)
-- ---------------------------------------------------------------------------
-- 0077 gave refunds a ledger and charged the restaurant-funded ones to a
-- statement. Its own resolution note said what it had not closed: a refund
-- raised after its week has been settled lands on the *next* statement, because
-- there is no hold period to claw back from. And a settlement, once rolled up,
-- was a number with no way to move it — `admin_approve_refund` has been telling
-- admins to "adjust the settlement instead" since 0077, of a thing that had no
-- adjustment.
--
-- Three changes:
--
--   1. **A statement is only raised for a week that has ended.** The batch has
--      grouped by `date_trunc('week', created_at)` since 0017 and taken whatever
--      it found — including the current, half-finished week. Running it on a
--      Wednesday settled Monday to Wednesday as though that were a week. Orders
--      from the running week are now left alone.
--
--   2. **A hold before it can be paid.** `hold_until` is `period_end` plus
--      `settlement_hold_days()`, and `admin_mark_settlement_paid` refuses before
--      it. The point is not the delay; it is that there is now a window in which
--      the statement exists, is visible to the restaurant, and can still change.
--      A refund approved inside that window is charged to the statement it
--      actually belongs to rather than to the one after it.
--
--   3. **An adjustments line.** A signed rollup on `settlements` and a row per
--      adjustment underneath it, each with a reason and the admin who wrote it.
--      Signed, because the cases run both ways: a goodwill credit to a kitchen
--      that took a bad week for us, and a charge for something a refund did not
--      capture. `net_payable` includes it, and the constraint makes a statement
--      whose parts do not sum to it unwritable.
--
-- **What this does not do: give the vendor a way to raise a dispute.** That is
-- VEN-007 and it is a screen, not a schema. What 0079 builds is the thing a
-- dispute would have to land in — a window in which the number is not yet final,
-- and a line to move it on. A vendor who disagrees today still telephones, and
-- an admin still types the adjustment. That is a smaller gap than the one where
-- the money had already left.
--
-- **No statement already paid is touched.** Existing rows are backfilled with
-- `hold_until = period_end`, which is a hold that has already elapsed for every
-- one of them, and `adjustments = 0`.

-- ===========================================================================
-- A. How long the money waits.
-- ===========================================================================
-- Three days after the week closes. A function and not a settings row, for the
-- reason 0077 gave about the refund promise: a window an admin can shorten from
-- a console, on the afternoon a vendor is complaining, is not a window.
create or replace function public.settlement_hold_days()
returns integer language sql immutable as $$ select 3 $$;

comment on function public.settlement_hold_days() is
  'Days after a settlement period closes before the statement may be paid. The '
  'window a refund or an adjustment has to land in (0079, audit BIZ-007).';

-- ===========================================================================
-- B. The hold and the adjustments line.
-- ===========================================================================
alter table public.settlements
  add column if not exists hold_until  date,
  add column if not exists adjustments integer not null default 0;

-- Every existing statement: a hold that closed the day the period did. Anything
-- else would retroactively put a paid statement in violation of the rule below,
-- and rewriting the history of money that has already moved is the one thing
-- this schema has never done.
update public.settlements set hold_until = period_end where hold_until is null;

alter table public.settlements alter column hold_until set not null;

alter table public.settlements
  drop constraint if exists settlement_hold_is_after_the_period;
alter table public.settlements
  add constraint settlement_hold_is_after_the_period
  check (hold_until >= period_end);

comment on column public.settlements.hold_until is
  'The date on or after which this statement may be marked paid. period_end + '
  'settlement_hold_days(). Backfilled to period_end on everything that existed '
  'before 0079 — those holds are long over.';

comment on column public.settlements.adjustments is
  'The signed sum of settlement_adjustments for this statement. Positive credits '
  'the restaurant, negative charges it. Added to net_payable last, after the '
  'commission and the refunds (0079, audit BIZ-007).';

-- ---------------------------------------------------------------------------
-- Each adjustment, with a reason and a name against it.
-- ---------------------------------------------------------------------------
-- A rollup column on its own would be a number nobody can explain three months
-- later — which is the same objection this audit raised about the settlement as
-- a whole. The rollup is for the arithmetic; these rows are for the argument.
create table if not exists public.settlement_adjustments (
  id            bigserial primary key,
  settlement_id bigint      not null references public.settlements (id) on delete cascade,
  amount        integer     not null check (amount <> 0),
  reason        text        not null check (length(trim(reason)) > 0),
  created_by    text        not null,
  created_at    timestamptz not null default now()
);

create index if not exists settlement_adjustments_settlement_idx
  on public.settlement_adjustments (settlement_id, created_at);

alter table public.settlement_adjustments enable row level security;

-- The table arrives writable to `authenticated` unless this says otherwise —
-- the lesson of SEC-002, and of every table added since. An adjustment is
-- written by one security-definer function and by nothing else.
revoke all on public.settlement_adjustments from public, anon, authenticated;
revoke all on sequence public.settlement_adjustments_id_seq from public, anon, authenticated;
grant select on public.settlement_adjustments to authenticated;

-- ...but readable by the restaurant it is charged to. A statement that says
-- "adjustments −₹400" and will not say why is worse than one that says nothing:
-- it tells the kitchen there is a reason and that they are not allowed to see
-- it. Scoped through the settlement, so a guessed id returns nothing.
drop policy if exists "staff read their restaurant's settlement adjustments"
  on public.settlement_adjustments;
create policy "staff read their restaurant's settlement adjustments"
  on public.settlement_adjustments for select to authenticated
  using (exists (
    select 1 from public.settlements s
     where s.id = settlement_adjustments.settlement_id
       and s.restaurant_id = public.staff_restaurant_id()
  ));

-- ---------------------------------------------------------------------------
-- The arithmetic, as a constraint.
-- ---------------------------------------------------------------------------
alter table public.settlements
  drop constraint if exists settlement_net_is_consistent;
alter table public.settlements
  add constraint settlement_net_is_consistent
  check (net_payable = gross_sales - vendor_funded_discount - commission
                       - refunds + adjustments);

-- ===========================================================================
-- C. The batch settles finished weeks, and stamps the hold.
-- ===========================================================================
-- 0077's function, with two changes: orders from the running week are excluded,
-- and the new row carries its hold. Everything else — the commission base, the
-- refund sweep, the two claiming updates — is 0077's and is untouched.
create or replace function public.run_settlement_batch()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
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
      -- New in 0079. A week is settled once it is over: taking the running week
      -- produced a "week" that was however many days had happened by the time
      -- somebody ran the batch, and left the rest of it to be settled again
      -- under the same period_start. A hold measured from period_end means
      -- nothing if period_end has not arrived.
      and o.created_at < date_trunc('week', now())
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
      restaurant_id, period_start, period_end, hold_until,
      order_count, gross_sales, vendor_funded_discount, commission, refunds,
      adjustments, net_payable
    ) values (
      b.restaurant_id, b.period_start, b.period_end,
      b.period_end + public.settlement_hold_days(),
      b.order_count, b.gross_sales, b.vendor_funded_discount, v_commission,
      v_refunds,
      0,
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
$function$;

-- ===========================================================================
-- D. A refund approved inside the window lands on the right statement.
-- ===========================================================================
-- This is the half of BIZ-004 that had nowhere to go. Before the hold there was
-- no such thing as an open statement: the week was rolled up and, as far as the
-- batch was concerned, closed, so a refund approved on Tuesday for Monday's
-- order was charged to next week. Now there is a window, and a refund that
-- arrives inside it is charged to the statement its own order is on.
--
-- `before`, so the row is written with its `settlement_id` already set rather
-- than updated a second time. Only ever *into* the charged statuses, and only
-- from a null claim, so a status moving on from `approved` to `paid` cannot
-- charge the same refund twice.
create or replace function public.refunds_charge_to_open_statement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement bigint;
begin
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

drop trigger if exists refunds_charge_to_open_statement on public.refunds;
create trigger refunds_charge_to_open_statement
  before insert or update of status, funded_by on public.refunds
  for each row execute function public.refunds_charge_to_open_statement();

-- ===========================================================================
-- E. The hold, enforced where the money moves.
-- ===========================================================================
create or replace function public.admin_mark_settlement_paid(
  p_id bigint, p_reference text
) returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ref    text;
  v_status text;
  v_hold   date;
begin
  perform public.assert_admin();

  v_ref := nullif(trim(coalesce(p_reference, '')), '');
  if v_ref is null then
    raise exception 'Add the bank reference — a settlement marked paid without one cannot be reconciled.'
      using errcode = 'P0001';
  end if;

  select s.status, s.hold_until into v_status, v_hold
    from public.settlements s where s.id = p_id for update;
  if not found then
    raise exception 'No such settlement.' using errcode = 'P0001';
  end if;
  if v_status = 'paid' then
    raise exception 'That settlement is already marked paid.' using errcode = 'P0001';
  end if;

  -- The hold, and the whole reason there is one: after this the statement is
  -- history, and a refund or an adjustment raised against it has to wait for
  -- the next. No override — a window an admin can wave through on the afternoon
  -- somebody is asking them to is not a window (0079, audit BIZ-007).
  if current_date < v_hold then
    raise exception 'This statement is on hold until % — a refund or an adjustment raised before then still lands on it.',
      to_char(v_hold, 'DD Mon YYYY') using errcode = 'P0001';
  end if;

  -- `notify_vendor_settlement` fires on this update and has since 0047. The
  -- vendor finds out because the row changed, not because this function
  -- remembered to tell them.
  update public.settlements
     set status = 'paid', reference = v_ref, paid_at = now()
   where id = p_id;
end;
$function$;

-- ===========================================================================
-- F. Writing an adjustment.
-- ===========================================================================
-- Pending statements only. A paid one is a line on a bank statement and the
-- money is gone; the honest place for a correction to it is the next week, which
-- is what the error sentence says rather than leaving somebody to guess.
create or replace function public.admin_adjust_settlement(
  p_id bigint, p_amount integer, p_reason text
) returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_status text;
  v_reason text;
  v_rest   text;
  v_net    integer;
  v_adj    bigint;
begin
  perform public.assert_admin();

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception 'Say what this adjustment is for — it is the only thing the restaurant will be able to read.'
      using errcode = 'P0001';
  end if;

  if p_amount is null or p_amount = 0 then
    raise exception 'An adjustment of nothing is not an adjustment.' using errcode = 'P0001';
  end if;

  select s.status, s.restaurant_id into v_status, v_rest
    from public.settlements s where s.id = p_id for update;
  if not found then
    raise exception 'No such settlement.' using errcode = 'P0001';
  end if;
  if v_status = 'paid' then
    raise exception 'That statement has been paid. Put the adjustment on the next one.'
      using errcode = 'P0001';
  end if;

  insert into public.settlement_adjustments (settlement_id, amount, reason, created_by)
  values (p_id, p_amount, v_reason, coalesce(lower(auth.jwt() ->> 'email'), 'admin'))
  returning id into v_adj;

  update public.settlements
     set adjustments = adjustments + p_amount,
         net_payable = net_payable + p_amount
   where id = p_id
  returning net_payable into v_net;

  -- A window in which the figure can change silently is not a window anybody
  -- can use. `notify_vendor_settlement` only fires on payment, so this is the
  -- one that says the number moved while it was still arguable. Swallowed on
  -- failure, like every other notification in this schema: an inbox row is not
  -- worth failing a money write over.
  begin
    insert into public.notifications
      (audience, restaurant_id, kind, title, body)
    values (
      'restaurant', v_rest, 'settlement',
      case when p_amount > 0 then 'Statement adjusted in your favour'
           else 'Statement adjusted' end,
      case when p_amount > 0 then '+₹' || p_amount else '−₹' || abs(p_amount) end
        || ' — ' || v_reason || '. Your statement now comes to '
        -- A negative net is a real outcome (0077 refused to floor it), so it has
        -- to read like one rather than as the stray hyphen of '₹-144'.
        || case when v_net < 0 then '−₹' || abs(v_net) else '₹' || v_net end || '.'
    );
  exception when others then
    null;
  end;

  return v_adj;
end;
$function$;

-- ===========================================================================
-- G. What the console reads.
-- ===========================================================================
-- Dropped and recreated, not replaced: the return type gains two columns, and
-- `create or replace` cannot change a function's result type. Appending to the
-- signature would be worse still — it would create a second overload and let
-- PostgREST choose between them (see 0075's note on the same hazard).
drop function if exists public.admin_list_settlements(text);
create function public.admin_list_settlements(p_status text default null)
returns table (
  id bigint, restaurant_id text, restaurant_name text,
  period_start date, period_end date, hold_until date,
  order_count integer, gross_sales integer, vendor_funded_discount integer,
  commission integer, refunds integer, adjustments integer, net_payable integer,
  status text, reference text, has_bank boolean, on_hold boolean,
  paid_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  perform public.assert_admin();

  return query
    select s.id, s.restaurant_id, r.name, s.period_start, s.period_end,
           s.hold_until,
           s.order_count, s.gross_sales, s.vendor_funded_discount,
           s.commission, s.refunds, s.adjustments, s.net_payable,
           s.status, s.reference,
           (a.account_number is not null),
           -- Computed here rather than on the page, so the button's enabled
           -- state and the function's refusal are the same fact.
           (s.status <> 'paid' and current_date < s.hold_until),
           s.paid_at
      from public.settlements s
      join public.restaurants r on r.id = s.restaurant_id
      left join public.restaurant_bank_accounts a on a.restaurant_id = s.restaurant_id
     where p_status is null or s.status = p_status
     order by s.status = 'paid', s.period_end desc, r.name;
end;
$function$;

create or replace function public.admin_list_settlement_adjustments(p_id bigint)
returns table (
  id bigint, amount integer, reason text, created_by text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  perform public.assert_admin();

  return query
    select a.id, a.amount, a.reason, a.created_by, a.created_at
      from public.settlement_adjustments a
     where a.settlement_id = p_id
     order by a.created_at;
end;
$function$;

-- ===========================================================================
-- H. Grants.
-- ===========================================================================
-- SEC-002's rule: every function is granted to the caller that needs it and to
-- nobody else. The admin RPCs go to `authenticated` because the console signs in
-- as an ordinary user and `assert_admin` is what separates them; the internals
-- go nowhere a client can reach.
revoke all on function public.settlement_hold_days() from public, anon, authenticated;
grant execute on function public.settlement_hold_days() to service_role;

revoke all on function public.refunds_charge_to_open_statement()
  from public, anon, authenticated;

revoke all on function public.run_settlement_batch() from public, anon, authenticated;
grant execute on function public.run_settlement_batch() to service_role;

revoke all on function
  public.admin_adjust_settlement(bigint, integer, text),
  public.admin_list_settlement_adjustments(bigint),
  public.admin_list_settlements(text),
  public.admin_mark_settlement_paid(bigint, text)
  from public, anon;
grant execute on function
  public.admin_adjust_settlement(bigint, integer, text),
  public.admin_list_settlement_adjustments(bigint),
  public.admin_list_settlements(text),
  public.admin_mark_settlement_paid(bigint, text)
  to authenticated, service_role;
