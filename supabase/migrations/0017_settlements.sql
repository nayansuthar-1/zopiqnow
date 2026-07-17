-- Step, migration 17: the money the kitchen is owed, and the batches that pay it.
--
-- Phase 5. Everything the vendor has seen so far is an *order* — one customer,
-- one bill, priced by `place_order`. This migration is the other side of that:
-- what the platform owes the restaurant for the orders it has already delivered,
-- and the weekly payout that clears it.
--
-- The rule this migration exists to enforce is the same one 0003 and 0009 were
-- built on: **the party being paid does not get to decide what it is paid.** A
-- vendor may *read* its earnings and its settlements; it may not write a single
-- figure. The commission rate is an ops number, the rollup is a `security
-- definer` function no vendor can call, and the settlement rows are select-only
-- through the API. A restaurant that could edit `net_payable` is a restaurant
-- that pays itself.
--
-- What money means here, stated once so the columns below are unambiguous:
--   * `gross_sales`  — the food value the restaurant sold, i.e. the *subtotal*
--     of its delivered orders. Delivery fees and taxes are the platform's to
--     collect and remit; they were never the kitchen's to earn.
--   * `commission`   — the platform's cut, `gross_sales * commission_bps`,
--     rounded to the rupee. Read from the restaurant, never from the client.
--   * `net_payable`  — `gross_sales - commission`. What actually gets paid out.

-- ---------------------------------------------------------------------------
-- The commission rate: an ops number that lives on the restaurant.
-- ---------------------------------------------------------------------------
-- Basis points, not a percent, so a 17.5% deal is an integer (1750) and not a
-- float that rounds differently on two machines. Default 20%. There is no grant
-- that lets a vendor update this column — `0012` gave the vendor an RPC that
-- edits name/cuisines/price and nothing else, and this is deliberately not in it.
alter table public.restaurants
  add column if not exists commission_bps integer not null default 2000
    check (commission_bps between 0 and 10000);

-- ---------------------------------------------------------------------------
-- Settlements: one payout batch — a restaurant, a week, the orders in it.
-- ---------------------------------------------------------------------------
create table if not exists public.settlements (
  id             bigserial primary key,
  restaurant_id  text not null references public.restaurants (id) on delete cascade,

  -- The week this batch covers, inclusive at both ends. A batch is a Mon–Sun
  -- window (see run_settlement_batch); storing the dates rather than a week
  -- number means the statement reads as "1–7 Jul" without the app doing calendar
  -- maths.
  period_start   date not null,
  period_end     date not null,

  order_count    integer not null check (order_count >= 0),

  -- Denormalised totals, written once by the rollup from the orders it attaches.
  -- Denormalised on purpose: a settlement is a statement of what was owed *that
  -- week*, and it must not move when a restaurant's commission rate changes next
  -- month.
  gross_sales    integer not null check (gross_sales >= 0),
  commission     integer not null check (commission >= 0),
  net_payable    integer not null,

  status         text not null default 'pending' check (status in ('pending', 'paid')),

  -- The bank's reference for a paid batch (a UTR). Null until ops marks it paid.
  reference      text,
  created_at     timestamptz not null default now(),
  paid_at        timestamptz,

  constraint settlement_net_is_consistent
    check (net_payable = gross_sales - commission),
  constraint settlement_period_is_ordered
    check (period_end >= period_start),
  -- A batch that says "paid" without a time it was paid is a batch nobody can
  -- reconcile. Same shape as `prepaid_order_has_a_payment_id` in 0003.
  constraint settlement_paid_has_a_timestamp
    check (status <> 'paid' or paid_at is not null)
);

create index if not exists settlements_restaurant_idx
  on public.settlements (restaurant_id, period_end desc);

-- The link from an order to the batch that paid for it. Nullable: an order is
-- unsettled until a batch claims it, and only *delivered* orders ever get
-- claimed. A partial index, because "the orders still waiting to be settled" is
-- the one question the rollup asks and it should not scan the whole book to
-- answer it.
alter table public.orders
  add column if not exists settlement_id bigint references public.settlements (id);

create index if not exists orders_unsettled_idx
  on public.orders (restaurant_id, created_at)
  where status = 'delivered' and settlement_id is null;

-- ---------------------------------------------------------------------------
-- What a vendor may read: its own settlements. Nothing else.
-- ---------------------------------------------------------------------------
-- Select-only, scoped by the same `staff_restaurant_id()` every vendor policy
-- since 0009 has used. There is no insert/update/delete grant: settlements are
-- born in the rollup below and marked paid by ops, never by the app. The
-- per-order breakdown a statement drills into is just `orders` filtered by
-- `settlement_id`, and that is already readable under the 0009 orders policy —
-- no second policy needed.
alter table public.settlements enable row level security;

