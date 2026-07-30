-- ---------------------------------------------------------------------------
-- 0075 — a code runs out. (Audit BIZ-003)
-- ---------------------------------------------------------------------------
-- `coupons` has carried code, min_subtotal, flat_off, percent_off, max_off,
-- is_active, restaurant_id and valid_until since 0003. There is no
-- max_redemptions, no max_per_user, no valid_from, no first_order_only and no
-- redemption log. `validate_coupon` checks that the code exists, is active, is
-- in scope, has not expired, and that the subtotal clears the minimum. Nothing
-- else.
--
-- So a ₹150-off welcome code is a ₹150-off every-order-forever code, for every
-- user, simultaneously. There is no way to run a capped campaign, no way to stop
-- a code that leaks to a deals forum short of deactivating it, and no way to
-- answer "what did that campaign cost?" afterwards. With 0074 it is at least
-- attributable; it is still unbounded, and 0074 is what makes bounding it worth
-- doing — a vendor-funded discount with no cap is a vendor's own bank account
-- with no cap.
--
-- The data already shows it. Of two discounted orders in the table, both are
-- WELCOME50 and both belong to the same customer.
--
-- WHAT A CAP HAS TO SURVIVE. Two devices tapping "Place order" at the same
-- moment. A check inside a function loses that race — both read a count of
-- zero, both write. So the count is taken with the coupon row held under
-- `select … for update`, which serialises redemptions of a given code for the
-- length of the transaction that is placing the order, and the one-per-user case
-- is additionally carried by a partial unique index, which does not depend on
-- anybody having remembered to take the lock.
--
-- THE ENUMERATION ORACLE. The finding also notes `validate_coupon` is granted to
-- anon with no rate limit, so the code namespace can be brute-forced at whatever
-- rate PostgREST will serve. It is granted to anon because 0073 kept it there,
-- and 0073 kept it there because the customer app leaves browsing and cart
-- building open to signed-out users. But `applyCoupon` is only ever called from
-- `checkout_page.dart`, and `/checkout` is one of the four guarded routes. No
-- signed-out user has ever reached this function. It is revoked from anon here,
-- which closes the anonymous oracle completely rather than rate-limiting it —
-- a throttle you do not need beats a throttle you have to tune.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The caps.
-- ---------------------------------------------------------------------------
alter table public.coupons
  add column if not exists valid_from       timestamptz,
  add column if not exists max_redemptions  integer,
  -- Nullable *and* defaulted, and the combination is deliberate: every coupon
  -- that does not say otherwise gets a cap of 1, and NULL is how you say
  -- "unlimited" out loud. NOT NULL here would make the unlimited case
  -- unexpressible while the rules below still read it.
  add column if not exists max_per_user     integer default 1,
  add column if not exists first_order_only boolean not null default false,
  add column if not exists budget           integer,
  add column if not exists is_public        boolean not null default true;

alter table public.coupons
  drop constraint if exists coupon_caps_are_positive;
alter table public.coupons
  add constraint coupon_caps_are_positive check (
    (max_redemptions is null or max_redemptions > 0)
    and (max_per_user is null or max_per_user > 0)
    and (budget is null or budget > 0)
  );

alter table public.coupons
  drop constraint if exists coupon_window_is_ordered;
alter table public.coupons
  add constraint coupon_window_is_ordered
  check (valid_from is null or valid_until is null or valid_until > valid_from);

-- `max_per_user` defaults to 1, and that default lands on the two existing
-- coupons. It is a behaviour change and it is the point of the finding: a
-- welcome code that can be used twice is not a welcome code. Null means no
-- per-user cap, and has to be asked for.
comment on column public.coupons.max_per_user is
  'How many times one customer may use this code. 1 by default — the safe '
  'answer, and the one a welcome code wants. NULL is unlimited and must be '
  'chosen deliberately (0075).';
comment on column public.coupons.max_redemptions is
  'Total redemptions across all customers. NULL is unlimited (0075).';
comment on column public.coupons.budget is
  'Total rupees of discount this code may give away before it stops. NULL is '
  'unbounded. Checked against the sum of redemptions, so it is a real ceiling '
  'on spend rather than a count of uses (0075).';
comment on column public.coupons.is_public is
  'Whether the code may be listed to anyone. False keeps a targeted or win-back '
  'campaign out of the world-readable policy below (0075).';

