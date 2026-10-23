-- ---------------------------------------------------------------------------
-- 0170 — the tax rates are a setting too.
-- ---------------------------------------------------------------------------
-- 0078 built the whole GST path and then said what it had not built:
--
--     There is also no console lever for `gst_rate_bps` yet.
--
-- Two of the three levers arrived anyway. A dish's slab is editable in the
-- console's item dialog, and a gift's through `admin_upsert_gift_item`. The one
-- left is the pair 0078 wrote as literals in its own section A:
--
--     create or replace function public.fee_gst_rate_bps()
--     returns integer language sql immutable as $$ select 1800 $$;
--
--     create or replace function public.packaging_gst_rate_bps()
--     returns integer language sql immutable as $$ select 500 $$;
--
-- 18% on the service charges — delivery, platform fee, surge — and 5% on
-- packaging, which follows the food it wraps rather than the service rate. Six
-- money functions read them (`place_order` and its twin in 0143,
-- `checkout_preflight`, `reorder_quote`, `gift_order_quote`, `place_gift_order`)
-- and not one carries a literal, which is the whole reason this is one table and
-- not six edits. They join the other five knobs 0159 and 0162 brought in from
-- psql.
--
-- ## Why a rate is worth a screen and a fee is not quite the same thing
--
-- A delivery fee is a judgement about this town on this evening. A GST rate is
-- not a judgement at all — it is a fact about the law, and the law changes on a
-- date announced in advance by somebody who is not us. That is exactly why it
-- belongs here rather than in a migration: the change is known weeks out, has
-- to land on a particular evening, and should not be waiting on a deploy
-- window. The GST Council has moved the restaurant and service slabs before and
-- will again.
--
-- ## The slabs are a list, not a number field
--
-- `menu_items.gst_rate_bps` is checked against `(0, 500, 1200, 1800)` and these
-- two columns are checked against the same list. A free-text basis-point box on
-- a tax rate is a form where 18 means 0.18% and 180000 means somebody's evening
-- is over, and neither mistake announces itself — it shows up as a wrong number
-- on a numbered tax invoice, which is the one document on this platform that
-- cannot be quietly corrected afterwards. A rate outside those four would be a
-- new slab, and a new slab is a conversation with an accountant, not a keystroke.
--
-- ## What moves and what does not
--
-- **Nothing already charged.** `orders` freezes `taxes`, `tax_on_fees`, `cgst`,
-- `sgst`, `igst` and every fee at purchase, `order_items` freezes each line's
-- rate and taxable value, and `order_invoice` (0063) renders from those frozen
-- figures. An invoice printed before this change and the same invoice printed
-- after are the same piece of paper. That is the promise 0078 made and this
-- keeps it.
--
-- **Not the food rate.** Food is taxed per dish, at the dish's own slab, and
-- that is the right shape — a thali and a sealed cold drink are not the same
-- rate and never were. Changing all of them at once is a menu operation, and
-- the console already edits them one at a time where somebody can see what they
-- are changing.
--
-- **The fees stay tax-inclusive.** A ₹40 delivery fee stays ₹40, with the tax
-- extracted from inside it; raising the rate here moves how much of that ₹40 is
-- tax, not what the customer pays. 0078 chose that deliberately so a compliance
-- change could not become a price rise, and this screen does not offer to
-- reverse it. Charging the tax on top instead is a pricing decision with a
-- re-priced fee behind it, and it would want its own migration.
--
-- ## `immutable` becomes `stable`
--
-- They have to: a function that reads a table is not immutable, and leaving the
-- marker on would let the planner fold last week's rate into a cached plan.
-- Both are called only from inside plpgsql bodies — no index, no generated
-- column, no check constraint depends on either, which is what makes the
-- volatility change safe to make at all. `create or replace` invalidates the
-- plans of the functions that call them.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The two numbers.
-- ---------------------------------------------------------------------------
create table if not exists public.tax_settings (
  id integer primary key default 1 check (id = 1),

  -- GST on a platform service charge: delivery, platform fee, surge. The fee
  -- amounts on an order are inclusive of it.
  fee_gst_rate_bps integer not null default 1800
    check (fee_gst_rate_bps in (0, 500, 1200, 1800)),

  -- GST on packaging. Ancillary to the supply of the food it wraps, so it
  -- follows the food rate rather than the service rate.
  packaging_gst_rate_bps integer not null default 500
    check (packaging_gst_rate_bps in (0, 500, 1200, 1800)),

  updated_at timestamptz not null default now()
);

