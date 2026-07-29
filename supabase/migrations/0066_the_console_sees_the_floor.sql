-- ---------------------------------------------------------------------------
-- 0066 — the console sees the floor. (Phase B7 — admin panel completion)
-- ---------------------------------------------------------------------------
-- Everything the console could do until now was *setup*: onboard a restaurant,
-- add a rider, write a hero slide, settle last week's rider pay. None of it was
-- about today. An order going wrong right now was invisible to ops, and the only
-- lever anybody had over it was a `psql` prompt.
--
-- This migration gives the console the running floor:
--
--   A. every open order, its status, and who is carrying it
--   B. the support override — release a rider, or end an order — with a reason
--   C. platform coupons, which have been seed data since 0003
--   D. a broadcast, and a record that it was sent
--   E. the platform's own numbers, not one restaurant's
--   F. vendor settlements, which have been rolled up weekly since 0017 and read
--      by nobody but the vendor
--
-- **And one bug, which is why B7 exists.** 0040 promised that a rider could not
-- be switched off while carrying an order. It checked `state in ('claimed',
-- 'picked_up')` — the two states that existed when it was written. 0049 added
-- `arrived_at_restaurant` and `arrived_at_customer`, and did not come back for
-- this list. Since then a rider standing at the customer's door has read to the
-- console as free, and the switch that was supposed to be refused was offered.
-- Section G fixes it, and states the rule the other way round: a delivery is
-- live unless it is `delivered` or `cancelled`. A positive list of live states
-- is a list that goes stale the next time somebody adds one; the negative list
-- cannot, because a new state is by definition not one of the two that end a
-- job.
--
-- Grants are at the bottom, done 0065's way: revoked from everybody first, then
-- given back to `authenticated`. `assert_admin()` inside each function is what
-- actually decides; the grant only stops a signed-out stranger reaching the
-- door at all.