-- ---------------------------------------------------------------------------
-- 2. The redemption ledger.
-- ---------------------------------------------------------------------------
create table if not exists public.coupon_redemptions (
  id           bigserial primary key,
  coupon_code  text not null references public.coupons(code) on update cascade on delete cascade,
  user_id      text not null,
  order_id     text not null references public.orders(id) on delete cascade,
  discount     integer not null check (discount > 0),

  -- The cap that applied when this row was written, not the cap that applies
  -- now. It is what the partial index below keys on, so tightening a live
  -- coupon's cap cannot retroactively invalidate redemptions that were legal
  -- when they happened. NULL means no per-user cap was in force — which is what
  -- was true for every redemption before this migration.
  max_per_user_at_redemption integer,

  created_at   timestamptz not null default now(),

  -- One coupon per order. The order is the thing being discounted and it is
  -- discounted once.
  constraint coupon_redemption_is_one_per_order unique (order_id)
);

create index if not exists coupon_redemption_by_code
  on public.coupon_redemptions (coupon_code, created_at desc);
create index if not exists coupon_redemption_by_user
  on public.coupon_redemptions (user_id, coupon_code);

-- The audit's item 2, and the reason the one-per-user case does not depend on
-- the lock: two concurrent claims that both pass the count check still collide
-- here, and one of them loses. Partial, so codes with a higher cap or no cap are
-- not constrained by it.
create unique index if not exists coupon_redemption_one_per_user
  on public.coupon_redemptions (coupon_code, user_id)
  where max_per_user_at_redemption = 1;

-- Backfill from the orders that already carry a code, so a cap introduced today
-- counts what happened yesterday. Without this, the customer who used WELCOME50
-- twice would get a third use out of the new limit — the ledger would say they
-- had never redeemed anything.
--
-- These rows get a NULL cap because no cap was in force when they were made.
-- That also keeps them out of the partial index, which is what lets the pair
-- above be inserted at all.
insert into public.coupon_redemptions
  (coupon_code, user_id, order_id, discount, max_per_user_at_redemption, created_at)
select o.coupon_code, o.user_id, o.id, o.discount, null, o.created_at
  from public.orders o
  join public.coupons c on c.code = o.coupon_code
 where o.coupon_code is not null
   and o.discount > 0
on conflict (order_id) do nothing;

alter table public.coupon_redemptions enable row level security;

-- No policies, and none coming. This table is written by `place_order` and read
-- by the coupon rules, both `security definer`. Nothing holds a grant on it.
revoke all on public.coupon_redemptions from public, anon, authenticated;
revoke all on sequence public.coupon_redemptions_id_seq from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. The rules, in one place.
-- ---------------------------------------------------------------------------
-- Both the preview the cart shows and the claim the order makes have to apply
-- exactly the same rules, or the checkout screen promises a discount the order
-- then refuses. They are written once here and called from both.
create or replace function public.coupon_discount_for(
  p_coupon   public.coupons,
  p_subtotal integer,
  p_user_id  text
) returns integer
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_discount integer;
  v_used     integer;
  v_spent    integer;
begin
  if p_user_id is null then
    raise exception 'Please sign in to use a code.' using errcode = 'P0001';
  end if;

  if p_coupon.valid_from is not null and now() < p_coupon.valid_from then
    raise exception 'This offer hasn''t started yet.' using errcode = 'P0001';
  end if;

  if p_coupon.valid_until is not null and now() > p_coupon.valid_until then
    raise exception 'This offer has ended.' using errcode = 'P0001';
  end if;

  if p_subtotal < p_coupon.min_subtotal then
    raise exception 'Add items worth ₹% more to use %.',
      p_coupon.min_subtotal - p_subtotal, p_coupon.code using errcode = 'P0001';
  end if;

  if p_coupon.first_order_only and exists (
    select 1 from public.orders o where o.user_id = p_user_id
  ) then
    raise exception 'This code is for your first order.' using errcode = 'P0001';
  end if;

  -- Per-customer. Counted from the ledger, which the backfill above made
  -- retrospective, so a cap introduced today knows about yesterday.
  if p_coupon.max_per_user is not null then
    select count(*) into v_used
      from public.coupon_redemptions r
     where r.coupon_code = p_coupon.code and r.user_id = p_user_id;
    if v_used >= p_coupon.max_per_user then
      raise exception 'You''ve already used this code.' using errcode = 'P0001';
    end if;
  end if;

  -- Across everybody.
  if p_coupon.max_redemptions is not null then
    select count(*) into v_used
      from public.coupon_redemptions r where r.coupon_code = p_coupon.code;
    if v_used >= p_coupon.max_redemptions then
      raise exception 'This offer has been fully claimed.' using errcode = 'P0001';
    end if;
  end if;

  v_discount := coalesce(
    p_coupon.flat_off,
    least(round(p_subtotal * p_coupon.percent_off / 100.0)::integer, p_coupon.max_off)
  );

  -- A discount may never exceed the subtotal: no coupon turns an order into a
  -- payout. Cheap to state, catastrophic to omit. (0003, unchanged.)
  v_discount := least(v_discount, p_subtotal);

  -- The budget is a ceiling on money, not on uses, so it is checked against what
  -- this redemption would actually cost — after the discount is known, and
  -- refusing rather than part-funding. A half-honoured coupon is a support
  -- ticket.
  if p_coupon.budget is not null then
    select coalesce(sum(r.discount), 0) into v_spent
      from public.coupon_redemptions r where r.coupon_code = p_coupon.code;
    if v_spent + v_discount > p_coupon.budget then
      raise exception 'This offer has been fully claimed.' using errcode = 'P0001';
    end if;
  end if;

  return v_discount;
