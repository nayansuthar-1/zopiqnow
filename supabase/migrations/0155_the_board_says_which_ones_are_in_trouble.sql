-- ---------------------------------------------------------------------------
-- 0155 — the board says which ones are in trouble.
-- ---------------------------------------------------------------------------
-- The live board sorts oldest-first and prints a sentence composed by the
-- console — "on the shelf, offered to Ravi, 22 seconds left". That is a person
-- doing breach detection by eye: reading twenty rows, subtracting two timestamps
-- in their head, and deciding which one to ring about.
--
-- The database already knows. Every fact the arithmetic needs is a column on
-- `orders`, `deliveries`, `delivery_offers` or `payment_intents`, and it is the
-- same arithmetic every time. So it moves here, beside the data, and the board
-- becomes a triage list: *which* orders are late, and *why*.
--
-- ## Six kinds, and what each one is really asking
--
--   * **`unaccepted`** — placed, and the kitchen has not answered. 0128's ring
--     and 0136's wake-up both exist to prevent exactly this, so an unaccepted
--     order is not only late, it is evidence that the ring did not work. Two
--     minutes by default, which is deliberately *before* `accept_deadline`: the
--     five-minute auto-reject is the customer's protection, and this is the
--     warning that lets somebody stop it being needed.
--
--   * **`stuck_prep`** — accepted, and the kitchen has gone quiet past its own
--     promise. `ready_by` is the prep time the kitchen itself chose, so this is
--     not the platform's opinion about how long food takes.
--
--   * **`no_rider`** — cooked, on the shelf, nobody carrying it. The one breach
--     here with food going cold at the other end.
--
--   * **`dispatch_stalled`** — riders were rung, none is holding it, and nothing
--     has been offered since. Named for what it measures. The honest condition
--     for *exhausted* is 0148's candidate query — every online rider has already
--     been offered and is therefore excluded — and reproducing that here would
--     be a second copy of dispatch's own selection logic, which would drift.
--     "We rang and have not rung again" is cheaper, always true when exhaustion
--     is true, and is the sentence an admin acts on either way.
--
--   * **`eta_slipped`** — the arrival time now promised is later than the one
--     promised at checkout. `created_at + eta_minutes` is that original promise;
--     `eta_at` is the live one (0057). This is the breach the customer already
--     knows about, which is why it is worth seeing before they ring.
--
--   * **`payment_unverified`** — a `upi` order with no verified intent behind it
--     (0085). The kitchen is cooking against money nobody proved. `cod` is not a
--     gap: the constraint on `orders.payment_method` allows exactly `cod` and
--     `upi`, and a cash order has no intent by design.
--
-- ## Why the thresholds are a row and not a constant
--
-- Every number above is a judgement about this town on this evening, not a fact
-- about the software. Two minutes is right for Sadri at eight o'clock and wrong
-- for a wedding weekend when every kitchen is under water and ops does not want
-- twenty red rows. A constant would make each of those a migration; a row makes
-- it an UPDATE, and — once T2 builds the settings screen — a form.
--
-- ## Why `admin_orders` is dropped rather than replaced
--
-- `create or replace` cannot change a function's return type, and this adds two
-- output columns. The signature is unchanged, so nothing that calls it has to
-- change; the grant is reapplied below because dropping takes it with it.
-- ---------------------------------------------------------------------------

create table if not exists public.sla_settings (
  -- One row, the way `dispatch_settings` and `payment_settings` are one row.
  id                       integer primary key default 1 check (id = 1),

  -- Placed, not yet accepted. Before `accept_deadline`, on purpose.
  unaccepted_seconds       integer not null default 120,
  -- Preparing, past the kitchen's own `ready_by`.
  stuck_prep_seconds       integer not null default 600,
  -- On the shelf with no rider carrying it.
  no_rider_seconds         integer not null default 300,
  -- Rung, nobody holding it, nothing offered since.
  dispatch_stalled_seconds integer not null default 120,

  updated_at               timestamptz not null default now(),

  -- A threshold of zero would put every live order in breach the moment it was
  -- placed, which is the same as having no breaches at all.
  constraint sla_thresholds_are_positive check (
    unaccepted_seconds > 0 and stuck_prep_seconds > 0
    and no_rider_seconds > 0 and dispatch_stalled_seconds > 0
  )
);

