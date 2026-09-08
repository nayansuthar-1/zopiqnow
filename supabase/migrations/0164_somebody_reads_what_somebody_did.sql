-- ---------------------------------------------------------------------------
-- 0164 — somebody reads what somebody did.
-- ---------------------------------------------------------------------------
-- `admin_actions` has been append-only since 0092 and the console has never
-- shown it. Every publish, block, refund, cancel, delete and override is in
-- there with the email of whoever did it — 1,103 rows on 2026-09-08, back to
-- 4 August — and the only way to read one has been a psql session.
--
-- ## Two of these functions already exist on the live database
--
-- And **no migration file records them.** They were applied by hand during an
-- earlier attempt at this screen whose migration was never committed, so the
-- live database has an eight-argument `admin_list_actions` and an
-- `admin_action_filters` that a database rebuilt from this directory would not.
-- That is the ledger drifting from the schema in the direction nobody notices:
-- everything works until the day somebody restores from the files.
--
-- So this file is written to be the record of what is already there. On the
-- live database it is a no-op for the shape and changes exactly one thing (the
-- payload, below); on a fresh one it is the whole feature.
--
-- ## Why 0092's signature is dropped rather than replaced
--
-- 0092 declared `admin_list_actions(text, text, integer, integer)` — target
-- type, actor, limit, offset. This wants six filters, and adding arguments does
-- not replace a function, it **creates a second one beside it**. PostgREST then
-- picks by the argument names it is handed, and the day somebody calls it with
-- a subset that matches the old four, they silently get the old body: no date
-- window, no total count, and a `detail` nobody reduced. Drop it.
--
-- ## What the browser is sent
--
-- `detail`, reduced through `audit_detail_changes` (0154). The trigger stores
-- `{before: <whole row>, after: <whole row>}`, which is the right thing to
-- store — a dispute is answered by the whole row — and fifty of those is a
-- megabyte of mostly-identical columns for a table that wants to show what
-- changed. A restaurant being paused becomes `{accepting_orders: {from: true,
-- to: false}}`. An insert's payload and a delete's snapshot pass through
-- untouched, because for those the whole row *is* the change, and a deleted
-- order's snapshot is the only copy of it left anywhere.
--
-- Nothing is masked. Rider licence and ID-proof numbers are in this trail and
-- are shown, because the same admins read them on the KYC screen already and a
-- redaction that protects nothing costs the trail its meaning. There is no
-- export: the screen is a reader, and an "export all" button is how an
-- append-only audit trail becomes a spreadsheet on somebody's laptop.
-- ---------------------------------------------------------------------------

drop function if exists public.admin_list_actions(text, text, integer, integer);

create or replace function public.admin_list_actions(
  p_actor       text default null,
  p_action      text default null,
  p_target_type text default null,
  p_target_id   text default null,
  p_from        timestamptz default null,
  p_to          timestamptz default null,
  p_limit       integer default 50,
  p_offset      integer default 0
)
returns table (
  id          bigint,
  actor_email text,
  action      text,
  target_type text,
  target_id   text,
  detail      jsonb,
  created_at  timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_actor  text;
  v_action text;
  v_type   text;
  v_target text;
  v_limit  integer;
begin
  perform public.assert_admin();

  v_actor  := nullif(lower(trim(coalesce(p_actor, ''))), '');
  v_action := nullif(trim(coalesce(p_action, '')), '');
  v_type   := nullif(trim(coalesce(p_target_type, '')), '');
  v_target := nullif(trim(coalesce(p_target_id, '')), '');
  v_limit  := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  with matched as (
    select a.id, a.actor_email, a.action, a.target_type,
           a.target_id, a.detail, a.created_at
      from public.admin_actions a
     where (v_actor  is null or a.actor_email = v_actor)
       and (v_action is null or a.action      = v_action)
       and (v_type   is null or a.target_type = v_type)
       -- Case-insensitive, and knowingly not index-friendly. What gets typed
       -- into that box is an order id off a customer's screenshot or an email
       -- out of a support thread, and `zpq-1044` finding nothing while
       -- `ZPQ-1044` finds six is a search box that lies. The table is 1,103 rows
       -- growing by a few hundred a month; the scan is not the thing that will
       -- ever be slow here.
       and (v_target is null or upper(a.target_id) = upper(v_target))
       and (p_from   is null or a.created_at >= p_from)
       and (p_to     is null or a.created_at <  p_to)
  )
  select m.id, m.actor_email, m.action, m.target_type,
         m.target_id, public.audit_detail_changes(m.detail), m.created_at,
         count(*) over () as total_count
    from matched m
   -- `id` after `created_at`, and not merely as a tie-break: rows written inside
   -- one transaction share an instant exactly, and a delete that cascaded into
   -- forty rows should read in the order it happened rather than in whatever
   -- order the planner hands them back.
   order by m.created_at desc, m.id desc
   limit v_limit offset greatest(coalesce(p_offset, 0), 0);
end;
$function$;

comment on function public.admin_list_actions(
  text, text, text, text, timestamptz, timestamptz, integer, integer) is
  '0164: the append-only admin trail (0092), filtered by actor, action, target type, target id and a date window. `detail` is reduced to its changed fields; `total_count` is the size of the whole match.';

-- Born executable by PUBLIC *and* with a default grant to `authenticated`
-- (0093). Shut both routes, then reopen the one the console signs in on;
-- `assert_admin()` is what actually decides.
revoke all on function public.admin_list_actions(
  text, text, text, text, timestamptz, timestamptz, integer, integer)
  from public, anon, authenticated;
grant execute on function public.admin_list_actions(
  text, text, text, text, timestamptz, timestamptz, integer, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- What is actually in there, for the three dropdowns.
-- ---------------------------------------------------------------------------
-- The alternative is a hardcoded list of tables and verbs in the browser, which
-- would be wrong the first time a trigger is added to a table — 0092 wired
-- thirteen and there are twenty-three now. Asking the trail what it contains
-- cannot drift, and the counts beside each value are what make the dropdown
-- readable: `menu_items` is 952 of the 1,103 rows, and knowing that before you
-- filter is the difference between "the trail is mostly one seeding run" and
-- "the trail is enormous".
create or replace function public.admin_action_filters()
returns table (kind text, value text, uses bigint)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  perform public.assert_admin();

  return query
  select 'actor'::text, a.actor_email, count(*)
    from public.admin_actions a group by a.actor_email
  union all
  select 'action'::text, a.action, count(*)
    from public.admin_actions a group by a.action
  union all
  select 'target'::text, a.target_type, count(*)
    from public.admin_actions a group by a.target_type
  order by 1, 3 desc, 2;
end;
$function$;

comment on function public.admin_action_filters() is
  '0164: every actor, action and target type present in admin_actions, with how many rows each one has. Feeds the audit screen dropdowns so they cannot drift from the triggers.';

revoke all on function public.admin_action_filters() from public, anon, authenticated;
grant execute on function public.admin_action_filters() to authenticated;