end;
$function$;

-- The preview. Same name and same signature it has always had: the cart calls
-- it, the tests call it, and the audit's suggested rename to `preview_coupon`
-- would be churn for a function that is already only ever a preview. What
-- changes is that it now applies every rule above, so the checkout screen and
-- the order agree, and that it no longer answers anonymous callers.
create or replace function public.validate_coupon(
  p_code text, p_subtotal integer, p_restaurant_id text default null
) returns integer
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  c public.coupons;
begin
  select * into c from public.coupons
    where code = upper(trim(p_code))
      and is_active
      -- The scope, as a join condition rather than as a check afterwards: a
      -- code that is not ours to use simply does not match, and falls into the
      -- same `not found` branch as a code that was never issued.
      and (restaurant_id is null or restaurant_id = p_restaurant_id);

  if not found then
    raise exception 'This code isn''t valid.' using errcode = 'P0001';
  end if;

  return public.coupon_discount_for(c, p_subtotal, auth.uid()::text);
end;
$function$;

-- The claim. Same rules, taken under a lock, and it hands back the funder too so
-- `place_order` reads the coupon exactly once instead of twice.
create or replace function public.coupon_lock_and_price(
  p_code text, p_subtotal integer, p_restaurant_id text, p_user_id text
) returns table (discount integer, funded_by text, max_per_user integer)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c public.coupons;
begin
  -- `for update` is the whole difference between this and the preview. It holds
  -- the coupon row until the placing transaction commits, so the counts below
  -- cannot be read by two orders at once.
  select * into c from public.coupons
    where code = upper(trim(p_code))
      and is_active
      and (restaurant_id is null or restaurant_id = p_restaurant_id)
    for update;

  if not found then
    raise exception 'This code isn''t valid.' using errcode = 'P0001';
  end if;

  return query select
    public.coupon_discount_for(c, p_subtotal, p_user_id),
    c.funded_by,
    c.max_per_user;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. place_order claims rather than merely checks.
