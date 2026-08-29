-- ---------------------------------------------------------------------------
-- 0148 — the ring moves on, but the job stays.
-- ---------------------------------------------------------------------------
-- Three changes to dispatch, and they are one change: a rider is asked loudly,
-- briefly, and alone — and being passed over no longer takes the job away from
-- them.
--
-- ## What was already true, so that what is new is legible
--
-- 0056 replaced the free-for-all board with a dispatcher: one rider is offered
-- an order at a time, 0099 ranked that choice nearest-first inside a widening
-- ring, and 0121 stopped two sweeper runs deadlocking over it. Phones have not
-- rung all at once since B3. What was wrong was everything around it:
--
--   1. **Forty-five seconds is a long time to hold a customer's order** while
--      one rider does not look at their phone, and the sweeper's 20-second tick
--      could add twenty more on top. Worst case, one unheard offer cost 65
--      seconds.
--
--   2. **A rider who missed the window lost the job entirely.**
--      `available_deliveries` hides any order with a live offer on it, from
--      everybody. So the moment the offer moved to the next partner, the first
--      one's app went blank — not "somebody else is deciding", *gone*. A rider
--      who was 300 m from the kitchen and reached their phone eight seconds too
--      late had nothing to reach for.
--
--   3. **The push was a polite ping.** 0128 taught the *kitchen's* phone to ring
--      like a call — the device ringtone on the alarm stream, repeating, drawn
--      by the app itself so `FLAG_INSISTENT` could be attached. A rider got the
--      ordinary `jobs`-channel notification, which a phone in a pocket on a road
--      does not produce. The ring is a **send-side** change (`send-notification`)
--      plus the rider app drawing its own notification; the only thing it needs
--      from the database is the deadline, which `offer_delivery` has written
--      into `notifications.data` since 0097. So there is nothing here for it.
--
-- ## What this migration does
--
-- **The window is 15 seconds and the tick is 5.** Both are rows in
-- `dispatch_settings` rather than constants, so the numbers can move without a
-- deploy — which matters, because 15 seconds is a guess about how long it takes
-- a rider to get a phone out of a pocket and nobody has measured it yet. Worst
-- case a rider who ignores an offer now costs 20 seconds instead of 65.
--
-- **A job you were offered stays on your board.** The visibility rule changes
-- from "hide any order under a live offer" to "hide it from everybody *except*
-- the riders it has already been offered to". So the ring moves down the line
-- and the order stays in the first rider's pool, marked as being with somebody
-- else, and they can still take it.
--
-- **Which is exactly what creates a race, so there is now a contest.** Before
-- this migration two riders could not both accept one order, because only one of
-- them could see it. Now three can. The rule asked for is *the nearest to the
-- restaurant wins*, and the honest way to do that is to stop deciding it on who
-- tapped first:
--
--   * The first tap on a **contested** order opens a two-second window.
--   * Every tap that lands inside it joins.
--   * When it shuts, the rider with the smallest distance to the kitchen is
--     awarded the job — and if they cannot actually take it (offline since,
--     over the cash ceiling, a licence that expired between the tap and the
--     decision), the next-nearest is tried, and so on.
--   * Everyone else is told, in one sentence, that somebody was closer.
--
-- **The two seconds are only spent when they buy something.** An order that only
-- one rider can see is not contested, and goes through with no hold at all —
-- which is the overwhelming majority of offers, because during a rider's own
-- 15-second window nobody else has been asked yet. A rider pays the wait exactly
-- when there is somebody to lose to.
--
-- **"There must never be two riders on one order"** was already true and stays
-- true by the same mechanism it always has: `deliveries_one_live_per_order`, the
-- partial unique index from 0025. The contest decides *who is offered* the
-- insert; the index is still what decides that only one lands. Nothing here
-- weakens it, and the loop above depends on it — a contestant losing that index
-- race is caught and the next one is tried.
--
-- **The kitchen tapping "Start preparing" dispatches immediately.** It always
-- triggered dispatch — `offer_delivery` takes orders in `preparing` — but only on
-- the next sweeper tick, so the first rider was rung up to twenty seconds after
-- the food went on. `set_order_status` now offers the order in the same
-- transaction, wrapped so a dispatch that fails can never fail the cook's tap.
--
-- ## The one thing worth arguing with
--
-- A rider who **declined** does not keep seeing the order. Only a rider whose
-- offer ran out does. Decline is the rider saying no, and an app that keeps
-- showing a job you refused is an app that punishes you for answering it —
-- which is the fastest way to teach a fleet to ignore the ring instead. They
-- still see it if the whole fleet is exhausted and it reaches the open board,
-- exactly as they did before.

-- ===========================================================================
-- A. The two new knobs.
-- ===========================================================================
-- Alongside 0099's ring settings, in the same one-row table, for the same
-- reason: `update public.dispatch_settings set offer_window_seconds = 20;` is a
-- change ops can make at 8pm on a Friday and a constant in a function is not.
alter table public.dispatch_settings
  add column if not exists offer_window_seconds integer not null default 15;

alter table public.dispatch_settings
  add column if not exists contest_seconds numeric(4,1) not null default 2.0;

comment on column public.dispatch_settings.offer_window_seconds is
  'How long one rider has the order to themselves, and how long their phone '
  'rings. 15s from 0148, down from the 45s constant 0056 shipped. The rider '
  'keeps seeing the order after this runs out — it is an exclusivity window, '
  'not a visibility one.';

comment on column public.dispatch_settings.contest_seconds is
  'How long a contested order collects accepts before awarding it to the '
  'nearest rider (0148). Paid only when more than one rider can see the order; '
  'an uncontested accept is not held at all.';

-- ===========================================================================
-- B. The window, read from the table.
-- ===========================================================================
-- Restated from 0056, which returned `interval '45 seconds'` and said, fairly,
-- that "a table nobody writes to is a table that lies about being
-- configurable". There is now a reason to write to it.
--
-- Two changes of shape come with that. `immutable` becomes `stable`: a function
-- that reads a table is not immutable, and leaving the label on would licence
-- the planner to fold one call's answer into another's. And `security definer`,
-- because `dispatch_settings` has RLS on with no policy and no grants (0099) —
-- every caller today is itself a definer function owned by postgres, so this is
-- belt and braces rather than a new privilege.
--
-- The grants are untouched: 0073 revoked execute from public, anon and
-- authenticated, and `create or replace` preserves an ACL.
create or replace function public.delivery_offer_window()
returns interval
language sql
stable
security definer
set search_path = public
as $$
  select make_interval(secs => offer_window_seconds)
    from public.dispatch_settings where id = 1
