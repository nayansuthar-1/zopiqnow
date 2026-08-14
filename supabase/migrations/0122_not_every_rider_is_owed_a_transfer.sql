-- Not every rider is owed a transfer.
--
-- Until now `delivery_partners` described how a rider travels (`vehicle`) and
-- whether they may work (`is_active`, KYC), but never *on what terms they are
-- engaged*. The weekly batch therefore paid ₹25 + ₹5/km to everyone who
-- delivered, which is right for exactly one of the three kinds of rider this
-- platform actually has:
--
--   freelance         works like a Zomato/Swiggy partner. Paid per delivery by
--                     Zopiq. This is what the batch already does, and it stays
--                     the default so nothing about today's five riders changes.
--   salaried          paid a wage off-platform. The delivery still records
--                     `rider_pay` so a route's cost stays visible, but no
--                     transfer is ever owed for it.
--   restaurant_owned  the kitchen's own rider, employed and paid by the
--                     kitchen. Zopiq owes them nothing, and the delivery fee
--                     the customer paid stays with Zopiq.
--
-- So the rule this migration adds is one sentence: **only a freelance rider
-- produces a payout row.** The other two accrue `rider_pay` for costing and
-- are never transferred to.

-- ---------------------------------------------------------------- the columns

alter table public.delivery_partners
  add column if not exists engagement text not null default 'freelance',
  add column if not exists employer_restaurant_id text;

comment on column public.delivery_partners.engagement is
  'How the rider is engaged. Only ''freelance'' is paid per delivery by Zopiq; '
  'salaried and restaurant_owned riders accrue rider_pay for costing and never '
  'produce a rider_payouts row. See run_rider_payout_batch.';

comment on column public.delivery_partners.employer_restaurant_id is
  'The kitchen that employs a restaurant_owned rider. Null for every other '
  'engagement, and required for that one.';

alter table public.delivery_partners
  drop constraint if exists delivery_partners_engagement_is_known;
alter table public.delivery_partners
  add constraint delivery_partners_engagement_is_known
  check (engagement in ('freelance', 'salaried', 'restaurant_owned'));

-- An employer is meaningless on a freelance or salaried rider and mandatory on
-- a restaurant's own, so the pair is constrained together rather than each
-- column being merely nullable and hoping the console agrees.
alter table public.delivery_partners
  drop constraint if exists delivery_partners_employer_matches_engagement;
alter table public.delivery_partners
  add constraint delivery_partners_employer_matches_engagement
  check (
    (engagement = 'restaurant_owned' and employer_restaurant_id is not null)
    or
    (engagement <> 'restaurant_owned' and employer_restaurant_id is null)
  );

-- `restrict`, deliberately, and it is the one behavioural change here that
-- reaches outside payouts: deleting a restaurant that still employs riders now
-- fails instead of silently orphaning them. `cascade` would delete the rider,
-- and `set null` would break the constraint above. Reassigning the riders first
-- is a decision somebody should have to make.
alter table public.delivery_partners
  drop constraint if exists delivery_partners_employer_fkey;
alter table public.delivery_partners
  add constraint delivery_partners_employer_fkey
  foreign key (employer_restaurant_id) references public.restaurants(id)
  on delete restrict;

create index if not exists delivery_partners_employer_idx
  on public.delivery_partners (employer_restaurant_id)
  where employer_restaurant_id is not null;

-- Changing how a rider is engaged decides whether they are paid at all, so it
-- belongs in 0092's trail beside blocking and deactivating them. Same shape as
-- delivery_partners_audit_active: the `when` clause does the filtering, so an
-- ordinary edit writes nothing.
drop trigger if exists delivery_partners_audit_engagement on public.delivery_partners;
create trigger delivery_partners_audit_engagement
  after update on public.delivery_partners
  for each row
  when (old.engagement is distinct from new.engagement
     or old.employer_restaurant_id is distinct from new.employer_restaurant_id)
  execute function public.record_admin_action('email');

