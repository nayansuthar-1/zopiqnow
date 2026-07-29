-- ---------------------------------------------------------------------------
-- 0061 — the order can be spoken to. (Phase B5, communication)
-- ---------------------------------------------------------------------------
-- Everything on this platform has been one-way until now. The customer watches a
-- timeline; the rider reads an address; the kitchen reads a ticket. Nobody can
-- say anything to anybody. Three gaps close here, and they are deliberately of
-- different weights:
--
--   1. **A number to ring.** The rider has been able to call the customer since
--      8g. The customer could only *read* the rider's number off a card, and
--      neither of them could call the kitchen. The data for all of that already
--      exists — `orders.user_phone`, `delivery_partners.phone`,
--      `restaurants.contact_phone` (0027) — it was simply never handed to the
--      screen that needed it. `my_deliveries` gains one column and the customer
--      app reads a column of the catalog join it already makes.
--
--   2. **Something to say without ringing.** A canned-message thread between the
--      customer and the rider carrying their order. Canned and not free text,
--      because free text is a moderation problem and a retention problem, and
--      neither is a thing to take on in the same week as the button. The rule
--      that makes "canned" mean anything is that **the database owns the
--      wording**: an app sends a code, and the sentence that gets stored is the
--      one this file chose. An app cannot put words in anybody's mouth.
--
--   3. **The sentence the rider actually needs.** Delivery instructions — "gate
--      2, the blue door", "ring the bell, the dog barks" — on the address, on
--      the order, and on the rider's job card. This is the one item of the three
--      that removes phone calls rather than enabling them.
--
-- **What is *not* here.** No masked numbers: a `tel:` to the real number is what
-- this platform can honestly do today, and a masking provider is a B5 line item
-- of its own with a vendor contract behind it. No vendor side of the chat — a
-- kitchen with a headset is a support product, not a delivery one. No free text.

-- ===========================================================================
-- A. Delivery instructions.
-- ===========================================================================
-- Two columns for one fact, for the same reason `orders.delivery_to` duplicates
-- `addresses.line1` (0006): the address is the customer's living document and
-- the order is a frozen record of one night. Editing "ring the bell twice" into
-- "the bell is broken" must not rewrite what the rider was told last Tuesday.
alter table public.addresses
  add column if not exists delivery_notes text;

alter table public.orders
  add column if not exists delivery_notes text;

-- A sentence, not an essay. 160 characters is about what a rider reads at a
-- gate without scrolling, and a note nobody reads is worse than no note.
-- Checked only when present, the 0027 way — null passes.
alter table public.addresses
  drop constraint if exists addresses_delivery_notes_is_a_sentence;
alter table public.addresses
  add constraint addresses_delivery_notes_is_a_sentence
  check (delivery_notes is null or length(delivery_notes) <= 160);

alter table public.orders
  drop constraint if exists orders_delivery_notes_is_a_sentence;
alter table public.orders
  add constraint orders_delivery_notes_is_a_sentence
  check (delivery_notes is null or length(delivery_notes) <= 160);

-- ---------------------------------------------------------------------------
-- place_order carries it onto the order.
-- ---------------------------------------------------------------------------
-- The whole of 0048's function, unchanged but for the new argument and the
-- column it fills. It could not be a separate "set the notes" call afterwards:
-- the client has no `update` grant on `orders` and is never getting one, and a
-- note that arrives a round trip after the order is a note the kitchen may
-- already have skipped past.
--
-- **Dropped first, not replaced.** A tenth argument is a different signature, so
-- `create or replace` would leave 0048's nine-argument version standing beside
-- this one and PostgREST would be free to bind either — the overload trap 0045
-- fell into. Dropping by exact signature is what makes this a replacement.
--
-- An installed app that does not send `p_delivery_notes` still binds here and
-- gets a null: the argument is defaulted precisely so the release order between
-- the database and the store does not matter.
drop function if exists public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text
);