drop policy if exists "staff read their restaurant's settlements" on public.settlements;
create policy "staff read their restaurant's settlements"
  on public.settlements for select to authenticated
  using (restaurant_id = public.staff_restaurant_id());

grant select on public.settlements to authenticated;

-- ---------------------------------------------------------------------------
-- vendor_earnings_summary: the live read behind the Payments screen.
-- ---------------------------------------------------------------------------
-- Settled or not, a kitchen wants to know what it has earned this week *today*,
-- not when the batch runs on Monday. This aggregates delivered orders in a date
-- window into totals plus a per-day series for the chart — computed, never
-- stored, so it is always current. `stable`: pure over a statement.
create or replace function public.vendor_earnings_summary(
  p_from date,
  p_to   date
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_bps        integer;
  v_result     jsonb;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  select commission_bps into v_bps
    from public.restaurants where id = v_restaurant;

  with daily as (
    select
      o.created_at::date          as day,
      count(*)::integer           as orders,
      sum(o.subtotal)::integer    as gross
    from public.orders o
    where o.restaurant_id = v_restaurant
      and o.status = 'delivered'
      and o.created_at::date between p_from and p_to
    group by o.created_at::date
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'commission_bps', v_bps,
    'order_count',  coalesce(sum(d.orders), 0),
    'gross_sales',  coalesce(sum(d.gross), 0),
    'commission',   coalesce(round(sum(d.gross) * v_bps / 10000.0)::integer, 0),
    'net_earnings', coalesce(
                      sum(d.gross) - round(sum(d.gross) * v_bps / 10000.0)::integer,
                      0
                    ),
    'daily', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'day',    d.day,
          'orders', d.orders,
          'gross',  d.gross,
          'net',    d.gross - round(d.gross * v_bps / 10000.0)::integer
        ) order by d.day
      ) filter (where d.day is not null),
      '[]'::jsonb
    )
  ) into v_result
  from daily d;

  return v_result;
end;
$$;

grant execute on function public.vendor_earnings_summary(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- run_settlement_batch: the rollup. Ops/cron only — never the vendor.
-- ---------------------------------------------------------------------------
-- Sweeps every delivered, unsettled order into a per-restaurant, per-week
-- settlement, then attaches those orders to the batch it just made. Idempotent
-- by construction: an order that already has a `settlement_id` is invisible to
-- the sweep, so running it twice creates nothing the second time.
--
-- Not granted to `authenticated`. The vendor is the party being paid; the party
-- being paid does not get to run its own payout.
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
  v_created    integer := 0;
begin
  for b in
    select
      o.restaurant_id                                          as restaurant_id,
      (date_trunc('week', o.created_at))::date                 as period_start,
      (date_trunc('week', o.created_at) + interval '6 days')::date as period_end,
      count(*)::integer                                        as order_count,
      sum(o.subtotal)::integer                                 as gross_sales,
      r.commission_bps                                         as bps
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
    where o.status = 'delivered'
      and o.settlement_id is null
    group by o.restaurant_id, date_trunc('week', o.created_at), r.commission_bps
  loop
    v_commission := round(b.gross_sales * b.bps / 10000.0)::integer;

    insert into public.settlements (
      restaurant_id, period_start, period_end,
      order_count, gross_sales, commission, net_payable
    ) values (
      b.restaurant_id, b.period_start, b.period_end,
      b.order_count, b.gross_sales, v_commission, b.gross_sales - v_commission
    ) returning id into v_settlement;

    -- Claim exactly the orders this bucket summed: same restaurant, same week,
    -- still unsettled. The week match is on the truncated date, the same
    -- expression the group-by used.
    update public.orders o
       set settlement_id = v_settlement
     where o.restaurant_id = b.restaurant_id
       and o.status = 'delivered'
       and o.settlement_id is null
       and (date_trunc('week', o.created_at))::date = b.period_start;

    v_created := v_created + 1;
  end loop;

  return v_created;
end;
$$;

-- Deliberately no grant to authenticated or anon. Callable only by the cron job
-- below (which runs as the table owner) and by a superuser via the dashboard.
revoke all on function public.run_settlement_batch() from public;

-- ---------------------------------------------------------------------------
-- The weekly payout, and the orders already delivered before today.
-- ---------------------------------------------------------------------------
-- Every Monday at 00:30, roll up the week that just ended. Reuses the same
-- pg_cron 0008 introduced and 0009 last touched.
select cron.unschedule('run-settlement-batch')
 where exists (select 1 from cron.job where jobname = 'run-settlement-batch');

select cron.schedule(
  'run-settlement-batch',
  '30 0 * * 1',
  $$ select public.run_settlement_batch(); $$
);

-- And clear the backlog once, now, so a restaurant that has been delivering
-- orders since before this migration has statements to open on day one rather
-- than an empty screen until the first Monday.
select public.run_settlement_batch();
