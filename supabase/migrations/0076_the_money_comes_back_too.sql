-- ---------------------------------------------------------------------------
-- 0076 — the money comes back too. (Audit BIZ-002)
-- ---------------------------------------------------------------------------
-- `payment_method` has accepted 'cod' since 0003 and a COD order runs the exact
-- lifecycle a UPI one does. On a ₹500 cash order the customer hands ₹500 in
-- notes to the rider; `confirm_delivered` marks it delivered and nothing else
-- happens. Then `run_rider_payout_batch` pays the rider their fee and
-- `run_settlement_batch` pays the vendor `subtotal − commission`, both from
-- platform funds, while the ₹500 stays in a pocket that no table in this schema
-- knows about. Searching all 75 migrations and all 325 Dart files for cash
-- collected, cash in hand or a deposit finds one SVG icon.
--
-- The loss on a COD order is therefore the whole order value, and COD is
-- typically a quarter to two-fifths of volume at launch in this market.
--
-- WHAT WAS ACTUALLY MODELLED WRONG. Cash was treated as a property of an order —
-- a column saying how it would be paid for — rather than as an obligation on a
-- rider. 0049's lifecycle is rigorous and it closes at "the food changed hands".
-- There has never been a step for the money changing hands the other way.
--
-- THE BALANCE IS NEVER STORED. `rider_cash_ledger` holds signed rows and cash in
-- hand is `sum(amount)`. There is deliberately no `delivery_partners.cash_held`
-- column to fall out of step with the rows that justify it — the same reason
-- 0045 recomputes a payout from the deliveries rather than incrementing a
-- running total, and the same reason a coupon's redemption count in 0075 is
-- counted rather than kept. Collections are positive, deposits and payout
-- netting are negative, and a balance that cannot be written cannot drift.
--
-- FIVE PLACES, BECAUSE A LEDGER NOBODY ACTS ON IS A REPORT.
--   1. `confirm_delivered` writes the collection in the same transaction that
--      marks the order delivered. Delivery and collection become one fact.
--   2. `claim_delivery` refuses a COD job that would put the rider over the
--      ceiling — and because `accept_offer` calls straight into it, the offer
--      path is covered by the same four lines. `offer_delivery` and
--      `available_deliveries` filter to match, so a rider is not shown a job the
--      claim would then refuse.
--   3. `run_rider_payout_batch` nets the outstanding cash off the week's pay,
--      floored at zero, and writes the adjustment row that discharges it. What
--      the netting could not cover stays outstanding and is carried.
--   4. `admin_set_rider_active` refuses to deactivate a rider still holding
--      money, with `admin_adjust_rider_cash` as the deliberate way out — a guard
--      with no escape hatch is how one bad row pins a rider to the roster
--      forever, which is the trap 0066 had to unpick for live deliveries.
--   5. The console gets the reconciliation screen: every rider's balance, the
--      deposit action, and the ledger behind the number.
--
-- WHAT THIS IS NOT. It is not a fix for PAY-001. Online payment is still a mock
-- and a UPI order still moves no money; this closes the hole under the payment
-- method that *does* move money today, which is the one that is live.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The ledger.
-- ---------------------------------------------------------------------------
-- Three kinds and one sign convention: `sum(amount)` is cash in hand, always.
-- Collections are positive because the rider took money; deposits and payout
-- netting are negative because they gave it back. Storing deposits positive and
-- subtracting them in every reader is the version where one reader eventually
-- forgets, and the number it prints is a rider's wages.
create table if not exists public.rider_cash_ledger (
  id            bigserial primary key,
  partner_email text not null references public.delivery_partners (email),

  kind          text not null check (kind in ('collected', 'deposited', 'adjustment')),

  -- Signed, whole rupees, like every money column in this schema.
  amount        integer not null,

  -- Set on a collection. The order the cash came from.
  order_id      text references public.orders (id),

  -- Set on the adjustment the payout batch writes. The batch that absorbed it.
  payout_id     bigint references public.rider_payouts (id),

  -- The bank's reference for a deposit. Required, for exactly the reason 0045
  -- requires one on a payout: a settlement with nothing to look up on a
  -- statement cannot be reconciled by anybody, ever.
  reference     text,

  note          text,

  -- Who wrote it. An admin's email for a deposit or an adjustment; the batch
  -- names itself.
  recorded_by   text,

  created_at    timestamptz not null default now(),

  constraint cash_collection_is_an_order check (
    kind <> 'collected' or (order_id is not null and amount > 0)
  ),
  constraint cash_deposit_has_a_reference check (
    kind <> 'deposited'
    or (reference is not null and amount < 0 and order_id is null)
  ),
  -- An adjustment is the manual override, so it is the one that has to explain
  -- itself. A zero adjustment is somebody having second thoughts halfway
  -- through, not a fact.
  constraint cash_adjustment_is_explained check (
    kind <> 'adjustment' or (amount <> 0 and note is not null)
  )
);