$$;

comment on function public.delivery_offer_window() is
  'How long one rider holds an offer, from dispatch_settings.offer_window_seconds (0148).';

-- ===========================================================================
-- C. Somewhere to hold a contest.
-- ===========================================================================
-- One row per (order, rider) tap. It is a queue for two seconds and a log after
-- that: `won` and `decided_at` are what let a rider's phone ask "did I get it?"
-- without the answer depending on a socket having stayed up.
--
-- `distance_km` is frozen at the moment of the tap, exactly as
-- `delivery_offers.distance_km` is frozen at the moment of the offer, and for
-- the same reason — an audit of "why did this rider get this job" must be able
-- to read the number the decision was made on, not one recomputed later from a
-- rider who has since ridden somewhere else.
create table if not exists public.delivery_claims (
  order_id      text not null references public.orders(id) on delete cascade,
  partner_email text not null
    references public.delivery_partners(email) on delete cascade,
  -- Rider → kitchen when they tapped, in kilometres. Null when the phone has
  -- never reported a position and no offer froze one either; such a claim is
  -- ranked last rather than treated as zero kilometres away.
  distance_km   numeric(6,2),
  claimed_at    timestamptz not null default now(),
  -- Null while the contest is open. This is the column everything keys off:
  -- "an open contest" is `exists (… where decided_at is null)`.
  decided_at    timestamptz,
  won           boolean,
  primary key (order_id, partner_email)
);

-- The sweeper's read, and `offer_delivery`'s guard: is anything still being
-- decided? Partial, because a settled contest is history and history is the
-- part of this table that grows.
create index if not exists delivery_claims_open_idx
  on public.delivery_claims (order_id) where decided_at is null;

-- Nothing outside Postgres reads or writes this. RLS on with no policy is the
-- select half; the revoke is the write half, and it is not optional — a new
-- table arrives with write grants to `anon` (0089), and RLS has never covered
-- TRUNCATE.
alter table public.delivery_claims enable row level security;
revoke all on public.delivery_claims from anon, authenticated;

comment on table public.delivery_claims is
  'One tap of Accept on a contested order (0148). Open for dispatch_settings.'
  'contest_seconds, then awarded to the nearest rider who can actually take it.';

