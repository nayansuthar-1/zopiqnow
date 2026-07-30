-- ---------------------------------------------------------------------------
-- 0074 — a discount has somebody who pays for it. (Audit BIZ-001)
-- ---------------------------------------------------------------------------
-- 0017 defined the weekly rollup as `gross_sales = sum(orders.subtotal)`, and
-- that was correct on the day it was written: every coupon was issued by the
-- platform and funded by the platform, so what the restaurant sold and what the
-- restaurant is owed were the same number. `orders.discount` existed, was
-- populated, and was deliberately not referenced.
--
-- 0064 gave vendors the ability to create coupons scoped to their own menu, and
-- did not revisit who pays for one. The two migrations are individually right
-- and jointly wrong. A vendor can create FREEFOOD, 100% off, no minimum, on
-- their own restaurant. A customer orders ₹1,000 of food and pays ₹90 — the
-- delivery fee and the tax. At the rollup that order contributes
-- gross_sales 1000, commission 200, net_payable 800. The platform wires ₹800
-- against ₹90 collected, out of its own bank account, and the vendor console
-- shows a normal promotion. There is no cap, no budget, and no approval step,
-- so it repeats without bound.
--
-- The fix is to make funding a property of the coupon, freeze it onto the order
-- at purchase, and teach both ledgers to read it.
--
--   gross_sales            = sum(subtotal)                    -- what was sold
--   vendor_funded_discount = sum(discount) where the coupon was the vendor's
--   commission             = round((gross_sales - vendor_funded_discount) * bps)
--   net_payable            = gross_sales - vendor_funded_discount - commission
--
-- Commission is charged on what the restaurant actually earned, not on the
-- pre-discount menu price. Charging commission on money the vendor discounted
-- away would be its own kind of wrong, and the sort a partner notices.
--
-- WHY THE FUNDER IS FROZEN ONTO THE ORDER. `orders.coupon_code` is already
-- stored, so the rollup could join back to `coupons` and read `funded_by` there.
-- It must not. A coupon is a mutable row; a settled order is a financial record.
-- Re-reading the funder at rollup time means an edit made in week three silently
-- rewrites what was owed in week one, in whichever direction the editor happens
-- to choose. `orders.discount` is frozen for exactly this reason and the funder
-- travels with it.
--
-- BACKFILL. Every existing coupon becomes `platform`, and the two existing
-- discounted orders (₹100 between them, both against platform-wide codes) become
-- `platform` too. No vendor coupon has ever been created, so nothing is being
-- reclassified — but the rule would hold anyway: a coupon issued under the old
-- contract was issued on the platform's account, and retroactively charging a
-- restaurant for a discount nobody told them they were funding is not a
-- reconciliation, it is a surprise on an invoice.
--
-- NOT IN THIS MIGRATION. Coupon caps, budgets and a redemption ledger are
-- BIZ-003 and land next. This one makes each discount attributable; that one
-- makes it bounded. Both are needed and they are not the same change.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Who funds a coupon.
-- ---------------------------------------------------------------------------
alter table public.coupons
  add column if not exists funded_by text;

update public.coupons set funded_by = 'platform' where funded_by is null;

alter table public.coupons
  alter column funded_by set not null;

-- No default, on purpose. A default would mean a writer that forgets to say who
-- pays gets an answer anyway — and the answer it would get is the expensive one.
-- Both writers are updated below; there is no third.
alter table public.coupons
  drop constraint if exists coupon_funded_by_is_known;
alter table public.coupons
  add constraint coupon_funded_by_is_known
  check (funded_by in ('platform', 'restaurant'));

-- A platform-wide coupon cannot be restaurant-funded: there is no restaurant to
-- charge it to. The reverse is allowed — a restaurant-scoped coupon that the
-- platform pays for is a real thing (a launch promotion, a make-good).
alter table public.coupons
  drop constraint if exists coupon_funder_matches_scope;
alter table public.coupons
  add constraint coupon_funder_matches_scope
  check (funded_by = 'platform' or restaurant_id is not null);

comment on column public.coupons.funded_by is
  'Whose money this discount is. Platform coupons come out of the platform''s '
  'promotional spend; restaurant coupons are deducted from that restaurant''s '
  'weekly settlement before commission (0074, audit BIZ-001).';

