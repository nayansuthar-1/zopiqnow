-- Migration 47: an inbox for everyone, not just the kitchen.
--
-- 0021 gave the vendor an inbox: a `notifications` table, one row per thing
-- worth telling a restaurant about, read over Realtime, marked read through two
-- RPCs. It was built restaurant-shaped — `restaurant_id not null`, a policy that
-- reads `staff_restaurant_id()`, a trigger on new orders. This migration widens
-- that one table to serve all three audiences — the customer, the rider and the
-- restaurant — and adds the events each of them actually cares about.
--
-- **Why one table and not three.** The shape is identical for everyone: a title,
-- a body, an optional order it points at, a `read_at`. Three tables would be
-- three copies of the same policy/RPC/Realtime plumbing drifting apart. The only
-- thing that differs between audiences is *who the row is for*, so that is the
-- only thing that varies here: an `audience` column and one recipient column per
-- kind of recipient, with a check that the right one is filled.
--
-- **Nothing the vendor already relies on changes.** Its select policy, its two
-- RPC names, the `new_order` trigger and the Realtime publication all keep
-- working — the vendor app needs no change to keep its inbox. The RPCs are
-- rewritten to serve any caller, but a vendor calling them behaves exactly as
-- before.

-- ---------------------------------------------------------------------------
-- Widen the table.
-- ---------------------------------------------------------------------------
-- `audience` says which app a row belongs in. `restaurant_id` loses its
-- not-null (a customer's row has none); `user_id` and `partner_email` are the
-- other two recipients, each nullable and each matching the identity its app
-- already authenticates as — `orders.user_id` is text (0003), a rider is keyed
-- by email everywhere (0025).
alter table public.notifications
  add column if not exists audience     text not null default 'restaurant',
  add column if not exists user_id      text,
  add column if not exists partner_email text;

alter table public.notifications
  alter column restaurant_id drop not null;

-- The audience must be one we know, and the recipient column that matches it
-- must be filled — a 'customer' row with no `user_id` is a notification nobody
-- can ever read, which is a bug we want the database to refuse rather than store.
alter table public.notifications
  drop constraint if exists notifications_audience_check,
  drop constraint if exists notifications_recipient_present;

alter table public.notifications
  add constraint notifications_audience_check
    check (audience in ('restaurant', 'customer', 'rider')),
  add constraint notifications_recipient_present
    check (
      case audience
        when 'restaurant' then restaurant_id is not null
        when 'customer'   then user_id is not null
        when 'rider'      then partner_email is not null
      end
    );

-- The `kind` set grows with the new sources. Kept as a check rather than an enum
-- for the same reason 0021 did: adding a value is one line here, not an
-- `alter type` that locks. Each app maps an unknown kind to a neutral default,
-- so an older build meeting a newer kind degrades to a plain row, never crashes.
alter table public.notifications
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check
    check (kind in (
      'new_order',      -- vendor: a customer placed an order (0021)
      'system',         -- anyone: a catch-all notice
      'order_update',   -- customer: their order changed status
      'job_available',  -- rider: a delivery is on the board to claim
      'payout',         -- rider: a payout was paid
      'account',        -- rider: their partner account was activated/deactivated
      'settlement'      -- vendor: a weekly settlement was paid
    ));

-- One index per recipient so each app's "my inbox, newest first" is a range
-- scan, matching the restaurant one 0021 already made.
create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc)
  where user_id is not null;

create index if not exists notifications_partner_idx
  on public.notifications (partner_email, created_at desc)
  where partner_email is not null;

-- ---------------------------------------------------------------------------
-- Who may read what.
-- ---------------------------------------------------------------------------
-- The vendor policy from 0021 stays. Two more, one per new audience, each the
-- same shape: you read the rows addressed to the identity you signed in as. A
-- customer is `auth.uid()`, a rider is `delivery_partner_email()` — the very
-- functions their other reads already lean on, so "my notifications" means
-- exactly what "my orders" and "my deliveries" already mean.
drop policy if exists "customers read their own notifications" on public.notifications;
create policy "customers read their own notifications"
  on public.notifications for select to authenticated
  using (audience = 'customer' and user_id = auth.uid()::text);

drop policy if exists "riders read their own notifications" on public.notifications;
create policy "riders read their own notifications"
  on public.notifications for select to authenticated
  using (audience = 'rider' and partner_email = public.delivery_partner_email());