-- ---------------------------------------------------------------------------
-- Two replacements on the live body, both guarded and both idempotent, for the
-- reason 0074 gave: this is a 200-line money function and re-pasting it from a
-- migration is how a line goes missing.
do $$
declare
  v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order';

  if v_src is null then
    raise exception 'place_order not found — 0075 cannot patch what is not there.';
  end if;

  if position('coupon_lock_and_price' in v_src) > 0 then
    raise notice '0075: place_order already claims its coupon; leaving it alone.';
    return;
  end if;

  if position('v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);' in v_src) = 0
     or position('  -- Pass two: the lines, in order, each with its frozen options.' in v_src) = 0 then
    raise exception '0075: place_order is not the shape 0074 left it in. Patch it by hand.';
  end if;

  v_src := replace(v_src,
    '  v_funded_by    text;',
    '  v_funded_by    text;' || E'\n' ||
    '  v_max_per_user integer;');

  -- Price and lock in one call. The old two-step read the coupon twice and held
  -- nothing between the reads.
  v_src := replace(v_src,
    '    v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);' || E'\n' ||
    '    -- Who pays for it, frozen here and never re-read from the coupon (0074).' || E'\n' ||
    '    -- Same scope predicate validate_coupon matched on, so this reads the row' || E'\n' ||
    '    -- that produced the discount and not a same-named one out of scope.' || E'\n' ||
    '    select c.funded_by into v_funded_by from public.coupons c' || E'\n' ||
    '      where c.code = upper(trim(p_coupon_code))' || E'\n' ||
    '        and (c.restaurant_id is null or c.restaurant_id = p_restaurant_id);',
    '    -- Locks the coupon row, applies every cap, and returns the discount, the' || E'\n' ||
    '    -- funder (0074) and the per-user cap in force (0075). The lock is held' || E'\n' ||
    '    -- until this transaction commits, so the redemption written below cannot' || E'\n' ||
    '    -- race another order placing the same code.' || E'\n' ||
    '    select p.discount, p.funded_by, p.max_per_user' || E'\n' ||
    '      into v_discount, v_funded_by, v_max_per_user' || E'\n' ||
    '      from public.coupon_lock_and_price(' || E'\n' ||
    '             p_coupon_code, v_subtotal, p_restaurant_id, v_user_id) p;');

  -- The redemption, inside the same transaction as the order it belongs to.
  -- After the order insert because it carries the order id.
  v_src := replace(v_src,
    '  -- Pass two: the lines, in order, each with its frozen options.',
    '  -- The redemption, in the same transaction as the order (0075). Before the' || E'\n' ||
    '  -- lines rather than after, so a cap breach fails as early as it can.' || E'\n' ||
    '  if v_discount > 0 then' || E'\n' ||
    '    insert into public.coupon_redemptions' || E'\n' ||
    '      (coupon_code, user_id, order_id, discount, max_per_user_at_redemption)' || E'\n' ||
    '    values (upper(trim(p_coupon_code)), v_user_id, v_order_id, v_discount,' || E'\n' ||
    '            v_max_per_user);' || E'\n' ||
    '  end if;' || E'\n' || E'\n' ||
    '  -- Pass two: the lines, in order, each with its frozen options.');

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
-- 5. A targeted campaign stays targeted.
-- ---------------------------------------------------------------------------
-- The old policy published every active platform coupon to the world, so a
-- win-back code aimed at twelve lapsed customers was readable by all of them
-- and everybody else. `is_public` defaults to true, which preserves today's
-- behaviour for today's codes; a private campaign now has a way to say so.
drop policy if exists "active platform coupons are world-readable" on public.coupons;
drop policy if exists "active public platform coupons are world-readable" on public.coupons;
create policy "active public platform coupons are world-readable"
  on public.coupons for select to anon, authenticated
  using (is_active and restaurant_id is null and is_public);

-- ---------------------------------------------------------------------------
-- 6. Grants.
-- ---------------------------------------------------------------------------
-- `validate_coupon` loses anon. It is reached only from the checkout screen,
-- which is behind the router's auth guard, so nothing signed-out is losing a
-- capability it was using — and the brute-forceable namespace goes with it.
revoke all on function public.validate_coupon(text, integer, text) from public, anon;
grant execute on function public.validate_coupon(text, integer, text)
  to authenticated, service_role;

-- Internal. Neither is an RPC and neither is granted to a client role.
revoke all on function
  public.coupon_discount_for(public.coupons, integer, text),
  public.coupon_lock_and_price(text, integer, text, text)
  from public, anon, authenticated;
