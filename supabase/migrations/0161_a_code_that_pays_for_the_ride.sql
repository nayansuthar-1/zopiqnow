-- ---------------------------------------------------------------------------
-- 0161 — a code that pays for the ride.
-- ---------------------------------------------------------------------------
-- A coupon has been able to say two things since 0003: so many rupees off, or
-- so many percent off up to a cap. Both of them are money off the *food*. The
-- offer every food app in the country actually runs — **free delivery** — has
-- had no way to be written down.
--
-- ## Why this is not just another discount
--
-- The obvious implementation is a ₹40 flat coupon, and it is wrong twice over.
--
-- `place_order` apportions a discount across the lines by value and taxes what
-- is left (0078). A ₹40 "free delivery" spent that way takes ₹40 off the food's
-- taxable base and hands back ₹2 of 5% GST that was never owed on the food,
-- while still charging the ₹40 delivery fee whose own 18% is sitting inside it.
-- The customer's total lands close enough that nobody notices; the invoice is
-- wrong, and the invoice is the thing with a GST number on it.
--
-- And it is not what the offer says. "Free delivery" is a promise about the
-- delivery line, and a cart that shows ₹40 delivery and −₹40 discount is a cart
-- arguing with its own coupon.
--
-- So free delivery **waives the fee**: `v_delivery_fee` becomes 0, the tax
-- inside it goes with it, and `orders.discount` stays 0. The food, its slabs and
-- its apportionment are untouched by this migration, which is the point.
--
-- ## What is *not* waived
--
-- The night and rain surcharge (0129). It is a separate line on the bill, it is
-- there because this particular ride costs more to make, and a code written for
-- a Tuesday lunch should not quietly absorb a monsoon. `surge_fee` is charged in
-- full beside a waived delivery fee, and the cart draws both.
--
-- ## The cost is still recorded
--
-- A waived fee is money the platform gave away, so it is written down twice:
-- `orders.delivery_waived` keeps what the ride would have cost on the order it
-- belonged to, and the `coupon_redemptions` row carries it as that redemption's
-- value. That second one is what makes the caps from 0075 work — a budget, a
-- total redemption count and a per-customer limit all apply to a free-delivery
-- code exactly as they apply to a discount, because they count the same column.
--
-- ## Two entry points, one rule
--
-- `validate_coupon` returns an integer and always has: the cart's preview, the
-- preflight and two shipped app builds call it. It keeps its signature and keeps
-- returning the food discount, which for a free-delivery code is 0. The richer
-- answer is a new function, `coupon_preview`, which returns the discount, the
-- fee it would waive and the flag. Both are three lines around
-- `coupon_discount_for`, which is still the only place a coupon's rules are
-- written — the thing 0075 established and the thing worth keeping.
--
-- `place_order` and `checkout_preflight` are patched from their own definitions
-- rather than restated, the way 0123 did it: this is a 250-line money function
-- and re-pasting one from a migration is how a line goes missing.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. A third kind of offer.
-- ---------------------------------------------------------------------------
alter table public.coupons
  add column if not exists free_delivery boolean not null default false;

comment on column public.coupons.free_delivery is
  'Waives the delivery fee instead of taking money off the food. Never both: '
  'the kind check below makes flat, percent and free delivery mutually '
  'exclusive (0161).';

-- 0003''s XOR grows a third arm. Dropped by its old name as well as its new one
-- so a re-run is a no-op rather than a duplicate.
alter table public.coupons
  drop constraint if exists coupon_is_flat_xor_capped_percent;
alter table public.coupons
  drop constraint if exists coupon_is_one_kind_of_offer;
alter table public.coupons
  add constraint coupon_is_one_kind_of_offer check (
    (flat_off is not null and percent_off is null and max_off is null
       and not free_delivery)
    or
    (flat_off is null and percent_off is not null and max_off is not null
       and not free_delivery)
    or
    (flat_off is null and percent_off is null and max_off is null
       and free_delivery)
  );

-- ---------------------------------------------------------------------------
-- 2. What the order gave away.
-- ---------------------------------------------------------------------------
-- `delivery_fee` is what was charged, and for a waived ride that is 0. This is
-- what it would have been — the campaign's cost, on the order that spent it, so
-- "why was delivery free on this one" has an answer for as long as the row does.
alter table public.orders
  add column if not exists delivery_waived integer not null default 0;

alter table public.orders
  drop constraint if exists order_delivery_waiver_is_not_negative;
