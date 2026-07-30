-- ---------------------------------------------------------------------------
-- 0073 — only the caller who needs it, everywhere. (Audit SEC-002)
-- ---------------------------------------------------------------------------
-- Postgres grants EXECUTE to PUBLIC on every function it creates, and Supabase
-- adds `alter default privileges in schema public grant all on functions to
-- anon, authenticated, service_role` on top. Between them, a function in this
-- project is born callable by anyone holding the anon key — and the anon key
-- ships inside every APK.
--
-- 94 of the 140 `security definer` functions carry an explicit `revoke ... from
-- public`. 46 do not. Measured against the live database rather than the
-- migration files the number is worse: **131 of 151** project-owned functions in
-- `public` were executable by `anon` before this migration, including
-- `set_order_status`, `confirm_pickup`, `confirm_delivered`, `claim_delivery`,
-- `accept_offer`, `cancel_my_order`, `order_pickup_code`, `order_delivery_code`,
-- `record_rider_location`, `vendor_analytics`, `rider_earnings` and
-- `register_device_token`.
--
-- Every one of those was read, and in every case the first statement is an
-- identity guard — `staff_restaurant_id()`, `delivery_partner_email()`,
-- `auth.uid()` — that raises for an anonymous caller. **This was missing defence
-- in depth, not an open door.** It is fixed at Critical rather than Blocker for
-- that reason. But the same class of mistake has already cost this project once:
-- 0064's own comment records that `coupons` "has carried Supabase's default
-- insert/update/delete grants for anon and authenticated since the day it was
-- created" — a real open write path that survived 61 migrations. A guard that is
-- one refactor away from being wrong should not be the only thing standing there.
--
-- WHAT THIS DOES NOT DO. It does not revoke `authenticated` wholesale and
-- re-grant from a hand-written list of every RPC. That version is tidier to read
-- and one typo away from a signed-in customer who cannot place an order. This
-- one removes exactly what is wrong and leaves every correct grant untouched:
--
--   1. PUBLIC loses EXECUTE on every function this project owns. Generated from
--      pg_proc, never hand-listed. Extension-owned functions (pg_trgm installs
--      26 of them into `public`) are excluded by owner and by pg_depend — they
--      belong to supabase_admin and breaking their operator classes would take
--      the search index with them.
--   2. `anon` loses EXECUTE everywhere except the four functions the signed-out
--      surface genuinely reaches. The customer app deliberately leaves browsing,
--      search and cart-building open (router.dart: only /checkout, /orders,
--      /addresses and /favourites are guarded), so that list is not empty and
--      must not be.
--   3. `authenticated` loses EXECUTE on the 19 functions that no client calls —
--      trigger bodies and internal helpers. Each was traced to its callers first;
--      all of them are `security definer` and therefore run as `postgres`, so
--      none needs a grant to the signed-in role. Trigger functions need no
--      EXECUTE grant at all: Postgres checks that privilege when the trigger is
--      created, not when it fires.
--   4. Default privileges are closed, for PUBLIC *and* for anon. Item 4 is the
--      actual fix; items 1-3 are the cleanup. Leaving Supabase's anon default in
--      place would mean the next function created is anon-callable again and this
--      sweep rots within a phase. The cost is that a genuinely public function
--      now needs an explicit `grant execute ... to anon` — a loud failure in
--      development, which is the right direction for this to fail in.
--
-- `order_message_body` is the one function that looks internal and is not. Its
-- caller `order_message_menu` is `security invoker`, so it runs as the customer,
-- not as postgres — it stays granted to `authenticated`. It is the single case
-- where "who calls it" was not enough and "as whom does the caller run" decided.
--
-- Table grants are NOT swept here. Every table carries the same default
-- insert/update/delete grants for anon and authenticated, but all 27 have RLS
-- enabled and only 8 permissive write policies exist across the schema — on
-- `addresses`, `favourites` and `menu_items`, each correctly scoped to
-- `authenticated` and to the row's owner. The grants are latent, not reachable.
-- That is the audit's SEC-002 item 4 and it is a separate task with a separate
-- risk profile; it is not smuggled in here.
-- ---------------------------------------------------------------------------

