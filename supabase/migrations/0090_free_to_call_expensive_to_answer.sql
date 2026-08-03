-- 0090 - free to call, expensive to answer
--
-- Ship-plan S6, 3 August 2026. Rate-limit the things that cost money or send
-- mail. Not every RPC - audit SEC-005 wants that and this is not the week - the
-- four the plan names: order placement, OTP send, broadcast, and push.
--
-- **Where each limit lives, and why it is not one shared mechanism.** A generic
-- bucket table would need its own writes, its own cleanup and its own bugs, and
-- would still have to be consulted from three different places. Each limit below
-- instead counts the rows the action itself already writes. That cannot drift
-- from the thing it is limiting, because it *is* the thing it is limiting.
--
-- --------------------------------------------------------------------------
-- 1. ORDER PLACEMENT - a `before insert` trigger, not a check inside
--    `place_order`.
-- --------------------------------------------------------------------------
--
-- The same shape as 0084's cash refusal, 0085's payment gate and 0088's blocked
-- user, and for the same reason: the rule belongs to the table, so every path
-- that creates an order is covered rather than the one path we remembered.
--
-- Ten per hour per customer. The number is generous on purpose - a household
-- ordering from three restaurants in an evening is nowhere near it - and the
-- abuse it stops is not subtle: with the payment gate disarmed (S5, still
-- waiting on merchant keys) a signed-in customer can place orders for nothing,
-- and every one of them rings a kitchen and makes somebody start cooking.
--
-- `orders_user_idx (user_id, created_at desc)` already exists, so the count is
-- an index scan and not a new index.
--
-- Cancelled and rejected orders still count. That is deliberate: each one rang
-- the kitchen, and a limit that resets when you cancel is not a limit.
--
-- The trigger name is chosen so it fires *after* `orders_reject_blocked_user`
-- and `orders_reject_new_cash` - a blocked customer should read that they are
-- blocked, not that they are in a hurry - and *before*
-- `orders_require_verified_payment`, so a refused order never consumes a
-- payment intent. Triggers fire in name order, and these four now read:
--
--     orders_reject_blocked_user
--     orders_reject_new_cash
--     orders_reject_too_many        <- this one
--     orders_require_verified_payment

create or replace function public.orders_reject_too_many()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  -- Not a settings row. A ceiling an operator can raise in a hurry is a ceiling
  -- that gets raised in a hurry, and this one is the only thing standing between
  -- a signed-in stranger and an unbounded number of kitchen tickets.
  v_max    constant integer := 10;
  v_window constant interval := interval '1 hour';
  v_recent integer;
begin
  select count(*) into v_recent
    from public.orders o
   where o.user_id = new.user_id
     and o.created_at > now() - v_window;

  if v_recent >= v_max then
    raise exception
      'That is % orders in an hour. Please wait a little before ordering again.',
      v_recent using errcode = 'P0001';
  end if;

  return new;
end;
$function$;

revoke execute on function public.orders_reject_too_many() from public;

create trigger orders_reject_too_many
  before insert on public.orders
  for each row execute function public.orders_reject_too_many();

-- --------------------------------------------------------------------------
-- 2. OTP SEND - stated here, and deliberately not built.
-- --------------------------------------------------------------------------
--
-- There is nothing to write. The OTP endpoint is GoTrue's, not PostgREST's; no
-- trigger, policy or function in this database is on that path, and anything
-- added here would be theatre. What actually governs it is server
-- configuration, and it is already set:
--
--   * `smtp_max_frequency` = 45 seconds between mails to the same address;
--   * `rate_limit_otp` and `rate_limit_email_sent` = 200/hour project-wide,
--     raised from the Supabase default of 30 on 3 August;
--   * `rate_limit_verify` = 30/hour and **still owed** - see ship-plan G13, where
--     it caps successful sign-ins across all three apps.
--
-- The abuse a throughput cap cannot answer is the distributed one: the 45s
-- throttle is per address, so thirty addresses typed into a sign-in form exhaust
-- nothing but the project-wide bucket. hCaptcha on the auth endpoints is the
-- control for that, it needs client work in all three apps, and G13 already
-- records it as a post-launch item. Writing a fake limit here would only make
-- this file look more complete than the system is.

-- --------------------------------------------------------------------------
-- 3. BROADCAST - a ceiling beside the duplicate guard that is already there.
-- --------------------------------------------------------------------------
--
-- One broadcast writes one `notifications` row per registered device, and each
-- of those fires a push. It is the single most expensive call in the system, and
-- until now the only thing limiting it was a five-minute refusal of the *exact
-- same* message - which stops a double submit and does nothing at all about a
-- hundred different ones.
--
-- Six an hour, per admin. An operator with more than six distinct things to
-- announce in an hour is testing, or is not the operator. Per admin rather than
-- platform-wide because `sent_by` is already recorded and a compromised session
-- belongs to somebody.
--
-- Everything else in this function is unchanged from the live definition.

create or replace function public.admin_send_broadcast(p_audience text, p_title text, p_body text)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  -- New in 0090 (ship S6). The guard above stops the same message twice; this
  -- one stops a hundred different ones. A broadcast is one push per registered
  -- device, so this is the most expensive thing anybody can ask this database
  -- to do.
  if (
    select count(*) from public.broadcasts b
     where b.sent_by = coalesce(v_who, 'unknown')
       and b.created_at > now() - interval '1 hour'
  ) >= 6 then
    raise exception
      'That is six broadcasts in an hour. Wait before sending another.'
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
$function$;

revoke execute on function public.admin_send_broadcast(text, text, text) from public;

-- --------------------------------------------------------------------------
-- 4. PUSH - limited at its producers, because it has no other door.
-- --------------------------------------------------------------------------
--
-- A push exists because a `notifications` row was written. Nothing can write one
-- from outside: the table has RLS on, no write policy, and after 0089 no write
-- privilege either, so every row comes from a SECURITY DEFINER function or a
-- trigger owned by `postgres`. The edge function that turns a row into a push is
-- already gated on `NOTIFY_WEBHOOK_SECRET` and re-reads the row from the table,
-- so it cannot be made to invent one (SEC-001).
--
-- That leaves exactly three producers of caller-driven volume, and two are now
-- capped above: order events (bounded by the order limit) and broadcasts. The
-- third is the rider/customer chat, and it is the one that rings a phone
-- belonging to somebody on a motorbike.
--
-- `send_order_message` already refuses a second line within three seconds. That
-- comment says out loud that it is a doorbell guard and not a velocity limit,
-- and it is right: three seconds still permits 1,200 messages an hour. The menu
-- is nine fixed lines (0061), so twenty per side on one delivery is far past any
-- real conversation and well short of a weapon.
--
-- Everything else in this function is unchanged from the live definition.

create or replace function public.send_order_message(p_order_id text, p_code text)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  -- New in 0090 (ship S6), and it is the velocity limit the comment above says
  -- it is not. Three seconds apart still allows 1,200 pushes an hour at one
  -- rider; the canned menu is nine lines, so twenty per side is a conversation
  -- nobody real will reach.
  if (
    select count(*) from public.order_messages m
     where m.order_id = p_order_id
       and m.sender = v_sender
  ) >= 20 then
    raise exception 'That is enough messages on this order.'
      using errcode = 'P0001';
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
$function$;

revoke execute on function public.send_order_message(text, text) from public;

-- The checks from 0087 and 0089 both still apply and both must return zero rows.
-- `create or replace` preserves a function's ACL rather than resetting it, so the
-- two revokes above are belt and braces - but 0087's whole lesson is that this is
-- the assumption worth restating in code rather than in a comment.