alter table public.orders
  add constraint order_delivery_waiver_is_not_negative
  check (delivery_waived >= 0);

comment on column public.orders.delivery_waived is
  'Rupees of delivery fee a free-delivery coupon paid for. `delivery_fee` is '
  'already net of it — this is the platform''s side of the same rupee (0161).';

-- ---------------------------------------------------------------------------
-- 3. The rules, still in one place.
-- ---------------------------------------------------------------------------
-- Same body 0075 wrote, with one branch added and the return widened: a coupon
-- is now worth either money off the food or a waived ride, and the caller has to
-- be told which. Dropped rather than replaced because the return type changes.
drop function if exists public.coupon_discount_for(public.coupons, integer, text);

create function public.coupon_discount_for(
  p_coupon       public.coupons,
  p_subtotal     integer,
  p_user_id      text,
  p_delivery_fee integer default 0
) returns table (discount integer, delivery_waived integer)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_discount integer := 0;
  v_waived   integer := 0;
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

  -- Per-customer. Counted from the ledger, which 0075's backfill made
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

  if p_coupon.free_delivery then
    -- The whole fee and never more than it. A caller that has not been told the
    -- fee yet gets 0 back, which is honest: nothing is waived until there is a
    -- ride to waive.
    v_waived := greatest(coalesce(p_delivery_fee, 0), 0);
  else
    v_discount := coalesce(
      p_coupon.flat_off,
      least(round(p_subtotal * p_coupon.percent_off / 100.0)::integer,
            p_coupon.max_off)
    );

    -- A discount may never exceed the subtotal: no coupon turns an order into a
    -- payout. Cheap to state, catastrophic to omit. (0003, unchanged.)
    v_discount := least(v_discount, p_subtotal);
  end if;

  -- The budget is a ceiling on money, not on uses, so it is checked against what
  -- this redemption would actually cost — after the value is known, and refusing
  -- rather than part-funding. A waived ride costs the same rupees a discount
  -- does, which is why both are in the sum.
  if p_coupon.budget is not null then
    select coalesce(sum(r.discount), 0) into v_spent
      from public.coupon_redemptions r where r.coupon_code = p_coupon.code;
    if v_spent + v_discount + v_waived > p_coupon.budget then
      raise exception 'This offer has been fully claimed.' using errcode = 'P0001';
    end if;
  end if;

  return query select v_discount, v_waived;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. The preview, twice: the old shape and the one that can say "free".
-- ---------------------------------------------------------------------------
-- Unchanged signature, unchanged meaning: rupees off the food. A free-delivery
-- code validates here and answers 0, which is true — it takes nothing off the
-- food — and is what a build shipped before today will draw.
create or replace function public.validate_coupon(
  p_code text, p_subtotal integer, p_restaurant_id text default null
) returns integer
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  c          public.coupons;
  v_discount integer;
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

  select d.discount into v_discount
    from public.coupon_discount_for(c, p_subtotal, auth.uid()::text, 0) d;
  return v_discount;
end;
$function$;

-- The full answer, for the cart that has to decide what to draw on the delivery
-- line. jsonb rather than a wider `returns table` so the next thing a coupon
-- learns to do does not break every caller again.
create or replace function public.coupon_preview(
  p_code text,
  p_subtotal integer,
  p_restaurant_id text default null,
  p_delivery_fee integer default 0
) returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  c          public.coupons;
  v_discount integer;
  v_waived   integer;