-- ===========================================================================
-- A. The floor.
-- ===========================================================================
-- One function, not two. With no query it is the live board — every order that
-- has not ended, oldest first, because the oldest open order is always the one
-- worth looking at. With a query it is a lookup by order id or customer phone
-- across *every* status, because the order support gets called about is usually
-- one that already ended badly.
--
-- Everything a support call needs is on the row, so answering "where is my
-- food" does not mean four more round trips: the kitchen, the rider, the codes'
-- *state* (never the codes themselves — 0049 put those beyond every read but
-- one function per identity, and an admin is not one of those identities), the
-- offer in flight, and the ETA together with the sentence explaining it.
create or replace function public.admin_orders(p_query text default null)
returns table (
  order_id          text,
  restaurant_id     text,
  restaurant_name   text,
  status            text,
  status_reason     text,
  placed_at         timestamptz,
  accept_deadline   timestamptz,
  ready_by          timestamptz,
  eta_at            timestamptz,
  eta_reason        text,
  total             integer,
  payment_method    text,
  coupon_code       text,
  delivery_to       text,
  customer_phone    text,
  route_km          numeric,
  rider_email       text,
  rider_name        text,
  rider_phone       text,
  rider_vehicle     text,
  delivery_state    text,
  claimed_at        timestamptz,
  offer_to          text,
  offer_expires_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q text;
begin
  perform public.assert_admin();

  v_q := nullif(trim(coalesce(p_query, '')), '');

  return query
    select
      o.id, o.restaurant_id, o.restaurant_name,
      o.status, o.status_reason, o.created_at,
      o.accept_deadline, o.ready_by, o.eta_at, o.eta_reason,
      o.total, o.payment_method, o.coupon_code,
      o.delivery_to, o.user_phone, o.route_km,
      d.partner_email, dp.name, dp.phone, dp.vehicle,
      d.state, d.claimed_at,
      off.partner_email, off.expires_at
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
    -- Live board: oldest first, because the order that has been open longest is
    -- the one somebody is about to ring about. Search: newest first, because a
    -- phone number matches every order that customer has ever placed.
    order by case when v_q is null then o.created_at end asc nulls last,
             o.created_at desc
    limit 200;
end;
$$;

-- ===========================================================================
-- B. The override.
-- ===========================================================================
-- The gap 8b-4 named and would not guess the shape of: *"a rider deactivated
-- while carrying still strands the order… making it structural needs an admin
-- force-abandon, which is a support flow that does not exist yet."* Here it is,
-- and the shape it took is two levers rather than one, because a rider who has
-- gone dark and an order that has to be called off are different problems and a
-- single button would have had to guess which one was happening.
--
-- **A reason is mandatory on both.** An override is the one action in this
-- system with no rule behind it — every other state change is refused or
-- allowed by a predicate, and these two are allowed because a person said so.
-- The only thing that makes that auditable afterwards is the sentence, so a
-- blank one is refused before anything moves.

-- Take the order off whoever is holding it and put it back in the dispatcher's
-- way. The order itself survives — this is "that rider is not going to finish
-- it", not "this is over".
create or replace function public.admin_release_delivery(
  p_order_id text,
  p_reason   text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason  text;
  v_status  text;
  v_rider   text;
  v_state   text;
  v_offered boolean;
begin
  perform public.assert_admin();

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception 'Say why you are taking this order off its rider — it is the only record of the decision.'
      using errcode = 'P0001';
  end if;

  -- Locked against the rider confirming a delivery in the same instant. If they
  -- get there first this reads 'delivered' below and refuses, which is right:
  -- the food arrived, and unwinding that would be inventing a fact.
  select o.status into v_status
    from public.orders o where o.id = p_order_id for update;

  if not found then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  if v_status in ('delivered', 'cancelled', 'rejected') then
    raise exception '%', case v_status
      when 'delivered' then 'That order has already been delivered.'
      when 'cancelled' then 'That order was already cancelled.'
      else 'The kitchen rejected that order.'
    end using errcode = 'P0001';
  end if;

  select d.partner_email, d.state into v_rider, v_state
    from public.deliveries d
   where d.order_id = p_order_id
     and d.state <> 'cancelled';

  select exists (
    select 1 from public.delivery_offers f
     where f.order_id = p_order_id
       and f.state = 'offered'
       and f.expires_at > now()
  ) into v_offered;

  if v_rider is null and not v_offered then
    raise exception 'Nobody is holding that order — it is already waiting for a rider.'
      using errcode = 'P0001';
  end if;

  -- The same call the customer's own cancellation makes (0051): cancel the
  -- delivery, destroy both codes, expire any offer in flight, and tell whoever
  -- was on it. Reusing it rather than repeating it is the point — the day a
  -- seventh thing has to happen when a job is released, it happens here too.
  perform public.release_order_delivery(
    p_order_id,
    'Support took order ' || p_order_id || ' off you. ' || v_reason
  );

  -- Back on the shelf. `dispatch_deliveries` only looks at 'preparing' and
  -- 'ready_for_pickup', so an order already out for delivery would otherwise
  -- sit there with no rider and nothing coming to find it one.
  --
  -- 'ready_for_pickup' and not 'preparing', because that is what is true: the
  -- food was cooked and packed. Whether it needs cooking *again* — the released
  -- rider still has the bag — is a judgement about the real world that no
  -- predicate can make, so the kitchen is told and decides.
  update public.orders
     set status = case when v_status = 'out_for_delivery'
                       then 'ready_for_pickup' else v_status end,
         status_reason = v_reason
   where id = p_order_id;

  begin
    insert into public.notifications
      (audience, restaurant_id, kind, title, body, order_id)
    select 'restaurant', o.restaurant_id, 'system',
           'Order back on the shelf',
           'Support released order ' || o.id || ' from its rider. ' || v_reason,
           o.id
      from public.orders o
     where o.id = p_order_id;
  exception when others then
    null;
  end;

  return coalesce(v_rider, 'the rider it was offered to');
end;
$$;

-- End the order. Everything the customer's own `cancel_my_order` does, minus the
-- window it is allowed in — that window is the customer's rule, not a rule about
-- what is possible.
create or replace function public.admin_cancel_order(
  p_order_id text,
  p_reason   text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text;
  v_status text;
begin
  perform public.assert_admin();

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception 'Say why this order is being cancelled — the customer is shown this sentence.'
      using errcode = 'P0001';
  end if;

  select o.status into v_status
    from public.orders o where o.id = p_order_id for update;

  if not found then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  -- A delivered order is refused, and not because the state machine says so.
  -- 0063 issues an invoice on delivery out of a gapless per-restaurant series;
  -- cancelling afterwards would leave a statutory document describing a supply
  -- that officially never happened. A delivery that went wrong is a refund
  -- (B2b), which is a second document, not the erasure of the first.
  if v_status in ('delivered', 'cancelled', 'rejected') then
    raise exception '%', case v_status
      when 'delivered' then 'That order has been delivered and invoiced. Refund it rather than cancelling it.'
      when 'cancelled' then 'That order was already cancelled.'
      else 'The kitchen already rejected that order.'
    end using errcode = 'P0001';
  end if;

  update public.orders
     set status = 'cancelled',
         status_reason = v_reason
   where id = p_order_id;

  perform public.release_order_delivery(
    p_order_id,
    'Support cancelled order ' || p_order_id || '. ' || v_reason
  );

  -- The customer is told by `orders_notify_customer`, which has fired on every
  -- status change since 0047 and does not need help here. The kitchen is not —
  -- its ticket would simply vanish — so it gets the sentence.
  begin
    insert into public.notifications
      (audience, restaurant_id, kind, title, body, order_id)
    select 'restaurant', o.restaurant_id, 'system',
           'Order cancelled by support',
           'Order ' || o.id || ' was cancelled. ' || v_reason,
           o.id
      from public.orders o
     where o.id = p_order_id;
  exception when others then
    null;
  end;

  return v_status;
end;
$$;

-- ===========================================================================
-- C. Coupons.
-- ===========================================================================
-- `coupons` has been a real table since 0003 and has only ever been filled by a
-- seed file. 0064 gave a kitchen a screen for its own codes; the platform's own
-- codes — the `restaurant_id is null` ones that work anywhere — still had none.

create or replace function public.admin_list_coupons()
returns table (
  code            text,
  restaurant_id   text,
  restaurant_name text,
  min_subtotal    integer,
  flat_off        integer,
  percent_off     integer,
  max_off         integer,
  valid_until     timestamptz,
  is_active       boolean,
  created_at      timestamptz,
  redeemed        integer,
  discount_given  integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  -- A kitchen's own offers are listed here too, read-only from this side. Ops
  -- being able to *see* a restaurant's promotion without being able to edit it
  -- is the useful half: "why is this order ₹200 off" has an answer, and 0064's
  -- rule that an offer belongs to whoever runs it still holds.
  return query
    select c.code, c.restaurant_id, r.name,
           c.min_subtotal, c.flat_off, c.percent_off, c.max_off,
           c.valid_until, c.is_active, c.created_at,
           coalesce(u.n, 0), coalesce(u.d, 0)
      from public.coupons c
      left join public.restaurants r on r.id = c.restaurant_id
      left join lateral (
        select count(*)::integer as n, sum(o.discount)::integer as d
          from public.orders o
         where o.coupon_code = c.code
           and o.status not in ('cancelled', 'rejected')
      ) u on true
     order by c.restaurant_id nulls first, c.created_at desc;
end;
$$;

-- Create or edit a platform coupon. Deliberately *not* a general coupon editor:
-- it writes `restaurant_id = null` and refuses to touch anything else.
create or replace function public.admin_save_coupon(
  p_code         text,
  p_min_subtotal integer,
  p_flat_off     integer     default null,
  p_percent_off  integer     default null,
  p_max_off      integer     default null,
  p_valid_until  timestamptz default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code  text;
  v_owner text;
  v_found boolean;
begin
  perform public.assert_admin();

  -- Hyphens survive the strip, unlike 0064's, and that is the whole point. A
  -- vendor code *is* `<restaurant id>-<suffix>`, so stripping the hyphen turns
  -- `R1-SUMMER` into `R1SUMMER` — a code that does not exist, that the
  -- ownership check below therefore cannot see, and that gets happily created
  -- as a new platform coupon. Which is exactly what the first run of this
  -- migration's edge-case matrix did.
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9-]', '', 'g'));
  if length(v_code) < 3 or length(v_code) > 16 then
    raise exception 'A coupon code is 3 to 16 letters, numbers or hyphens.'
      using errcode = 'P0001';
  end if;

  -- The same three checks 0064 makes for a vendor, for the same reason: the
  -- table's constraints already refuse a bad row, and a constraint violation is
  -- not a sentence anybody can act on.
  if (p_flat_off is not null) = (p_percent_off is not null) then
    raise exception 'A coupon is either a flat amount off or a percentage, not both.'
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

  if coalesce(p_min_subtotal, 0) < 0 then
    raise exception 'A minimum order value cannot be negative.' using errcode = 'P0001';
  end if;

  if p_valid_until is not null and p_valid_until <= now() then
    raise exception 'That end date has already passed.' using errcode = 'P0001';
  end if;

  -- 0064 reserved `<restaurant id>-…` for the kitchens without ever saying so
  -- out loud. Said out loud here: that prefix is theirs whether or not the code
  -- exists yet. Refusing only *existing* vendor codes would leave an admin free
  -- to create `R1-SUMMER` today and `vendor_save_offer` refusing r1 their own
  -- namespace tomorrow, with a message about a code they have never seen.
  if strpos(v_code, '-') > 1 and exists (
    select 1 from public.restaurants r
     where upper(r.id) = split_part(v_code, '-', 1)
  ) then
    raise exception 'Codes starting %- belong to that restaurant''s own offers. Pick another prefix.',
      split_part(v_code, '-', 1) using errcode = 'P0001';
  end if;

  select c.restaurant_id into v_owner from public.coupons c where c.code = v_code;
  v_found := found;

  -- Belt and braces behind the prefix rule: a restaurant that is deleted after
  -- issuing a code would slip past the check above, and the code would still be
  -- somebody's, still be on somebody's receipt, and still not be ours to edit.
  if v_found and v_owner is not null then
    raise exception 'That code belongs to a restaurant''s own offer. Edit it from their account.'
      using errcode = 'P0001';
  end if;

  insert into public.coupons
    (code, restaurant_id, min_subtotal, flat_off, percent_off, max_off,
     valid_until, is_active)
  values
    (v_code, null, coalesce(p_min_subtotal, 0), p_flat_off, p_percent_off,
     p_max_off, p_valid_until, true)
  on conflict (code) do update
     set min_subtotal = excluded.min_subtotal,
         flat_off     = excluded.flat_off,
         percent_off  = excluded.percent_off,
         max_off      = excluded.max_off,
         valid_until  = excluded.valid_until;

  return v_code;
end;
$$;

create or replace function public.admin_set_coupon_active(
  p_code   text,
  p_active boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  perform public.assert_admin();

  v_code := upper(trim(coalesce(p_code, '')));

  -- A restaurant's own code can be switched off from here, and only off. That
  -- is the abuse lever ops actually needs — a kitchen running a code it cannot
  -- afford — and it stops short of ops turning somebody's promotion back on for
  -- them, which is their decision to make.
  update public.coupons c
     set is_active = p_active
   where c.code = v_code
     and (c.restaurant_id is null or p_active = false);

  if not found then
    raise exception 'No such coupon, or it belongs to a restaurant and can only be switched off from here.'
      using errcode = 'P0001';
  end if;
end;
$$;

-- A real delete, and only for a code no order has ever carried. `orders.
-- coupon_code` is a foreign key, so a redeemed code is part of somebody's
-- receipt; deleting it would either fail or, with a cascade nobody should ever
-- add, rewrite what an order was charged.
create or replace function public.admin_delete_coupon(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_used integer;
  v_own  text;
  v_hit  boolean;
begin
  perform public.assert_admin();

  v_code := upper(trim(coalesce(p_code, '')));

  select c.restaurant_id into v_own from public.coupons c where c.code = v_code;
  v_hit := found;
  if not v_hit then
    raise exception 'No such coupon.' using errcode = 'P0001';
  end if;
  if v_own is not null then
    raise exception 'That code belongs to a restaurant''s own offer. Switch it off instead.'
      using errcode = 'P0001';
  end if;

  select count(*)::integer into v_used
    from public.orders o where o.coupon_code = v_code;

  if v_used > 0 then
    raise exception '% has been used on % order(s) and is part of their bill. Switch it off instead.',
      v_code, v_used using errcode = 'P0001';
  end if;

  delete from public.coupons where code = v_code;
end;
$$;

-- ===========================================================================
-- D. The broadcast.
-- ===========================================================================
-- 0047 built one path from a `notifications` row to a phone. A broadcast is not
-- a new path — it is rows on that path, one per recipient, because the inbox is
-- per person and a shared row would have no read receipt and no owner.
--
-- The table exists so that a broadcast leaves a mark. A message to every
-- customer is the most public thing this console can do and it has no undo; a
-- list of what has been sent, by whom, to how many, is the least it should
-- cost.
create table if not exists public.broadcasts (
  id              bigint generated always as identity primary key,
  audience        text not null
                  check (audience in ('customer', 'rider', 'restaurant')),
  title           text not null,
  body            text,
  recipient_count integer not null,
  sent_by         text not null,
  created_at      timestamptz not null default now()
);

alter table public.broadcasts enable row level security;

-- 0061's lesson, applied without having to learn it again: Supabase's default
-- privileges hand `anon` and `authenticated` insert/update/delete on every new
-- table in `public`. No policies and no grants — this table is read through one
-- function, like `delivery_codes`.
revoke all on public.broadcasts from public, anon, authenticated;

-- How many phones this would reach, answered before anybody commits to it. The
-- confirm dialog says a number, and the number is this one.
create or replace function public.admin_broadcast_reach(p_audience text)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  perform public.assert_admin();

  -- Customers are counted off `device_tokens`, riders and restaurants off their
  -- own rosters. Not an inconsistency: a customer is anybody who ever signed in,
  -- and writing an inbox row for a hundred thousand of them to reach the nine
  -- hundred with the app installed is a mailing list, not a notification. A
  -- rider and a restaurant are hand-onboarded and few, and both will read the
  -- inbox next time they open the app whether or not a push landed.
  select case p_audience
    when 'customer' then (
      select count(distinct t.user_id)::integer from public.device_tokens t
       where t.audience = 'customer' and t.user_id is not null)
    when 'rider' then (
      select count(*)::integer from public.delivery_partners p where p.is_active)
    when 'restaurant' then (
      select count(*)::integer from public.restaurants r where r.is_active)
  end into v_n;

  if v_n is null then
    raise exception 'Pick customers, riders or restaurants.' using errcode = 'P0001';
  end if;

  return v_n;
end;
$$;

create or replace function public.admin_send_broadcast(
  p_audience text,
  p_title    text,
  p_body     text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_body  text;
  v_who   text;
  v_n     integer;
begin
  perform public.assert_admin();

  v_who   := lower(auth.jwt() ->> 'email');
  v_title := nullif(trim(coalesce(p_title, '')), '');
  v_body  := nullif(trim(coalesce(p_body, '')), '');

  if v_title is null then
    raise exception 'A broadcast needs a title — it is the line on the lock screen.'
      using errcode = 'P0001';
  end if;
  if length(v_title) > 80 then
    raise exception 'Keep the title to 80 characters; Android truncates it anyway.'
      using errcode = 'P0001';
  end if;
  if v_body is not null and length(v_body) > 240 then
    raise exception 'Keep the message to 240 characters.' using errcode = 'P0001';
  end if;

  -- The realistic failure on this screen is not a wrong audience, it is the
  -- same broadcast twice — a double submit, a page reload, a second admin who
  -- did not know the first had sent it. There is no undo, so the second one is
  -- refused rather than delivered.
  if exists (
    select 1 from public.broadcasts b
     where b.audience = p_audience
       and b.title = v_title
       and b.body is not distinct from v_body
       and b.created_at > now() - interval '5 minutes'
  ) then
    raise exception 'That exact message went out in the last five minutes. It has not been sent again.'
      using errcode = 'P0001';
  end if;

  -- Also the audience check: `admin_broadcast_reach` raises on anything that is
  -- not one of the three, so a bad value never reaches the branch below.
  v_n := public.admin_broadcast_reach(p_audience);
  if v_n = 0 then
    raise exception '%', case p_audience
      when 'customer'   then 'No customer has a device registered yet.'
      when 'rider'      then 'There are no active riders to send it to.'
      else                   'There are no active restaurants to send it to.'
    end using errcode = 'P0001';
  end if;

  -- One row per recipient. Each fires `push_on_notification_insert`, which is
  -- the whole delivery mechanism and is unchanged: a broadcast is not a special
  -- kind of push, it is an ordinary one sent many times.
  if p_audience = 'customer' then
    insert into public.notifications (audience, user_id, kind, title, body)
    select 'customer', t.user_id, 'system', v_title, v_body
      from (select distinct t.user_id from public.device_tokens t
             where t.audience = 'customer' and t.user_id is not null) t;
  elsif p_audience = 'rider' then
    insert into public.notifications (audience, partner_email, kind, title, body)
    select 'rider', p.email, 'system', v_title, v_body
      from public.delivery_partners p where p.is_active;
  else
    insert into public.notifications (audience, restaurant_id, kind, title, body)
    select 'restaurant', r.id, 'system', v_title, v_body
      from public.restaurants r where r.is_active;
  end if;

  get diagnostics v_n = row_count;

  insert into public.broadcasts (audience, title, body, recipient_count, sent_by)
  values (p_audience, v_title, v_body, v_n, coalesce(v_who, 'unknown'));

  return v_n;
end;
$$;

create or replace function public.admin_list_broadcasts()
returns table (
  id              bigint,
  audience        text,
  title           text,
  body            text,
  recipient_count integer,
  sent_by         text,
  created_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select b.id, b.audience, b.title, b.body, b.recipient_count,
           b.sent_by, b.created_at
      from public.broadcasts b
     order by b.created_at desc
     limit 100;
end;
$$;

-- ===========================================================================
-- E. The platform's numbers.
-- ===========================================================================
-- The vendor app has had its own analytics since 0017. Nobody has ever been able
-- to ask how the *platform* is doing, which is a strange thing to be unable to
-- ask from the platform's own console.
--
-- Everything here is derived, every time. There is no rollup table and there
-- should not be one at this volume: a stored figure is a figure that can be
-- wrong, and 0062's whole argument about `restaurants.rating` applies to a
-- dashboard just as well as to a star.
create or replace function public.admin_platform_stats(p_days integer default 30)
returns table (
  days               integer,
  orders_placed      integer,
  orders_delivered   integer,
  orders_cancelled   integer,
  orders_rejected    integer,
  gmv                integer,
  commission         integer,
  discount_given     integer,
  avg_order          integer,
  live_orders        integer,
  restaurants_live   integer,
  riders_active      integer,
  riders_carrying    integer,
  customers_ordering integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from timestamptz;
begin
  perform public.assert_admin();

  v_from := now() - make_interval(days => v_days);

  return query
  with w as (
    select o.*, r.commission_bps
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
     where o.created_at >= v_from
  )
  select
    v_days,
    (select count(*)::integer from w),
    (select count(*)::integer from w where w.status = 'delivered'),
    (select count(*)::integer from w where w.status = 'cancelled'),
    (select count(*)::integer from w where w.status = 'rejected'),
    -- GMV is delivered orders only. An order that was placed and cancelled is
    -- not revenue, and counting it would make a bad week look like a good one.
    (select coalesce(sum(w.total), 0)::integer from w where w.status = 'delivered'),
    -- The same arithmetic `run_settlement_batch` uses, on the same base
    -- (`subtotal`, not `total` — the platform does not take a cut of tax or of
    -- the delivery fee). Two expressions of one rule, and if they ever diverge
    -- the settlement is the one that is right, because it is the one that pays.
    (select coalesce(sum(round(w.subtotal * w.commission_bps / 10000.0)), 0)::integer
       from w where w.status = 'delivered'),
    (select coalesce(sum(w.discount), 0)::integer from w where w.status = 'delivered'),
    (select coalesce(round(avg(w.total)), 0)::integer from w where w.status = 'delivered'),
    (select count(*)::integer from public.orders o
      where o.status not in ('delivered', 'cancelled', 'rejected')),
    (select count(*)::integer from public.restaurants r
      where r.is_active and r.accepting_orders),
    (select count(*)::integer from public.delivery_partners p where p.is_active),
    -- Joined to the order for the reason section G gives: a `deliveries` row
    -- that never closed under an order that did is not a rider on the road, and
    -- counting it would put a permanent 1 on this tile.
    (select count(distinct d.partner_email)::integer
       from public.deliveries d
       join public.orders o2 on o2.id = d.order_id
      where d.state not in ('delivered', 'cancelled')
        and o2.status not in ('delivered', 'cancelled', 'rejected')),
    (select count(distinct w.user_id)::integer from w);
end;
$$;

-- The series behind the chart, with the quiet days in it. A `group by` alone
-- would drop a day with no orders, and a line that skips a Tuesday is a line
-- that lies about the shape of the week.
create or replace function public.admin_daily_orders(p_days integer default 30)
returns table (
  day       date,
  placed    integer,
  delivered integer,
  cancelled integer,
  gmv       integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
begin
  perform public.assert_admin();

  return query
    select d.day::date,
           count(o.id)::integer,
           count(o.id) filter (where o.status = 'delivered')::integer,
           count(o.id) filter (where o.status = 'cancelled')::integer,
           coalesce(sum(o.total) filter (where o.status = 'delivered'), 0)::integer
      from generate_series(
             (current_date - (v_days - 1))::timestamptz,
             current_date::timestamptz,
             interval '1 day') as d(day)
      left join public.orders o on o.created_at::date = d.day::date
     group by d.day
     order by d.day;
end;
$$;

create or replace function public.admin_top_restaurants(
  p_days  integer default 30,
  p_limit integer default 10
)
returns table (
  restaurant_id text,
  name          text,
  orders        integer,
  gmv           integer,
  rating        numeric,
  rating_count  integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
begin
  perform public.assert_admin();

  return query
    select r.id, r.name,
           count(o.id)::integer,
           coalesce(sum(o.total), 0)::integer,
           r.rating, r.rating_count
      from public.restaurants r
      join public.orders o
        on o.restaurant_id = r.id
       and o.status = 'delivered'
       and o.created_at >= now() - make_interval(days => v_days)
     group by r.id, r.name, r.rating, r.rating_count
     order by 4 desc
     limit greatest(1, least(coalesce(p_limit, 10), 50));
end;
$$;

-- ===========================================================================
-- F. Vendor settlements.
-- ===========================================================================
-- `run_settlement_batch` has rolled these up every Monday since 0017 and the
-- only eyes on them have been the vendor's own. Nothing here creates a
-- settlement — the same shape as rider payouts, and for the same reason: this
-- page does not move money, it records that a person did.
create or replace function public.admin_list_settlements(p_status text default null)
returns table (
  id              bigint,
  restaurant_id   text,
  restaurant_name text,
  period_start    date,
  period_end      date,
  order_count     integer,
  gross_sales     integer,
  commission      integer,
  net_payable     integer,
  status          text,
  reference       text,
  has_bank        boolean,
  paid_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select s.id, s.restaurant_id, r.name, s.period_start, s.period_end,
           s.order_count, s.gross_sales, s.commission, s.net_payable,
           s.status, s.reference,
           (a.account_number is not null),
           s.paid_at
      from public.settlements s
      join public.restaurants r on r.id = s.restaurant_id
      left join public.restaurant_bank_accounts a on a.restaurant_id = s.restaurant_id
     where p_status is null or s.status = p_status
     order by s.status = 'paid', s.period_end desc, r.name;
end;
$$;

create or replace function public.admin_mark_settlement_paid(
  p_id        bigint,
  p_reference text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref    text;
  v_status text;
begin
  perform public.assert_admin();

  v_ref := nullif(trim(coalesce(p_reference, '')), '');
  if v_ref is null then
    raise exception 'Add the bank reference — a settlement marked paid without one cannot be reconciled.'
      using errcode = 'P0001';
  end if;

  select s.status into v_status from public.settlements s where s.id = p_id;
  if not found then
    raise exception 'No such settlement.' using errcode = 'P0001';
  end if;
  if v_status = 'paid' then
    raise exception 'That settlement is already marked paid.' using errcode = 'P0001';
  end if;

  -- `notify_vendor_settlement` fires on this update and has since 0047. The
  -- vendor finds out because the row changed, not because this function
  -- remembered to tell them.
  update public.settlements
     set status = 'paid', reference = v_ref, paid_at = now()
   where id = p_id;
end;
$$;

-- The full account number, for whoever is actually making the transfer.
-- `admin_get_restaurant` returns the last four and will keep returning the last
-- four: an onboarding form is read across a desk, and this is not.
create or replace function public.admin_get_restaurant_bank(p_id text)
returns table (
  account_holder text,
  account_number text,
  ifsc           text,
  bank_name      text,
  verified       boolean,
  updated_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select a.account_holder, a.account_number, a.ifsc, a.bank_name,
           a.verified, a.updated_at
      from public.restaurant_bank_accounts a
     where a.restaurant_id = p_id;
end;
$$;

-- ===========================================================================
-- G. The stale state list, fixed.
-- ===========================================================================
-- Both of these enumerated the live delivery states as ('claimed','picked_up'),
-- which was the whole set on 2026-07-22 and has been two-thirds of it since
-- 0049. Stated negatively now, so the next state to be added is live by default
-- rather than invisible by default — the safe direction for a guard to fail in.
--
-- **And the order has to be live too**, which is the half the original never
-- said. Writing the fix uncovered a `deliveries` row sitting at
-- `arrived_at_customer` under an order that reached `delivered` by some other
-- route back in B1 — a job that ended fourteen months of app-time ago and never
-- closed its own row. Under the old list it was invisible; under a corrected
-- list and nothing else, that one orphan would have pinned its rider to the
-- roster as permanently carrying and refused every attempt to switch them off,
-- for ever. So "live" is the conjunction it always meant: this delivery has not
-- ended *and* the order it belongs to has not either. That is true of every
-- orphan, not just the one that happens to exist today.
--
-- The orphan row itself is left exactly where it is. Closing it would move it
-- into the next Monday's payout batch, and paying somebody is not a data repair.
create or replace function public.admin_list_riders()
returns table (
  email           text,
  name            text,
  phone           text,
  vehicle         text,
  is_active       boolean,
  created_at      timestamptz,
  live_order_id   text,
  delivered_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select p.email, p.name, p.phone, p.vehicle, p.is_active, p.created_at,
           (select d.order_id
              from public.deliveries d
              join public.orders o on o.id = d.order_id
             where d.partner_email = p.email
               and d.state not in ('delivered', 'cancelled')
               and o.status not in ('delivered', 'cancelled', 'rejected')
             limit 1),
           (select count(*)::integer
              from public.deliveries d
             where d.partner_email = p.email
               and d.state = 'delivered')
      from public.delivery_partners p
     order by p.is_active desc, p.created_at;
end;
$$;

create or replace function public.admin_set_rider_active(p_email text, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_order text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));

  if not p_active then
    select d.order_id into v_order
      from public.deliveries d
      join public.orders o on o.id = d.order_id
     where d.partner_email = v_email
       and d.state not in ('delivered', 'cancelled')
       and o.status not in ('delivered', 'cancelled', 'rejected')
     limit 1;

    if v_order is not null then
      -- The message changes with this migration, because the answer does. Until
      -- now the only way out was the rider's own app — useless in the case this
      -- guard exists for, which is a rider who has stopped answering.
      raise exception
        'They are carrying order %. Release it from the live orders screen first, or the order cannot be delivered by anyone.',
        v_order using errcode = 'P0001';
    end if;
  end if;

  update public.delivery_partners
     set is_active = p_active
   where email = v_email;

  if not found then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;
end;
$$;

-- ===========================================================================
-- H. Grants.
-- ===========================================================================
-- Postgres grants `execute` on every new function to `PUBLIC`. Revoke first,
-- then hand it back. Every one of these calls `assert_admin()` on its first
-- line, so this is the outer of two doors — but "a signed-out caller cannot
-- invoke it" is a shorter thing to verify than "every branch inside checks".
revoke all on function public.admin_orders(text) from public, anon, authenticated;
grant execute on function public.admin_orders(text) to authenticated;

revoke all on function public.admin_release_delivery(text, text) from public, anon, authenticated;
grant execute on function public.admin_release_delivery(text, text) to authenticated;

revoke all on function public.admin_cancel_order(text, text) from public, anon, authenticated;
grant execute on function public.admin_cancel_order(text, text) to authenticated;

revoke all on function public.admin_list_coupons() from public, anon, authenticated;
grant execute on function public.admin_list_coupons() to authenticated;

revoke all on function public.admin_save_coupon(text, integer, integer, integer, integer, timestamptz)
  from public, anon, authenticated;
grant execute on function public.admin_save_coupon(text, integer, integer, integer, integer, timestamptz)
  to authenticated;

revoke all on function public.admin_set_coupon_active(text, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_coupon_active(text, boolean) to authenticated;

revoke all on function public.admin_delete_coupon(text) from public, anon, authenticated;
grant execute on function public.admin_delete_coupon(text) to authenticated;

revoke all on function public.admin_broadcast_reach(text) from public, anon, authenticated;
grant execute on function public.admin_broadcast_reach(text) to authenticated;

revoke all on function public.admin_send_broadcast(text, text, text) from public, anon, authenticated;
grant execute on function public.admin_send_broadcast(text, text, text) to authenticated;

revoke all on function public.admin_list_broadcasts() from public, anon, authenticated;
grant execute on function public.admin_list_broadcasts() to authenticated;

revoke all on function public.admin_platform_stats(integer) from public, anon, authenticated;
grant execute on function public.admin_platform_stats(integer) to authenticated;

revoke all on function public.admin_daily_orders(integer) from public, anon, authenticated;
grant execute on function public.admin_daily_orders(integer) to authenticated;

revoke all on function public.admin_top_restaurants(integer, integer) from public, anon, authenticated;
grant execute on function public.admin_top_restaurants(integer, integer) to authenticated;

revoke all on function public.admin_list_settlements(text) from public, anon, authenticated;
grant execute on function public.admin_list_settlements(text) to authenticated;

revoke all on function public.admin_mark_settlement_paid(bigint, text) from public, anon, authenticated;
grant execute on function public.admin_mark_settlement_paid(bigint, text) to authenticated;

revoke all on function public.admin_get_restaurant_bank(text) from public, anon, authenticated;
grant execute on function public.admin_get_restaurant_bank(text) to authenticated;

-- The two that already existed and were replaced above. Their argument lists are
-- unchanged, so `create or replace` genuinely replaced them (0051's lesson) and
-- their existing grants survived — re-stated anyway, because a reader should not
-- have to go and check which of the functions in this file are new.
revoke all on function public.admin_list_riders() from public, anon, authenticated;
grant execute on function public.admin_list_riders() to authenticated;

revoke all on function public.admin_set_rider_active(text, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_rider_active(text, boolean) to authenticated;