-- ---------------------------------------------------------------------------
-- Marking read, now for any caller.
-- ---------------------------------------------------------------------------
-- 0021's two RPCs were scoped to the restaurant. Rewritten to scope to whoever
-- the caller is: a row is theirs if it is addressed to their restaurant, their
-- user id, or their rider email. A caller is only ever one of those three (a
-- customer is not a rider), and the two identity functions return null for the
-- audiences a caller does not belong to, so the OR collapses to the single
-- clause that applies. Still `read_at` and nothing else — the reason 0021 gave
-- (RLS picks rows, not columns) has not changed.
create or replace function public.mark_notification_read(p_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications
     set read_at = now()
   where id = p_id
     and read_at is null
     and (
       restaurant_id = public.staff_restaurant_id()
       or user_id = auth.uid()::text
       or partner_email = public.delivery_partner_email()
     );
end;
$$;

grant execute on function public.mark_notification_read(bigint) to authenticated;

create or replace function public.mark_all_notifications_read()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications
     set read_at = now()
   where read_at is null
     and (
       restaurant_id = public.staff_restaurant_id()
       or user_id = auth.uid()::text
       or partner_email = public.delivery_partner_email()
     );
end;
$$;

grant execute on function public.mark_all_notifications_read() to authenticated;

-- ===========================================================================
-- The sources. Every trigger below is wrapped so it can never abort the write
-- it rides on — the lesson 0021 stated and this file keeps: the event is the
-- thing that matters, the notification is a courtesy on top of it.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Customer: your order changed.
-- ---------------------------------------------------------------------------
-- One row per customer-meaningful status. The internal steps are skipped:
-- 'placed' is the customer's own tap (they were just there), 'preparing' and
-- 'ready_for_pickup' are kitchen mechanics they do not need pinged for. What is
-- left is the five moments a customer wants to hear about, each in their words,
-- with the reason attached to the two that carry one.
create or replace function public.notify_customer_order_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_body  text;
begin
  if new.status = old.status then
    return new;
  end if;

  v_title := case new.status
    when 'accepted'         then 'Order confirmed'
    when 'out_for_delivery' then 'On the way'
    when 'delivered'        then 'Delivered'
    when 'rejected'         then 'Order declined'
    when 'cancelled'        then 'Order cancelled'
    else null
  end;

  -- A status we do not narrate to the customer (preparing, ready_for_pickup).
  if v_title is null then
    return new;
  end if;

  v_body := case new.status
    when 'accepted'         then new.restaurant_name || ' is preparing your order'
    when 'out_for_delivery' then 'Your order from ' || new.restaurant_name || ' is on its way'
    when 'delivered'        then 'Your order from ' || new.restaurant_name || ' has arrived'
    when 'rejected'         then coalesce(new.status_reason, 'The restaurant could not take this order')
    when 'cancelled'        then coalesce(new.status_reason, 'This order was cancelled')
  end;

  begin
    insert into public.notifications (audience, user_id, kind, title, body, order_id)
    values ('customer', new.user_id, 'order_update', v_title, v_body, new.id);
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists orders_notify_customer on public.orders;
create trigger orders_notify_customer
  after update of status on public.orders
  for each row execute function public.notify_customer_order_update();

-- ---------------------------------------------------------------------------
-- Rider: a delivery is on the board.
-- ---------------------------------------------------------------------------
-- Fired the moment an order first becomes claimable — when the kitchen moves it
-- into 'preparing', which is the earliest state `available_deliveries` (0025)
-- shows and the earliest a rider can head for the counter. One row per active
-- rider: the job belongs to whoever grabs it first, so everyone who could is
-- told. Deactivated riders are skipped — the same `is_active` filter the app
-- and every RPC already apply.
create or replace function public.notify_riders_job_available()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'preparing' and old.status is distinct from 'preparing'
     and new.delivery_lat is not null and new.delivery_lng is not null then
    begin
      insert into public.notifications (audience, partner_email, kind, title, body, order_id)
      select 'rider', p.email, 'job_available',
             'New delivery',
             'A delivery from ' || new.restaurant_name || ' is ready to claim',
             new.id
        from public.delivery_partners p
       where p.is_active;
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_notify_riders on public.orders;
create trigger orders_notify_riders
  after update of status on public.orders
  for each row execute function public.notify_riders_job_available();

-- ---------------------------------------------------------------------------
-- Rider: you have been paid.
-- ---------------------------------------------------------------------------
-- On a payout crossing into 'paid' (the admin marking a batch settled, 0045).
-- The amount is whole rupees, like everywhere.
create or replace function public.notify_rider_payout()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    begin
      insert into public.notifications (audience, partner_email, kind, title, body)
      values ('rider', new.partner_email, 'payout',
              'Payout sent',
              '₹' || new.amount || ' for ' ||
                to_char(new.period_start, 'DD Mon') || ' – ' ||
                to_char(new.period_end, 'DD Mon') || ' is on its way to your bank');
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists rider_payouts_notify on public.rider_payouts;
create trigger rider_payouts_notify
  after update of status on public.rider_payouts
  for each row execute function public.notify_rider_payout();

-- ---------------------------------------------------------------------------
-- Rider: your account was switched on or off.
-- ---------------------------------------------------------------------------
-- A deactivated rider is refused by every action (0040); telling them why beats
-- a screen that silently stops working. Fired only when `is_active` actually
-- flips, not on every edit to the row.
create or replace function public.notify_rider_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active is distinct from old.is_active then
    begin
      insert into public.notifications (audience, partner_email, kind, title, body)
      values ('rider', new.email, 'account',
              case when new.is_active then 'Account active' else 'Account paused' end,
              case when new.is_active
                   then 'You can now take deliveries on Zopiqnow'
                   else 'You have been paused and cannot take deliveries for now' end);
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists delivery_partners_notify on public.delivery_partners;
create trigger delivery_partners_notify
  after update of is_active on public.delivery_partners
  for each row execute function public.notify_rider_account();

-- ---------------------------------------------------------------------------
-- Vendor: your settlement was paid.
-- ---------------------------------------------------------------------------
-- The one important restaurant event 0021 could not carry yet. On a settlement
-- crossing into 'paid' (0017), the kitchen learns money moved without opening
-- the payments screen to check.
create or replace function public.notify_vendor_settlement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    begin
      insert into public.notifications (audience, restaurant_id, kind, title, body)
      values ('restaurant', new.restaurant_id, 'settlement',
              'Payment received',
              '₹' || new.net_payable || ' for ' ||
                to_char(new.period_start, 'DD Mon') || ' – ' ||
                to_char(new.period_end, 'DD Mon') || ' has been settled');
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists settlements_notify on public.settlements;
create trigger settlements_notify
  after update of status on public.settlements
  for each row execute function public.notify_vendor_settlement();

-- ===========================================================================
-- Push: the same widening, for the token table.
-- ===========================================================================
-- 0020's `device_tokens` was restaurant-shaped too. A push is just a
-- notification that reaches a dark screen, so the recipient model must match the
-- one above: an audience and the three possible owners. The sender (an Edge
-- Function, out of band) reads this as the service role and rings whichever
-- tokens belong to a new notification's recipient.
alter table public.device_tokens
  add column if not exists audience     text not null default 'restaurant',
  add column if not exists user_id      text,
  add column if not exists partner_email text;

alter table public.device_tokens
  alter column restaurant_id drop not null;

alter table public.device_tokens
  drop constraint if exists device_tokens_audience_check,
  drop constraint if exists device_tokens_owner_present;

alter table public.device_tokens
  add constraint device_tokens_audience_check
    check (audience in ('restaurant', 'customer', 'rider')),
  add constraint device_tokens_owner_present
    check (
      case audience
        when 'restaurant' then restaurant_id is not null
        when 'customer'   then user_id is not null
        when 'rider'      then partner_email is not null
      end
    );

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id) where user_id is not null;