-- ---------------------------------------------------------------------------
-- 2. The funder, frozen onto the order.
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists discount_funded_by text;

update public.orders
   set discount_funded_by = 'platform'
 where discount > 0 and discount_funded_by is null;

alter table public.orders
  drop constraint if exists order_discount_funder_is_known;
alter table public.orders
  add constraint order_discount_funder_is_known
  check (discount_funded_by is null or discount_funded_by in ('platform', 'restaurant'));

-- An order with a discount has a funder; an order without one does not. Stated
-- as a constraint because the settlement maths below reads the column and a null
-- would silently fall out of the `filter` as platform-funded.
alter table public.orders
  drop constraint if exists order_discount_has_a_funder;
alter table public.orders
  add constraint order_discount_has_a_funder
  check ((discount = 0) = (discount_funded_by is null));

comment on column public.orders.discount_funded_by is
  'Frozen at purchase from coupons.funded_by. Never re-read from the coupon: '
  'the coupon is editable and this is a financial record (0074).';

-- ---------------------------------------------------------------------------
-- 3. The two writers say who pays.
-- ---------------------------------------------------------------------------
-- `create or replace` with the identical argument list. Changing it would create
-- an overload and leave the app bound to whichever one PostgREST resolved first.
create or replace function public.admin_save_coupon(
  p_code         text,
  p_min_subtotal integer,
  p_flat_off     integer default null,
  p_percent_off  integer default null,
  p_max_off      integer default null,
  p_valid_until  timestamptz default null
) returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_code  text;
  v_owner text;
  v_found boolean;
begin
  perform public.assert_admin();

  -- Hyphens survive the strip, unlike 0064's, and that is the whole point. A
  -- vendor code *is* `<restaurant id>-<suffix>`, so stripping the hyphen turns
  -- `R1-SUMMER` into `R1SUMMER` — a code that does not exist, that the
  -- ownership check below therefore cannot see, and that gets happily created
  -- as a new platform coupon.
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9-]', '', 'g'));
  if length(v_code) < 3 or length(v_code) > 16 then
    raise exception 'A coupon code is 3 to 16 letters, numbers or hyphens.'
      using errcode = 'P0001';
  end if;

  if (p_flat_off is not null) = (p_percent_off is not null) then
    raise exception 'A coupon is either a flat amount off or a percentage, not both.'
      using errcode = 'P0001';
  end if;

  if p_flat_off is not null and p_flat_off <= 0 then
    raise exception 'A flat discount has to be more than ₹0.' using errcode = 'P0001';
  end if;

  if p_percent_off is not null
     and (p_percent_off <= 0 or p_percent_off > 100
          or p_max_off is null or p_max_off <= 0) then
    raise exception 'A percentage coupon needs a percentage from 1 to 100 and a cap.'
      using errcode = 'P0001';
  end if;

  if coalesce(p_min_subtotal, 0) < 0 then
    raise exception 'A minimum order value cannot be negative.' using errcode = 'P0001';
  end if;

  if p_valid_until is not null and p_valid_until <= now() then
    raise exception 'That end date has already passed.' using errcode = 'P0001';
  end if;

  if strpos(v_code, '-') > 1 and exists (
    select 1 from public.restaurants r
     where upper(r.id) = split_part(v_code, '-', 1)
  ) then
    raise exception 'Codes starting %- belong to that restaurant''s own offers. Pick another prefix.',
      split_part(v_code, '-', 1) using errcode = 'P0001';
  end if;

  select c.restaurant_id into v_owner from public.coupons c where c.code = v_code;
  v_found := found;

  if v_found and v_owner is not null then
    raise exception 'That code belongs to a restaurant''s own offer. Edit it from their account.'
      using errcode = 'P0001';
  end if;

  insert into public.coupons
    (code, restaurant_id, min_subtotal, flat_off, percent_off, max_off,
     valid_until, is_active, funded_by)
  values
    (v_code, null, coalesce(p_min_subtotal, 0), p_flat_off, p_percent_off,
     p_max_off, p_valid_until, true, 'platform')
  on conflict (code) do update
     set min_subtotal = excluded.min_subtotal,
         flat_off     = excluded.flat_off,
         percent_off  = excluded.percent_off,
         max_off      = excluded.max_off,
         valid_until  = excluded.valid_until;
         -- funded_by is deliberately not in the update list. A campaign that has
         -- already put discounts on receipts does not get its funder rewritten.

  return v_code;
