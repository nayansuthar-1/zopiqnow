-- ---------------------------------------------------------------------------
-- 0162 — what the ride costs is a setting.
-- ---------------------------------------------------------------------------
-- `v_delivery_fee := 40;` — a literal, in two 250-line money functions, and a
-- third copy as a `const` compiled into the customer app. Changing what delivery
-- costs has therefore been a migration *and* a store release, which is the
-- shape 0159 spent a whole migration arguing against: this is a judgement about
-- this town on this evening, not a fact about the software.
--
-- It joins the other four knobs. `delivery_fee_settings` is one row holding one
-- number, the same shape `payment_settings` and `rider_cash_policy` already
-- have, and the console writes it through `admin_set_delivery_fee`.
--
-- ## What it does not change
--
-- **Orders already placed.** `orders.delivery_fee` is what that customer was
-- charged, frozen on the row at purchase. Lowering the fee tonight does not
-- rewrite last week's receipts, and the settlement that reads them is untouched.
--
-- **Rider pay.** It is distance-based (`rider_pay_quote`, 0043/0122) and has
-- never been a share of this fee. A cheaper ride for the customer is not a
-- cheaper ride for the rider.
--
-- **The surcharge.** Night and rain (0129) are added on top and stay their own
-- number on their own screen. This is the base.
--
-- ## The app stops guessing
--
-- `CartBill.flatDeliveryFee` stays in the app as the value to draw *while the
-- read is in flight* — a cart that renders nothing until a round trip lands is
-- worse than a cart that briefly shows the shipped default. It is no longer the
-- number that is charged. `delivery_fee_now()` is, and the cart, the preflight
-- and `place_order` all read it from here.
--
-- `coupon_preview` (0161) stops being told the fee by the phone at all: it looks
-- it up. A client-supplied fee was a client-supplied *price*, and this project
-- has one rule above all the others — the client never decides what anything
-- costs.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The number.
-- ---------------------------------------------------------------------------
create table if not exists public.delivery_fee_settings (
  id         integer primary key default 1 check (id = 1),

  -- Gross, GST included, exactly like the fee it replaces: `place_order`
  -- extracts the 18% from inside it rather than adding it on top (0078). An
  -- admin typing 40 here is promising the customer a ₹40 line, not ₹47.
  base_fee   integer not null default 40
             check (base_fee >= 0 and base_fee <= 500),

  updated_at timestamptz not null default now()
);

insert into public.delivery_fee_settings (id) values (1) on conflict (id) do nothing;

comment on table public.delivery_fee_settings is
  'One row. What delivery costs before the night and rain surcharge (0129) is '
  'added and before a free-delivery coupon (0161) waives it. Gross, GST '
  'inclusive. Read by place_order, checkout_preflight and the customer app '
  '(0162).';

-- Tables are born writable: `anon` gets grants nobody asked for, and RLS does
-- not cover TRUNCATE. Both routes closed, and no policy is added — this is read
-- through a `security definer` function and written through another one.
alter table public.delivery_fee_settings enable row level security;
revoke all on public.delivery_fee_settings from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. What everything reads.
-- ---------------------------------------------------------------------------
create or replace function public.delivery_fee_now()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  -- `coalesce` and not a bare select: a missing row would otherwise price every
  -- order at null and take the delivery line out of the bill entirely. 40 is the
  -- value this table ships with and the value the app falls back to.
  select coalesce((select base_fee from public.delivery_fee_settings where id = 1), 40);
$$;

comment on function public.delivery_fee_now() is
  '0162: the base delivery fee, gross. The one place the number lives.';

revoke all on function public.delivery_fee_now() from public, anon, authenticated;
grant execute on function public.delivery_fee_now() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. The two functions that charge it.
-- ---------------------------------------------------------------------------
-- Patched from their own definitions and guarded, the way 0123 and 0161 did it.
-- The two differ by a space in the assignment, so each is matched on its own
-- text rather than on a shared guess.
do $$
declare
  f     record;
  v_def text;
  v_old text;
  v_n   integer := 0;
begin
  for f in
    select p.oid, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('place_order', 'checkout_preflight')
  loop
    v_def := pg_get_functiondef(f.oid);

    if position('delivery_fee_now' in v_def) > 0 then
      raise notice '0162: % already reads the setting; leaving it alone.', f.proname;
      v_n := v_n + 1;
      continue;
    end if;

    -- `place_order` aligns its assignments in a column and `checkout_preflight`
    -- does not. Both spellings, one of which must be there.
    v_old := case
               when position('  v_delivery_fee  := 40;' in v_def) > 0
                 then '  v_delivery_fee  := 40;'
               when position('  v_delivery_fee := 40;' in v_def) > 0
                 then '  v_delivery_fee := 40;'
             end;

    if v_old is null then
      raise exception
        '0162: % no longer assigns a flat 40 to v_delivery_fee. Read the live '
        'definition before re-running this.', f.proname;
    end if;

    execute replace(v_def, v_old,
      replace(v_old, '40;', 'public.delivery_fee_now();'));
    v_n := v_n + 1;
  end loop;

  if v_n <> 2 then
    raise exception '0162: expected to find 2 functions, found %.', v_n;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. The coupon prices its own waiver.