create index if not exists device_tokens_partner_idx
  on public.device_tokens (partner_email) where partner_email is not null;

-- register: this device, for whoever is signed in.
-- ---------------------------------------------------------------------------
-- Rewritten to detect the caller's audience the same way the read policies do —
-- restaurant first, then rider, then a plain signed-in customer — and stamp the
-- token accordingly. A token is unique per install (still the primary key), so a
-- device that re-registers, or that a person signs into as a different identity,
-- re-points its single row rather than growing a second. The old two-argument
-- signature is preserved so the vendor app calls it unchanged.
create or replace function public.register_device_token(
  p_token    text,
  p_platform text default 'android'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_rider      text;
  v_user       text;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return;
  end if;

  v_restaurant := public.staff_restaurant_id();
  v_rider      := public.delivery_partner_email();
  v_user       := auth.uid()::text;

  if v_restaurant is not null then
    insert into public.device_tokens (token, audience, restaurant_id, platform, updated_at)
    values (p_token, 'restaurant', v_restaurant, coalesce(p_platform, 'android'), now())
    on conflict (token) do update
      set audience = 'restaurant', restaurant_id = excluded.restaurant_id,
          user_id = null, partner_email = null,
          platform = excluded.platform, updated_at = now();
  elsif v_rider is not null then
    insert into public.device_tokens (token, audience, partner_email, platform, updated_at)
    values (p_token, 'rider', v_rider, coalesce(p_platform, 'android'), now())
    on conflict (token) do update
      set audience = 'rider', partner_email = excluded.partner_email,
          restaurant_id = null, user_id = null,
          platform = excluded.platform, updated_at = now();
  elsif v_user is not null then
    insert into public.device_tokens (token, audience, user_id, platform, updated_at)
    values (p_token, 'customer', v_user, coalesce(p_platform, 'android'), now())
    on conflict (token) do update
      set audience = 'customer', user_id = excluded.user_id,
          restaurant_id = null, partner_email = null,
          platform = excluded.platform, updated_at = now();
  else
    raise exception 'Please sign in before registering for notifications.'
      using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.register_device_token(text, text) to authenticated;