end;
$function$;

create or replace function public.vendor_save_offer(
  p_code         text,
  p_min_subtotal integer,
  p_flat_off     integer default null,
  p_percent_off  integer default null,
  p_max_off      integer default null,
  p_valid_until  timestamptz default null
) returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_restaurant text;
  v_suffix     text;
  v_code       text;
  v_owner      text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You are not signed in to a restaurant.' using errcode = 'P0001';
  end if;

  if public.staff_role() <> 'owner' then
    raise exception 'Only the owner can run offers.' using errcode = 'P0001';
  end if;

  -- Letters and digits, upper-cased. A code with a space in it is a code
  -- somebody mistypes at checkout and blames us for.
  v_suffix := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(v_suffix) < 3 or length(v_suffix) > 16 then
    raise exception 'Give the offer a code of 3 to 16 letters or numbers.'
      using errcode = 'P0001';
  end if;

  v_code := upper(v_restaurant) || '-' || v_suffix;

  if (p_flat_off is not null) = (p_percent_off is not null) then
    raise exception 'An offer is either a flat amount off or a percentage, not both.'
      using errcode = 'P0001';
  end if;

  if p_flat_off is not null and p_flat_off <= 0 then
    raise exception 'A flat discount has to be more than ₹0.' using errcode = 'P0001';
  end if;

  if p_percent_off is not null
     and (p_percent_off <= 0 or p_percent_off > 100
          or p_max_off is null or p_max_off <= 0) then
    raise exception 'A percentage offer needs a percentage from 1 to 100 and a cap.'
      using errcode = 'P0001';
  end if;

  if coalesce(p_min_subtotal, 0) < 0 then
    raise exception 'A minimum order value cannot be negative.' using errcode = 'P0001';
  end if;

  if p_valid_until is not null and p_valid_until <= now() then
    raise exception 'That end date has already passed.' using errcode = 'P0001';
  end if;

  select restaurant_id into v_owner from public.coupons where code = v_code;
  if found and v_owner is distinct from v_restaurant then
    raise exception 'That code is already in use.' using errcode = 'P0001';
  end if;

  insert into public.coupons
    (code, restaurant_id, min_subtotal, flat_off, percent_off, max_off,
     valid_until, is_active, funded_by)
  values
    (v_code, v_restaurant, coalesce(p_min_subtotal, 0), p_flat_off, p_percent_off,
     p_max_off, p_valid_until, true, 'restaurant')
  on conflict (code) do update
     set min_subtotal = excluded.min_subtotal,
         flat_off     = excluded.flat_off,
         percent_off  = excluded.percent_off,
         max_off      = excluded.max_off,
         valid_until  = excluded.valid_until;
         -- As above: the funder of a live offer is not editable.

  return v_code;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. place_order freezes the funder alongside the discount.
