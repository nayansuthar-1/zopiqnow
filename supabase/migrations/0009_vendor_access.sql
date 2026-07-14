-- Step 10, migration 9: the kitchen's side of an order.
--
-- Everything so far has had exactly one kind of authenticated caller: a customer,
-- who owns their orders and their addresses and nothing else. This introduces the
-- second kind — someone who works at a restaurant — and the whole migration is an
-- answer to one question: *what is a vendor allowed to touch?*
--
-- The answer, precisely:
--   * read the orders placed at their restaurant, and the lines in them;
--   * move an order's status forward, one step at a time, through an RPC;
--   * see and edit their own menu, including the rows a customer cannot see.
--
-- And what they are *not* allowed to touch, which matters more:
--   * any order at any other restaurant;
--   * any figure on an order. Not the subtotal, not the discount, not the total.
--     `place_order` priced it and nothing may reprice it — least of all the party
--     being paid.

-- ---------------------------------------------------------------------------
-- Who works where.
-- ---------------------------------------------------------------------------
-- Keyed by *email*, not by `auth.uid()`, and that is the whole design. Ops
-- onboards a restaurant — "the kitchen at Paradise Biryani is kitchen@paradise.in"
-- — days before anyone at that kitchen has ever opened the app and been issued a
-- uid. A table keyed by uid could only be filled in *after* the first sign-in,
-- which is exactly backwards: it would mean the first person to sign in with any
-- email at all is the one who gets to claim the restaurant.
--
-- So the grant is made to an address, and the address is what the vendor proves
-- they control by receiving an OTP at it. Self-service signup does not exist and
-- must not: a restaurant account is created by ops (PM_CHECKLIST §8), and until
-- an admin dashboard exists, that means a row inserted here by hand.
create table if not exists public.restaurant_staff (
  email          text primary key,
  restaurant_id  text not null references public.restaurants (id) on delete cascade,
  created_at     timestamptz not null default now(),

  -- Emails are case-insensitive in practice and the JWT carries whatever the user
  -- typed. Normalising on the way in means the lookup never has to guess.
  constraint restaurant_staff_email_is_lowercase check (email = lower(email))
);

create index if not exists restaurant_staff_restaurant_idx
  on public.restaurant_staff (restaurant_id);

-- The table is not readable by anyone through the API. It answers "which
-- restaurant do I work for", and the *function* below answers that — for the
-- caller, about themselves. A vendor has no business enumerating the staff of
-- other restaurants, and a customer has no business knowing this table exists.
alter table public.restaurant_staff enable row level security;

-- ---------------------------------------------------------------------------
-- The one question every policy below asks.
-- ---------------------------------------------------------------------------
-- `security definer`, so it can read `restaurant_staff` while the table itself
-- stays closed. `stable`, so Postgres evaluates it once per statement instead of
-- once per row — an RLS predicate that re-queries for every row of a scan is how
-- a policy becomes a performance bug.
--
-- Null for a customer, which is what makes every vendor policy below a no-op for
-- them: `restaurant_id = null` is not false, it is *unknown*, and a row is only
-- returned when the predicate is true. Customers see nothing through these.
create or replace function public.staff_restaurant_id() returns text
language sql
stable
security definer
set search_path = public
as $$
  select s.restaurant_id
    from public.restaurant_staff s
   where s.email = lower(auth.jwt() ->> 'email')
$$;

grant execute on function public.staff_restaurant_id() to authenticated;

-- ---------------------------------------------------------------------------
-- What a vendor can read.
-- ---------------------------------------------------------------------------
-- Orders at their restaurant. This *is* the queue, and Realtime rides the same
-- policy (0008), so a vendor's subscription delivers exactly the orders this
-- select would return and no others.
drop policy if exists "staff read their restaurant's orders" on public.orders;
create policy "staff read their restaurant's orders"
  on public.orders for select to authenticated
  using (restaurant_id = public.staff_restaurant_id());