grant execute on function
  public.coupon_discount_for(public.coupons, integer, text),
  public.coupon_lock_and_price(text, integer, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 7. The console can set the caps.
-- ---------------------------------------------------------------------------
-- A cap nobody can configure is not a cap. `admin_save_coupon` gains the five
-- new levers, and `admin_list_coupons` returns them so the screen can show what
-- a code is actually bounded by.
--
-- Both are dropped and recreated rather than replaced. Appending parameters to
-- a Postgres function does not replace it, it creates a second one — and then
-- PostgREST picks between them by the argument names it happens to be sent,
-- which is how a console ends up silently calling last month's version.
drop function if exists public.admin_save_coupon(text, integer, integer, integer, integer, timestamptz);

create function public.admin_save_coupon(
  p_code             text,
  p_min_subtotal     integer,
  p_flat_off         integer     default null,
  p_percent_off      integer     default null,
  p_max_off          integer     default null,
  p_valid_until      timestamptz default null,
  p_valid_from       timestamptz default null,
  p_max_redemptions  integer     default null,
  p_max_per_user     integer     default 1,
  p_first_order_only boolean     default false,
  p_budget           integer     default null,
  p_is_public        boolean     default true
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

  if p_valid_from is not null and p_valid_until is not null
     and p_valid_until <= p_valid_from then
    raise exception 'The offer would end before it started.' using errcode = 'P0001';
  end if;

  -- Each of these is a table constraint too. Checked here so an ops mistake
  -- comes back as a sentence rather than as a constraint violation.
  if p_max_redemptions is not null and p_max_redemptions <= 0 then
    raise exception 'A redemption limit has to be at least 1.' using errcode = 'P0001';
  end if;
  if p_max_per_user is not null and p_max_per_user <= 0 then
    raise exception 'A per-customer limit has to be at least 1.' using errcode = 'P0001';
  end if;
  if p_budget is not null and p_budget <= 0 then
    raise exception 'A budget has to be more than ₹0.' using errcode = 'P0001';
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
     valid_until, is_active, funded_by,
     valid_from, max_redemptions, max_per_user, first_order_only, budget, is_public)
  values
    (v_code, null, coalesce(p_min_subtotal, 0), p_flat_off, p_percent_off,
     p_max_off, p_valid_until, true, 'platform',
     p_valid_from, p_max_redemptions, p_max_per_user,
     coalesce(p_first_order_only, false), p_budget, coalesce(p_is_public, true))
  on conflict (code) do update
     set min_subtotal     = excluded.min_subtotal,
         flat_off         = excluded.flat_off,
         percent_off      = excluded.percent_off,
         max_off          = excluded.max_off,
         valid_until      = excluded.valid_until,
         valid_from       = excluded.valid_from,
         max_redemptions  = excluded.max_redemptions,
         max_per_user     = excluded.max_per_user,
         first_order_only = excluded.first_order_only,
         budget           = excluded.budget,
         is_public        = excluded.is_public;
         -- funded_by still absent: a live campaign's funder is not editable.

  return v_code;
end;
$function$;

drop function if exists public.admin_list_coupons();

create function public.admin_list_coupons()
returns table (
  code text, restaurant_id text, restaurant_name text,
  min_subtotal integer, flat_off integer, percent_off integer, max_off integer,
  valid_from timestamptz, valid_until timestamptz, is_active boolean,
  created_at timestamptz,
  max_redemptions integer, max_per_user integer, first_order_only boolean,
  budget integer, is_public boolean, funded_by text,
  redeemed integer, discount_given integer
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  perform public.assert_admin();

  -- A kitchen's own offers are listed here too, read-only from this side. Ops
  -- being able to *see* a restaurant's promotion without being able to edit it
  -- is the useful half: "why is this order 200 rupees off" has an answer, and
  -- 0064's rule that an offer belongs to whoever runs it still holds.
  return query
    select c.code, c.restaurant_id, r.name,
           c.min_subtotal, c.flat_off, c.percent_off, c.max_off,
           c.valid_from, c.valid_until, c.is_active, c.created_at,
           c.max_redemptions, c.max_per_user, c.first_order_only,
           c.budget, c.is_public, c.funded_by,
           coalesce(u.n, 0), coalesce(u.d, 0)
      from public.coupons c
      left join public.restaurants r on r.id = c.restaurant_id
      -- Still counted from `orders` rather than from the new ledger, and on
      -- purpose: this column answers "what has this campaign cost", and an order
      -- that was cancelled or rejected cost nothing. The ledger is the gate; the
      -- orders table is the bill.
      left join lateral (
        select count(*)::integer as n, sum(o.discount)::integer as d
          from public.orders o
         where o.coupon_code = c.code
           and o.status not in ('cancelled', 'rejected')
      ) u on true
     order by c.restaurant_id nulls first, c.created_at desc;
end;
$function$;

revoke all on function public.admin_list_coupons() from public, anon;
grant execute on function public.admin_list_coupons() to authenticated, service_role;
revoke all on function public.admin_save_coupon(
  text, integer, integer, integer, integer, timestamptz, timestamptz,
  integer, integer, boolean, integer, boolean) from public, anon;
grant execute on function public.admin_save_coupon(
  text, integer, integer, integer, integer, timestamptz, timestamptz,
  integer, integer, boolean, integer, boolean) to authenticated, service_role;