begin
  select * into c from public.coupons
    where code = upper(trim(p_code))
      and is_active
      and (restaurant_id is null or restaurant_id = p_restaurant_id);

  if not found then
    raise exception 'This code isn''t valid.' using errcode = 'P0001';
  end if;

  select d.discount, d.delivery_waived into v_discount, v_waived
    from public.coupon_discount_for(
           c, p_subtotal, auth.uid()::text,
           greatest(coalesce(p_delivery_fee, 0), 0)) d;

  return jsonb_build_object(
    'code',            c.code,
    'discount',        v_discount,
    'delivery_waived', v_waived,
    'free_delivery',   c.free_delivery
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. The claim.
-- ---------------------------------------------------------------------------
-- Dropped and recreated rather than replaced: it gains an argument, and an
-- argument appended to a Postgres function is a second function beside the first
-- one that callers then pick between by accident.
drop function if exists public.coupon_lock_and_price(text, integer, text, text);

create function public.coupon_lock_and_price(
  p_code text, p_subtotal integer, p_restaurant_id text, p_user_id text,
  p_delivery_fee integer default 0
) returns table (
  discount integer, funded_by text, max_per_user integer, delivery_waived integer
)
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
    d.discount,
    c.funded_by,
    c.max_per_user,
    d.delivery_waived
  from public.coupon_discount_for(
         c, p_subtotal, p_user_id, greatest(coalesce(p_delivery_fee, 0), 0)) d;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. place_order charges the waived fee to nobody.
-- ---------------------------------------------------------------------------
-- Patched from its own definition, guarded line by line, and idempotent. The
-- coupon is read *after* the fee stack is set, which is what makes this possible
-- at all: the fee it waives is already sitting in `v_delivery_fee`.
do $$
declare
  v_n   integer;
  v_i   integer;
  v_def text;
  v_new text;

  -- The fragments to find and what each becomes, paired by position and applied
  -- in order. A fragment that has moved on since 0151 stops the migration rather
  -- than half-patching a money function.
  v_old text[];
  v_sub text[];
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order';
  if v_n <> 1 then
    raise exception '0161: expected exactly one place_order, found %.', v_n;
  end if;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order';

  if position('v_delivery_waived' in v_def) > 0 then
    raise notice '0161: place_order already waives delivery; leaving it alone.';
    return;
  end if;

  v_old := array[
    -- the variable
    '  v_max_per_user  integer;',
    -- the coupon, priced against the fee it may waive
    '    select p.discount, p.funded_by, p.max_per_user',
    '      into v_discount, v_funded_by, v_max_per_user',
    '             p_coupon_code, v_subtotal, p_restaurant_id, v_user_id) p;',
    -- the order remembers what it gave away
    '    subtotal, delivery_fee, platform_fee, packaging_fee, surge_fee,',
    '    v_subtotal, v_delivery_fee, v_platform_fee, v_packaging_fee, v_surge_fee,',
    -- the redemption, so every cap in 0075 counts a waived ride too
    '  if v_discount > 0 then' || E'\n' ||
    '    insert into public.coupon_redemptions',
    '    values (upper(trim(p_coupon_code)), v_user_id, v_order_id, v_discount,'
  ];

  v_sub := array[
    '  v_max_per_user  integer;' || E'\n' ||
    '  v_delivery_waived integer := 0;',

    '    select p.discount, p.funded_by, p.max_per_user, p.delivery_waived',

    '      into v_discount, v_funded_by, v_max_per_user, v_delivery_waived',

    '             p_coupon_code, v_subtotal, p_restaurant_id, v_user_id,' || E'\n' ||
    '             v_delivery_fee) p;' || E'\n' ||
    '    -- Free delivery is a waived fee and not a discount (0161): the tax' || E'\n' ||
    '    -- inside the fee goes with it, and the food''s slabs never move.' || E'\n' ||
    '    v_delivery_fee := v_delivery_fee - v_delivery_waived;',

    '    subtotal, delivery_fee, delivery_waived, platform_fee, packaging_fee, surge_fee,',

    '    v_subtotal, v_delivery_fee, v_delivery_waived, v_platform_fee, v_packaging_fee, v_surge_fee,',

    '  if v_discount + v_delivery_waived > 0 then' || E'\n' ||
    '    insert into public.coupon_redemptions',

    '    values (upper(trim(p_coupon_code)), v_user_id, v_order_id,' || E'\n' ||
    '            v_discount + v_delivery_waived,'
  ];

  v_new := v_def;
  for v_i in 1 .. array_length(v_old, 1) loop
    if position(v_old[v_i] in v_new) = 0 then
      raise exception
        '0161: place_order is not the shape 0151 left it in — it no longer '
        'contains: %. Read the live definition before re-running this.',
        v_old[v_i];
    end if;
    v_new := replace(v_new, v_old[v_i], v_sub[v_i]);
  end loop;

  execute v_new;
end $$;


-- ---------------------------------------------------------------------------
-- 7. checkout_preflight quotes what place_order will charge.
-- ---------------------------------------------------------------------------
-- The preflight is the number the payment gate compares against (0085), so a
-- preflight that still charges a waived fee refuses the order it just approved.
do $$
declare
  v_n   integer;
  v_def text;
  v_new text;
  v_old constant text :=
    '    v_discount := public.validate_coupon(p_coupon_code, v_subtotal, p_restaurant_id);';
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'checkout_preflight';
  if v_n <> 1 then
    raise exception '0161: expected exactly one checkout_preflight, found %.', v_n;
  end if;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'checkout_preflight';

  if position('v_delivery_waived' in v_def) > 0 then
    raise notice '0161: checkout_preflight already waives delivery; leaving it alone.';
    return;
  end if;

  if position(v_old in v_def) = 0 or position('  v_discount      integer := 0;' in v_def) = 0 then
    raise exception '0161: checkout_preflight is not the shape 0120 left it in. '
                    'Read the live definition before re-running this.';
  end if;

  v_new := replace(v_def,
    '  v_discount      integer := 0;',
    '  v_discount      integer := 0;' || E'\n' ||
    '  v_delivery_waived integer := 0;');

  v_new := replace(v_new, v_old,
    '    select (j ->> ''discount'')::integer, (j ->> ''delivery_waived'')::integer' || E'\n' ||
    '      into v_discount, v_delivery_waived' || E'\n' ||
    '      from public.coupon_preview(' || E'\n' ||
    '             p_coupon_code, v_subtotal, p_restaurant_id, v_delivery_fee) as j;' || E'\n' ||
    '    -- A waived fee, not a discount (0161). Same swap place_order makes, so' || E'\n' ||
    '    -- the quote and the charge agree to the rupee.' || E'\n' ||
    '    v_delivery_fee := v_delivery_fee - v_delivery_waived;');

  execute v_new;
end $$;

-- ---------------------------------------------------------------------------
-- 8. The offer, worded.
-- ---------------------------------------------------------------------------
-- 0064 put the wording here rather than in three apps, and said why: the day the
-- rule grows a case the sentence grows with it, next to the arithmetic. This is
-- that day. Without it a free-delivery code renders `null` — the `else` arm
-- concatenates a null percentage — and the offers list drops a row the customer
-- can actually use.
create or replace function public.restaurant_offers(p_restaurant_id text)
returns table (
  code         text,
  label        text,
  min_subtotal integer,
  is_exclusive boolean,
  valid_until  timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.code,
         case
           when c.free_delivery      then 'Free delivery'
           when c.flat_off is not null then '₹' || c.flat_off || ' off'
           else c.percent_off || '% off up to ₹' || c.max_off
         end,
         c.min_subtotal,
         c.restaurant_id is not null,
         c.valid_until
    from public.coupons c
   where c.is_active
     and (c.valid_until is null or c.valid_until > now())
     and (c.restaurant_id is null or c.restaurant_id = p_restaurant_id)
   order by c.restaurant_id is null, c.min_subtotal;
$$;

-- ---------------------------------------------------------------------------
-- 9. The console can write one.
-- ---------------------------------------------------------------------------
-- Free delivery is a platform offer and only a platform offer: the fee belongs
-- to the platform, and `admin_save_coupon` has only ever written
-- `restaurant_id = null` anyway. A kitchen's own Offers screen is untouched and
-- still writes flat and percent codes.
drop function if exists public.admin_save_coupon(
  text, integer, integer, integer, integer, timestamptz, timestamptz,
  integer, integer, boolean, integer, boolean);

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
  p_is_public        boolean     default true,
  p_free_delivery    boolean     default false
) returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_code  text;
  v_owner text;
  v_found boolean;
  v_free  boolean := coalesce(p_free_delivery, false);
begin
  perform public.assert_admin();

  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9-]', '', 'g'));
  if length(v_code) < 3 or length(v_code) > 16 then
    raise exception 'A coupon code is 3 to 16 letters, numbers or hyphens.'
      using errcode = 'P0001';
  end if;

  -- Three kinds, exactly one of them. The table says the same thing; this says
  -- it in a sentence rather than as a constraint violation.
  if v_free then
    if p_flat_off is not null or p_percent_off is not null or p_max_off is not null then
      raise exception 'A free-delivery coupon waives the delivery fee. It cannot also take money off the food.'
        using errcode = 'P0001';
    end if;
  else
    if (p_flat_off is not null) = (p_percent_off is not null) then
      raise exception 'A coupon is either a flat amount off, a percentage, or free delivery.'
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
     valid_from, max_redemptions, max_per_user, first_order_only, budget,
     is_public, free_delivery)
  values
    (v_code, null, coalesce(p_min_subtotal, 0), p_flat_off, p_percent_off,
     p_max_off, p_valid_until, true, 'platform',
     p_valid_from, p_max_redemptions, p_max_per_user,
     coalesce(p_first_order_only, false), p_budget, coalesce(p_is_public, true),
     v_free)
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
         is_public        = excluded.is_public,
         free_delivery    = excluded.free_delivery;
         -- funded_by still absent: a live campaign's funder is not editable.

  return v_code;
