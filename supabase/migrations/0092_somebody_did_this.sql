-- 0092 - somebody did this
--
-- Ship-plan S8, 3 August 2026. Audit SEC-003 says the admin console is one flat
-- role with no MFA, and that it can release, cancel and delete orders - the
-- delete being unguarded since 0069. Full RBAC and MFA are deferred until a
-- second admin account exists. **An append-only record of who did what is not**,
-- because the whole value of RBAC you do not have is knowing afterwards.
--
-- --------------------------------------------------------------------------
-- Why triggers on tables, and not a log line inside each admin function.
-- --------------------------------------------------------------------------
--
-- There are 72 `admin_*` functions and roughly 25 of them are destructive. Adding
-- a call to each means rewriting 25 bodies, and every one is a chance to
-- mistranscribe a function that is working today. Worse, it records only what we
-- remembered to instrument: the next migration that deletes a row directly, or a
-- console screen that grows a new delete, is silently outside the trail.
--
-- A trigger on the table cannot be forgotten, because it is attached to the
-- thing being protected rather than to the path that happens to reach it. That
-- is the same reasoning as 0084, 0085, 0088 and 0090 - the rule belongs to the
-- table - and it is why this migration rewrites no existing function at all.
--
-- The actor comes from the JWT, so it is whoever the request belonged to. A
-- deletion run by a migration or a cron job has no JWT and is recorded as
-- `system`, which is a true and useful answer rather than a null.
--
-- --------------------------------------------------------------------------
-- What is covered, stated plainly so the gaps are known rather than assumed.
-- --------------------------------------------------------------------------
--
-- **Every DELETE** on: orders, restaurants, menu_items, coupons, hero_slides,
-- platform_admins, restaurant_staff, delivery_partners. These are the rows whose
-- loss cannot be undone from inside the product.
--
-- **Privilege grants:** an INSERT into platform_admins. Adding an admin is the
-- one action that manufactures more of the power this table exists to watch, so
-- it is recorded even though it destroys nothing.
--
-- **Money and livelihood, on the state change that matters:** refunds,
-- settlements and rider_payouts when `status` moves; delivery_partners and
-- restaurants when `is_active` moves. The `when` clause does the filtering, so an
-- ordinary edit writes nothing and the trail stays readable.
--
-- **Deliberately not covered:** ordinary order lifecycle transitions (the kitchen
-- and the rider move those constantly and they are already reconstructable from
-- the order), menu edits short of deletion, and reads. An audit log that records
-- everything is one nobody reads.
--
-- **Two narrower ledgers already exist and both stay.** `admin_order_deletions`
-- (0069) keeps a full snapshot of a deleted order, which is richer than this;
-- `user_blocks` (0088) is the moderation history a person's page renders. This
-- table double-records an order deletion on purpose - the snapshot ledger is
-- written by `admin_delete_order`, so it only sees deletions that went through
-- that function, and the point of the trigger is to see the ones that did not.

create table if not exists public.admin_actions (
  id           bigserial primary key,
  actor_email  text        not null,
  action       text        not null,
  target_type  text        not null,
  target_id    text,
  detail       jsonb,
  created_at   timestamptz not null default now()
);

create index if not exists admin_actions_recent_idx
  on public.admin_actions (created_at desc);
create index if not exists admin_actions_actor_idx
  on public.admin_actions (actor_email, created_at desc);

alter table public.admin_actions enable row level security;

-- No policies, deliberately. The table is read through `admin_list_actions`
-- below and nowhere else - the same shape as `user_blocks` (0088). RLS with no
-- policy means PostgREST returns nothing to anybody, whatever the grants say.

-- Append-only, and meant literally. Grants alone would leave `postgres` and
-- `service_role` able to rewrite history; a trigger refuses the statement itself,
-- so the only way to alter this table is to deliberately disable a trigger -
-- which is an act nobody performs by accident.
create or replace function public.admin_actions_are_append_only()
returns trigger
language plpgsql
as $function$
begin
  raise exception
    'admin_actions is append-only — a row that has been written cannot be changed or removed.'
    using errcode = 'P0001';
end;
$function$;

revoke execute on function public.admin_actions_are_append_only() from public;

create trigger admin_actions_no_update
  before update on public.admin_actions
  for each statement execute function public.admin_actions_are_append_only();

create trigger admin_actions_no_delete
  before delete on public.admin_actions
  for each statement execute function public.admin_actions_are_append_only();

-- --------------------------------------------------------------------------
-- The recorder. One function for every table, told which column names the row.
-- --------------------------------------------------------------------------
--
-- `TG_ARGV[0]` is the primary-key column, which differs per table (`id`, `code`,
-- `email`). Reading it out of `to_jsonb(row)` keeps this one function generic
-- without any dynamic SQL.

create or replace function public.record_admin_action()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor text;
  v_old   jsonb;
  v_new   jsonb;
