-- Phase 8d, migration 45: the money actually moves.
--
-- 0043 worked out what a delivery is worth and wrote it on the delivery. It
-- stopped there, and the closing note said so: nothing paid the rider. A number
-- recorded and never settled is a promise, not a wage.
--
-- This is the rider's half of what 0017 built for restaurants, and it is
-- deliberately the *same* machinery rather than a second invention — a weekly
-- Mon–Sun batch, a `pending`/`paid` status, a bank reference, and a foreign key
-- from the work to the batch that paid for it. An admin who has understood
-- settlements already understands this.
--
-- **One difference, and it is the whole difference: there is no commission.** A
-- settlement is gross sales minus the platform's cut. A payout is what the rider
-- earned, and the platform does not take a percentage of it — the commission was
-- already taken from the restaurant. So there is one amount here where
-- settlements have three, and no `net = gross - commission` constraint, because
-- there is nothing to subtract.

-- ---------------------------------------------------------------------------
-- Somewhere to send it.
-- ---------------------------------------------------------------------------
-- A separate table rather than four more columns on `delivery_partners`, exactly
-- as `restaurant_bank_accounts` is separate from `restaurants` (0029). The
-- reason is the same: this is the most sensitive data the platform holds about a
-- person, and a table of its own can be reasoned about, policied, and audited as
-- one thing.
--
-- **Admin-entered, never rider-entered.** Swiggy lets a rider type their own
-- account in; this does not, and the choice follows 0009's standing ban on
-- self-service onboarding that 0040 reaffirmed for the roster. A rider who can
-- write their own payout destination is the whole fraud surface of a payout
-- system in one form field, and the roster is hand-managed anyway.
create table if not exists public.delivery_partner_bank_accounts (
  partner_email  text primary key references public.delivery_partners (email),

  account_holder text,

  -- The same format checks `restaurant_bank_accounts` uses. They catch a typo,
  -- not a lie: nothing here proves the account belongs to this rider.
  account_number text check (account_number is null or account_number ~ '^[0-9]{9,18}$'),
  ifsc           text check (ifsc is null or ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  bank_name      text,

  -- Someone checked it against a document. Never set by code.
  verified       boolean not null default false,
  updated_at     timestamptz not null default now()
);

-- RLS on, no policies, no grant. Only the `security definer` admin functions
-- below touch this. A rider cannot read their own row — there is nothing in it
-- they told us, and an app that can read an account number is an app that can
-- leak one.
alter table public.delivery_partner_bank_accounts enable row level security;

-- ---------------------------------------------------------------------------
-- A payout: one rider, one week, the deliveries in it.
-- ---------------------------------------------------------------------------
create table if not exists public.rider_payouts (
  id             bigserial primary key,
  partner_email  text not null references public.delivery_partners (email),

  -- Inclusive at both ends, a Mon–Sun window, stored as dates so a statement
  -- reads as "1–7 Jul" without the app doing calendar arithmetic. Same shape as
  -- `settlements`.
  period_start   date not null,
  period_end     date not null,

  delivery_count integer not null check (delivery_count >= 0),

  -- Denormalised on purpose, and for a sharper reason than the settlements
  -- version: `deliveries.rider_pay` is itself a snapshot of a rate that can
  -- change, and this is a snapshot of those snapshots. A payout is a statement
  -- of what was owed that week and must not move afterwards for any reason.
  amount         integer not null check (amount >= 0),

  status         text not null default 'pending' check (status in ('pending', 'paid')),

  -- The bank's reference (a UTR). Null until an admin marks it paid.
  reference      text,
  created_at     timestamptz not null default now(),
  paid_at        timestamptz,

  constraint payout_period_is_ordered check (period_end >= period_start),
  -- A batch that says "paid" with no time it was paid is a batch nobody can
  -- reconcile. Same constraint settlements carry, for the same reason.
  constraint payout_paid_has_a_timestamp
    check (status <> 'paid' or paid_at is not null)
);

create index if not exists rider_payouts_partner_idx
  on public.rider_payouts (partner_email, period_end desc);

-- The link from the work to the batch that paid for it. Nullable: a delivery is
-- unpaid until a batch claims it, and only `delivered` ones are ever claimed.
alter table public.deliveries
  add column if not exists payout_id bigint references public.rider_payouts (id);

-- The one question the rollup asks, and it should not scan every delivery ever
-- made to answer it.
create index if not exists deliveries_unpaid_idx
  on public.deliveries (partner_email, delivered_at)
  where state = 'delivered' and payout_id is null;

-- ---------------------------------------------------------------------------
-- What a rider may read: their own payouts, and nothing else.
-- ---------------------------------------------------------------------------
-- A select policy, not another RPC. 8b-1 kept riders off `orders` entirely
-- because that table's policies already encode customer-vs-staff and a third
-- clause would be a third way to widen the first two. This table has no such
-- history: it is the rider's own, and `delivery_partner_email()` is the same
-- helper every rider rule has used since 0025. Exactly what 0017 did for
-- vendors.
--
-- Select only. A payout is born in the rollup and marked paid by an admin;
-- neither is a thing the app does.
alter table public.rider_payouts enable row level security;

drop policy if exists "riders read their own payouts" on public.rider_payouts;
create policy "riders read their own payouts"
  on public.rider_payouts for select to authenticated
  using (partner_email = public.delivery_partner_email());

grant select on public.rider_payouts to authenticated;

-- ---------------------------------------------------------------------------
-- The rollup.
-- ---------------------------------------------------------------------------
-- Sweeps every delivered-but-unpaid delivery into a per-rider, per-week batch
-- and attaches them to it. Idempotent by construction: a delivery that already
-- has a `payout_id` is invisible to the sweep, so running it twice creates
-- nothing the second time.
--
-- Not granted to `authenticated`. The rider is the party being paid, and the
-- party being paid does not get to run their own payout.
--
-- The week comes from `delivered_at`, not `claimed_at`: a job taken at 11pm on
-- Sunday and delivered at 12:20am on Monday belongs to the week the rider was
-- paid for finishing it, which is the same week the app's earnings screen put it
-- in (0043 groups by delivered day, in IST).
create or replace function public.run_rider_payout_batch()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  b         record;
  v_payout  bigint;
  v_created integer := 0;
begin
  for b in
    select
      d.partner_email                                                as partner_email,
      (date_trunc('week', d.delivered_at at time zone 'Asia/Kolkata'))::date
                                                                     as period_start,
      (date_trunc('week', d.delivered_at at time zone 'Asia/Kolkata')
        + interval '6 days')::date                                   as period_end,
      count(*)::integer                                              as delivery_count,
      -- `coalesce` covers any delivery claimed before 0043 existed. There are
      -- none, and a payout run is not the place to discover otherwise.
      sum(coalesce(d.rider_pay, 0))::integer                          as amount
    from public.deliveries d
    where d.state = 'delivered'
      and d.payout_id is null
      and d.delivered_at is not null
    group by d.partner_email,
             date_trunc('week', d.delivered_at at time zone 'Asia/Kolkata')
  loop
    insert into public.rider_payouts (
      partner_email, period_start, period_end, delivery_count, amount
    ) values (
      b.partner_email, b.period_start, b.period_end, b.delivery_count, b.amount
    ) returning id into v_payout;

    -- Claim exactly the deliveries this bucket summed: same rider, same week,
    -- still unpaid. The week match uses the same expression the group-by did —
    -- including the timezone conversion, which is the easy half to forget.
    update public.deliveries d
       set payout_id = v_payout
     where d.partner_email = b.partner_email
       and d.state = 'delivered'
       and d.payout_id is null
       and d.delivered_at is not null
       and (date_trunc('week', d.delivered_at at time zone 'Asia/Kolkata'))::date
           = b.period_start;

    v_created := v_created + 1;
  end loop;

  return v_created;
end;
$$;

-- ---------------------------------------------------------------------------
-- Locking the batch down, and fixing the same hole in the vendor's.
-- ---------------------------------------------------------------------------
-- `revoke all ... from public` is what 0017 wrote for `run_settlement_batch`,
-- and it is **not enough on Supabase**. The project ships default privileges
-- that grant `execute` on new functions in `public` directly to `anon`,
-- `authenticated` and `service_role`. Revoking from `PUBLIC` does not touch a
-- direct grant to a named role, so the function stayed callable — by anybody,
-- signed in or not.
--
-- Found by testing it: a rider ran their own payout batch in the verification
-- for this migration, which is exactly the thing the comment above swore they
-- could not do.
--
-- Every `admin_*` function has the same untidy `anon` grant and is *not*
-- exposed by it, because each one calls `assert_admin()` on its first line and
-- an anon caller has no JWT email to match. These two batch functions have no
-- such guard — the grant was the only thing standing in front of them.
--
-- `run_settlement_batch` is fixed here too rather than in a migration of its
-- own. It is the same defect, it has been live since 0017, and splitting the
-- fix across two files would leave whichever one is applied second briefly
-- describing a state that was never true.
revoke all on function public.run_rider_payout_batch()
  from public, anon, authenticated;

revoke all on function public.run_settlement_batch()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Ops: the bank account.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_rider_bank(
  p_email text,
  p_bank  jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  perform public.assert_admin();

  v_email := lower(trim(coalesce(p_email, '')));
  if not exists (select 1 from public.delivery_partners p where p.email = v_email) then
    raise exception 'No such delivery partner.' using errcode = 'P0001';
  end if;

  insert into public.delivery_partner_bank_accounts as a (
    partner_email, account_holder, account_number, ifsc, bank_name, updated_at
  ) values (
    v_email,
    nullif(trim(coalesce(p_bank ->> 'account_holder', '')), ''),
    nullif(trim(coalesce(p_bank ->> 'account_number', '')), ''),
    -- An IFSC is upper-case by definition, and a form that refuses "sbin0001234"
    -- for being lower-case is a form fighting its user over nothing.
    upper(nullif(trim(coalesce(p_bank ->> 'ifsc', '')), '')),
    nullif(trim(coalesce(p_bank ->> 'bank_name', '')), ''),
    now()
  )
  on conflict (partner_email) do update
     set account_holder = excluded.account_holder,
         account_number = excluded.account_number,
         ifsc           = excluded.ifsc,
         bank_name      = excluded.bank_name,
         -- Changing the destination un-verifies it. Whoever checked the old
         -- account against a document did not check this one.
         verified       = false,
         updated_at     = now();
end;
$$;

revoke execute on function public.admin_set_rider_bank(text, jsonb) from public;
grant execute on function public.admin_set_rider_bank(text, jsonb) to authenticated;

create or replace function public.admin_get_rider_bank(p_email text)
returns table (
  account_holder text,
  account_number text,
  ifsc           text,
  bank_name      text,
  verified       boolean,
  updated_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select a.account_holder, a.account_number, a.ifsc, a.bank_name,
           a.verified, a.updated_at
      from public.delivery_partner_bank_accounts a
     where a.partner_email = lower(trim(p_email));
end;
$$;

revoke execute on function public.admin_get_rider_bank(text) from public;
grant execute on function public.admin_get_rider_bank(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Ops: the payout run.
-- ---------------------------------------------------------------------------
-- Everything owed, newest first, with the bank details needed to actually pay
-- it. `has_bank` rather than the account number itself: a list is read at a
-- glance and over shoulders, and the number is only needed once somebody is
-- making the transfer.
create or replace function public.admin_list_rider_payouts(p_status text default null)
returns table (
  id             bigint,
  partner_email  text,
  partner_name   text,
  period_start   date,
  period_end     date,
  delivery_count integer,
  amount         integer,
  status         text,
  reference      text,
  has_bank       boolean,
  paid_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select p.id, p.partner_email, dp.name, p.period_start, p.period_end,
           p.delivery_count, p.amount, p.status, p.reference,
           (a.account_number is not null),
           p.paid_at
      from public.rider_payouts p
      join public.delivery_partners dp on dp.email = p.partner_email
      left join public.delivery_partner_bank_accounts a
             on a.partner_email = p.partner_email
     where p_status is null or p.status = p_status
     order by p.status = 'paid', p.period_end desc, dp.name;
end;
$$;

revoke execute on function public.admin_list_rider_payouts(text) from public;
grant execute on function public.admin_list_rider_payouts(text) to authenticated;

-- Marking one paid. A reference is required and that is the point of the
-- function: `status = 'paid'` with nothing to look up in a bank statement is a
-- record that cannot be reconciled, and this is the last moment anybody has the
-- UTR in front of them.
create or replace function public.admin_mark_rider_payout_paid(
  p_id        bigint,
  p_reference text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref    text;
  v_status text;
begin
  perform public.assert_admin();

  v_ref := nullif(trim(coalesce(p_reference, '')), '');
  if v_ref is null then
    raise exception 'Add the bank reference — a payout marked paid without one cannot be reconciled.'
      using errcode = 'P0001';
  end if;

  select status into v_status from public.rider_payouts where id = p_id;
  if not found then
    raise exception 'No such payout.' using errcode = 'P0001';
  end if;
  if v_status = 'paid' then
    raise exception 'That payout is already marked paid.' using errcode = 'P0001';
  end if;

  update public.rider_payouts
     set status = 'paid', reference = v_ref, paid_at = now()
   where id = p_id;
end;
$$;

revoke execute on function public.admin_mark_rider_payout_paid(bigint, text) from public;
grant execute on function public.admin_mark_rider_payout_paid(bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Weekly, half an hour after the restaurants are settled.
-- ---------------------------------------------------------------------------
-- 01:00 rather than 00:30 for no cleverer reason than not wanting two rollups
-- competing for the same rows on the same tick. They touch different tables and
-- would be fine; staggering them costs nothing and makes a slow night's log
-- readable.
select cron.unschedule('run-rider-payout-batch')
 where exists (select 1 from cron.job where jobname = 'run-rider-payout-batch');

select cron.schedule(
  'run-rider-payout-batch',
  '0 1 * * 1',
  $$ select public.run_rider_payout_batch(); $$
);

-- Clear whatever backlog exists, once, now — the same courtesy 0017 did for
-- restaurants, so a rider who has been delivering since before this migration
-- opens the app to statements rather than an empty screen.
select public.run_rider_payout_batch();
