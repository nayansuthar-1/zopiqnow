-- 0130 — a rider who accepts must collect.
--
-- Accepting a job and then not collecting it is the most expensive thing a
-- rider can do to an order, and until now it cost them nothing. The order sat
-- `ready_for_pickup` with a live `deliveries` row, which is exactly the state
-- `offer_delivery` refuses to dispatch (0121: "if a delivery exists and is not
-- cancelled, return null") — so the food went cold behind a rider who was never
-- coming, and no other rider could be offered it. The only way out was a
-- support release by hand.
--
-- This closes it in three parts:
--
--   1. **The order goes back on the board.** A sweep pulls the job back and
--      re-dispatches it. That is the customer-facing half and the reason this
--      runs every minute rather than nightly.
--   2. **The rider is warned, once.** The first no-show is a notification in
--      their inbox saying what happened and what happens if it repeats.
--   3. **A repeat reaches an admin.** Two in a week raises an alert in the
--      console — the rider, the count, the orders — with the suspend switch
--      beside it, and emails whoever is on `platform_admins`. It **suggests**
--      the suspension and never performs it: `delivery_partners.is_active` is
--      ops' switch (0025) and stopping somebody earning is a person's decision,
--      not a cron job's.
--
-- ---------------------------------------------------------------------------
-- When the clock starts, and why it is not `claimed_at`.
-- ---------------------------------------------------------------------------
-- A rider who accepts a job for a kitchen that has not finished cooking is
-- doing the right thing — arriving early is what makes `ready_by` worth
-- chasing (0049). Striking them for the kitchen's slowness would teach the
-- fleet to accept late, which is the opposite of what dispatch wants.
--
-- So the clock starts at the **later** of the acceptance and the moment the
-- food was actually ready, and there was no record of the second one: `ready_by`
-- is an estimate made when the order is accepted, not a stamp of when the bag
-- hit the counter. Section A adds it.
--
-- ---------------------------------------------------------------------------
-- On a rider who has arrived and still not collected.
-- ---------------------------------------------------------------------------
-- They are struck too, on the same clock — otherwise "I've arrived" becomes a
-- button you tap from home to buy immunity, and that button is self-reported
-- with nothing behind it. But a rider who was standing at the counter when the
-- handover failed is quite possibly not the one at fault: the vendor may have
-- marked the bag ready ten minutes before packing it. So `had_arrived` is
-- recorded on the strike and shown in the console, and the alert is a
-- suggestion an admin reads rather than an action the system takes. A false
-- strike costs a rider nothing on its own; it costs them a conversation.

-- ===========================================================================
-- A. When the food was actually ready.
-- ===========================================================================
-- A `before update` trigger rather than a line inside whichever RPC marks an
-- order ready, for 0092's reason about audit triggers: a trigger on the table
-- cannot be forgotten by the next function that writes the same column. Vendor
-- app, admin console and any future path all stamp it.
--
-- Stamped once. An order that somehow returns to `ready_for_pickup` keeps the
-- first time it was ready, which is the time the rider was made to wait.
alter table public.orders
  add column if not exists ready_at timestamptz;

comment on column public.orders.ready_at is
  'When the bag was actually on the counter. Distinct from ready_by, which is '
  'an estimate made at acceptance. Starts the rider no-show clock.';

create or replace function public.stamp_order_ready_at()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'ready_for_pickup' and new.ready_at is null then
    new.ready_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists orders_stamp_ready_at on public.orders;
create trigger orders_stamp_ready_at
  before update of status on public.orders
  for each row when (new.status = 'ready_for_pickup')
  execute function public.stamp_order_ready_at();

-- Orders already sitting ready when this migration ran have no stamp and would
-- never be swept. Stamped `now()` rather than reconstructed: `orders` keeps no
-- `updated_at`, so the only honest reconstruction available is "when we started
-- watching". Backdating them to `created_at` would strike whichever riders
-- happen to be holding those jobs the moment the sweep first runs, for a rule
-- that did not exist while they were holding them.
update public.orders
   set ready_at = now()
 where status = 'ready_for_pickup' and ready_at is null;

-- ===========================================================================
-- B. The knobs.
-- ===========================================================================
-- Onto `dispatch_settings` rather than a table of their own: these are numbers
-- about how a job moves between riders, which is what that table is, and three
-- integers do not earn a second settings row to keep in sync.
alter table public.dispatch_settings
  -- Minutes from the later of (accepted, food ready) before the job is pulled
  -- back. Ten: long enough to cross any of the three towns we serve, short
  -- enough that the food is still worth eating when the next rider gets it.
  add column if not exists no_show_after_minutes integer not null default 10,
  -- The window a repeat has to fall inside. A rider who no-shows twice six
  -- months apart is not a pattern.
  add column if not exists no_show_window_days   integer not null default 7,
  -- How many inside that window before an admin hears about it. Two: the first
  -- is the warning, the second is the repetition.
  add column if not exists no_show_alert_at      integer not null default 2;

-- ===========================================================================
-- C. What happened.
-- ===========================================================================
-- A log, not a queue: rows are never deleted, because the count over the last
-- seven days *is* the feature and a table that forgets cannot answer it.
create table if not exists public.rider_no_shows (
  id            bigint generated always as identity primary key,
  partner_email text not null references public.delivery_partners(email),
  order_id      text not null references public.orders(id) on delete cascade,

  accepted_at   timestamptz not null,
  ready_at      timestamptz,
  -- Whether they had tapped "I've arrived" before the clock ran out. See the
  -- header: this is the column that keeps a queue at the counter from reading
  -- as a rider who never showed up.
  had_arrived   boolean     not null default false,

  released_at   timestamptz not null default now()
);

create index if not exists rider_no_shows_partner_idx
  on public.rider_no_shows (partner_email, released_at desc);

-- One strike per rider per order, ever. Without it a re-offer that comes back
-- to the same rider and is ghosted twice counts as two, and worse, the sweep
-- retrying inside a single minute could double-count one failure.
create unique index if not exists rider_no_shows_once_per_job
  on public.rider_no_shows (partner_email, order_id);

alter table public.rider_no_shows enable row level security;
revoke all on public.rider_no_shows from anon, authenticated;

-- ===========================================================================
-- D. The admin's desk.
-- ===========================================================================
-- Deliberately not a row in `notifications`. That table's audiences are the
-- three apps (0047) and its recipient columns are checked against them; an
-- 'admin' audience would mean a fourth recipient column, a widened constraint,
-- and a read policy for a console that authenticates differently from all three
-- apps. This is a smaller thing: a list of things somebody should look at, read
-- by RPC like every other console surface.
create table if not exists public.admin_alerts (
  id          bigint generated always as identity primary key,
  kind        text not null,
  -- Who or what the alert is about. For a no-show alert, the rider's email —
  -- and the column the "is one already open" check keys on.
  subject     text,
  title       text not null,
  body        text not null,
  order_id    text references public.orders(id) on delete set null,
  created_at  timestamptz not null default now(),

  resolved_at timestamptz,
  resolved_by text
);

-- One open alert per subject per kind. The point of the index: a rider who
-- no-shows a third and fourth time updates the alert that is already on the
-- desk rather than laying a fresh one beside it, so the console shows a queue
-- of people, not a queue of incidents.
create unique index if not exists admin_alerts_one_open_per_subject
  on public.admin_alerts (kind, subject) where resolved_at is null;

create index if not exists admin_alerts_open_idx
  on public.admin_alerts (created_at desc) where resolved_at is null;

alter table public.admin_alerts enable row level security;
revoke all on public.admin_alerts from anon, authenticated;

-- Resolving an alert is an admin deciding that a rider who ghosted three orders
-- needs nothing done about it. 0092's trail should have that.
drop trigger if exists admin_alerts_audit_resolve on public.admin_alerts;
create trigger admin_alerts_audit_resolve after update on public.admin_alerts
  for each row when (old.resolved_at is distinct from new.resolved_at)
  execute function public.record_admin_action('id');

-- ===========================================================================
-- E. A word the rider's inbox understands.
-- ===========================================================================
-- 0047's constraint is a `check` and not an enum precisely so that this is an
-- `alter` and not a lock: each app maps a kind it does not know to a neutral
-- notice, so a build already on a phone shows this as a plain row rather than
-- crashing on it.
--
-- **The list below is 0077's, not 0047's**, and the difference cost this
-- migration a failed run. `drop constraint` then `add constraint` restates the
-- whole set, so the set has to be the *live* one — and 0047's eight kinds are
-- five short of the thirteen that have accumulated since (`order_live`,
-- `job_offer`, `job_cancelled`, `message`, `review`, `refund`). Restating the
-- list from the migration that first declared the column drops five kinds with
-- 300 rows behind them, and Postgres refuses the constraint rather than the
-- data — which is the good outcome, but only because the rows happened to be
-- there. Whoever adds the fourteenth kind: read the live constraint, not this
-- file.
alter table public.notifications
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check
    check (kind in (
      'new_order',      -- vendor: a customer placed an order (0021)
      'system',         -- anyone: a catch-all notice
      'order_update',   -- customer: their order changed status
      'order_live',     -- customer: the live tracking card (0052)
      'job_offer',      -- rider: a job offered to them by name (0056)
      'job_available',  -- rider: a delivery is on the board to claim
      'job_cancelled',  -- rider: the job they held was called off (0051)
      'payout',         -- rider: a payout was paid
      'account',        -- rider: their partner account was activated/deactivated
      'settlement',     -- vendor: a weekly settlement was paid
      'message',        -- anyone: a line of order chat (0061)
      'review',         -- vendor: the meal got a verdict (0062)
      'refund',         -- customer: money is coming back (0077)
      'warning'         -- rider: they did something that will cost them (0130)
    ));

-- ===========================================================================
-- F. The email.
-- ===========================================================================
-- `pg_net` straight at Brevo's transactional API — the same account that
-- already sends the login OTP, and the same in-database shape as 0046's route
-- lookups, for the same reason: the Edge Functions in this project go weeks
-- between deploys and an alert must not wait on one.
--
-- **The key is not in this file and is not in the database yet.** Brevo's SMTP
-- password (the `xsmtpsib-` string in `.env`) is not an API key and will not
-- authenticate here; a `xkeysib-` key has to be minted in the Brevo console and
-- put in Vault:
--
--     select vault.create_secret('xkeysib-…', 'brevo_api_key');
--
-- Until that exists this returns quietly and **the alert is still raised** — the
-- console is the surface that must never depend on a third party, and the email
-- is the convenience on top of it. A missing key must not cost us the record.
create or replace function public.email_admin_alert(p_alert_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key   text;
  v_alert record;
  v_to    jsonb;
begin
  select decrypted_secret into v_key
    from vault.decrypted_secrets
   where name = 'brevo_api_key';
  if v_key is null then
    return;
  end if;

  select * into v_alert from public.admin_alerts where id = p_alert_id;
  if not found then
    return;
  end if;

  select jsonb_agg(jsonb_build_object('email', email))
    into v_to
    from public.platform_admins;
  if v_to is null then
    return;
  end if;

  -- The sender is the address Brevo has verified for this account and is the
  -- same one the login OTP comes from. An unverified sender is a 400 from
  -- Brevo, not a bounce, so it fails loudly in `net._http_response`.
  perform net.http_post(
    url     := 'https://api.brevo.com/v3/smtp/email',
    headers := jsonb_build_object(
      'api-key',      v_key,
      'content-type', 'application/json',
      'accept',       'application/json'
    ),
    body := jsonb_build_object(
      'sender', jsonb_build_object('email', 'zopiqnow2026@gmail.com',
                                   'name',  'Zopiqnow'),
      'to',           v_to,
      'subject',      v_alert.title,
      'textContent',  v_alert.body
    ),
    timeout_milliseconds := 8000
  );
end;
$$;

revoke all on function public.email_admin_alert(bigint)
  from public, anon, authenticated;

-- ===========================================================================
-- G. The sweep.
-- ===========================================================================
-- Every minute, and doing four things per stranded job: take it off the rider,
-- record the strike, warn them, and put the order back into dispatch.
--
-- **Each job is wrapped in its own exception block.** One rider whose strike
-- insert conflicts, or one order `offer_delivery` chokes on, must not abort the
-- sweep and leave every other stranded order stranded — the failure mode of a
-- fix for stranded orders should not be more stranded orders.
create or replace function public.sweep_rider_no_shows()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s          public.dispatch_settings%rowtype;
  j          record;
  v_count    integer;
  v_orders   text;
  v_name     text;
  v_alert_id bigint;
  v_offered  text;
  v_body     text;
begin
  select * into s from public.dispatch_settings where id = 1;

  for j in
    select d.order_id,
           d.partner_email,
           d.claimed_at,
           o.ready_at,
           d.state = 'arrived_at_restaurant' as had_arrived
      from public.deliveries d
      join public.orders o on o.id = d.order_id
     where d.state in ('claimed', 'arrived_at_restaurant')
       and o.status = 'ready_for_pickup'
       and o.ready_at is not null
       and greatest(d.claimed_at, o.ready_at)
             < now() - make_interval(mins => s.no_show_after_minutes)
  loop
    begin
      -- 1. Off the rider. Scoped to the live row and the holder, per 0049's
      --    abandon-and-reclaim lesson: an order with a cancelled row beside the
      --    live one must not have the corpse dragged along.
      update public.deliveries
         set state = 'cancelled'
       where order_id = j.order_id
         and partner_email = j.partner_email
         and state in ('claimed', 'arrived_at_restaurant');

      if not found then
        -- They collected it in the seconds between the query and here. Nothing
        -- happened, and nothing should be recorded.
        continue;
      end if;

      -- The codes go with the job, exactly as `abandon_delivery` does it: a
      -- rider who has been taken off an order must not still hold a working
      -- pickup code for it.
      delete from public.delivery_codes where order_id = j.order_id;

      -- 2. The strike.
      insert into public.rider_no_shows
        (partner_email, order_id, accepted_at, ready_at, had_arrived)
      values
        (j.partner_email, j.order_id, j.claimed_at, j.ready_at, j.had_arrived)
      on conflict (partner_email, order_id) do nothing;

      -- 3. The warning. Always sent, including on the run that also raises the
      --    admin alert — a rider being discussed by ops should know why.
      insert into public.notifications
        (audience, partner_email, kind, title, body, order_id)
      values
        ('rider', j.partner_email, 'warning',
         'Order taken back',
         'You accepted this delivery but did not collect it, so it has been '
         'given to another rider. Repeatedly accepting orders you do not pick '
         'up can get your account suspended.',
         j.order_id);

      -- 4. Back on the board. `offer_delivery` will not return it to the same
      --    rider — it excludes anyone who already has an offer row on the order
      --    (0121), and theirs says 'accepted'.
      --
      --    In its own block: a dispatch that raises must not roll back the
      --    release above it. An order freed from a rider with nobody offered it
      --    yet is picked up by `dispatch_deliveries` within twenty seconds
      --    anyway, so the release is the part worth keeping — and rolling it
      --    back would strand the order forever behind a rider who is not coming,
      --    which is the exact bug this migration exists to fix.
      begin
        v_offered := public.offer_delivery(j.order_id);
        if v_offered is null then
          perform public.announce_open_delivery(j.order_id);
        end if;
      exception when others then
        null;
      end;

      -- 5. Is this a pattern?
      select count(*),
             string_agg(ns.order_id, ', ' order by ns.released_at desc)
        into v_count, v_orders
        from public.rider_no_shows ns
       where ns.partner_email = j.partner_email
         and ns.released_at > now() - make_interval(days => s.no_show_window_days);

      if v_count >= s.no_show_alert_at then
        select name into v_name
          from public.delivery_partners where email = j.partner_email;

        v_body :=
          coalesce(v_name, j.partner_email) || ' (' || j.partner_email || ') has '
          || 'accepted ' || v_count || ' orders in the last '
          || s.no_show_window_days || ' days without collecting them.' || chr(10)
          || chr(10)
          || 'Orders: ' || v_orders || chr(10) || chr(10)
          || 'Each one was taken back and given to another rider. Consider '
          || 'suspending this delivery partner in the Zopiqnow console '
          || '(Riders -> Active switch) until you have spoken to them.';

        -- One open alert per rider: the third and fourth no-show update the
        -- alert already on the desk rather than queueing behind it.
        insert into public.admin_alerts (kind, subject, title, body, order_id)
        values (
          'rider_no_shows', j.partner_email,
          'Rider not collecting orders: ' || coalesce(v_name, j.partner_email),
          v_body, j.order_id
        )
        on conflict (kind, subject) where resolved_at is null
        do update set title      = excluded.title,
                      body       = excluded.body,
                      order_id   = excluded.order_id,
                      created_at = now()
        returning id into v_alert_id;

        -- Emailed on every repeat, not only the first: an alert that silently
        -- updates itself is one nobody is told about twice.
        perform public.email_admin_alert(v_alert_id);
      end if;
    exception when others then
      -- Log-free by necessity (there is nowhere to log to that a cron job's
      -- failure would not also break) and deliberate: the next tick tries this
      -- job again in sixty seconds.
      null;
    end;
  end loop;
end;
$$;

revoke all on function public.sweep_rider_no_shows()
  from public, anon, authenticated;

select cron.unschedule('sweep-rider-no-shows')
 where exists (select 1 from cron.job where jobname = 'sweep-rider-no-shows');

select cron.schedule(
  'sweep-rider-no-shows',
  '* * * * *',
  $$ select public.sweep_rider_no_shows(); $$
);

-- ===========================================================================
-- H. What the console reads.
-- ===========================================================================
-- Through RPCs, like every other admin surface (0066 onward), so the tables
-- above stay closed and the read is one auditable place rather than a policy
-- somebody widens later.
create or replace function public.admin_alerts_list(p_include_resolved boolean default false)
returns table (
  id            bigint,
  kind          text,
  subject       text,
  title         text,
  body          text,
  order_id      text,
  created_at    timestamptz,
  resolved_at   timestamptz,
  resolved_by   text,
  -- The rider the alert is about, so the console can offer the switch without
  -- a second round trip and can show whether somebody already threw it.
  rider_name    text,
  rider_phone   text,
  rider_active  boolean,
  no_show_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  s public.dispatch_settings%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Not a Zopiqnow admin.' using errcode = 'P0001';
  end if;

  -- Aliased, and `ds.id` rather than `id`: this function's OUT parameters
  -- include `id`, and plpgsql resolves a bare column name against them first —
  -- an unqualified `where id = 1` is "column reference id is ambiguous" at run
  -- time, on a function that compiles perfectly.
  select ds.* into s from public.dispatch_settings ds where ds.id = 1;

  return query
    select a.id, a.kind, a.subject, a.title, a.body, a.order_id,
           a.created_at, a.resolved_at, a.resolved_by,
           p.name, p.phone, p.is_active,
           (select count(*)::integer
              from public.rider_no_shows ns
             where ns.partner_email = a.subject
               and ns.released_at > now() - make_interval(days => s.no_show_window_days))
      from public.admin_alerts a
      left join public.delivery_partners p on p.email = a.subject
     where p_include_resolved or a.resolved_at is null
     order by a.resolved_at nulls first, a.created_at desc
     limit 200;
end;
$$;

revoke all on function public.admin_alerts_list(boolean)
  from public, anon, authenticated;
grant execute on function public.admin_alerts_list(boolean) to authenticated;

-- Dealt with. Not a delete: who dismissed an alert about a rider, and when, is
-- the kind of thing that matters the day the rider disputes a suspension.
create or replace function public.admin_resolve_alert(p_alert_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not a Zopiqnow admin.' using errcode = 'P0001';
  end if;

  update public.admin_alerts
     set resolved_at = now(),
         resolved_by = lower(auth.jwt() ->> 'email')
   where id = p_alert_id
     and resolved_at is null;
end;
$$;

revoke all on function public.admin_resolve_alert(bigint)
  from public, anon, authenticated;
grant execute on function public.admin_resolve_alert(bigint) to authenticated;

-- The incidents behind one alert, for the admin who wants to see them before
-- taking somebody's income away.
create or replace function public.admin_rider_no_shows(p_email text)
returns table (
  order_id    text,
  accepted_at timestamptz,
  ready_at    timestamptz,
  had_arrived boolean,
  released_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not a Zopiqnow admin.' using errcode = 'P0001';
  end if;

  return query
    select ns.order_id, ns.accepted_at, ns.ready_at, ns.had_arrived, ns.released_at
      from public.rider_no_shows ns
     where ns.partner_email = lower(p_email)
     order by ns.released_at desc
     limit 50;
end;
$$;

revoke all on function public.admin_rider_no_shows(text)
  from public, anon, authenticated;
grant execute on function public.admin_rider_no_shows(text) to authenticated;

-- ---------------------------------------------------------------- verification
-- 1. The stamp. Mark an order ready from the vendor app and read it back:
--
--      select id, status, ready_by, ready_at from public.orders
--       where status = 'ready_for_pickup' order by ready_at desc limit 5;
--
-- 2. The sweep, without waiting ten minutes. Take a live claimed delivery on a
--    ready order, age it, and run the sweep by hand:
--
--      update public.deliveries set claimed_at = now() - interval '30 minutes'
--       where order_id = '<id>';
--      update public.orders set ready_at = now() - interval '30 minutes'
--       where id = '<id>';
--      select public.sweep_rider_no_shows();
--
--      select * from public.rider_no_shows order by released_at desc limit 5;
--      select state from public.deliveries where order_id = '<id>';   -- cancelled
--      select * from public.notifications
--       where kind = 'warning' order by created_at desc limit 5;
--      select id, title, subject from public.admin_alerts
--       where resolved_at is null;                    -- only on the 2nd strike
--
-- 3. The console's reads, as an admin and as somebody who is not:
--
--      select * from public.admin_alerts_list();
--      select public.admin_resolve_alert(<id>);
--      select * from public.admin_actions order by created_at desc limit 3;
--
-- 4. Grants, per 0087. The three console RPCs executable by `authenticated`
--    (they check `is_admin()` themselves); the sweep, the email and nothing
--    else by nobody:
--
--      select has_function_privilege('authenticated','public.sweep_rider_no_shows()','execute'),
--             has_function_privilege('anon',         'public.sweep_rider_no_shows()','execute'),
--             has_function_privilege('authenticated','public.email_admin_alert(bigint)','execute'),
--             has_function_privilege('authenticated','public.admin_alerts_list(boolean)','execute');
--
-- 5. The tables are closed to the API:
--
--      select has_table_privilege('anon','public.admin_alerts','select'),
--             has_table_privilege('authenticated','public.rider_no_shows','select');