create function public.place_order(
  p_user_phone       text,
  p_restaurant_id    text,
  p_items            jsonb,
  p_delivery_to      text,
  p_payment_method   text,
  p_delivery_lat     double precision default null,
  p_delivery_lng     double precision default null,
  p_coupon_code      text default null,
  p_payment_id       text default null,
  p_delivery_notes   text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      text;
  v_order_id     text;
  v_subtotal     integer := 0;
  v_delivery_fee integer;
  v_taxes        integer;
  v_discount     integer := 0;
  v_total        integer;
  v_eta          integer;
  v_name         text;
  v_accepting    boolean;
  v_notes        text;
  v_line         jsonb;
  v_seq          integer;
  v_mi_id        text;
  v_mi_name      text;
  v_base         integer;
  v_qty          integer;
  v_opt_ids      text[];
  v_opts         jsonb;
  v_addons       integer;
  v_unit         integer;
  v_line_total   integer;
  v_line_id      bigint;
  v_row          record;
  v_opt          jsonb;
begin
  v_user_id := auth.uid()::text;
  if v_user_id is null then
    raise exception 'Please sign in to place an order.' using errcode = 'P0001';
  end if;

  if p_user_phone is null or length(trim(p_user_phone)) = 0 then
    raise exception 'We need a phone number for your rider.' using errcode = 'P0001';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty.' using errcode = 'P0001';
  end if;

  if p_payment_method = 'upi'
     and (p_payment_id is null or length(trim(p_payment_id)) = 0) then
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  -- Trimmed and truncated rather than refused. A note is a courtesy the customer
  -- typed on the way past; failing an order over its length would be absurd.
  v_notes := nullif(trim(coalesce(p_delivery_notes, '')), '');
  v_notes := left(v_notes, 160);

  select name, eta_minutes, accepting_orders
    into v_name, v_eta, v_accepting
    from public.restaurants where id = p_restaurant_id and is_active;
  if not found then
    raise exception 'This restaurant isn''t available right now.'
      using errcode = 'P0001';
  end if;

  if not v_accepting then
    raise exception 'This restaurant has stopped taking orders for now.'
      using errcode = 'P0001';
  end if;

  if not public.restaurant_is_open_now(p_restaurant_id) then
    raise exception 'This restaurant is closed right now. Please check its hours before ordering.'
      using errcode = 'P0001';
  end if;

  -- Pass one: price every line into a scratch table, options and all, and total
  -- the subtotal — without touching `orders` yet, so an invalid coupon below is
  -- still answered with a sentence rather than a foreign-key violation.
  create temp table _lines (
    seq          integer,
    menu_item_id text,
    name         text,
    unit_price   integer,
    quantity     integer,
    line_total   integer,
    options      jsonb
  ) on commit drop;

  for v_line, v_seq in
    select value, ordinality from jsonb_array_elements(p_items) with ordinality
  loop
    v_qty := (v_line ->> 'quantity')::integer;
    if v_qty is null or v_qty < 1 then
      raise exception 'Your cart has an invalid quantity.' using errcode = 'P0001';
    end if;

    select id, name, price into v_mi_id, v_mi_name, v_base
      from public.menu_items
     where id = (v_line ->> 'menu_item_id')
       and restaurant_id = p_restaurant_id
       and is_available;
    if not found then
      raise exception 'Something in your cart is no longer available.'
        using errcode = 'P0001';
    end if;

    -- The claimed options for this line (absent → empty → all defaults filled).
    v_opt_ids := coalesce(
      (select array_agg(value)
         from jsonb_array_elements_text(coalesce(v_line -> 'option_ids', '[]'::jsonb))),
      array[]::text[]
    );

    -- Resolve once into what is actually charged (name + delta, frozen), then
    -- price off that so the sum and the stored choices can never disagree.
    select coalesce(
             jsonb_agg(jsonb_build_object('name', option_name, 'price_delta', price_delta)),
             '[]'::jsonb
           )
      into v_opts
      from public.resolve_order_line_options(v_mi_id, v_opt_ids);

    v_addons := coalesce(
      (select sum((e ->> 'price_delta')::integer)
         from jsonb_array_elements(v_opts) as e),
      0
    );

    v_unit := v_base + v_addons;
    v_line_total := v_unit * v_qty;
    v_subtotal := v_subtotal + v_line_total;

    insert into _lines
      values (v_seq, v_mi_id, v_mi_name, v_unit, v_qty, v_line_total, v_opts);
  end loop;

  v_delivery_fee := case when v_subtotal >= 500 then 0 else 40 end;
  v_taxes := round(v_subtotal * 0.05)::integer;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_discount := public.validate_coupon(p_coupon_code, v_subtotal);
  end if;

  v_total := v_subtotal + v_delivery_fee + v_taxes - v_discount;

  insert into public.orders (
    user_id, user_phone, restaurant_id, restaurant_name,
    subtotal, delivery_fee, taxes, discount, total,
    coupon_code, payment_method, payment_id,
    delivery_to, delivery_lat, delivery_lng, delivery_notes, eta_minutes
  ) values (
    v_user_id, p_user_phone, p_restaurant_id, v_name,
    v_subtotal, v_delivery_fee, v_taxes, v_discount, v_total,
    nullif(upper(trim(coalesce(p_coupon_code, ''))), ''), p_payment_method, p_payment_id,
    p_delivery_to, p_delivery_lat, p_delivery_lng, v_notes, v_eta
  ) returning id into v_order_id;

  -- Pass two: the lines, in order, each with its frozen options.
  for v_row in select * from _lines order by seq
  loop
    insert into public.order_items
      (order_id, menu_item_id, name, unit_price, quantity, line_total)
    values (v_order_id, v_row.menu_item_id, v_row.name, v_row.unit_price,
            v_row.quantity, v_row.line_total)
    returning id into v_line_id;

    insert into public.order_item_options (order_item_id, name, price_delta)
    select v_line_id, e ->> 'name', (e ->> 'price_delta')::integer
      from jsonb_array_elements(v_row.options) as e;
  end loop;

  return jsonb_build_object(
    'id', v_order_id,
    'restaurant_name', v_name,
    'delivery_to', p_delivery_to,
    'total', v_total,
    'payment_method', p_payment_method,
    'payment_id', p_payment_id,
    'eta_minutes', v_eta
  );
end;
$$;

grant execute on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text, text
) to authenticated;