-- ===========================================================================
-- D. Is this order contested at all?
-- ===========================================================================
-- True when more than one rider can see it, which is the only case where "who
-- is nearest" is a question. Two ways that happens:
--
--   * it has been offered more than once — the first rider's window ran out,
--     the second is deciding, and the first still has it on their board;
--   * it reached the open board, where the whole fleet can see it.
--
-- Deliberately *not* "more than one rider has tapped": that is only knowable
-- after the fact, and the point of the window is to be open before the second
-- tap arrives.
create or replace function public.delivery_is_contested(p_order_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (
    select count(*) from public.delivery_offers where order_id = p_order_id
  ) > 1
  or exists (
    select 1 from public.notifications
     where kind = 'job_available' and order_id = p_order_id
  );
$$;

revoke all on function public.delivery_is_contested(text)
  from public, anon, authenticated;

-- The `job_available` half of that, and `announce_open_delivery`'s own
-- idempotency guard, have both been sequential scans of `notifications` since
-- 0056. At a 20-second tick nobody noticed; at five seconds it is worth an
-- index, and it is one line.
create index if not exists notifications_board_announcement_idx
  on public.notifications (order_id) where kind = 'job_available';

-- ===========================================================================
-- E. Claiming on somebody else's behalf.
-- ===========================================================================
-- `claim_delivery` reads the rider out of the JWT, which is right for a rider
-- tapping a button and impossible for a contest resolved on behalf of whoever
-- turned out to be nearest. So the body moves here, takes the rider as an
-- argument, and `claim_delivery` becomes the two lines that read the JWT and
-- call it.
--
-- Restated verbatim from 0097 apart from that. Every check stays and stays in
-- the same order — the KYC block before the online check (0080: "your licence
-- expired" is the more useful of the two sentences when both are true), the cash
-- ceiling before the insert (0076), the pay snapshot read off the accepted offer
-- (0097) so the fee that was rung is the fee that is paid.
--
-- ⚠️ **This must never be executable by a signed-in role.** It takes the rider
-- as a parameter, so a grant here is a grant to claim a job as somebody else.
-- Revoked from all three below, and `has_function_privilege` is the check worth
-- running after applying this file.
create or replace function public.claim_delivery_for(
  p_order_id text,
  p_rider    text
) returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_online   boolean;
  v_status   text;
  v_id       bigint;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_distance numeric(6,2);
  v_pay      integer;
  v_method   text;
  v_total    integer;
  v_cash     integer;
  v_cap      integer;
  v_block    text;
begin
  if p_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  v_block := public.rider_work_block(p_rider);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  select is_online into v_online
    from public.delivery_partners where email = p_rider;

  if not coalesce(v_online, false) then
    raise exception 'You are offline. Go online to take deliveries.'
      using errcode = 'P0001';
  end if;

  select o.status, o.payment_method, o.total
    into v_status, v_method, v_total
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found then
    raise exception 'That order no longer exists.' using errcode = 'P0001';
  end if;

  if v_status not in ('preparing', 'ready_for_pickup') then
    raise exception 'That order is no longer available.' using errcode = 'P0001';
  end if;

  if v_method = 'cod' then
    v_cash := public.rider_cash_in_hand(p_rider);
    v_cap  := public.rider_cash_cap();

    if v_cash + v_total > v_cap then
      raise exception
        'You''re holding ₹% in cash and this order collects ₹%, which is over the ₹% limit. Deposit what you''re carrying to take cash orders again.',
        v_cash, v_total, v_cap
        using errcode = 'P0001';
    end if;
  end if;

  -- What this rider was promised, if anybody promised them anything.
  select off.ride_km, off.pay_base, off.pay_per_km, off.rider_pay
    into v_distance, v_base, v_per_km, v_pay
    from public.delivery_offers off
   where off.order_id = p_order_id
     and off.partner_email = p_rider
     and off.state = 'accepted'
     and off.rider_pay is not null
   order by off.responded_at desc nulls last
   limit 1;

  -- Off the board, or an offer made before 0097 and so carrying no figures.
  if not found then
    select q.ride_km, q.pay_base, q.pay_per_km, q.rider_pay
      into v_distance, v_base, v_per_km, v_pay
      from public.rider_pay_quote(p_order_id) q;
  end if;

  insert into public.deliveries (
    order_id, partner_email,
    distance_km, pay_base, pay_per_km, rider_pay
  )
  values (
    p_order_id,
    p_rider,
    v_distance,
    v_base,
    v_per_km,
    v_pay
  )
  on conflict do nothing
  returning id into v_id;

  -- The index decided it, not us. Write the codes only for the winner.
  if v_id is null then
    raise exception 'Another partner just took that one.' using errcode = 'P0001';
  end if;

  insert into public.delivery_codes (order_id, pickup_code, delivery_code)
  values (
    p_order_id,
    lpad((floor(random() * 10000))::integer::text, 4, '0'),
    lpad((floor(random() * 10000))::integer::text, 4, '0')
  )
  on conflict (order_id) do update
     set pickup_code       = excluded.pickup_code,
         delivery_code     = excluded.delivery_code,
         pickup_attempts   = 0,
         delivery_attempts = 0,
         updated_at        = now();
end;
$function$;

revoke all on function public.claim_delivery_for(text, text)
  from public, anon, authenticated;

-- And the caller-scoped one, now a wrapper. Same signature, so this replaces
-- rather than overloads (0051's lesson).
--
-- **It gains the exclusivity check, and the reason is a version skew rather than
-- a rule.** `take_delivery` below is the door this app uses from 0148 on, and it
-- refuses a rider reaching into somebody else's fifteen seconds. Every rider
-- phone already in the field calls *this* instead — and until 0148 that was
-- safe, because `available_deliveries` never showed them an order under a live
-- offer at all. This migration makes it show them one. Without the check, an
-- un-updated build would be handed the ability to snipe a job out of the middle
-- of another rider's countdown, which is precisely what the window is for.
--
-- Deliberately **not** in `claim_delivery_for`: the contest resolves on behalf
-- of a rider whose own offer has by then been flipped to `'accepted'`, so the
-- same predicate there would reject every winner it just chose.
create or replace function public.claim_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_rider text;
  v_mine  text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select off.state into v_mine
    from public.delivery_offers off
   where off.order_id = p_order_id and off.partner_email = v_rider;

  if exists (
    select 1 from public.delivery_offers off
     where off.order_id = p_order_id
       and off.state = 'offered'
       and off.expires_at > now()
  ) and coalesce(v_mine, '') not in ('offered', 'expired') then
    raise exception
      'That job is with another partner right now. If they pass on it, it comes back to you.'
      using errcode = 'P0001';
  end if;

  perform public.claim_delivery_for(p_order_id, v_rider);
end;
$function$;

revoke execute on function public.claim_delivery(text) from public, anon;
grant execute on function public.claim_delivery(text) to authenticated;

-- ===========================================================================
-- F. Awarding a job: the offer is marked taken, then the delivery is written.
-- ===========================================================================
-- The order of the two statements is the point. `claim_delivery_for` reads the
-- pay off an offer in state `'accepted'`, so the flip has to happen first or the
-- winner is paid a freshly recomputed quote instead of the number their phone
-- rang with — the single fastest way to lose a fleet's trust (0056).
--
-- **`'expired'` is accepted as well as `'offered'`, and that is deliberate.**
-- A rider whose fifteen seconds ran out and who took the job from their board
-- thirty seconds later did accept the offer; they accepted it late. Their frozen
-- fee is still the honest one, because it is what they were shown.
--
-- If the claim raises — somebody else's insert won the unique index, the rider
-- went offline, the cash ceiling moved — the flip rolls back with it. There is
-- no state in which an offer reads `accepted` for a rider holding nothing.
create or replace function public.award_delivery(
  p_order_id text,
  p_rider    text
) returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  update public.delivery_offers
     set state = 'accepted', responded_at = now()
   where order_id = p_order_id
     and partner_email = p_rider
     and state in ('offered', 'expired');

  perform public.claim_delivery_for(p_order_id, p_rider);
end;
$function$;

revoke all on function public.award_delivery(text, text)
  from public, anon, authenticated;

-- ===========================================================================
-- G. What a contest says back to one rider.
-- ===========================================================================
-- Split out because three call sites need the same answer and it must be the
-- same answer in all three. Null caller — the sweeper, cron — gets 'resolved',
-- which is true and says nothing about anybody.
--
-- 'none' is a rider asking about a contest they are not in. It leaks nothing:
-- the same word comes back for an order that was never contested and for one
-- somebody else settled a minute ago.
create or replace function public.contest_outcome(
  p_order_id text,
  p_rider    text
) returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_rider is null then jsonb_build_object('state', 'resolved')
    else coalesce(
      (select case
                when c.decided_at is null then jsonb_build_object('state', 'pending')
                when c.won            then jsonb_build_object('state', 'won')
                else jsonb_build_object(
                       'state',   'lost',
                       'message', 'Another partner was closer to the restaurant.'
                     )
              end
         from public.delivery_claims c
        where c.order_id = p_order_id
          and c.partner_email = p_rider),
      jsonb_build_object('state', 'none')
    )
  end;
$$;

revoke all on function public.contest_outcome(text, text)
  from public, anon, authenticated;

-- ===========================================================================
-- H. Shutting the window and awarding the job.
-- ===========================================================================
-- Idempotent, and called from three places: the rider whose phone is waiting out
-- the two seconds, any other contestant who gets there first, and the sweeper as
-- a backstop for the case where every contestant's app died between the tap and
-- the deadline.
--
-- **Namespace 4243 in the advisory-lock registry 0121 opened.**
--
--   namespace 4242 — Zopiqnow background jobs
--     1  dispatch_deliveries
--   namespace 4243 — one delivery contest, keyed by hashtext(order_id)   (0148)
--
-- A separate namespace rather than a second key under 4242, because the key here
-- is a hash and a hash that happened to come out as 1 would silently serialise
-- one order's contest against the whole dispatcher.
--
-- The blocking form, not `try`: unlike a sweeper tick, a caller here needs an
-- answer rather than permission to skip. The wait is bounded by one contest
-- resolution, and there is no cycle to deadlock on — the sweeper takes (4242,1)
-- then (4243,…), and nothing ever takes them the other way round.
create or replace function public.resolve_delivery_contest(p_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_caller text;
  v_opened timestamptz;
  v_closes timestamptz;
  v_holder text;
  v_winner text;
  v_s      public.dispatch_settings%rowtype;
  c        record;
begin
  v_caller := public.delivery_partner_email();

  perform pg_advisory_xact_lock(4243, hashtext(p_order_id));

  select * into v_s from public.dispatch_settings where id = 1;

  select min(claimed_at) into v_opened
    from public.delivery_claims
   where order_id = p_order_id and decided_at is null;

  -- Nothing open: never contested, or settled by whoever arrived first. The
  -- caller still gets their own outcome, which is the whole reason two riders
  -- can both call this and both be told the truth.
  if v_opened is null then
    return public.contest_outcome(p_order_id, v_caller);
  end if;

  v_closes := v_opened
            + make_interval(secs => v_s.contest_seconds::double precision);

  -- Somebody already holds the job — an admin assignment (0067), or an
  -- uncontested claim that landed while this window was open. The contest has
  -- nothing left to award; it only has to tell people.
  select d.partner_email into v_holder
    from public.deliveries d
   where d.order_id = p_order_id and d.state <> 'cancelled'
   limit 1;

  if v_holder is not null then
    update public.delivery_claims
       set decided_at = now(), won = (partner_email = v_holder)
     where order_id = p_order_id and decided_at is null;
    return public.contest_outcome(p_order_id, v_caller);
  end if;

  -- Still collecting. Told rather than made to guess, so a phone that woke up
  -- early can wait exactly the right amount longer.
  if now() < v_closes then
    return jsonb_build_object(
      'state', 'pending',
      'decide_at', to_char(v_closes at time zone 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    );
  end if;

  -- A tap that landed after the window shut is not in this contest. It would
  -- otherwise be possible for a rider arriving four seconds late to beat one who
  -- had been waiting since the first second, purely by being nearer — which is
  -- the opposite of a two-second window meaning anything.
  update public.delivery_claims
     set decided_at = now(), won = false
   where order_id = p_order_id
     and decided_at is null
     and claimed_at > v_closes;

  -- Nearest first. `nulls last` for the same reason the dispatcher uses it: a
  -- rider whose app has never reported a position is not zero kilometres away.
  -- The loop, rather than a single winner, is what makes "the nearest rider who
  -- can *actually* take it" true — a licence that expired, a shift ended, a cash
  -- ceiling crossed between the tap and now, or simply losing the unique-index
  -- race to a claim from outside the contest.
  for c in
    select partner_email, distance_km
      from public.delivery_claims
     where order_id = p_order_id and decided_at is null
     order by distance_km nulls last, claimed_at
  loop
    begin
      perform public.award_delivery(p_order_id, c.partner_email);
      v_winner := c.partner_email;
      exit;
    exception when others then
      -- This one cannot have it. Settled as a loss here rather than left to the
      -- bulk update below, because the bulk update runs after a winner is known
      -- and this rider's refusal is a fact independent of who wins.
      update public.delivery_claims
         set decided_at = now(), won = false
       where order_id = p_order_id and partner_email = c.partner_email;
    end;
  end loop;

  update public.delivery_claims
     set decided_at = now(),
         won = (v_winner is not null and partner_email = v_winner)
   where order_id = p_order_id and decided_at is null;

  return public.contest_outcome(p_order_id, v_caller);
end;
$function$;

revoke execute on function public.resolve_delivery_contest(text)
  from public, anon;
grant execute on function public.resolve_delivery_contest(text) to authenticated;

-- ===========================================================================
-- I. Yes — the one door, whether the job came as an offer or off the board.
-- ===========================================================================
-- `accept_offer` (0080) and `claim_delivery` both still exist and both still
-- work; what neither can do is tell a rider "wait two seconds, somebody else is
-- also reaching for this". So the app calls this instead, and gets back one of:
--
--   {"state":"won"}                              — it is yours, go
--   {"state":"pending","decide_at":"…"}          — wait, then ask again
--   {"state":"lost","message":"…"}               — somebody was closer
--
-- The refusals are still raised as P0001 with a sentence written for a human,
-- because they are answers to a different question: not "did you win" but "were
-- you ever allowed to ask".
create or replace function public.take_delivery(p_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_rider  text;
  v_block  text;
  v_online boolean;
  v_status text;
  v_mine   text;
  v_live   boolean;
  v_dist   numeric(6,2);
  v_opened timestamptz;
  v_decide timestamptz;
  v_s      public.dispatch_settings%rowtype;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  v_block := public.rider_work_block(v_rider);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  select is_online into v_online
    from public.delivery_partners where email = v_rider;
  if not coalesce(v_online, false) then
    raise exception 'You are offline. Go online to take deliveries.'
      using errcode = 'P0001';
  end if;

  select status into v_status from public.orders where id = p_order_id;
  if not found then
    raise exception 'That order no longer exists.' using errcode = 'P0001';
  end if;
  if v_status not in ('preparing', 'ready_for_pickup') then
    raise exception 'That order is no longer available.' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.deliveries d
     where d.order_id = p_order_id and d.state <> 'cancelled'
  ) then
    raise exception 'Another partner just took that one.' using errcode = 'P0001';
  end if;

  select off.state into v_mine
    from public.delivery_offers off
   where off.order_id = p_order_id and off.partner_email = v_rider;

  v_live := exists (
    select 1 from public.delivery_offers off
     where off.order_id = p_order_id
       and off.state = 'offered'
       and off.expires_at > now()
  );

  -- The same rule the board draws, enforced where it counts. A rider who has
  -- never been offered this order cannot take it out from under the one who is
  -- currently deciding about it; a rider whose own window ran out can, which is
  -- the entire point of this migration.
  if v_live and coalesce(v_mine, '') not in ('offered', 'expired') then
    raise exception
      'That job is with another partner right now. If they pass on it, it comes back to you.'
      using errcode = 'P0001';
  end if;

  -- Nobody to be nearer than. The common case by a wide margin — during a
  -- rider's own fifteen seconds, no second rider has been asked yet — and it
  -- costs nothing.
  if not public.delivery_is_contested(p_order_id) then
    perform public.award_delivery(p_order_id, v_rider);
    return jsonb_build_object('state', 'won');
  end if;

  select * into v_s from public.dispatch_settings where id = 1;

  -- Where this rider is standing *now*, which is the number the contest is
  -- decided on. `rider_locations` is one row per rider, updated while they are
  -- carrying (0057), so a rider on a job has a real fix and an idle one may not.
  select public.delivery_distance_km(l.lat, l.lng, r.latitude, r.longitude)
    into v_dist
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
    left join public.rider_locations l on l.partner_email = v_rider
   where o.id = p_order_id;

  -- Nothing live. The distance frozen onto their own offer is the next best
  -- answer and is usually only seconds old; failing that the claim is ranked
  -- last rather than as zero.
  if v_dist is null then
    select off.distance_km into v_dist
      from public.delivery_offers off
     where off.order_id = p_order_id and off.partner_email = v_rider;
  end if;

  insert into public.delivery_claims (order_id, partner_email, distance_km)
  values (p_order_id, v_rider, v_dist)
  on conflict (order_id, partner_email) do nothing;

  select min(claimed_at) into v_opened
    from public.delivery_claims
   where order_id = p_order_id and decided_at is null;

  -- Settled between the insert and this read, or this rider tapped twice on a
  -- contest that has already closed. Either way the answer is on the row.
  if v_opened is null then
    return public.contest_outcome(p_order_id, v_rider);
  end if;

  v_decide := v_opened
            + make_interval(secs => v_s.contest_seconds::double precision);

  if now() >= v_decide then
    return public.resolve_delivery_contest(p_order_id);
  end if;

  return jsonb_build_object(
    'state', 'pending',
    'decide_at', to_char(v_decide at time zone 'UTC',
                         'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );
end;
$function$;

revoke execute on function public.take_delivery(text) from public, anon;
grant execute on function public.take_delivery(text) to authenticated;

-- ===========================================================================
-- J. The board, which stops taking jobs away from people.
-- ===========================================================================
-- Restated from 0097. Two changes.
--
-- **The visibility rule.** It was "hide any order under a live offer", full
-- stop. It is now "hide it from everybody except the riders it has already been
-- offered to" — so the first rider's board keeps the job while the second one's
-- phone rings, and they can still take it.
--
-- `'offered'` is in the set as well as `'expired'` on purpose: a rider holding a
-- live offer sees the same job in two places, the sheet and the board. That is
-- not a duplicate to be tidied away — it is what makes the transition invisible
-- when the sheet closes on the countdown. The card was already there.
--
-- `'declined'` is not in the set. See the note at the top of this file.
--
-- **`offered_to_other`**, so the card can say why the button might lose. A
-- rider tapping Accept on a job somebody else is mid-decision about needs to
-- have been told that before they tap, not after.
--
-- Drop-and-recreate, not replace: the return shape widens by a column, and
-- `create or replace` with a changed output column list is refused outright.
drop function if exists public.available_deliveries();
create function public.available_deliveries()
returns table (
  order_id        text,
  restaurant_name text,
  restaurant_lat  double precision,
  restaurant_lng  double precision,
  deliver_to      text,
  total           integer,
  payment_method  text,
  status          text,
  route_km        numeric,
  rider_pay       integer,
  ready_by        timestamptz,
  placed_at       timestamptz,
  offered_to_other boolean
)
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_email    text;
  v_headroom integer;
  v_block    text;
begin
  v_email := public.delivery_partner_email();
  if v_email is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- 0080. Raised rather than returning nothing: an empty board reads as "no
  -- work right now", which is a different and much worse thing to tell somebody
  -- whose documents are sitting unverified in a queue.
  v_block := public.rider_work_block(v_email);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  -- How much more cash this rider may be holding. Computed once here rather
  -- than per row: it does not change while the query runs.
  v_headroom := public.rider_cash_cap() - public.rider_cash_in_hand(v_email);

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status,
           q.ride_km,
           q.rider_pay,
           o.ready_by, o.created_at,
           exists (
             select 1 from public.delivery_offers off
              where off.order_id = o.id
                and off.state = 'offered'
                and off.expires_at > now()
                and off.partner_email <> v_email
           )
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
      left join lateral public.rider_pay_quote(o.id) q on true
     where o.status in ('preparing', 'ready_for_pickup')
       and (o.payment_method <> 'cod' or o.total <= v_headroom)
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = o.id and d.state <> 'cancelled'
       )
       and (
         not exists (
           select 1 from public.delivery_offers off
            where off.order_id = o.id
              and off.state = 'offered'
              and off.expires_at > now()
         )
         or exists (
           select 1 from public.delivery_offers mine
            where mine.order_id = o.id
              and mine.partner_email = v_email
              and mine.state in ('offered', 'expired')
         )
       )
     order by (o.status = 'ready_for_pickup') desc, o.created_at;
end;
$function$;

revoke execute on function public.available_deliveries() from public, anon;
grant execute on function public.available_deliveries() to authenticated;

-- ===========================================================================
-- K. The dispatcher leaves a contest alone.
-- ===========================================================================
-- Restated from 0121. One block added, right after the "already has a rider"
-- check, and it is the same idea: an order that is being decided about does not
-- want a new offer made on it.
--
-- Without it, the two-second contest would race the five-second tick — the
-- sweeper would expire the live offer, hand the order to a fourth rider, and
-- that rider's ring would start while three people were waiting to hear who
-- won.
create or replace function public.offer_delivery(p_order_id text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rider    text;
  v_dist     numeric(6,2);
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_d_lat    double precision;
  v_d_lng    double precision;
  v_name     text;
  v_status   text;
  v_pay      integer;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_route    numeric(6,2);
  v_method   text;
  v_total    integer;
  v_cap      integer;
  v_started  timestamptz;
  v_radius   numeric(6,2);
  v_s        public.dispatch_settings%rowtype;
begin
  -- The order still has to be one that wants a rider. Checked here as well as
  -- in the sweeper because `decline_offer` calls straight into this function,
  -- and an order cancelled between the offer and the decline must not be
  -- handed to somebody else.
  select o.status, r.name, r.latitude, r.longitude,
         o.delivery_lat, o.delivery_lng, o.payment_method, o.total
    into v_status, v_name, v_r_lat, v_r_lng,
         v_d_lat, v_d_lng, v_method, v_total
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found or v_status not in ('preparing', 'ready_for_pickup') then
    return null;
  end if;

  if exists (
    select 1 from public.deliveries d
     where d.order_id = p_order_id and d.state <> 'cancelled'
  ) then
    return null;
  end if;

  -- New in 0148. Riders are mid-tap on this one; nobody new is asked until it
  -- is settled, which is at most `contest_seconds` away.
  if exists (
    select 1 from public.delivery_claims
     where order_id = p_order_id and decided_at is null
  ) then
    return null;
  end if;

  -- What the job pays, at today's rate and this order's distance. One call, and
  -- the answer is written onto the offer below so that `claim_delivery` can pay
  -- this number rather than work it out again from inputs that may have moved.
  select q.ride_km, q.pay_base, q.pay_per_km, q.rider_pay
    into v_route, v_base, v_per_km, v_pay
    from public.rider_pay_quote(p_order_id) q;

  select * into v_s from public.dispatch_settings where id = 1;

  -- The clock starts on the first pass, found or not.
  --
  -- **Read before written** (0121), which is not a micro-optimisation: the
  -- unconditional `update` took a row lock on every dispatchable order on every
  -- tick, held until the sweeper committed, so a cook tapping "Ready" queued
  -- behind a write with nothing left to say. Only the first pass writes now.
  --
  -- `coalesce` stays inside the `update` and is still load-bearing. Two callers
  -- can both read null and both fall through — `decline_offer` re-offers inline
  -- and does not hold the sweeper's advisory lock — and the one that arrives
  -- second re-evaluates the row under the lock it waited for, so it preserves
  -- the first one's timestamp instead of resetting the ring.
  select dispatch_started_at into v_started
    from public.orders where id = p_order_id;

  if v_started is null then
    update public.orders
       set dispatch_started_at = coalesce(dispatch_started_at, now())
     where id = p_order_id
    returning dispatch_started_at into v_started;
  end if;

  -- 0–60 s: 4 km. 60–120 s: 8 km. Then 12 km and no wider.
  v_radius := least(
    v_s.first_radius_km
      + v_s.radius_step_km
      * floor(extract(epoch from (now() - v_started)) / v_s.widen_after_seconds),
    v_s.max_radius_km
  );
  v_cap := public.rider_cash_cap();

  select cand.email, cand.km
    into v_rider, v_dist
    from (
      select p.email,
             public.delivery_distance_km(l.lat, l.lng, v_r_lat, v_r_lng) as km,
             l.lat is not null and l.lng is not null                     as has_fix,
             public.serviceable_point(l.lat, l.lng)                      as in_area,
             (select count(*) from public.deliveries d
               where d.partner_email = p.email
                 and d.state in ('claimed', 'arrived_at_restaurant',
                                 'picked_up', 'arrived_at_customer')
             ) as live_jobs,
             -- Already carrying something that finishes near where this one
             -- finishes. The comparison is drop to drop and not pickup to
             -- pickup: two orders from one kitchen going to opposite ends of
             -- town are two rides however close the counters are.
             exists (
               select 1
                 from public.deliveries d
                 join public.orders o2 on o2.id = d.order_id
                where d.partner_email = p.email
                  and d.state in ('claimed', 'arrived_at_restaurant',
                                  'picked_up', 'arrived_at_customer')
                  and public.delivery_distance_km(o2.delivery_lat, o2.delivery_lng,
                                                  v_d_lat, v_d_lng)
                      <= v_s.stack_drop_km
             ) as stackable
        from public.delivery_partners p
        left join public.rider_locations l on l.partner_email = p.email
       where p.is_active
         and p.is_online
         -- 0080. A `sql` function over an indexed primary key, inlinable by the
         -- planner, on a fleet of hundreds — the same order of cost as the cash
         -- check that has sat beside it since 0076.
         and public.rider_is_verified(p.email)
         -- Evaluated per candidate, which is a sum over one rider's ledger rows
         -- on an indexed column, and only for a cash order. A fleet is hundreds
         -- of rows, not millions.
         and (v_method <> 'cod'
              or public.rider_cash_in_hand(p.email) + v_total <= v_cap)
    ) cand
   where cand.live_jobs < v_s.max_live_jobs
     -- The ring, and the boundary — **for riders we can actually place.**
     --
     -- A rider with no position is not excluded, only outranked. That is a
     -- deliberate retreat from the obvious rule, and the reason is worth
     -- writing down: `RiderLocationReporter` is started and stopped by the
     -- rider's own live jobs, so **an idle rider reports nothing**, and an idle
     -- rider is precisely who a fresh order is looking for. Gating them on the
     -- ring would have meant every order waiting for the widest ring before it
     -- could be offered to anybody — a two-minute delay added to every single
     -- dispatch, which is worse than the problem 0099 was fixing.
     and (
       not cand.has_fix
       or (cand.in_area and cand.km <= v_radius)
     )
     and not exists (
       select 1 from public.delivery_offers o
        where o.order_id = p_order_id and o.partner_email = cand.email
     )
     and not exists (
       select 1 from public.delivery_offers o
        where o.partner_email = cand.email
          and o.state = 'offered'
          and o.expires_at > now()
     )
   -- Stackable first — a rider already going that way turns two rides into one,
   -- and that is worth more than the few minutes an idle rider would have
   -- saved. Then a rider we can actually see, because a known 3 km beats an
   -- unknown anything. Then the old rule: least busy, then nearest.
   order by cand.stackable desc, cand.has_fix desc,
            cand.live_jobs, cand.km nulls last, cand.email
   limit 1;

  if v_rider is null then
    return null;
  end if;

  insert into public.delivery_offers
    (order_id, partner_email, distance_km, expires_at,
     ride_km, pay_base, pay_per_km, rider_pay)
  values
    (p_order_id, v_rider, v_dist, now() + public.delivery_offer_window(),
     v_route, v_base, v_per_km, v_pay)
  -- Two sweeper ticks overlapping, or a decline racing the sweep. The index is
  -- what decides it; losing simply means somebody else's offer is already live.
  on conflict do nothing;

  if not found then
    return null;
  end if;

  -- The push. `data` carries the numbers so the sheet can draw itself from the
  -- notification alone — a rider woken by this is on a lock screen, and a sheet
  -- that has to round-trip before it can show a countdown has already spent the
  -- seconds it is counting.
  --
  -- `expires_at` is what bounds the **ring** on the device, the same way
  -- `accept_deadline` bounds the kitchen's (0136): a message that sat in a Doze
  -- queue for twelve seconds must ring for the three that are left, not for a
  -- fresh fifteen.
  begin
    insert into public.notifications
      (audience, partner_email, kind, title, body, order_id, data)
    values
      ('rider', v_rider, 'job_offer',
       'New delivery — ₹' || v_pay,
       'Pick up from ' || v_name ||
         case when v_dist is null then ''
              else ' · ' || v_dist || ' km away' end,
       p_order_id,
       jsonb_build_object(
         'order_id',    p_order_id,
         'restaurant',  v_name,
         'pay',         v_pay,
         'route_km',    v_route,
         'to_pickup_km', v_dist,
         'expires_at',  to_char(
                          (now() + public.delivery_offer_window())
                            at time zone 'UTC',
                          'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                        )
       ));
  exception when others then
    -- 0021's rule, kept: the offer is the event, the push is a courtesy on top
    -- of it. A rider who missed the buzz still finds the offer in the app.
    null;
  end;

  return v_rider;
end;
$function$;

revoke execute on function public.offer_delivery(text) from public, anon;

-- ===========================================================================
-- L. The sweeper, five seconds apart.
-- ===========================================================================
-- Restated from 0121. Two changes.
--
-- **It settles contests first.** The backstop for a phone that tapped Accept and
-- then went into a tunnel: without it, a contest whose every contestant's app
-- died would hold the order out of dispatch for ever, because section K refuses
-- to offer an order with an open claim on it. Runs before the loop so the loop
-- sees a settled board.
--
-- **It skips contested orders**, for the same reason section K does, and here as
-- well as there because the loop would otherwise read `offer_delivery`'s null as
-- "the fleet is exhausted" and broadcast a two-second-old contest to everybody.
--
-- The advisory lock, the read-before-write and the location purge are 0121's and
-- 0057's, unchanged.
create or replace function public.dispatch_deliveries()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  o record;
  v_offered text;
begin
  -- A tick already working the board owns it. Leaving is the correct answer and
  -- not a dropped beat: the next tick is five seconds away, the run in progress
  -- is doing the very work this one would have done, and an order it has not
  -- reached yet is still on the board for the run after.
  if not pg_try_advisory_xact_lock(4242, 1) then
    return;
  end if;

  -- New in 0148. Bounded — a contest is at most `contest_seconds` old before it
  -- is due, and there is one row per rider who tapped.
  for o in
    select distinct order_id from public.delivery_claims where decided_at is null
  loop
    perform public.resolve_delivery_contest(o.order_id);
  end loop;

  update public.delivery_offers
     set state = 'expired', responded_at = now()
   where state = 'offered'
     and expires_at <= now();

  for o in
    select ord.id
      from public.orders ord
     where ord.status in ('preparing', 'ready_for_pickup')
       and ord.delivery_lat is not null
       and ord.delivery_lng is not null
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = ord.id and d.state <> 'cancelled'
       )
       and not exists (
         select 1 from public.delivery_offers off
          where off.order_id = ord.id
            and off.state = 'offered'
            and off.expires_at > now()
       )
       and not exists (
         select 1 from public.delivery_claims dc
          where dc.order_id = ord.id and dc.decided_at is null
       )
     order by (ord.status = 'ready_for_pickup') desc, ord.created_at
     limit 50
  loop
    v_offered := public.offer_delivery(o.id);
    if v_offered is null then
      perform public.announce_open_delivery(o.id);
    end if;
  end loop;

  -- 0057. Inside the guard, so a skipped tick skips this too — it is a purge of
  -- stale rows and the next tick does it just as well.
  perform public.purge_rider_locations();
end;
$function$;

revoke all on function public.dispatch_deliveries()
  from public, anon, authenticated;

comment on function public.dispatch_deliveries() is
  'The 5-second dispatch tick (0148, was 20s). Settles due contests, retires '
  'expired offers, offers what is waiting. Holds advisory lock (4242, 1) for '
  'its transaction so two runs cannot interleave their order-row locks and '
  'deadlock (0121).';

-- Five seconds, because a 15-second offer window handed off on a 20-second tick
-- would spend more time waiting for the sweeper than ringing anybody. Worst case
-- a rider who ignores an offer now costs the customer 20 seconds.
--
-- ⚠️ This is four times the tick rate of the second-largest consumer of database
-- time on this project (0111 measured `dispatch_deliveries` at 9.5 ms mean).
-- It is affordable because 0111's `orders_dispatchable_idx` bounds the driving
-- scan and an idle board matches nothing — but it is the number to look at first
-- if this instance ever starts running hot.
select cron.schedule(
  'dispatch-deliveries',
  '5 seconds',
  $$ select public.dispatch_deliveries(); $$
);

-- ===========================================================================
-- M. "Start preparing" rings a rider in the same breath.
-- ===========================================================================
-- Restated from 0094. The transition rules, the row lock, the prep stamp, the
-- photographs and the delivery release are verbatim; the only new thing is the
-- block at the end.
--
-- Dispatch has always begun at `preparing` — `offer_delivery` takes orders in
-- exactly that status — but only when the sweeper next came round, so the first
-- rider was rung up to twenty seconds after the food went on. There is no reason
-- to wait: the kitchen has just told us the order is real and is being cooked,
-- which is the whole precondition.
--
-- **Wrapped, and it has to be.** Placement is sacred and so is the kitchen's
-- ladder — a dispatcher that raises must not be able to fail the cook's tap and
-- leave an accepted order stuck at `accepted`. If this block swallows something,
-- the sweeper picks the order up five seconds later exactly as it did before.
--
-- **`announce_open_delivery` is deliberately not called here.** The sweeper
-- announces when `offer_delivery` finds nobody, and at t=0 the ring is at its
-- tightest 4 km — "nobody in range yet" is the ordinary case in the first
-- seconds, not evidence the fleet is exhausted. Broadcasting to everybody here
-- would make the free-for-all board the front door again, which is the thing
-- 0056 was written to stop.
drop function if exists
  public.set_order_status(text, text, text, integer, text, text);

create or replace function public.set_order_status(
  p_order_id         text,
  p_status           text,
  p_reason           text default null,
  p_prep_minutes     integer default null,
  p_cooked_photo_url text default null,
  p_packed_photo_url text default null
) returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_restaurant text;
  v_current    text;
  v_allowed    text[];
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  -- Locked, because two tablets in one kitchen is the normal case. Without this,
  -- both can read the same status and race to write different next ones. It is
  -- also what makes the auto-decline sweeper safe: it takes the same lock and
  -- skips a row a cook is mid-accept on.
  select o.status into v_current
    from public.orders o
   where o.id = p_order_id
     and o.restaurant_id = v_restaurant
   for update;

  if not found then
    raise exception 'That order is not one of yours.' using errcode = 'P0001';
  end if;

  -- The kitchen's authority ends at `ready_for_pickup` (0050). It may move an
  -- order to the next step it owns, decline a *new* one, or call off one it has
  -- accepted while the food is still on its counter. It may not skip ahead, it
  -- may not go back, and it may not cross into the rider's half of the story:
  --
  --   placed           → accept, or reject outright
  --   accepted         → prepare, or cancel
  --   preparing        → ready for pickup, or cancel
  --   ready_for_pickup → cancel only        (the rider collects; confirm_pickup)
  --   out_for_delivery → nothing            (the rider delivers; confirm_delivered)
  v_allowed := case v_current
    when 'placed'           then array['accepted', 'rejected']
    when 'accepted'         then array['preparing', 'cancelled']
    when 'preparing'        then array['ready_for_pickup', 'cancelled']
    when 'ready_for_pickup' then array['cancelled']
    else array[]::text[]
  end;

  if not (p_status = any (v_allowed)) then
    raise exception 'An order that is % cannot become %.', v_current, p_status
      using errcode = 'P0001';
  end if;

  update public.orders
     set status = p_status,
         -- The reason is kept only for the two statuses that have one. A forward
         -- step leaves any earlier note untouched rather than blanking it.
         status_reason = case
           when p_status in ('rejected', 'cancelled')
             then nullif(trim(coalesce(p_reason, '')), '')
           else status_reason
         end,
         -- A prep time is meaningful only at the moment of accepting. Stamped
         -- from the server's clock, not the client's, so the countdown cannot be
         -- skewed by a tablet whose time is wrong. (0015, kept verbatim.)
         ready_by = case
           when p_status = 'accepted'
                and p_prep_minutes is not null
                and p_prep_minutes > 0
             then now() + make_interval(mins => p_prep_minutes)
           else ready_by
         end,
         -- The photographs, and only on the one transition they describe. Two
         -- guards, both of which matter:
         --
         --   `p_status = 'ready_for_pickup'` — a cancel must not be able to
         --   smuggle a photo onto the row, and an accept has nothing to show.
         --
         --   `coalesce(new, existing)` — a second call cannot blank a photo that
         --   is already there. There is no legitimate reason to un-photograph an
         --   order, and `ready_for_pickup` is reachable only once anyway.
         cooked_photo_url = case
           when p_status = 'ready_for_pickup'
             then coalesce(
               nullif(trim(coalesce(p_cooked_photo_url, '')), ''),
               cooked_photo_url
             )
           else cooked_photo_url
         end,
         packed_photo_url = case
           when p_status = 'ready_for_pickup'
             then coalesce(
               nullif(trim(coalesce(p_packed_photo_url, '')), ''),
               packed_photo_url
             )
           else packed_photo_url
         end
   where id = p_order_id;

  -- A cancelled order must not leave a `deliveries` row pointing at a dead
  -- order. Only reachable from 'ready_for_pickup' backwards, so the rider is at
  -- most standing at the counter — but the release does not depend on that, and
  -- should not.
  if p_status in ('cancelled', 'rejected') then
    perform public.release_order_delivery(
      p_order_id,
      'The restaurant called off order ' || p_order_id || '.'
    );
  end if;

  -- New in 0148. The nearest rider's phone rings while the cook is still putting
  -- the ticket up, rather than on the next five-second tick.
  if p_status = 'preparing' then
    begin
      perform public.offer_delivery(p_order_id);
    exception when others then
      null;
    end;
  end if;

  return p_status;
end;
$function$;

-- Born executable by PUBLIC, like every function (0087). Revoking from
-- `anon, authenticated` alone would leave the PUBLIC grant standing and the
-- function open to the world.
revoke all on function
  public.set_order_status(text, text, text, integer, text, text)
  from public, anon;
grant execute on function
  public.set_order_status(text, text, text, integer, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Verification — none of this counts as applied until all six hold.
-- ---------------------------------------------------------------------------
-- 1. **The window is read, not compiled in.**
--
--      select public.delivery_offer_window();          -- 00:00:15
--      update public.dispatch_settings set offer_window_seconds = 20 where id = 1;
--      select public.delivery_offer_window();          -- 00:00:20
--      update public.dispatch_settings set offer_window_seconds = 15 where id = 1;
--
-- 2. **A passed-over rider keeps the job on their board.** With two riders
--    online, place an order and move it to `preparing`. Rider A is offered it.
--    Wait 20 seconds. Then, as A:
--
--      select order_id, offered_to_other from public.available_deliveries();
--
--    The order must still be listed, with `offered_to_other` true. Before this
--    migration the list was empty.
--
-- 3. **Nobody but an offeree can snipe a live offer.** As a third rider C who
--    has never been offered it, while B's window is open:
--
--      select public.take_delivery('<order>');
--      -- ERROR: That job is with another partner right now. …
--
-- 4. **The nearest of two simultaneous accepts wins, and only one delivery
--    exists.** As A and B, inside two seconds of each other:
--
--      select public.take_delivery('<order>');   -- both: {"state":"pending",…}
--
--    then, after `decide_at`, from either:
--
--      select public.resolve_delivery_contest('<order>');
--      select partner_email, distance_km, won from public.delivery_claims
--       where order_id = '<order>';
--      select count(*) from public.deliveries
--       where order_id = '<order>' and state <> 'cancelled';   -- exactly 1
--
--    `won` must be true for the row with the smaller `distance_km`, whichever
--    of the two tapped first.
--
-- 5. **An uncontested accept is not held.** A fresh order, its first offeree
--    accepting inside their own window:
--
--      select public.take_delivery('<order>');   -- {"state":"won"} immediately
--
-- 6. **Nothing signed in can claim as somebody else.** With a rider's JWT:
--
--      select has_function_privilege('authenticated',
--               'public.claim_delivery_for(text,text)', 'execute');   -- f
--      select has_function_privilege('authenticated',
--               'public.award_delivery(text,text)', 'execute');       -- f
--      select array_to_string(proacl, ',') ~ '(^|,)=X/' as public_can_execute
--        from pg_proc where proname in ('claim_delivery_for','award_delivery');
--      -- both f; see 0087 — PUBLIC is a second door and does not show up in
--      -- has_function_privilege at all.
