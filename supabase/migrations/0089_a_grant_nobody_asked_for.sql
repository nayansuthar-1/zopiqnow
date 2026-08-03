-- 0089 - a grant nobody asked for
--
-- Found by the ship-plan money-path sweep (S4), 3 August 2026, and it is 0087's
-- finding wearing different clothes: a privilege that arrives by default, that
-- nobody wrote down, held harmless by a second control that was never meant to
-- be the only one.
--
-- **What is true today.** Twenty-five tables in `public` carry INSERT, UPDATE,
-- DELETE and TRUNCATE for both `anon` and `authenticated`. Among them: `orders`,
-- `order_items`, `restaurants`, `settlements`, `platform_admins`, `user_blocks`.
-- Read from the live database, not from the migrations:
--
--     select table_name, grantee, privilege_type
--       from information_schema.role_table_grants
--      where table_schema = 'public'
--        and grantee in ('anon', 'authenticated')
--        and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE');
--
-- **Nothing is exploitable through them right now, and that is not the point.**
-- Every one of those tables has RLS enabled and not one permissive write policy,
-- so an UPDATE matches zero rows and an INSERT fails its check. Verified over
-- HTTP with the anon key: a POST to /rest/v1/orders is 401, and to
-- /rest/v1/payment_intents and /rest/v1/refunds - which carry no grant at all -
-- also 401. The difference between those two 401s is the whole finding. One is
-- refused because the privilege does not exist; the other is refused because a
-- policy is doing the work of a privilege.
--
-- So the system is one mistake deep. A single `for all using (true)` written in
-- a hurry, or one `alter table ... disable row level security` run while
-- debugging, turns a policy oversight into a stranger rewriting `orders.total`.
-- Defence in depth means the grant should not be there either.
--
-- **TRUNCATE is the one that is not merely theoretical.** Row-level security
-- governs SELECT, INSERT, UPDATE, DELETE and MERGE. It does not govern TRUNCATE,
-- which is checked against the TRUNCATE privilege alone - so for these tables RLS
-- is not a second control at all, it is no control. What stops it today is that
-- PostgREST exposes no TRUNCATE verb and `anon` and `authenticated` are NOLOGIN
-- roles reachable only through it. That is an accident of the client, not a
-- decision of ours, and it is the sort of thing that changes in a minor release.
--
-- **Where these came from, and why sweeping is not enough.** Two stored
-- default-ACL rows in `public` grant `arwdDxtm` on every new table to `anon` and
-- `authenticated`:
--
--     select pg_get_userbyid(defaclrole), defaclacl from pg_default_acl
--      where defaclnamespace = 'public'::regnamespace and defaclobjtype = 'r';
--     -- postgres        {...,anon=arwdDxtm/postgres,authenticated=arwdDxtm/...}
--     -- supabase_admin  {...,anon=arwdDxtm/supabase_admin,...}
--
-- Every table any migration has ever created arrived fully writable by anonymous
-- callers, and every table a future one creates would too. The last statement in
-- this file fixes the `postgres` row, which is the one our migrations run under,
-- so this is a default that is corrected rather than a list that is swept. The
-- `supabase_admin` row is left alone: we never create tables as that role, and it
-- is not ours to alter.
--
-- **What keeps its privileges, and why.** Exactly three tables are written to
-- directly by a client rather than through an RPC - confirmed by reading every
-- `.from(...).insert/update/upsert/delete` in all three Flutter apps and the
-- admin console, which between them produce matches for these three and nothing
-- else:
--
--     addresses    a customer's own addresses   (user_id = auth.uid())
--     favourites   a customer's own favourites  (user_id = auth.uid())
--     menu_items   a restaurant's own menu      (restaurant_id = staff_restaurant_id())
--
-- Those keep INSERT, UPDATE and DELETE for `authenticated`. They lose them for
-- `anon`, which could never have satisfied any of those policies - all three turn
-- on a null `auth.uid()` - and they lose TRUNCATE, which no policy governs and no
-- caller needs.
--
-- Nothing here changes what any signed-in user can do. Every write in all four
-- clients goes through a SECURITY DEFINER function owned by `postgres`, and those
-- are unaffected by table grants on `anon` and `authenticated`.

-- --------------------------------------------------------------------------
-- The twenty-five with no write policy at all: every write privilege goes.
-- --------------------------------------------------------------------------

revoke insert, update, delete, truncate on table
  public.deliveries,
  public.delivery_offers,
  public.delivery_partner_bank_accounts,
  public.delivery_partners,
  public.device_tokens,
  public.gift_items,
  public.gift_shops,
  public.menu_option_groups,
  public.menu_options,
  public.notifications,
  public.order_item_options,
  public.order_items,
  public.order_route_jobs,
  public.orders,
  public.platform_admins,
  public.restaurant_bank_accounts,
  public.restaurant_hours,
  public.restaurant_legal,
  public.restaurant_staff,
  public.restaurants,
  public.rider_locations,
  public.rider_pay_rates,
  public.rider_payouts,
  public.settlements,
  public.user_blocks
from anon, authenticated;

-- --------------------------------------------------------------------------
-- The three a client really does write: `anon` loses everything, and TRUNCATE
-- goes for both. `authenticated` keeps what its policies are there to scope.
-- --------------------------------------------------------------------------

revoke insert, update, delete, truncate on table
  public.addresses, public.favourites, public.menu_items
from anon;

revoke truncate on table
  public.addresses, public.favourites, public.menu_items
from authenticated;

-- --------------------------------------------------------------------------
-- And the default that produced all of it. Tables created after this line by
-- `postgres` - which is every table a migration makes - arrive readable and not
-- writable, so the next one does not need to remember.
-- --------------------------------------------------------------------------

alter default privileges for role postgres in schema public
  revoke insert, update, delete, truncate on tables from anon, authenticated;

-- The check that keeps this closed, in the shape of 0087's. Run it before every
-- release; it must return zero rows. A row means a table carries a write
-- privilege that no policy scopes - either the grant is wrong, or the policy it
-- was written for is missing.
--
--   select g.table_name, g.grantee, g.privilege_type
--     from information_schema.role_table_grants g
--    where g.table_schema = 'public'
--      and g.grantee in ('anon', 'authenticated', 'PUBLIC')
--      and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
--      and not exists (
--            select 1
--              from pg_policy p
--              join pg_class c on c.oid = p.polrelid
--              join pg_namespace n on n.oid = c.relnamespace
--             where n.nspname = 'public'
--               and c.relname = g.table_name
--               and p.polcmd <> 'r'
--               and g.privilege_type <> 'TRUNCATE'
--          );