end;
$function$;

revoke all on function public.admin_save_coupon(
  text, integer, integer, integer, integer, timestamptz, timestamptz,
  integer, integer, boolean, integer, boolean, boolean) from public, anon;
grant execute on function public.admin_save_coupon(
  text, integer, integer, integer, integer, timestamptz, timestamptz,
  integer, integer, boolean, integer, boolean, boolean)
  to authenticated, service_role;

drop function if exists public.admin_list_coupons();

create function public.admin_list_coupons()
returns table (
  code text, restaurant_id text, restaurant_name text,
  min_subtotal integer, flat_off integer, percent_off integer, max_off integer,
  valid_from timestamptz, valid_until timestamptz, is_active boolean,
  created_at timestamptz,
  max_redemptions integer, max_per_user integer, first_order_only boolean,
  budget integer, is_public boolean, funded_by text, free_delivery boolean,
  redeemed integer, discount_given integer
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  perform public.assert_admin();

  return query
    select c.code, c.restaurant_id, r.name,
           c.min_subtotal, c.flat_off, c.percent_off, c.max_off,
           c.valid_from, c.valid_until, c.is_active, c.created_at,
           c.max_redemptions, c.max_per_user, c.first_order_only,
           c.budget, c.is_public, c.funded_by, c.free_delivery,
           coalesce(u.n, 0), coalesce(u.d, 0)
      from public.coupons c
      left join public.restaurants r on r.id = c.restaurant_id
      -- Still counted from `orders` rather than from the new ledger, and on
      -- purpose: this column answers "what has this campaign cost", and an order
      -- that was cancelled or rejected cost nothing. A waived ride is part of
      -- that cost and sits in its own column (0161), so both are summed.
      left join lateral (
        select count(*)::integer                            as n,
               sum(o.discount + o.delivery_waived)::integer as d
          from public.orders o
         where o.coupon_code = c.code
           and o.status not in ('cancelled', 'rejected')
      ) u on true
     order by c.restaurant_id nulls first, c.created_at desc;
end;
$function$;

revoke all on function public.admin_list_coupons() from public, anon;
grant execute on function public.admin_list_coupons() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 10. Grants.
-- ---------------------------------------------------------------------------
-- Functions are born PUBLIC-executable and granted to `authenticated` by
-- default: both routes are closed, then the one caller is let back in.
revoke all on function public.coupon_preview(text, integer, text, integer)
  from public, anon, authenticated;
grant execute on function public.coupon_preview(text, integer, text, integer)
  to authenticated, service_role;

-- Internal. Neither is an RPC and neither is granted to a client role.
revoke all on function public.coupon_discount_for(public.coupons, integer, text, integer)
  from public, anon, authenticated;
revoke all on function public.coupon_lock_and_price(text, integer, text, text, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- verification
-- 1. The three kinds, and the refusal of a fourth:
--
--      insert into public.coupons (code, free_delivery, flat_off)
--      values ('BAD-FREE', true, 50);
--      -- expected: coupon_is_one_kind_of_offer violation
--
-- 2. Both functions carry the waiver:
--
--      select p.proname,
--             pg_get_functiondef(p.oid) like '%v_delivery_waived%' as patched
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('place_order', 'checkout_preflight');
--      -- expected: both true
--
-- 3. As a signed-in customer (see the money-path probe in 0090's footer for how
--    to forge the sub), with a free-delivery code live:
--
--      select public.coupon_preview('FREERIDE', 300, 'r1', 40);
--      -- expected: {"discount": 0, "delivery_waived": 40, "free_delivery": true}
--
--      select public.checkout_preflight('r1', '[…]', null, null, 'FREERIDE');
--      -- expected: delivery_fee 0, and total lower than the same call with a
--      -- null coupon by exactly 40 — no more, because the food's GST must not
--      -- move.
--
-- 4. After placing one:
--
--      select delivery_fee, delivery_waived, discount, discount_funded_by
--        from public.orders order by created_at desc limit 1;
--      -- expected: 0, 40, 0, null
--
--      select discount from public.coupon_redemptions order by id desc limit 1;
--      -- expected: 40 — the cap and the budget count the ride.