-- ===========================================================================
-- B. The canned messages, and who is allowed to send which.
-- ===========================================================================
-- The list lives in a function and not in a table, for the reason 0056 gave
-- about the dispatcher's constants: a table nobody has a screen to write to is a
-- table that lies about being configurable. It lives in the *database* and not
-- in the apps for a harder reason — the apps must show the customer the sentence
-- that will actually be stored, and two copies of a list is two lists.
--
-- Immutable, so the menu below is a constant scan and not a per-row call.
create or replace function public.order_message_body(p_sender text, p_code text)
returns text
language sql
immutable
as $$
  select case when p_sender = 'customer' then
    case p_code
      when 'where_are_you'  then 'Where are you right now?'
      when 'call_on_arrive' then 'Please call me when you get here.'
      when 'leave_at_door'  then 'Please leave it at the door.'
      when 'hard_to_find'   then 'The address is hard to find — I''ll guide you.'
      when 'coming_down'    then 'I''m coming down, please wait a minute.'
      when 'thank_you'      then 'Thank you!'
    end
  when p_sender = 'rider' then
    case p_code
      when 'on_my_way'      then 'I''m on my way with your order.'
      when 'kitchen_late'   then 'I''m at the restaurant — your order isn''t ready yet.'
      when 'five_minutes'   then 'I''ll be there in about 5 minutes.'
      when 'cant_find'      then 'I can''t find the address — can you guide me?'
      when 'at_the_gate'    then 'I''m outside. Please come down.'
      when 'please_pick_up' then 'I tried calling — please pick up.'
    end
  end;
$$;