insert into public.tax_settings (id) values (1) on conflict (id) do nothing;

comment on table public.tax_settings is
  'One row. The two platform-level GST rates 0078 wrote as literals: the rate '
  'inside a service fee and the rate on packaging. Food is taxed per dish on '
  'menu_items.gst_rate_bps and is not here (0170).';

-- Same close-up as 0162's table: `anon` gets grants nobody asked for and RLS
-- does not cover TRUNCATE, so both routes come off. No policy is added — this
-- is read through a `security definer` function and written through another.
alter table public.tax_settings enable row level security;
revoke all on public.tax_settings from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. What the money functions read.
-- ---------------------------------------------------------------------------
-- The bodies change; the signatures, the names and the grants do not, so all six
-- callers are untouched and there is no second copy of either rate.
--
-- `coalesce` and not a bare select, for the reason `delivery_fee_now()` gives:
-- a missing row would otherwise make `tax_on_fees` null and take the tax line
-- off the bill entirely. The fallbacks are 0078's own literals.
create or replace function public.fee_gst_rate_bps()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select t.fee_gst_rate_bps from public.tax_settings t where t.id = 1),
    1800
  );
$$;

comment on function public.fee_gst_rate_bps() is
  'GST on a platform service charge — delivery, platform fee, surge. The fee '
  'amounts stored on an order are inclusive of it (0078). Read from '
  'tax_settings since 0170; was a literal 1800.';

create or replace function public.packaging_gst_rate_bps()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select t.packaging_gst_rate_bps from public.tax_settings t where t.id = 1),
    500
  );
$$;

comment on function public.packaging_gst_rate_bps() is
  'GST on a packaging charge. Ancillary to the supply of the food it wraps, so '
  'it follows the food rate rather than the service rate (0078). Read from '
  'tax_settings since 0170; was a literal 500.';

-- 0078 created both without a revoke, so each has been executable by PUBLIC
-- since. They are definer functions reading a settings table now, which is the
-- point at which that stops being merely untidy. The standing rule from 0089:
-- both routes off, then granted back to the roles that need them.
revoke all on function public.fee_gst_rate_bps() from public, anon, authenticated;
grant execute on function public.fee_gst_rate_bps() to authenticated, service_role;

revoke all on function public.packaging_gst_rate_bps() from public, anon, authenticated;
grant execute on function public.packaging_gst_rate_bps() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. The console writes them.
-- ---------------------------------------------------------------------------
-- Both in one call, because they are saved by one button on one card: two RPCs
-- would let a page half-save and leave the invoice basis in a state nobody
-- chose.
create or replace function public.admin_set_tax_settings(
  p_fee_gst_rate_bps       integer,
  p_packaging_gst_rate_bps integer
) returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_slabs constant integer[] := array[0, 500, 1200, 1800];
begin
  perform public.assert_admin();

  if p_fee_gst_rate_bps is null or p_packaging_gst_rate_bps is null then
    raise exception 'A GST rate is a number, even when that number is 0.'
      using errcode = 'P0001';
  end if;

  -- The column checks would refuse these too, as a constraint violation. Said
  -- here instead so the screen shows a sentence, and said with the list in it
  -- because "not a slab" is only useful alongside which ones are.
  if not (p_fee_gst_rate_bps = any (v_slabs)) then
    raise exception
      '% is not a GST slab. The rates on this platform are 0, 5%%, 12%% and 18%% — pass 0, 500, 1200 or 1800 basis points.',
      p_fee_gst_rate_bps
      using errcode = 'P0001';
  end if;
  if not (p_packaging_gst_rate_bps = any (v_slabs)) then
    raise exception
      '% is not a GST slab. The rates on this platform are 0, 5%%, 12%% and 18%% — pass 0, 500, 1200 or 1800 basis points.',
      p_packaging_gst_rate_bps
      using errcode = 'P0001';
  end if;

  update public.tax_settings
     set fee_gst_rate_bps       = p_fee_gst_rate_bps,
         packaging_gst_rate_bps = p_packaging_gst_rate_bps,
         updated_at             = now()
   where id = 1;

  -- The sentence names the thing somebody changing a tax rate is most likely to
  -- be wrong about: that it reaches backwards. It does not.
  -- Integer division, not `/ 100.0`: all four slabs are whole percents, so this
  -- says "18%" where numeric would say "18.0%". And a single `%`, because this
  -- is concatenation and not a `raise` format string.
  return 'GST is now ' || (p_fee_gst_rate_bps / 100) || '% inside service fees and '
      || (p_packaging_gst_rate_bps / 100) || '% on packaging, for orders placed from now on. '
      || 'Orders already on the books keep the tax they were charged, and their invoices do not change.';