-- ---------------------------------------------------------------------------
-- Only two statements change in a 190-line function, so this is a targeted
-- rewrite of those two rather than a re-paste of the whole body: a new
-- `v_funded_by` read next to the `validate_coupon` call, and the column added to
-- the insert. Everything else is 0064's text, unchanged.
do $$
declare
  v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order';

  if v_src is null then
    raise exception 'place_order not found — 0074 cannot patch what is not there.';
  end if;

  -- Idempotence, and not as a formality. This patch works by string replacement
  -- on the existing body, so a second run would happily insert a second copy of
  -- the funder read. Migrations get re-run — by a ledger reconciliation, by a
  -- from-zero apply in CI, by somebody being careful — and this one has to
  -- survive it.
  if position('c.funded_by into v_funded_by' in v_src) > 0 then
    raise notice '0074: place_order already carries the funder read; leaving it alone.';
    return;
  end if;

  -- Guard the assumptions. If 0064's text has moved on, fail loudly here rather
  -- than produce a function that silently writes no funder.
  if position('v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);' in v_src) = 0
     or position('coupon_code, payment_method, payment_id,' in v_src) = 0 then
    raise exception '0074: place_order does not look like 0064''s. Patch it by hand.';
  end if;

  v_src := replace(v_src,
    '  v_discount     integer := 0;',
    '  v_discount     integer := 0;' || E'\n' ||
    '  v_funded_by    text;');

  v_src := replace(v_src,
    '    v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);',
    '    v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);' || E'\n' ||
    '    -- Who pays for it, frozen here and never re-read from the coupon (0074).' || E'\n' ||
    '    -- Same scope predicate validate_coupon matched on, so this reads the row' || E'\n' ||
    '    -- that produced the discount and not a same-named one out of scope.' || E'\n' ||
    '    select c.funded_by into v_funded_by from public.coupons c' || E'\n' ||
    '      where c.code = upper(trim(p_coupon_code))' || E'\n' ||
    '        and (c.restaurant_id is null or c.restaurant_id = p_restaurant_id);');

  v_src := replace(v_src,
    '    coupon_code, payment_method, payment_id,',
    '    coupon_code, discount_funded_by, payment_method, payment_id,');

  v_src := replace(v_src,
    '    nullif(upper(trim(coalesce(p_coupon_code, ''''))), ''''), p_payment_method, p_payment_id,',
    '    nullif(upper(trim(coalesce(p_coupon_code, ''''))), ''''),' || E'\n' ||
    '    case when v_discount > 0 then v_funded_by end, p_payment_method, p_payment_id,');

  execute format(
    'create or replace function public.place_order('
    || 'p_user_phone text, p_restaurant_id text, p_items jsonb, p_delivery_to text, '
    || 'p_payment_method text, p_delivery_lat double precision default null, '
    || 'p_delivery_lng double precision default null, p_coupon_code text default null, '
    || 'p_payment_id text default null, p_delivery_notes text default null) '
    || 'returns jsonb language plpgsql security definer set search_path to ''public'' as %L',
    v_src);
end $$;

-- ---------------------------------------------------------------------------
-- 5. The settlement statement explains itself.
-- ---------------------------------------------------------------------------
alter table public.settlements
  add column if not exists vendor_funded_discount integer not null default 0;

alter table public.settlements
  drop constraint if exists settlements_vendor_funded_discount_check;
alter table public.settlements
  add constraint settlements_vendor_funded_discount_check
  check (vendor_funded_discount >= 0);

-- The constraint that makes a wrong rollup unwritable. Existing rows all carry
-- vendor_funded_discount = 0, so they satisfy the new form unchanged.
alter table public.settlements
  drop constraint if exists settlement_net_is_consistent;
alter table public.settlements
  add constraint settlement_net_is_consistent
  check (net_payable = gross_sales - vendor_funded_discount - commission);

comment on column public.settlements.vendor_funded_discount is
  'The part of this week''s discounts the restaurant issued itself. Deducted '
  'before commission, so the platform charges commission on what was actually '
  'earned rather than on the pre-discount menu price (0074, audit BIZ-001).';

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
  v_created    integer := 0;