drop policy if exists "staff read their restaurant's order items" on public.order_items;
create policy "staff read their restaurant's order items"
  on public.order_items for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = order_items.order_id
         and o.restaurant_id = public.staff_restaurant_id()
    )
  );

-- Their own restaurant row, *including when it is inactive*. The customer-facing
-- policy is `using (is_active)`, so a delisted vendor would otherwise be unable
-- to see the restaurant they are locked out of — which is the one moment they
-- most need the app to tell them something.
drop policy if exists "staff read their own restaurant" on public.restaurants;
create policy "staff read their own restaurant"
  on public.restaurants for select to authenticated
  using (id = public.staff_restaurant_id());

-- Their own menu, *including unavailable dishes*. Same shape of bug: the customer
-- policy is `using (is_available)`, and a vendor who cannot see a sold-out dish
-- can never switch it back on.
drop policy if exists "staff read their own menu" on public.menu_items;
create policy "staff read their own menu"
  on public.menu_items for select to authenticated
  using (restaurant_id = public.staff_restaurant_id());

grant select on public.orders to authenticated;
grant select on public.order_items to authenticated;

-- ---------------------------------------------------------------------------
-- What a vendor can write: a status, and only forwards.
-- ---------------------------------------------------------------------------
-- Not an `update` policy, and the reason is the same one that put `place_order`
-- behind a function: RLS can say *which rows* a caller may write, but not *which
-- columns*, and an `update` on `orders` that lets a vendor set `status` is one
-- typo away from letting them set `total`. A restaurant editing the price of an
-- order the customer has already agreed to is not a bug we want to be one
-- `using` clause away from.
--
-- So there is no update grant on `orders` at all. There is this, which takes an
-- id and a status and writes nothing else:
create or replace function public.set_order_status(
  p_order_id text,
  p_status   text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  text;
  v_current     text;
  v_allowed     text[];
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  -- Locked, because two tablets in one kitchen is the normal case, not the edge
  -- case. Without this, both can read 'placed' and both can write 'accepted' —
  -- harmless — but both can equally read 'preparing' and race to write different
  -- next states.
  select o.status into v_current
    from public.orders o
   where o.id = p_order_id
     and o.restaurant_id = v_restaurant
   for update;

  if not found then
    -- Not "no such order": an order at another restaurant is none of this
    -- vendor's business, including whether it exists.
    raise exception 'That order is not one of yours.' using errcode = 'P0001';
  end if;

  -- The kitchen may move an order to the next step, or call the whole thing off
  -- while it still can. It may not skip ahead — an order that was never cooked
  -- cannot be out for delivery — and it may not go back: a customer who has been
  -- told their food is on its way must not watch it return to the kitchen.
  v_allowed := case v_current
    when 'placed'           then array['accepted', 'cancelled']
    when 'accepted'         then array['preparing', 'cancelled']
    when 'preparing'        then array['out_for_delivery', 'cancelled']
    -- No cancelling once it is with the rider. The food has left the building;
    -- that is a refund conversation, not a status change.
    when 'out_for_delivery' then array['delivered']
    else array[]::text[]
  end;

  if not (p_status = any (v_allowed)) then
    raise exception 'An order that is % cannot become %.', v_current, p_status
      using errcode = 'P0001';
  end if;

  update public.orders set status = p_status where id = p_order_id;

  return p_status;
end;
$$;

grant execute on function public.set_order_status(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The kitchen we did not have, which we now do.
-- ---------------------------------------------------------------------------
-- 0008 scheduled a cron job to walk orders through the statuses, because nothing
-- else would. Something else does now, and leaving the job running would mean a
-- vendor and a cron job both writing `status` — the vendor pressing "Accept" on
-- an order the simulator had already sent out for delivery.
--
-- This is the deletion 0008 said it was written for.
select cron.unschedule('advance-open-orders')
 where exists (select 1 from cron.job where jobname = 'advance-open-orders');

drop function if exists public.advance_open_orders();