-- One collection per order, enforced by the index rather than by the function
-- that writes it. `confirm_delivered` cannot reach its insert twice — the
-- delivery has left `arrived_at_customer` by then — but "cannot happen" is a
-- statement about today's call sites and this is a statement about the data.
create unique index if not exists rider_cash_one_collection_per_order
  on public.rider_cash_ledger (order_id)
  where kind = 'collected';

create index if not exists rider_cash_by_partner_idx
  on public.rider_cash_ledger (partner_email, created_at desc);

-- RLS on, no policies, no grants — the shape 0045 gave
-- `delivery_partner_bank_accounts`, for a related reason. Every read below goes
-- through a `security definer` function that decides what the caller may see:
-- a rider gets their own total, an admin gets the roster. Supabase grants
-- insert, update and delete on a new table to `anon` and `authenticated` by
-- default, which is how `coupons` spent 61 migrations writable by the anon key
-- (0064). Revoked before it can happen again.
alter table public.rider_cash_ledger enable row level security;

revoke all on table public.rider_cash_ledger from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. The ceiling.
-- ---------------------------------------------------------------------------
-- One row, platform-wide, exactly as `rider_pay_rates` is (0043) — including
-- being unreadable by riders, who are told their own headroom by the function
-- below rather than handed the policy.
--
-- ₹3,000 is the low end of the Indian norm and the right end to start at: the
-- cost of a ceiling set too low is a rider making a deposit sooner than they
-- would like, and the cost of one set too high is the entire loss this
-- migration exists to bound.
create table if not exists public.rider_cash_policy (
  id         integer primary key default 1 check (id = 1),
  cap        integer not null check (cap > 0),
  updated_at timestamptz not null default now()
);

insert into public.rider_cash_policy (id, cap)
values (1, 3000)
on conflict (id) do nothing;

alter table public.rider_cash_policy enable row level security;

revoke all on table public.rider_cash_policy from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. The two questions everything else asks.
-- ---------------------------------------------------------------------------
-- Internal. Both are called from `security definer` functions that have already
-- established who the caller is and what they may know; neither is granted to
-- anybody, so neither can be asked about a rider by somebody who is not them.
create or replace function public.rider_cash_in_hand(p_email text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(amount), 0)::integer
    from public.rider_cash_ledger
   where partner_email = p_email;
$$;

revoke all on function public.rider_cash_in_hand(text) from public, anon, authenticated;

create or replace function public.rider_cash_cap()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select cap from public.rider_cash_policy where id = 1;
$$;

revoke all on function public.rider_cash_cap() from public, anon, authenticated;