-- What *this* caller may send, in the order it should be shown.
--
-- The role is derived, never passed: a rider is whoever
-- `delivery_partner_email()` recognises, and everybody else is a customer. An
-- app that asked for the other side's list would get its own.
create or replace function public.order_message_menu()
returns table (code text, body text)
language sql
stable
set search_path = public
as $$
  select c.code, public.order_message_body(v.sender, c.code)
    from (select case when public.delivery_partner_email() is null
                      then 'customer' else 'rider' end as sender) v
    cross join lateral unnest(
      case when v.sender = 'customer'
           then array['where_are_you', 'call_on_arrive', 'leave_at_door',
                      'hard_to_find', 'coming_down', 'thank_you']
           else array['on_my_way', 'kitchen_late', 'five_minutes',
                      'cant_find', 'at_the_gate', 'please_pick_up']
      end
    ) with ordinality as c(code, rank)
   order by c.rank;
$$;

grant execute on function public.order_message_menu() to authenticated;

-- ===========================================================================
-- C. The thread.
-- ===========================================================================
-- `body` is stored alongside `code` rather than derived from it on read. The
-- code is what was chosen; the body is what was *said*, and rewording a canned
-- line next month must not rewrite a conversation that already happened. The
-- same argument `order_items.name` makes about a renamed dish.
create table if not exists public.order_messages (
  id         bigserial primary key,
  order_id   text not null references public.orders (id) on delete cascade,

  -- Which end of the ride said it. Not an account id: the customer is
  -- `orders.user_id` and the rider is an email, and the only thing a thread
  -- needs to know is which side of itself a line came from.
  sender     text not null check (sender in ('customer', 'rider')),

  code       text not null,
  body       text not null,
  created_at timestamptz not null default now(),

  -- Set by the *other* side opening the thread. Null on a line nobody has seen,
  -- which is the whole of the unread badge.
  read_at    timestamptz
);

create index if not exists order_messages_order_idx
  on public.order_messages (order_id, created_at);

alter table public.order_messages enable row level security;

-- Read, from both ends. Note the asymmetry, and that it is not an accident: the
-- customer may read their own order's thread forever (it is their receipt of a
-- conversation), while the rider's window closes with the job — the same shape
-- `my_deliveries` uses, and the same reason 0039 gave for taking the customer's
-- number back at delivery.
drop policy if exists "customers read their own order thread" on public.order_messages;
create policy "customers read their own order thread"
  on public.order_messages for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = order_messages.order_id
         and o.user_id = auth.uid()::text
    )
  );

drop policy if exists "riders read the thread of a job they hold" on public.order_messages;
create policy "riders read the thread of a job they hold"
  on public.order_messages for select to authenticated
  using (
    exists (
      select 1 from public.deliveries d
       where d.order_id = order_messages.order_id
         and d.partner_email = public.delivery_partner_email()
         and d.state <> 'cancelled'
    )
  );

-- Select and nothing else. Every line is written by `send_order_message` below,
-- which is the only place that knows whether the sender is entitled to speak and
-- what the words are allowed to be. A client that could insert would write any
-- body it liked under either sender, which would make "canned" a decoration.
--
-- **The revoke is not decoration either.** Supabase ships a default privilege
-- that grants `anon` and `authenticated` all of insert/update/delete on every
-- new table in `public` — so this table arrives writable and a bare
-- `grant select` adds nothing. RLS would still refuse the write for want of a
-- policy, but "no policy exists yet" is a weaker guarantee than "no grant
-- exists", and the next migration to add an insert policy for one purpose would
-- silently open all three. This is 0045's lesson applied to a table instead of a
-- function.
revoke all on public.order_messages from anon, authenticated;
grant select on public.order_messages to authenticated;

-- Realtime, the same way 0008 and 0021 did it: a policy decides what a
-- subscriber is told, and the publication decides whether they are told at all.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'order_messages'
  ) then
    alter publication supabase_realtime add table public.order_messages;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Saying something.
