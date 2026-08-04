-- ---------------------------------------------------------------------------
-- 0094 — three photographs of a dinner
-- ---------------------------------------------------------------------------
-- An order now carries evidence of itself at three moments:
--
--   the kitchen, when the food is cooked      orders.cooked_photo_url
--   the kitchen, once the bag is sealed       orders.packed_photo_url
--   the doorstep, at the handover             orders.delivery_photo_url
--
-- All three are Cloudinary delivery URLs, uploaded straight from the device
-- through the unsigned preset the vendor app already uses for dish photos. The
-- database stores a string; it does not know what a photo is and never fetches
-- one.
--
-- ## The gate is deliberately in the apps, not here
--
-- The obvious thing to write below is `if cooked is null then raise`. It is not
-- written, on purpose, and this is the paragraph that stops someone adding it
-- later without meaning to.
--
-- A wall here means a kitchen whose phone has no signal cannot mark food ready,
-- and a rider standing at a dark doorstep cannot close a delivery they have
-- actually made. The order would sit in `preparing` with the food going cold on
-- the counter, and support would have no move — because the wall would refuse
-- them too. The cost of that failure is a lost dinner and an angry customer; the
-- cost of a missing photo is a weaker position in a dispute that may never come.
--
-- So the button is disabled in both apps until the upload returns a URL, which
-- is where the pressure belongs, and the transition itself still works. Support
-- can always move an order. If the compliance number turns out to be bad, the
-- raise goes in then, as its own migration, with the operations team warned.
--
-- ## Who reads them
--
-- The admin console, and nothing else. `admin_order_photos` is a separate
-- function rather than three more columns on `admin_all_orders` because support
-- opens one order at a time, and a list of fifty rows has no use for three URLs
-- each. The customer app is untouched: these are evidence, not a feature.
--
-- ## Overloads
--
-- Both functions gain arguments, so both old signatures are dropped by hand
-- first. A `create or replace` with a longer argument list does not replace
-- anything — it creates a *second* function, and which one runs then depends on
-- how many arguments the caller happens to send. That has bitten this schema
-- before (0051 §C).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The columns.
-- ---------------------------------------------------------------------------
-- Nullable, with no default and no backfill: every order placed before today
-- genuinely has no photograph, and inventing an empty string for them would make
-- "never photographed" and "photographed, badly" the same value.
alter table public.orders
  add column if not exists cooked_photo_url   text,
  add column if not exists packed_photo_url   text,
  add column if not exists delivery_photo_url text;

comment on column public.orders.cooked_photo_url is
  'Cloudinary URL, photographed by the kitchen as the food came off the pass. Null for orders placed before 0094, and for any the app let through.';
comment on column public.orders.packed_photo_url is
  'Cloudinary URL, photographed by the kitchen once the bag was sealed.';
comment on column public.orders.delivery_photo_url is
  'Cloudinary URL, photographed by the rider at the handover. Written only on a successful confirm_delivered — a wrong code records nothing.';

-- ---------------------------------------------------------------------------
-- 2. The kitchen's ladder, now carrying two photographs.
-- ---------------------------------------------------------------------------
-- 0051's function, unchanged except for the two new arguments and the two lines
-- that write them. The transition rules, the row lock, the prep stamp and the
-- delivery release are all kept verbatim — this is not the migration to rethink
-- any of them.
drop function if exists public.set_order_status(text, text, text, integer);

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
as $$
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

  return p_status;
end;
$$;

-- Born executable by PUBLIC, like every function (see 0087). Revoking from
-- `anon, authenticated` alone would leave the PUBLIC grant standing and the
-- function open to the world.
revoke all on function
  public.set_order_status(text, text, text, integer, text, text)
  from public, anon;
grant execute on function
  public.set_order_status(text, text, text, integer, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The doorstep, now carrying one.
-- ---------------------------------------------------------------------------
-- 0076's function, unchanged except for the argument and the one column added to
-- the `orders` update. Note where that update sits: *after* the code check. A
-- rider who types the wrong code five times has photographed a doorstep they
-- were never let into, and none of those attempts writes anything.
drop function if exists public.confirm_delivered(text, text);

create or replace function public.confirm_delivered(
  p_order_id text,
  p_otp      text,
  p_photo_url text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_status   text;
  v_code     text;
  v_attempts integer;
  v_method   text;
  v_total    integer;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  select o.status, o.payment_method, o.total
    into v_status, v_method, v_total
    from public.deliveries d
    join public.orders o on o.id = d.order_id
   where d.order_id = p_order_id
     and d.partner_email = v_rider
     and d.state = 'arrived_at_customer'
   for update of d;

  if not found then
    raise exception
      'Tap "I''ve arrived" at the customer before completing the delivery.'
      using errcode = 'P0001';
  end if;

  -- 0041's check, kept: an order that is not out for delivery cannot arrive.
  if v_status <> 'out_for_delivery' then
    raise exception 'That order is %, so it can''t be marked delivered.', v_status
      using errcode = 'P0001';
  end if;

  select delivery_code, delivery_attempts into v_code, v_attempts
    from public.delivery_codes
   where order_id = p_order_id
   for update;

  if not found then
    raise exception 'That order has no delivery code.' using errcode = 'P0001';
  end if;

  if v_attempts >= 5 then
    return 'locked';
  end if;

  if p_otp is distinct from v_code then
    update public.delivery_codes
       set delivery_attempts = delivery_attempts + 1, updated_at = now()
     where order_id = p_order_id;

    return case when v_attempts + 1 >= 5 then 'locked' else 'wrong_code' end;
  end if;

  update public.deliveries
     set state = 'delivered', delivered_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'arrived_at_customer';

  update public.orders
     set status = 'delivered',
         delivery_photo_url = coalesce(
           nullif(trim(coalesce(p_photo_url, '')), ''),
           delivery_photo_url
         )
   where id = p_order_id;

  -- The order total, not the subtotal and not the rider's fee: what the
  -- customer was asked to pay is what the customer handed over. The rider's own
  -- pay for the run is settled weekly and separately, and netting the two here
  -- would be a rider paying themselves out of somebody's dinner money.
  if v_method = 'cod' then
    insert into public.rider_cash_ledger
      (partner_email, kind, amount, order_id, recorded_by)
    values
      (v_rider, 'collected', v_total, p_order_id, 'delivery')
    on conflict (order_id) where kind = 'collected' do nothing;
  end if;

  return 'ok';
end;
$$;

revoke all on function public.confirm_delivered(text, text, text)
  from public, anon;
grant execute on function public.confirm_delivered(text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. What support can see.
-- ---------------------------------------------------------------------------
-- One order at a time, because that is how a complaint arrives. Returns the row
-- even when all three are null — "this order has no photographs" is an answer
-- support needs, and an empty result would look like a lookup failure.
create or replace function public.admin_order_photos(p_order_id text)
returns table (
  order_id           text,
  status             text,
  cooked_photo_url   text,
  packed_photo_url   text,
  delivery_photo_url text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
  select o.id, o.status,
         o.cooked_photo_url, o.packed_photo_url, o.delivery_photo_url
    from public.orders o
   where o.id = p_order_id;
end;
$$;

revoke all on function public.admin_order_photos(text) from public, anon;
grant execute on function public.admin_order_photos(text) to authenticated;