do $$
declare
  -- The functions the signed-out surface reaches. Browsing a menu, reading a
  -- restaurant's offers and reviews, and pricing a coupon into a cart all happen
  -- before a user has given us a phone number. This is the whole list; it was
  -- taken from the four functions the migrations had already granted `anon`
  -- deliberately, and re-derived from the router's unprotected routes.
  v_anon constant text[] := array[
    'menu_item_is_servable_now',
    'restaurant_offers',
    'restaurant_reviews',
    'validate_coupon'
  ];

  -- Trigger bodies and internal helpers. No client calls any of these, and every
  -- caller of every one of them is `security definer`, so the signed-in role
  -- never needs to execute them itself.
  v_internal constant text[] := array[
    -- trigger bodies
    'enqueue_order_route',
    'notify_customer_delivery_live',
    'notify_customer_order_live',
    'notify_customer_order_update',
    'notify_new_order',
    'notify_rider_account',
    'notify_rider_payout',
    'notify_vendor_settlement',
    'reestimate_on_delivery_change',
    'reestimate_on_order_change',
    'restaurants_set_search_text',
    -- helpers, called only from `security definer` bodies
    'delivery_distance_km',      -- available_deliveries, claim_delivery, my_offers, offer_delivery, order_live_payload, recompute_order_eta
    'delivery_offer_window',     -- offer_delivery
    'handover_minutes',          -- recompute_order_eta
    'rider_city_speed_kmh',      -- recompute_order_eta
    'resolve_order_line_options',-- place_order
    'restaurant_is_open_now',    -- place_order
    'regenerate_delivery_code',  -- no caller; the rider's code is issued by confirm_pickup
    'notify_riders_job_available'-- no caller; announce_open_delivery took this over
  ];

  f record;
  v_public_revoked int := 0;
  v_anon_revoked   int := 0;
  v_auth_revoked   int := 0;
begin
  for f in
    select p.oid::regprocedure as sig,
           p.proname,
           -- `has_function_privilege` takes a role name and PUBLIC is not one,
           -- so the PUBLIC grant has to be read off the aclitem directly: an
           -- entry with an empty grantee is PUBLIC's.
           array_to_string(p.proacl, ',') ~ '(^|,)=X/' as had_public
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_roles r     on r.oid = p.proowner
    where n.nspname = 'public'
      and p.prokind = 'f'
      and r.rolname = 'postgres'
      and not exists (
        select 1 from pg_depend d
        where d.objid = p.oid
          and d.classid = 'pg_proc'::regclass
          and d.deptype = 'e'          -- installed by an extension; not ours to touch
      )
    order by p.proname
  loop
    -- 1. PUBLIC, always. This is the finding.
    if f.had_public then
      v_public_revoked := v_public_revoked + 1;
    end if;
    execute format('revoke execute on function %s from public', f.sig);

    -- 2. anon, unless the signed-out surface reaches it. Tested *after* the
    --    PUBLIC revoke above, so what it measures is anon's own grant rather
    --    than the access it was inheriting through PUBLIC.
    if not (f.proname = any(v_anon)) then
      if has_function_privilege('anon', f.sig::oid, 'execute') then
        v_anon_revoked := v_anon_revoked + 1;
      end if;
      execute format('revoke execute on function %s from anon', f.sig);
    else
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;

    -- 3. authenticated, only where nothing signed-in calls it.
    if f.proname = any(v_internal) then
      if has_function_privilege('authenticated', f.sig::oid, 'execute') then
        v_auth_revoked := v_auth_revoked + 1;
      end if;
      execute format('revoke execute on function %s from authenticated', f.sig);
    end if;

    -- The Edge Functions and the scheduled runners hold the service key and are
    -- the one caller that must never be locked out by this sweep.
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;

  raise notice 'SEC-002: revoked execute from PUBLIC on % function(s), from anon on %, from authenticated on %.',
    v_public_revoked, v_anon_revoked, v_auth_revoked;
end $$;

-- 4. The actual fix. Everything above is cleanup; without this the next `create
--    function` re-opens the hole and nobody finds out.
--
--    Both spellings are needed. The unqualified form covers objects created by
--    the role running this statement; the `for role postgres` form covers the
--    role that owns everything here and that migrations run as. Postgres keys
--    default privileges on the creating role, so a default set by one role says
--    nothing about another.
alter default privileges in schema public
  revoke execute on functions from public;
alter default privileges in schema public
  revoke execute on functions from anon;

alter default privileges for role postgres in schema public
  revoke execute on functions from public;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;