-- ---------------------------------------------------------------------------
-- 0161 had the phone send the fee so the preview could tell a free-delivery
-- code what it was about to be worth. It does not need telling. The argument
-- stays for the one caller that has a good answer — `checkout_preflight`, which
-- has already read the fee this order will be charged — and defaults to the
-- setting for everyone else. Same signature, so nothing rebinds.
create or replace function public.coupon_preview(
  p_code text,
  p_subtotal integer,
  p_restaurant_id text default null,
  p_delivery_fee integer default null
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
           greatest(coalesce(p_delivery_fee, public.delivery_fee_now()), 0)) d;

  return jsonb_build_object(
    'code',            c.code,
    'discount',        v_discount,
    'delivery_waived', v_waived,
    'free_delivery',   c.free_delivery
  );
end;
$function$;

revoke all on function public.coupon_preview(text, integer, text, integer)
  from public, anon, authenticated;
grant execute on function public.coupon_preview(text, integer, text, integer)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. The console writes it.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_delivery_fee(p_fee integer)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
begin
  perform public.assert_admin();

  if p_fee is null then
    raise exception 'A delivery fee is a number, even when that number is 0.'
      using errcode = 'P0001';
  end if;
  if p_fee < 0 then
    raise exception 'A delivery fee cannot be negative — that would pay people to order.'
      using errcode = 'P0001';
  end if;
  -- The same refusal the surcharge setter makes, and for the same reason: the
  -- damage is done at the moment somebody types an extra zero.
  if p_fee > 500 then
    raise exception 'A delivery fee over ₹500 is almost certainly a typo. Refused.'
      using errcode = 'P0001';
  end if;

  update public.delivery_fee_settings
     set base_fee = p_fee, updated_at = now()
   where id = 1;

  -- Said on every save, because both halves are what somebody changing this
  -- number is most likely to be wrong about.
  return case
    when p_fee = 0 then
      'Delivery is now free on every order. Orders already placed keep the fee they were charged.'
    else
      'Delivery fee is now ₹' || p_fee || ' on new orders. Riders are paid by '
      'distance and are unaffected.'
  end;
end;
$fn$;

comment on function public.admin_set_delivery_fee(integer) is
  '0162: the base delivery fee. Applies to orders placed after it, never to '
  'orders already on the books.';

revoke all on function public.admin_set_delivery_fee(integer) from public, anon, authenticated;
grant execute on function public.admin_set_delivery_fee(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The settings screen reads it with the rest.
-- ---------------------------------------------------------------------------
-- Restated whole rather than patched: it is a `jsonb_build_object` and a
-- one-line insertion into one is legible in a way a string replacement over a
-- money function is not.
create or replace function public.admin_platform_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_result jsonb;
begin
  perform public.assert_admin();

  select jsonb_build_object(
    'delivery', (
      select to_jsonb(f) from public.delivery_fee_settings f where f.id = 1
    ),
    'dispatch', (
      select to_jsonb(d) from public.dispatch_settings d where d.id = 1
    ),
    'surcharge', (
      select to_jsonb(s) - 'weather_api_key'
             || jsonb_build_object(
                  -- Whether, never what. See 0159's header.
                  'has_weather_key',
                  nullif(trim(coalesce(s.weather_api_key, '')), '') is not null)
        from public.delivery_surcharge_settings s where s.id = 1
    ),
    'payments', jsonb_build_object(
      'require_verified_payment', (
        select p.require_verified_payment from public.payment_settings p
      ),
      -- The number that decides whether turning the gate **on** is safe, and the
      -- number that says what turning it off has been costing. Live orders only:
      -- a finished order's payment is somebody else's problem now.
      'unverified_live_orders', (
        select count(*) from public.orders o
         where o.status not in ('delivered', 'cancelled', 'rejected')
           and o.payment_method = 'upi'
           and not exists (
             select 1 from public.payment_intents pi
              where pi.order_id = o.id and pi.verified_at is not null
           )
      )
    ),
    'cash', jsonb_build_object(
      -- Read-only here. The Cash screen owns this one and has since 0076.
      'cap', (select c.cap from public.rider_cash_policy c where c.id = 1)
    )
  ) into v_result;

  return v_result;
end;
$fn$;

comment on function public.admin_platform_settings() is
  '0159: dispatch, surcharge and payment settings in one object, plus the rider cash cap for reference, plus the base delivery fee (0162). Never returns the weather API key.';

revoke all on function public.admin_platform_settings() from public, anon, authenticated;
grant execute on function public.admin_platform_settings() to authenticated;

-- ---------------------------------------------------------------- verification
-- 1. Both money functions read the setting, and neither carries a literal:
--
--      select p.proname,
--             pg_get_functiondef(p.oid) like '%delivery_fee_now%' as reads_setting
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('place_order', 'checkout_preflight');
--      -- expected: both true
--
-- 2. Move it and watch a quote move with it, inside a transaction that is then
--    rolled back:
--
--      begin;
--      update public.delivery_fee_settings set base_fee = 25 where id = 1;
--      select public.checkout_preflight(…);   -- delivery_fee 25
--      rollback;
--
-- 3. A free-delivery coupon still waives whatever the fee has become:
--
--      begin;
--      update public.delivery_fee_settings set base_fee = 25 where id = 1;
--      select public.coupon_preview('FREEDEL', 300, '<restaurant>');
--      -- expected: delivery_waived 25, not 40
--      rollback;
--
-- 4. The typo guard:
--
--      select public.admin_set_delivery_fee(4000);  -- refused, as a sentence