end;
$fn$;

comment on function public.admin_set_tax_settings(integer, integer) is
  '0170: the two platform-level GST rates. Applies to orders placed after it, '
  'never to orders already on the books.';

revoke all on function public.admin_set_tax_settings(integer, integer)
  from public, anon, authenticated;
grant execute on function public.admin_set_tax_settings(integer, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The trail.
-- ---------------------------------------------------------------------------
-- The same shape the other four settings tables got in 0159. `'id'` is the
-- column left out of the recorded row; there is no credential on this table, so
-- that is the only argument.
drop trigger if exists tax_settings_audit on public.tax_settings;
create trigger tax_settings_audit
  after update on public.tax_settings
  for each row
  when (
    old.fee_gst_rate_bps is distinct from new.fee_gst_rate_bps
    or old.packaging_gst_rate_bps is distinct from new.packaging_gst_rate_bps
  )
  execute function public.record_admin_action('id');

-- ---------------------------------------------------------------------------
-- 5. The settings screen reads them with the rest.
-- ---------------------------------------------------------------------------
-- Restated whole rather than patched, for 0162's reason: it is a
-- `jsonb_build_object` and a one-line insertion into one is legible in a way a
-- string replacement over a function body is not.
--
-- `food_slabs_in_use` is the honest answer to the question this card raises and
-- does not itself answer — "so what is the food taxed at?". Food is per dish,
-- so the only true answer is which slabs the live menu actually sits on, and a
-- screen that showed one number here would be inventing a rate the platform
-- does not have.
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
    'tax', (
      select to_jsonb(t)
             || jsonb_build_object(
                  -- Which slabs the available menu is actually on, with a dish
                  -- count each. Read-only: the item dialog owns these.
                  'food_slabs_in_use',
                  coalesce((
                    select jsonb_agg(jsonb_build_object('rate_bps', s.gst_rate_bps,
                                                        'items', s.n)
                                     order by s.gst_rate_bps)
                      from (select m.gst_rate_bps, count(*) as n
                              from public.menu_items m
                              join public.restaurants r on r.id = m.restaurant_id
                             where m.is_available and r.is_active
                             group by m.gst_rate_bps) s
                  ), '[]'::jsonb))
        from public.tax_settings t where t.id = 1
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
  '0159: dispatch, surcharge and payment settings in one object, plus the rider cash cap for reference, plus the base delivery fee (0162) and the two GST rates (0170). Never returns the weather API key.';

revoke all on function public.admin_platform_settings() from public, anon, authenticated;
grant execute on function public.admin_platform_settings() to authenticated;

-- ---------------------------------------------------------------- verification
-- 1. Neither rate is a literal any more, and all six money functions still
--    reach them by name:
--
--      select p.proname
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and pg_get_functiondef(p.oid) like '%fee_gst_rate_bps%'
--         and p.proname <> 'fee_gst_rate_bps';
--      -- expected: place_order, checkout_preflight, reorder_quote,
--      --           gift_order_quote, place_gift_order (and 0143's twin)
--
--      select p.provolatile from pg_proc p join pg_namespace n
--             on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('fee_gst_rate_bps', 'packaging_gst_rate_bps');
--      -- expected: 's' for both, not 'i'
--
-- 2. Move the rate and watch a quote move with it, then put it back:
--
--      begin;
--      update public.tax_settings set fee_gst_rate_bps = 500 where id = 1;
--      select public.checkout_preflight(…);   -- tax_on_fees drops
--      rollback;
--
-- 3. The delivery fee itself does not move when the rate does — the tax comes
--    out of the inside of it:
--
--      begin;
--      update public.tax_settings set fee_gst_rate_bps = 0 where id = 1;
--      select public.checkout_preflight(…);   -- delivery_fee unchanged, tax_on_fees 0
--      rollback;
--
-- 4. The guard, as a sentence rather than a constraint violation:
--
--      select public.admin_set_tax_settings(18, 500);    -- refused
--      select public.admin_set_tax_settings(1800, 2800); -- refused
--
-- 5. An invoice does not move. Pick an order, print it, change the rate, print
--    it again, and diff:
--
--      select public.order_invoice('<order>');