begin
  for b in
    select
      o.restaurant_id                                          as restaurant_id,
      (date_trunc('week', o.created_at))::date                 as period_start,
      (date_trunc('week', o.created_at) + interval '6 days')::date as period_end,
      count(*)::integer                                        as order_count,
      sum(o.subtotal)::integer                                 as gross_sales,
      -- The whole finding, in one clause. `discount_funded_by` is frozen on the
      -- order, so this reads what was true when the customer paid.
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

    insert into public.settlements (
      restaurant_id, period_start, period_end,
      order_count, gross_sales, vendor_funded_discount, commission, net_payable
    ) values (
      b.restaurant_id, b.period_start, b.period_end,
      b.order_count, b.gross_sales, b.vendor_funded_discount, v_commission,
      v_net_sales - v_commission
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
$function$;

-- ---------------------------------------------------------------------------
-- 6. The vendor's own earnings screen agrees with the statement.
-- ---------------------------------------------------------------------------
-- `vendor_earnings_summary` carried the identical bug: gross, commission and net
-- all computed off `subtotal`. Left alone it would show a vendor one net figure
-- all week and pay them a different one on Monday — two ledgers disagreeing,
-- which is worse than either being wrong on its own.
create or replace function public.vendor_earnings_summary(p_from date, p_to date)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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
      sum(o.subtotal)::integer    as gross,
      coalesce(sum(o.discount) filter (
        where o.discount_funded_by = 'restaurant'
      ), 0)::integer              as own_offers
    from public.orders o
    where o.restaurant_id = v_restaurant
      and o.status = 'delivered'
      and o.created_at::date between p_from and p_to
    group by o.created_at::date
  ), totals as (
    select
      coalesce(sum(d.orders), 0)::integer     as order_count,
      coalesce(sum(d.gross), 0)::integer      as gross_sales,
      coalesce(sum(d.own_offers), 0)::integer as own_offers
    from daily d
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'commission_bps', v_bps,
    'order_count',  t.order_count,
    'gross_sales',  t.gross_sales,
    -- Named to match settlements.vendor_funded_discount, because a vendor
    -- comparing this screen to their statement should find the same word.
    'vendor_funded_discount', t.own_offers,
    'commission',   round((t.gross_sales - t.own_offers) * v_bps / 10000.0)::integer,
    'net_earnings', (t.gross_sales - t.own_offers)
                    - round((t.gross_sales - t.own_offers) * v_bps / 10000.0)::integer,
    'daily', coalesce(
      (select jsonb_agg(
        jsonb_build_object(
          'day',    d.day,
          'orders', d.orders,
          'gross',  d.gross,
          'vendor_funded_discount', d.own_offers,
          'net',    (d.gross - d.own_offers)
                    - round((d.gross - d.own_offers) * v_bps / 10000.0)::integer
        ) order by d.day
      ) from daily d),
      '[]'::jsonb
    )
  ) into v_result
  from totals t;

  return v_result;
end;
$function$;

-- The sweep in 0073 is now the standing rule, so a replaced function has to be
-- re-granted deliberately. All four are called by a signed-in client.
revoke execute on function
  public.admin_save_coupon(text, integer, integer, integer, integer, timestamptz),
  public.vendor_save_offer(text, integer, integer, integer, integer, timestamptz),
  public.vendor_earnings_summary(date, date)
  from public, anon;

grant execute on function
  public.admin_save_coupon(text, integer, integer, integer, integer, timestamptz),
  public.vendor_save_offer(text, integer, integer, integer, integer, timestamptz),
  public.vendor_earnings_summary(date, date)
  to authenticated, service_role;

-- The rollup is a runner. It stays ungranted by construction — the party being
-- paid must not be able to start its own payout (0017's rule, preserved).
revoke all on function public.run_settlement_batch() from public, anon, authenticated;
grant execute on function public.run_settlement_batch() to service_role;

-- ---------------------------------------------------------------------------
-- 7. The console can see a vendor-funded discount for what it is.
-- ---------------------------------------------------------------------------
-- The finding's last sentence: a vendor discounting at the platform's expense is
-- "indistinguishable from legitimate promotional activity in the admin console".
-- It is distinguishable now, on the row where the money is.
--
-- `drop` then `create`, not `create or replace`: the return type gains a column
-- and Postgres refuses to replace a function whose result type changed. The
-- argument list is identical, so no overload survives the drop.
drop function if exists public.admin_list_settlements(text);

create function public.admin_list_settlements(p_status text default null)
returns table (
  id bigint, restaurant_id text, restaurant_name text,
  period_start date, period_end date, order_count integer,
  gross_sales integer, vendor_funded_discount integer,
  commission integer, net_payable integer,
  status text, reference text, has_bank boolean, paid_at timestamptz
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  perform public.assert_admin();

  return query
    select s.id, s.restaurant_id, r.name, s.period_start, s.period_end,
           s.order_count, s.gross_sales, s.vendor_funded_discount,
           s.commission, s.net_payable,
           s.status, s.reference,
           (a.account_number is not null),
           s.paid_at
      from public.settlements s
      join public.restaurants r on r.id = s.restaurant_id
      left join public.restaurant_bank_accounts a on a.restaurant_id = s.restaurant_id
     where p_status is null or s.status = p_status
     order by s.status = 'paid', s.period_end desc, r.name;
end;
$function$;

revoke all on function public.admin_list_settlements(text) from public, anon;
grant execute on function public.admin_list_settlements(text) to authenticated, service_role;