begin
  -- Whoever the request belonged to. No JWT means a migration, a cron job or a
  -- trigger cascade — `system` says that honestly.
  v_actor := coalesce(
    lower(nullif(trim(coalesce(auth.jwt() ->> 'email', '')), '')),
    'system'
  );

  if tg_op = 'DELETE' then
    v_old := to_jsonb(old);
  elsif tg_op = 'INSERT' then
    v_new := to_jsonb(new);
  else
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
  end if;

  insert into public.admin_actions
    (actor_email, action, target_type, target_id, detail)
  values (
    v_actor,
    lower(tg_op),
    tg_table_name,
    coalesce(v_old, v_new) ->> tg_argv[0],
    case
      when tg_op = 'DELETE' then jsonb_build_object('deleted', v_old)
      when tg_op = 'INSERT' then jsonb_build_object('created', v_new)
      else jsonb_build_object('before', v_old, 'after', v_new)
    end
  );

  -- An `after` trigger's return value is ignored; null is the conventional way
  -- to say so.
  return null;
end;
$function$;

revoke execute on function public.record_admin_action() from public;

-- --------------------------------------------------------------------------
-- Deletions. Nothing here can be undone from inside the product.
-- --------------------------------------------------------------------------

create trigger orders_audit_delete after delete on public.orders
  for each row execute function public.record_admin_action('id');

create trigger restaurants_audit_delete after delete on public.restaurants
  for each row execute function public.record_admin_action('id');

create trigger menu_items_audit_delete after delete on public.menu_items
  for each row execute function public.record_admin_action('id');

create trigger coupons_audit_delete after delete on public.coupons
  for each row execute function public.record_admin_action('code');

create trigger hero_slides_audit_delete after delete on public.hero_slides
  for each row execute function public.record_admin_action('id');

create trigger platform_admins_audit_delete after delete on public.platform_admins
  for each row execute function public.record_admin_action('email');

create trigger restaurant_staff_audit_delete after delete on public.restaurant_staff
  for each row execute function public.record_admin_action('email');

create trigger delivery_partners_audit_delete after delete on public.delivery_partners
  for each row execute function public.record_admin_action('email');

-- --------------------------------------------------------------------------
-- Privilege. Making an admin is the action that makes more of this power.
-- --------------------------------------------------------------------------

create trigger platform_admins_audit_insert after insert on public.platform_admins
  for each row execute function public.record_admin_action('email');

-- --------------------------------------------------------------------------
-- Money, and the two switches that stop somebody working. Only on the change
-- that matters, so an ordinary edit does not fill the trail with noise.
-- --------------------------------------------------------------------------

create trigger refunds_audit_status after update on public.refunds
  for each row when (old.status is distinct from new.status)
  execute function public.record_admin_action('id');

create trigger settlements_audit_status after update on public.settlements
  for each row when (old.status is distinct from new.status)
  execute function public.record_admin_action('id');

create trigger rider_payouts_audit_status after update on public.rider_payouts
  for each row when (old.status is distinct from new.status)
  execute function public.record_admin_action('id');

create trigger delivery_partners_audit_active after update on public.delivery_partners
  for each row when (old.is_active is distinct from new.is_active)
  execute function public.record_admin_action('email');

create trigger restaurants_audit_active after update on public.restaurants
  for each row when (old.is_active is distinct from new.is_active)
  execute function public.record_admin_action('id');

-- --------------------------------------------------------------------------
-- Reading it back. The console's only door to this table.
-- --------------------------------------------------------------------------

create or replace function public.admin_list_actions(
  p_target_type text default null,
  p_actor       text default null,
  p_limit       integer default 100,
  p_offset      integer default 0
)
returns table (
  id          bigint,
  actor_email text,
  action      text,
  target_type text,
  target_id   text,
  detail      jsonb,
  created_at  timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  perform public.assert_admin();

  return query
  select a.id, a.actor_email, a.action, a.target_type, a.target_id,
         a.detail, a.created_at
    from public.admin_actions a
   where (p_target_type is null or a.target_type = p_target_type)
     and (p_actor is null or a.actor_email = lower(trim(p_actor)))
   order by a.created_at desc, a.id desc
   limit greatest(least(coalesce(p_limit, 100), 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$function$;

revoke execute on function public.admin_list_actions(text, text, integer, integer)
  from public;
grant execute on function public.admin_list_actions(text, text, integer, integer)
  to authenticated;

-- --------------------------------------------------------------------------
-- Reading it is for admins only, and not because a policy says so.
-- --------------------------------------------------------------------------
--
-- 0089's fixed default worked: `admin_actions` arrived with no INSERT, UPDATE,
-- DELETE or TRUNCATE for `anon` or `authenticated` — the first table created
-- since, and a live confirmation rather than a comment. **SELECT it did still
-- get**, because that default is unchanged and correct for the ninety per cent
-- of tables the apps read directly.
--
-- This is not one of those. RLS with no policy already returns nothing to
-- everybody, but S4's lesson was precisely that RLS should not be the only thing
-- standing in front of a table — and this one holds `detail` snapshots of
-- deleted rows, which is the most personal data in the schema gathered into one
-- place. `user_blocks` (0088) is the same kind of ledger and gets the same
-- treatment here.
--
-- Both are read through their admin RPCs, which are SECURITY DEFINER and so are
-- unaffected by this.

revoke select on table public.admin_actions from anon, authenticated;
revoke select on table public.user_blocks  from anon, authenticated;