-- ------------------------------------------------------------- the batch
-- Reproduced whole because `create or replace` cannot patch a line. **One
-- change only** — the join to delivery_partners and the engagement filter,
-- marked below. Every other line, and every comment, is 0043's as it stood.

create or replace function public.run_rider_payout_batch()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  b          record;
  v_payout   bigint;
  v_created  integer := 0;
  v_cash     integer;
  v_withheld integer;
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
    -- 0122: only a freelance rider is owed a transfer. A salaried or
    -- restaurant-owned rider still carries `rider_pay` on the delivery so the
    -- route's cost is visible, but never forms a bucket here, so no payout row
    -- is created and their deliveries keep `payout_id is null` for ever —
    -- which is the truth: no payout was ever owed.
    join public.delivery_partners p on p.email = d.partner_email
    where d.state = 'delivered'
      and d.payout_id is null
      and d.delivered_at is not null
      and p.engagement = 'freelance'
    group by d.partner_email,
             date_trunc('week', d.delivered_at at time zone 'Asia/Kolkata')
  loop
    -- Read inside the loop, not before it. A rider with two unpaid weeks
    -- produces two buckets, and the second must see the balance the first one
    -- already reduced — otherwise the same cash is netted twice and the rider
    -- is short a week's wages.
    --
    -- `greatest(…, 0)` because a balance can go negative: a rider who deposited
    -- more than they were holding, or an adjustment written to correct one. That
    -- is an over-payment to be sorted out by hand, not a licence for the batch
    -- to add it to this week's transfer.
    v_cash     := greatest(public.rider_cash_in_hand(b.partner_email), 0);
    v_withheld := least(v_cash, b.amount);

    insert into public.rider_payouts (
      partner_email, period_start, period_end, delivery_count,
      gross_amount, cash_withheld, amount,
      -- Nothing to transfer means nothing to reconcile, so a fully-netted week
      -- is closed here rather than sitting in the console's pending queue
      -- forever waiting for a UTR that will never exist. The reference says why
      -- in the same place every other reference says which bank line to look at.
      status, reference, paid_at
    ) values (
      b.partner_email, b.period_start, b.period_end, b.delivery_count,
      b.amount, v_withheld, b.amount - v_withheld,
      case when b.amount - v_withheld = 0 then 'paid' else 'pending' end,
      case when b.amount - v_withheld = 0
           then 'Settled in full against cash in hand' end,
      case when b.amount - v_withheld = 0 then now() end
    ) returning id into v_payout;

    -- The row that actually discharges the obligation. Without it the same cash
    -- would be netted off again next week, and the ledger would still say the
    -- rider owed money they have already worked off.
    if v_withheld > 0 then
      insert into public.rider_cash_ledger
        (partner_email, kind, amount, payout_id, note, recorded_by)
      values
        (b.partner_email, 'adjustment', -v_withheld, v_payout,
         'Netted off the payout for ' || b.period_start || ' to ' || b.period_end,
         'payout batch');
    end if;

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
$function$;

-- ------------------------------------------------------------ the admin side