-- ---------------------------------------------------------------------------
-- The window is `picked_up` and `arrived_at_customer` — exactly the states in
-- which the customer can already see who their rider is (0049). Before pickup
-- there is a rider who may still drop the job, and the customer has not been
-- told their name; after delivery the two have no business with each other and
-- the rider's number has already been taken back.
create or replace function public.send_order_message(
  p_order_id text,
  p_code     text
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider     text;
  v_sender    text;
  v_body      text;
  v_partner   text;
  v_user      text;
  v_rider_name text;
  v_id        bigint;
begin
  v_rider := public.delivery_partner_email();

  -- One query answers both "is there a live delivery here?" and "whose is it?".
  select d.partner_email, o.user_id, p.name
    into v_partner, v_user, v_rider_name
    from public.deliveries d
    join public.orders o on o.id = d.order_id
    join public.delivery_partners p on p.email = d.partner_email
   where d.order_id = p_order_id
     and d.state in ('picked_up', 'arrived_at_customer');

  if not found then
    raise exception 'There is nobody on this order to message right now.'
      using errcode = 'P0001';
  end if;

  if v_rider is not null and v_rider = v_partner then
    v_sender := 'rider';
  elsif v_user = auth.uid()::text then
    v_sender := 'customer';
  else
    -- Not their order and not their job. Deliberately the same sentence as
    -- above: a stranger probing this function learns nothing from the answer.
    raise exception 'There is nobody on this order to message right now.'
      using errcode = 'P0001';
  end if;

  v_body := public.order_message_body(v_sender, p_code);
  if v_body is null then
    raise exception 'That is not a message we send.' using errcode = 'P0001';
  end if;

  -- Every line fires a push at somebody who is riding a motorbike or waiting at
  -- a door. Three seconds is not a security control — B8 owns velocity limits —
  -- it is the difference between a conversation and a doorbell held down.
  if exists (
    select 1 from public.order_messages m
     where m.order_id = p_order_id
       and m.sender = v_sender
       and m.created_at > now() - interval '3 seconds'
  ) then
    raise exception 'One at a time, please.' using errcode = 'P0001';
  end if;

  insert into public.order_messages (order_id, sender, code, body)
  values (p_order_id, v_sender, p_code, v_body)
  returning id into v_id;

  -- The other end hears about it. Wrapped for 0047's reason: the message is the
  -- event, the notification is a courtesy on top of it, and a push that cannot
  -- be written must not lose the line that was said.
  begin
    if v_sender = 'customer' then
      insert into public.notifications
        (audience, partner_email, kind, title, body, order_id)
      values ('rider', v_partner, 'message', 'Message from your customer',
              v_body, p_order_id);
    else
      insert into public.notifications
        (audience, user_id, kind, title, body, order_id)
      values ('customer', v_user, 'message',
              coalesce(v_rider_name, 'Your rider') || ' says', v_body, p_order_id);
    end if;
  exception when others then
    null;
  end;

  return v_id;
end;
$$;

revoke all on function public.send_order_message(text, text)
  from public, anon;
grant execute on function public.send_order_message(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Having read it.
-- ---------------------------------------------------------------------------
-- Only the lines the caller did *not* write, which is what makes this idempotent
-- and what stops a sender from marking their own message read on the way out.
-- Scoped through the same two identities the select policies use, so a caller
-- with no business here updates nothing rather than being told off.
create or replace function public.mark_order_messages_read(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider  text;
  v_sender text;
begin
  v_rider := public.delivery_partner_email();

  if v_rider is not null and exists (
    select 1 from public.deliveries d
     where d.order_id = p_order_id
       and d.partner_email = v_rider
       and d.state <> 'cancelled'
  ) then
    v_sender := 'rider';
  elsif exists (
    select 1 from public.orders o
     where o.id = p_order_id
       and o.user_id = auth.uid()::text
  ) then
    v_sender := 'customer';
  else
    return;
  end if;

  update public.order_messages
     set read_at = now()
   where order_id = p_order_id
     and sender <> v_sender
     and read_at is null;
end;
$$;

revoke all on function public.mark_order_messages_read(text) from public, anon;
grant execute on function public.mark_order_messages_read(text) to authenticated;

-- A chat line is a new kind of inbox row. Re-declared in full because a check
-- constraint cannot be added to — 0051 and 0056 did the same, and the list below
-- is 0056's with one line on the end.
alter table public.notifications
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check
    check (kind in (
      'new_order',      -- vendor: a customer placed an order (0021)
      'system',         -- anyone: a catch-all notice
      'order_update',   -- customer: their order changed status (0047)
      'order_live',     -- customer: silent tick for the live card (0052)
      'job_offer',      -- rider: this job is yours if you take it now (0056)
      'job_available',  -- rider: a delivery reached the open board
      'job_cancelled',  -- rider: a job they were holding was called off (0051)
      'payout',         -- rider: a payout was paid
      'account',        -- rider: their partner account was activated/deactivated
      'settlement',     -- vendor: a weekly settlement was paid
      'message'         -- customer/rider: the other one said something (0061)
    ));

-- ===========================================================================
-- D. What the rider is handed.
-- ===========================================================================
-- Two columns onto `my_deliveries`: the kitchen's phone number, so a rider stuck
-- at a counter can ask rather than wait, and the customer's note, so they stop
-- ringing to ask which gate.
--
-- Dropped and recreated for 0059's reason — a new column in a `returns table` is
-- a new result type, which `create or replace` refuses. The argument list is
-- unchanged (there isn't one), so this replaces rather than overloads.
--
-- `restaurants.contact_phone` is null on every seeded restaurant and on any
-- draft an admin has not finished (0027). Null reaches the app as null and the
-- button is simply absent — a dialler opening on an empty number is worse than
-- no button.
drop function if exists public.my_deliveries();

create function public.my_deliveries()
returns table (
  order_id                 text,
  state                    text,
  order_status             text,
  restaurant_name          text,
  restaurant_lat           double precision,
  restaurant_lng           double precision,
  restaurant_phone         text,
  deliver_to               text,
  deliver_lat              double precision,
  deliver_lng              double precision,
  delivery_notes           text,
  customer_phone           text,
  total                    integer,
  payment_method           text,
  distance_km              numeric,
  pay_base                 integer,
  pay_per_km               numeric,
  rider_pay                integer,
  claimed_at               timestamptz,
  arrived_at_restaurant_at timestamptz,
  picked_up_at             timestamptz,
  arrived_at_customer_at   timestamptz,
  delivered_at             timestamptz,
  route_polyline           text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  return query
    select o.id, d.state, o.status, r.name, r.latitude, r.longitude,
           r.contact_phone,
           o.delivery_to, o.delivery_lat, o.delivery_lng,
           -- Withheld on a finished job, exactly as the phone number below is.
           -- The note is the customer's description of their own front door.
           case when d.state = 'delivered' then null else o.delivery_notes end,
           case when d.state = 'delivered' then null else o.user_phone end,
           o.total, o.payment_method,
           d.distance_km, d.pay_base, d.pay_per_km, d.rider_pay,
           d.claimed_at, d.arrived_at_restaurant_at,
           d.picked_up_at, d.arrived_at_customer_at, d.delivered_at,
           o.route_polyline
      from public.deliveries d
      join public.orders o on o.id = d.order_id
      join public.restaurants r on r.id = o.restaurant_id
     where d.partner_email = v_rider
       and d.state <> 'cancelled'
     order by d.claimed_at desc;
end;
$$;

grant execute on function public.my_deliveries() to authenticated;

-- The customer's side of the same question needs no function: `restaurants` is
-- world-readable while active (0001) and `contact_phone` has been a column of it
-- since 0027, so the order screen reads it off the catalog join it already makes
-- for the photo. Showing it only on an order — and not on the restaurant page —
-- is a product choice and not a boundary: a kitchen's number is worth having
-- when there is food coming, and is noise on a browse screen.