-- What the rider's own screen shows. Their balance and the ceiling it is
-- measured against, because "₹2,400" on its own is not information — "₹2,400 of
-- ₹3,000" is the number that tells somebody to go and deposit.
create or replace function public.my_cash_in_hand()
returns table (
  outstanding integer,
  cap         integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  return query
    select public.rider_cash_in_hand(v_rider), public.rider_cash_cap();
end;
$$;

revoke all on function public.my_cash_in_hand() from public, anon;
grant execute on function public.my_cash_in_hand() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Handing the food over is also taking the money.
-- ---------------------------------------------------------------------------
-- The live 0049 body, unchanged, plus the order's payment method and total read
-- in the same statement that already reads its status, and one insert.
--
-- Inside the same transaction on purpose. A collection row written afterwards by
-- a second call is a collection that a dropped connection can lose while the
-- order still says delivered, which is the failure mode the whole finding
-- describes — money moving with no record of it.
create or replace function public.confirm_delivered(p_order_id text, p_otp text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_status   text;
  v_code     text;
  v_attempts integer;
  v_method   text;
  v_total    integer;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select o.status, o.payment_method, o.total
    into v_status, v_method, v_total
    from public.deliveries d
    join public.orders o on o.id = d.order_id
   where d.order_id = p_order_id
     and d.partner_email = v_rider
     and d.state = 'arrived_at_customer'
   for update of d;

  if not found then
    raise exception
      'Tap "I''ve arrived" at the customer before completing the delivery.'
      using errcode = 'P0001';
  end if;

  -- 0041's check, kept: an order that is not out for delivery cannot arrive.
  if v_status <> 'out_for_delivery' then
    raise exception 'That order is %, so it can''t be marked delivered.', v_status
      using errcode = 'P0001';
  end if;

  select delivery_code, delivery_attempts into v_code, v_attempts
    from public.delivery_codes
   where order_id = p_order_id
   for update;

  if not found then
    raise exception 'That order has no delivery code.' using errcode = 'P0001';
  end if;

  if v_attempts >= 5 then
    return 'locked';
  end if;

  if p_otp is distinct from v_code then
    update public.delivery_codes
       set delivery_attempts = delivery_attempts + 1, updated_at = now()
     where order_id = p_order_id;

    return case when v_attempts + 1 >= 5 then 'locked' else 'wrong_code' end;
  end if;

  update public.deliveries
     set state = 'delivered', delivered_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'arrived_at_customer';

  update public.orders set status = 'delivered' where id = p_order_id;

  -- The order total, not the subtotal and not the rider's fee: what the
  -- customer was asked to pay is what the customer handed over. The rider's own
  -- pay for the run is settled weekly and separately, and netting the two here
  -- would be a rider paying themselves out of somebody's dinner money.
  if v_method = 'cod' then
    insert into public.rider_cash_ledger
      (partner_email, kind, amount, order_id, recorded_by)
    values
      (v_rider, 'collected', v_total, p_order_id, 'delivery')
    on conflict (order_id) where kind = 'collected' do nothing;
  end if;

  return 'ok';
end;
$$;

revoke all on function public.confirm_delivered(text, text) from public, anon;
grant execute on function public.confirm_delivered(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The ceiling, where a job is taken.
-- ---------------------------------------------------------------------------
-- The live 0049 body plus one guard. `accept_offer` (0056) does its own bookkeeping
-- and then calls straight into this, so putting the rule here rather than in both
-- means the offer path and the board path cannot disagree about it — the same
-- reasoning 0049 used for the offline check that sits four lines above it.
--
-- Refused rather than capped-and-allowed. A rider carrying more cash than the
-- platform is willing to be owed is the exposure; letting them take "just one
-- more" is how a ceiling becomes a suggestion.
create or replace function public.claim_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_online   boolean;
  v_status   text;
  v_id       bigint;
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_d_lat    double precision;
  v_d_lng    double precision;
  v_route_km numeric(6,2);
  v_base     integer;
  v_per_km   numeric(6,2);
  v_distance numeric(6,2);
  v_method   text;
  v_total    integer;
  v_cash     integer;
  v_cap      integer;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select is_online into v_online
    from public.delivery_partners where email = v_rider;

  if not coalesce(v_online, false) then
    raise exception 'You are offline. Go online to take deliveries.'
      using errcode = 'P0001';
  end if;

  select o.status, r.latitude, r.longitude, o.delivery_lat, o.delivery_lng,
         o.route_km, o.payment_method, o.total
    into v_status, v_r_lat, v_r_lng, v_d_lat, v_d_lng,
         v_route_km, v_method, v_total
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found then
    raise exception 'That order no longer exists.' using errcode = 'P0001';
  end if;

  if v_status not in ('preparing', 'ready_for_pickup') then
    raise exception 'That order is no longer available.' using errcode = 'P0001';
  end if;

  if v_method = 'cod' then
    v_cash := public.rider_cash_in_hand(v_rider);
    v_cap  := public.rider_cash_cap();

    if v_cash + v_total > v_cap then
      raise exception
        'You''re holding ₹% in cash and this order collects ₹%, which is over the ₹% limit. Deposit what you''re carrying to take cash orders again.',
        v_cash, v_total, v_cap
        using errcode = 'P0001';
    end if;
  end if;

  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;

  -- The road distance if we have it; the straight line if we do not.
  v_distance := coalesce(
    v_route_km,
    public.delivery_distance_km(v_r_lat, v_r_lng, v_d_lat, v_d_lng)
  );

  insert into public.deliveries (
    order_id, partner_email,
    distance_km, pay_base, pay_per_km, rider_pay
  )
  values (
    p_order_id,
    v_rider,
    v_distance,
    v_base,
    v_per_km,
    v_base + round(coalesce(v_distance, 0) * v_per_km)::integer
  )
  on conflict do nothing
  returning id into v_id;

  -- The index decided it, not us. Write the codes only for the winner.
  if v_id is null then
    raise exception 'Another partner just took that one.' using errcode = 'P0001';
  end if;

  insert into public.delivery_codes (order_id, pickup_code, delivery_code)
  values (
    p_order_id,
    lpad((floor(random() * 10000))::integer::text, 4, '0'),
    lpad((floor(random() * 10000))::integer::text, 4, '0')
  )
  on conflict (order_id) do update
     set pickup_code       = excluded.pickup_code,
         delivery_code     = excluded.delivery_code,
         pickup_attempts   = 0,
         delivery_attempts = 0,
         updated_at        = now();
end;
$$;

revoke all on function public.claim_delivery(text) from public, anon;
grant execute on function public.claim_delivery(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Not offering what the claim would refuse.
-- ---------------------------------------------------------------------------
-- Both reads are filtered to agree with rule 5. Without this the dispatcher's
-- nearest-rider ranking would keep picking a rider who is over the ceiling, they
-- would decline or fail, and the order would work its way down the fleet one
-- twenty-second countdown at a time — an outage produced entirely by a rule that
-- was right.
--
-- The board is filtered rather than annotated: a job a rider cannot take is not
-- information they can act on, and a greyed-out card with an explanation is a
-- third place for the ceiling to be stated and to eventually be stated wrongly.
create or replace function public.offer_delivery(p_order_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_dist     numeric(6,2);
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_name     text;
  v_status   text;
  v_pay      integer;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_route    numeric(6,2);
  v_method   text;
  v_total    integer;
  v_cap      integer;
begin
  -- The order still has to be one that wants a rider. Checked here as well as
  -- in the sweeper because `decline_offer` calls straight into this function,
  -- and an order cancelled between the offer and the decline must not be
  -- handed to somebody else.
  select o.status, r.name, r.latitude, r.longitude,
         coalesce(
           o.route_km,
           public.delivery_distance_km(r.latitude, r.longitude,
                                       o.delivery_lat, o.delivery_lng)
         ),
         o.payment_method, o.total
    into v_status, v_name, v_r_lat, v_r_lng, v_route, v_method, v_total
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found or v_status not in ('preparing', 'ready_for_pickup') then
    return null;
  end if;

  if exists (
    select 1 from public.deliveries d
     where d.order_id = p_order_id and d.state <> 'cancelled'
  ) then
    return null;
  end if;

  -- What the job pays, at today's rate and this order's distance. Shown in the
  -- offer, and deliberately computed the same way `claim_delivery` will compute
  -- it a moment later — a fee quoted in the offer that differs from the fee on
  -- the accepted job is the single fastest way to lose a fleet's trust.
  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;
  v_pay := v_base + round(coalesce(v_route, 0) * v_per_km)::integer;

  v_cap := public.rider_cash_cap();

  select cand.email, cand.km
    into v_rider, v_dist
    from (
      select p.email,
             public.delivery_distance_km(l.lat, l.lng, v_r_lat, v_r_lng) as km,
             (select count(*) from public.deliveries d
               where d.partner_email = p.email
                 and d.state in ('claimed', 'arrived_at_restaurant',
                                 'picked_up', 'arrived_at_customer')
             ) as live_jobs
        from public.delivery_partners p
        left join public.rider_locations l on l.partner_email = p.email
       where p.is_active
         and p.is_online
         -- Evaluated per candidate, which is a sum over one rider's ledger rows
         -- on an indexed column, and only for a cash order. A fleet is hundreds
         -- of rows, not millions.
         and (v_method <> 'cod'
              or public.rider_cash_in_hand(p.email) + v_total <= v_cap)
    ) cand
   where cand.live_jobs < 3
     and not exists (
       select 1 from public.delivery_offers o
        where o.order_id = p_order_id and o.partner_email = cand.email
     )
     and not exists (
       select 1 from public.delivery_offers o
        where o.partner_email = cand.email
          and o.state = 'offered'
          and o.expires_at > now()
     )
   -- Idle riders first, then nearest. `nulls last` is what keeps a rider whose
   -- app has never reported a position from being treated as zero kilometres
   -- away and winning every job in the city.
   order by cand.live_jobs, cand.km nulls last, cand.email
   limit 1;

  if v_rider is null then
    return null;
  end if;

  insert into public.delivery_offers
    (order_id, partner_email, distance_km, expires_at)
  values
    (p_order_id, v_rider, v_dist, now() + public.delivery_offer_window())
  -- Two sweeper ticks overlapping, or a decline racing the sweep. The index is
  -- what decides it; losing simply means somebody else's offer is already live.
  on conflict do nothing;

  if not found then
    return null;
  end if;

  -- The push. `data` carries the numbers so the sheet can draw itself from the
  -- notification alone — a rider woken by this is on a lock screen, and a sheet
  -- that has to round-trip before it can show a countdown has already spent the
  -- seconds it is counting.
  begin
    insert into public.notifications
      (audience, partner_email, kind, title, body, order_id, data)
    values
      ('rider', v_rider, 'job_offer',
       'New delivery — ₹' || v_pay,
       'Pick up from ' || v_name ||
         case when v_dist is null then ''
              else ' · ' || v_dist || ' km away' end,
       p_order_id,
       jsonb_build_object(
         'order_id',    p_order_id,
         'restaurant',  v_name,
         'pay',         v_pay,
         'route_km',    v_route,
         'to_pickup_km', v_dist,
         'expires_at',  to_char(
                          (now() + public.delivery_offer_window())
                            at time zone 'UTC',
                          'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                        )
       ));
  exception when others then
    -- 0021's rule, kept: the offer is the event, the push is a courtesy on top
    -- of it. A rider who missed the buzz still finds the offer in the app.
    null;
  end;

  return v_rider;
end;
$$;

-- Cron and the two response functions call this in their own definer context.
-- Nothing signed in has any business dispatching a job to somebody.
revoke all on function public.offer_delivery(text) from public, anon, authenticated;

create or replace function public.available_deliveries()
returns table (
  order_id        text,
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  total           integer,
  payment_method  text,
  status          text,
  route_km        numeric,
  rider_pay       integer,
  ready_by        timestamptz,
  placed_at       timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base     integer;
  v_per_km   numeric(6,2);
  v_email    text;
  v_headroom integer;
begin
  v_email := public.delivery_partner_email();
  if v_email is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;

  -- How much more cash this rider may be holding. Computed once here rather
  -- than per row: it does not change while the query runs.
  v_headroom := public.rider_cash_cap() - public.rider_cash_in_hand(v_email);

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status,
           km.value,
           v_base + round(coalesce(km.value, 0) * v_per_km)::integer,
           o.ready_by, o.created_at
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
      cross join lateral (
        select coalesce(
                 o.route_km,
                 public.delivery_distance_km(r.latitude, r.longitude,
                                             o.delivery_lat, o.delivery_lng)
               ) as value
      ) km
     where o.status in ('preparing', 'ready_for_pickup')
       and (o.payment_method <> 'cod' or o.total <= v_headroom)
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = o.id and d.state <> 'cancelled'
       )
       and not exists (
         select 1 from public.delivery_offers off
          where off.order_id = o.id
            and off.state = 'offered'
            and off.expires_at > now()
       )
     order by (o.status = 'ready_for_pickup') desc, o.created_at;
end;
$$;

revoke all on function public.available_deliveries() from public, anon;
grant execute on function public.available_deliveries() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. The payout settles the cash first.
-- ---------------------------------------------------------------------------
-- `amount` keeps its meaning as *what is transferred*, which is what the console
-- pays and what the rider's app calls a payout. The week's earnings move to
-- `gross_amount` and the difference is named. Three numbers where 0045 had one,
-- and the constraint says how they relate so nothing can write a statement that
-- does not add up.
alter table public.rider_payouts
  add column if not exists gross_amount  integer,
  add column if not exists cash_withheld integer not null default 0;

-- Every payout that already exists was struck before any cash was tracked, so
-- its gross is its net by definition.
update public.rider_payouts set gross_amount = amount where gross_amount is null;

alter table public.rider_payouts
  alter column gross_amount set not null;

alter table public.rider_payouts
  drop constraint if exists payout_nets_the_cash;
alter table public.rider_payouts
  add constraint payout_nets_the_cash check (
    gross_amount >= 0
    and cash_withheld >= 0
    and amount = gross_amount - cash_withheld
  );

comment on column public.rider_payouts.gross_amount is
  'What the week''s deliveries earned, before cash in hand was netted off '
  '(0076). This is the number 0045''s `amount` used to hold.';
comment on column public.rider_payouts.cash_withheld is
  'How much of `gross_amount` was kept back against COD cash the rider was '
  'still holding. The matching negative row in `rider_cash_ledger` is what '
  'discharges the obligation (0076).';

create or replace function public.run_rider_payout_batch()
returns integer
language plpgsql
security definer
set search_path = public
as $$
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
    where d.state = 'delivered'
      and d.payout_id is null
      and d.delivered_at is not null
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
$$;

revoke all on function public.run_rider_payout_batch() from public, anon, authenticated;

-- The payout list learns the two new numbers. Return shape changes, so this is a
-- drop and recreate.
drop function if exists public.admin_list_rider_payouts(text);

create function public.admin_list_rider_payouts(p_status text default null)
returns table (
  id             bigint,
  partner_email  text,
  partner_name   text,
  period_start   date,
  period_end     date,
  delivery_count integer,
  gross_amount   integer,
  cash_withheld  integer,
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
           p.delivery_count, p.gross_amount, p.cash_withheld, p.amount,
           p.status, p.reference,
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

revoke all on function public.admin_list_rider_payouts(text) from public, anon;
grant execute on function public.admin_list_rider_payouts(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. A rider holding money stays on the roster.
-- ---------------------------------------------------------------------------
-- The live 0066 body plus a second reason to refuse. Deactivation is how ops
-- ends a relationship, and ending it while the platform's cash is in somebody's
-- pocket writes the loss off silently. `admin_adjust_rider_cash` below is the
-- way to write it off *loudly*, with a sentence saying who decided to.
--
-- Going *offline* is untouched: a rider ending a shift with cash on them is a
-- normal evening, and refusing it would strand them online.
create or replace function public.admin_set_rider_active(p_email text, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_order text;
  v_cash  integer;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));

  if not p_active then
    select d.order_id into v_order
      from public.deliveries d
      join public.orders o on o.id = d.order_id
     where d.partner_email = v_email
       and d.state not in ('delivered', 'cancelled')
       and o.status not in ('delivered', 'cancelled', 'rejected')
     limit 1;

    if v_order is not null then
      -- The message changes with this migration, because the answer does. Until
      -- now the only way out was the rider's own app — useless in the case this
      -- guard exists for, which is a rider who has stopped answering.
      raise exception
        'They are carrying order %. Release it from the live orders screen first, or the order cannot be delivered by anyone.',
        v_order using errcode = 'P0001';
    end if;

    v_cash := public.rider_cash_in_hand(v_email);
    if v_cash > 0 then
      raise exception
        'They are still holding ₹% of the platform''s cash. Record the deposit on the cash screen, or write it off there, before deactivating them.',
        v_cash using errcode = 'P0001';
    end if;
  end if;

  update public.delivery_partners
     set is_active = p_active
   where email = v_email;

  if not found then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.admin_set_rider_active(text, boolean) from public, anon;
grant execute on function public.admin_set_rider_active(text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. The reconciliation screen.
-- ---------------------------------------------------------------------------
-- Every rider, not only the ones holding something. "Nobody is carrying cash" is
-- a thing ops needs to be able to see, and a screen that is empty when all is
-- well is indistinguishable from one that is broken.
create or replace function public.admin_rider_cash()
returns table (
  partner_email     text,
  partner_name      text,
  phone             text,
  is_active         boolean,
  outstanding       integer,
  collected_total   integer,
  deposited_total   integer,
  adjusted_total    integer,
  collections       integer,
  last_collected_at timestamptz,
  last_deposit_at   timestamptz,
  cap               integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select p.email, p.name, p.phone, p.is_active,
           coalesce(l.outstanding, 0),
           coalesce(l.collected, 0),
           -- Reported positive. The ledger stores a deposit negative so the
           -- balance is a plain sum; a column headed "deposited" showing a
           -- minus sign is arithmetic leaking into a screen.
           coalesce(-l.deposited, 0),
           coalesce(l.adjusted, 0),
           coalesce(l.collections, 0),
           l.last_collected_at,
           l.last_deposit_at,
           public.rider_cash_cap()
      from public.delivery_partners p
      left join lateral (
        select sum(c.amount)::integer                                  as outstanding,
               sum(c.amount) filter (where c.kind = 'collected')::integer  as collected,
               sum(c.amount) filter (where c.kind = 'deposited')::integer  as deposited,
               sum(c.amount) filter (where c.kind = 'adjustment')::integer as adjusted,
               count(*) filter (where c.kind = 'collected')::integer    as collections,
               max(c.created_at) filter (where c.kind = 'collected')    as last_collected_at,
               max(c.created_at) filter (where c.kind = 'deposited')    as last_deposit_at
          from public.rider_cash_ledger c
         where c.partner_email = p.email
      ) l on true
     order by coalesce(l.outstanding, 0) desc, p.is_active desc, p.name;
end;
$$;

revoke all on function public.admin_rider_cash() from public, anon;
grant execute on function public.admin_rider_cash() to authenticated;

-- The rows behind one rider's number. Bounded, because a ledger grows one row
-- per cash delivery forever and a reconciliation screen wants the recent end of
-- it — PERF-002's rule, applied to a table on the day it is created rather than
-- retrofitted.
create or replace function public.admin_rider_cash_ledger(
  p_email text,
  p_limit integer default 100
)
returns table (
  id          bigint,
  kind        text,
  amount      integer,
  order_id    text,
  payout_id   bigint,
  reference   text,
  note        text,
  recorded_by text,
  created_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select c.id, c.kind, c.amount, c.order_id, c.payout_id,
           c.reference, c.note, c.recorded_by, c.created_at
      from public.rider_cash_ledger c
     where c.partner_email = lower(trim(p_email))
     order by c.created_at desc, c.id desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

revoke all on function public.admin_rider_cash_ledger(text, integer) from public, anon;
grant execute on function public.admin_rider_cash_ledger(text, integer) to authenticated;

-- Money handed in. Takes the amount positive, because that is how somebody
-- counting notes on a desk says it, and stores it negative.
create or replace function public.admin_record_cash_deposit(
  p_email     text,
  p_amount    integer,
  p_reference text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_ref   text;
  v_cash  integer;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));
  v_ref   := nullif(trim(coalesce(p_reference, '')), '');

  if not exists (select 1 from public.delivery_partners where email = v_email) then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;

  if coalesce(p_amount, 0) <= 0 then
    raise exception 'A deposit has to be more than zero.' using errcode = 'P0001';
  end if;

  if v_ref is null then
    raise exception
      'Add the reference — the slip number, the UTR, or whoever took the cash. A deposit nobody can trace is not a record.'
      using errcode = 'P0001';
  end if;

  v_cash := public.rider_cash_in_hand(v_email);

  -- Refused rather than allowed-and-flagged. A deposit larger than the balance
  -- is a mistyped figure far more often than it is a real over-payment, and the
  -- real one has `admin_adjust_rider_cash` to say so deliberately.
  if p_amount > v_cash then
    raise exception
      'They are holding ₹%, so ₹% cannot be a deposit. Check the figure, or use an adjustment if this is a correction.',
      v_cash, p_amount using errcode = 'P0001';
  end if;

  insert into public.rider_cash_ledger
    (partner_email, kind, amount, reference, recorded_by)
  values
    (v_email, 'deposited', -p_amount, v_ref,
     lower(auth.jwt() ->> 'email'));
end;
$$;

revoke all on function public.admin_record_cash_deposit(text, integer, text) from public, anon;
grant execute on function public.admin_record_cash_deposit(text, integer, text) to authenticated;

-- The escape hatch, and the only signed write in the ledger. A rider who
-- disappeared with ₹800, a deposit banked twice, a collection recorded against
-- the wrong order — all of them are corrections somebody decided to make, so the
-- note is required and the person is recorded.
create or replace function public.admin_adjust_rider_cash(
  p_email  text,
  p_amount integer,
  p_note   text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_note  text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));
  v_note  := nullif(trim(coalesce(p_note, '')), '');

  if not exists (select 1 from public.delivery_partners where email = v_email) then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;

  if coalesce(p_amount, 0) = 0 then
    raise exception 'An adjustment of zero changes nothing.' using errcode = 'P0001';
  end if;

  if v_note is null then
    raise exception 'Say why. An unexplained adjustment to somebody''s cash balance is the thing this ledger exists to prevent.'
      using errcode = 'P0001';
  end if;

  insert into public.rider_cash_ledger
    (partner_email, kind, amount, note, recorded_by)
  values
    (v_email, 'adjustment', p_amount, v_note,
     lower(auth.jwt() ->> 'email'));
end;
$$;

revoke all on function public.admin_adjust_rider_cash(text, integer, text) from public, anon;
grant execute on function public.admin_adjust_rider_cash(text, integer, text) to authenticated;

create or replace function public.admin_set_rider_cash_cap(p_cap integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if coalesce(p_cap, 0) <= 0 then
    raise exception 'The cash limit has to be more than zero.' using errcode = 'P0001';
  end if;

  update public.rider_cash_policy
     set cap = p_cap, updated_at = now()
   where id = 1;
end;
$$;

revoke all on function public.admin_set_rider_cash_cap(integer) from public, anon;
grant execute on function public.admin_set_rider_cash_cap(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- What is still owed after this.
-- ---------------------------------------------------------------------------
-- Nothing backfills the cash already collected on COD orders delivered before
-- this migration. It is deliberate and it is the honest choice: the ledger would
-- be asserting that a rider is holding money that was in fact handed over weeks
-- ago and reconciled, if at all, in somebody's head. The balance starts at zero
-- for everyone and is true from here.
--
-- BIZ-007 is still open and now visible from this side: the payout batch nets
-- cash against wages the same week, with no hold period, so a refund (BIZ-004)
-- still has nothing to claw back from. That is the next money item after
-- PAY-001, not a gap in this one.
-- ---------------------------------------------------------------------------