create or replace function public.admin_set_rider_engagement(
  p_email      text,
  p_engagement text,
  p_employer   text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_email text := lower(p_email);
begin
  perform public.assert_admin();

  if p_engagement not in ('freelance', 'salaried', 'restaurant_owned') then
    raise exception 'Engagement must be freelance, salaried or restaurant_owned.';
  end if;

  -- Said here as well as in the check constraint, because a constraint
  -- violation reaches the console as a Postgres error nobody can act on and
  -- these two reach it as sentences.
  if p_engagement = 'restaurant_owned' and p_employer is null then
    raise exception 'A restaurant''s own rider needs the restaurant naming.';
  end if;

  if p_engagement <> 'restaurant_owned' and p_employer is not null then
    raise exception 'Only a restaurant''s own rider has an employer.';
  end if;

  if p_employer is not null
     and not exists (select 1 from public.restaurants r where r.id = p_employer) then
    raise exception 'No such restaurant.';
  end if;

  update public.delivery_partners
     set engagement             = p_engagement,
         employer_restaurant_id = p_employer
   where email = v_email;

  if not found then
    raise exception 'No such rider.';
  end if;
end;
$function$;

-- Extended, not replaced: three columns on the end so the console can show and
-- set the engagement. Every existing column keeps its position, because the
-- console reads these by name but a positional client would not.
--
-- Dropped rather than replaced because `create or replace` cannot change the
-- row type an OUT-parameter function returns. The argument list is unchanged,
-- so this creates no overload to bind wrongly — and the drop and the create
-- commit in one transaction, so there is no instant where the console finds
-- the function missing.
drop function if exists public.admin_list_riders();

create function public.admin_list_riders()
returns table(
  email text, name text, phone text, vehicle text, is_active boolean,
  created_at timestamp with time zone, live_order_id text,
  delivered_count integer, kyc_status text, kyc_blocked boolean,
  kyc_overridden boolean,
  engagement text, employer_restaurant_id text, employer_name text
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  perform public.assert_admin();

  return query
    select p.email, p.name, p.phone, p.vehicle, p.is_active, p.created_at,
           (select d.order_id
              from public.deliveries d
              join public.orders o on o.id = d.order_id
             where d.partner_email = p.email
               and d.state not in ('delivered', 'cancelled')
               and o.status not in ('delivered', 'cancelled', 'rejected')
             limit 1),
           (select count(*)::integer
              from public.deliveries d
             where d.partner_email = p.email
               and d.state = 'delivered'),
           coalesce(l.status, 'pending'),
           -- Not the same question as `status <> 'verified'`: a verified rider
           -- whose insurance lapsed last night is still 'verified' here and is
           -- still blocked, and the console needs to show the second thing.
           not public.rider_is_verified(p.email),
           -- And a third question again: *why* they are not blocked. A rider
           -- working on somebody's say-so should never be counted in the same
           -- breath as one whose papers were read.
           public.rider_override_active(p.email),
           p.engagement, p.employer_restaurant_id, e.name
      from public.delivery_partners p
      left join public.rider_legal l on l.partner_email = p.email
      left join public.restaurants e on e.id = p.employer_restaurant_id
     order by not public.rider_is_verified(p.email) desc,
              p.is_active desc, p.created_at;
end;
$function$;

-- 0087's standing rule: every function owned by postgres is born executable by
-- PUBLIC, and both anon and authenticated inherit from it. Revoking a role's
-- own grant leaves the one it inherits, so PUBLIC is the one that matters.
revoke execute on function public.admin_set_rider_engagement(text, text, text) from public, anon, authenticated;
revoke execute on function public.run_rider_payout_batch() from public, anon, authenticated;
revoke execute on function public.admin_list_riders() from public;

-- The console calls these as a signed-in admin; assert_admin() in the body is
-- what actually guards them. The batch is cron's alone.
grant execute on function public.admin_set_rider_engagement(text, text, text) to authenticated;
grant execute on function public.admin_list_riders() to authenticated;

-- ---------------------------------------------------------------- verification
-- Both standing release checks live in the footers of
-- `0087_a_revoke_that_did_nothing.sql` and `0089_a_grant_nobody_asked_for.sql`.
-- Run those two verbatim; both returned zero rows after this migration.
--
-- Do not paraphrase them. A `has_function_privilege('public', …)` sweep over
-- every function in the schema counts the extensions' own, and a bare grant
-- sweep counts privileges a policy correctly scopes — both report dozens of
-- false positives and teach the next reader to ignore a check that matters.
-- 0087 filters on `pg_get_userbyid(p.proowner) = 'postgres'` and an explicit
-- grantee of 0; 0089 excludes tables carrying a non-read policy. Those two
-- clauses are the whole point.