insert into public.sla_settings (id) values (1) on conflict (id) do nothing;

comment on table public.sla_settings is
  '0155: how long each stage may take before the live board calls it a breach. One row.';

-- Born writable by `anon` (0093). Nothing outside the database reads this yet —
-- `admin_orders` reads it as definer — so shut every route and let T2''s
-- settings screen open the one it needs.
alter table public.sla_settings enable row level security;
revoke all on table public.sla_settings from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The live board, with the breaches on it.
-- ---------------------------------------------------------------------------
-- Everything above the two new columns is 0066's function unchanged, taken from
-- `pg_get_functiondef` on the live database rather than from its migration file,
-- so what is replaced is what was actually running.

drop function if exists public.admin_orders(text);

create function public.admin_orders(p_query text default null)
returns table (
  order_id text,
  restaurant_id text,
  restaurant_name text,
  status text,
  status_reason text,
  placed_at timestamptz,
  accept_deadline timestamptz,
  ready_by timestamptz,
  eta_at timestamptz,
  eta_reason text,
  total integer,
  payment_method text,
  coupon_code text,
  delivery_to text,
  customer_phone text,
  route_km numeric,
  rider_email text,
  rider_name text,
  rider_phone text,
  rider_vehicle text,
  delivery_state text,
  claimed_at timestamptz,
  offer_to text,
  offer_expires_at timestamptz,
  -- New in 0155. Empty array, never null, so the console can count it without
  -- asking whether it exists.
  breaches text[],
  -- When the *oldest* live breach started, so the board can sort by "worst
  -- first" rather than by age. Null when there are none.
  breach_since timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_q text;
  v_sla public.sla_settings%rowtype;
begin
  perform public.assert_admin();

  v_q := nullif(trim(coalesce(p_query, '')), '');

  select * into v_sla from public.sla_settings where id = 1;

  return query
    select
      o.id, o.restaurant_id, o.restaurant_name,
      o.status, o.status_reason, o.created_at,
      o.accept_deadline, o.ready_by, o.eta_at, o.eta_reason,
      o.total, o.payment_method, o.coupon_code,
      o.delivery_to, o.user_phone, o.route_km,
      d.partner_email, dp.name, dp.phone, dp.vehicle,
      d.state, d.claimed_at,
      off.partner_email, off.expires_at,
      b.kinds,
      b.since
    from public.orders o
    -- The live delivery, if there is one. `state <> 'cancelled'` is the same
    -- predicate as the partial unique index behind it, so this join can match
    -- at most one row by construction rather than by a `limit 1` and a hope.
    left join public.deliveries d
           on d.order_id = o.id and d.state <> 'cancelled'
    left join public.delivery_partners dp on dp.email = d.partner_email
    left join lateral (
      select f.partner_email, f.expires_at
        from public.delivery_offers f
       where f.order_id = o.id
         and f.state = 'offered'
         and f.expires_at > now()
       order by f.expires_at desc
       limit 1
    ) off on true

    -- When this order was last rung, whatever came of it. Lifted out here rather
    -- than written inside the breach arm below, because a plain subquery in a
    -- FROM clause cannot reach the outer row — only a lateral one can, and one
    -- lateral read is cheaper than the three scalar subqueries the arm would
    -- otherwise repeat.
    left join lateral (
      select max(f.expires_at) as last_offer_at
        from public.delivery_offers f
       where f.order_id = o.id
    ) lo on true

    -- The breaches, as one array and one clock.
    --
    -- Each arm is a (kind, started) pair or nothing, and the whole thing is
    -- computed once per row rather than six times: `since` is the minimum of
    -- whatever the arms produced, which is the moment this order first went
    -- wrong by any measure.
    --
    -- A finished order is never in breach. What went wrong on an order that has
    -- already been delivered, rejected or cancelled is a question for its own
    -- page (0154) and for Analytics — not for a board whose whole job is the
    -- things somebody can still do something about.
    left join lateral (
      select
        coalesce(array_agg(x.kind order by x.started), '{}'::text[]) as kinds,
        min(x.started)                                              as since
      from (
        select 'unaccepted' as kind, o.created_at as started
         where o.status = 'placed'
           and now() > o.created_at + make_interval(secs => v_sla.unaccepted_seconds)

        union all
        select 'stuck_prep', o.ready_by
         where o.status = 'preparing'
           and o.ready_by is not null
           and now() > o.ready_by + make_interval(secs => v_sla.stuck_prep_seconds)

        union all
        select 'no_rider', coalesce(o.ready_at, o.ready_by, o.created_at)
         where o.status = 'ready_for_pickup'
           and d.id is null
           and now() > coalesce(o.ready_at, o.ready_by, o.created_at)
                       + make_interval(secs => v_sla.no_rider_seconds)

        union all
        -- Rung at least once, nobody holding it now, and the last ring lapsed
        -- long enough ago that the dispatcher should have gone round again.
        select 'dispatch_stalled', lo.last_offer_at
         where o.status not in ('delivered', 'cancelled', 'rejected')
           and d.id is null
           and lo.last_offer_at is not null
           and off.partner_email is null
           and now() > lo.last_offer_at
                       + make_interval(secs => v_sla.dispatch_stalled_seconds)

        union all
        -- The promise made at checkout, against the one being made now.
        select 'eta_slipped', o.created_at + make_interval(mins => o.eta_minutes)
         where o.status not in ('delivered', 'cancelled', 'rejected')
           and o.eta_at is not null
           and o.eta_at > o.created_at + make_interval(mins => o.eta_minutes)

        union all
        select 'payment_unverified', o.created_at
         where o.status not in ('delivered', 'cancelled', 'rejected')
           and o.payment_method = 'upi'
           and not exists (
             select 1 from public.payment_intents pi
              where pi.order_id = o.id and pi.verified_at is not null
           )
      ) x
      -- A terminal order carries no breaches at all, whatever the arms above
      -- would have said. Stated once here rather than repeated into six `where`
      -- clauses, three of which would otherwise be the only place it was said.
      where o.status not in ('delivered', 'cancelled', 'rejected')
    ) b on true

    where (
      v_q is null
      and o.status not in ('delivered', 'cancelled', 'rejected')
    ) or (
      v_q is not null
      and (
        upper(o.id) = upper(v_q)
        -- A phone match on the last digits, so a number typed with or without
        -- +91 finds the same customer. Guarded against an all-letters query,
        -- which would strip to '' and then match every order ever placed.
        or (
          regexp_replace(v_q, '[^0-9]', '', 'g') <> ''
          and o.user_phone like '%' || regexp_replace(v_q, '[^0-9]', '', 'g')
        )
      )
    )
    -- Live board: **worst first, then oldest**. Breach order is the change 0155
    -- makes to this list, and it is the whole point — an order that has been
    -- open twelve minutes and is fine matters less than one that has been open
    -- three and nobody has accepted. Search: newest first, because a phone
    -- number matches every order that customer has ever placed.
    order by case when v_q is null then b.since end asc nulls last,
             case when v_q is null then o.created_at end asc nulls last,
             o.created_at desc
    limit 200;
end;
$fn$;

comment on function public.admin_orders(text) is
  '0155: the live board, each row carrying the breaches it is in and when the oldest of them started. No argument is every open order, worst first; an argument is a lookup by id or phone across every status.';

-- Born executable by PUBLIC *and* with a default grant to `authenticated`
-- (0093), and the drop above took the explicit grant with it. Shut both routes,
-- then reopen the one the console signs in on.
revoke all on function public.admin_orders(text) from public, anon, authenticated;
grant execute on function public.admin_orders(text) to authenticated;
