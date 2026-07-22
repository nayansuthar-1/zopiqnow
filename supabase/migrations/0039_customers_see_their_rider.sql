-- ---------------------------------------------------------------------------
-- 0039 — The customer sees who is bringing their order. (Phase 8b-3)
-- ---------------------------------------------------------------------------
-- 0025 gave the *kitchen* a name and a number for the rider carrying its order.
-- The person actually waiting for the food had none: a rider picked the bag up
-- and, on the tracking screen, nothing changed. This closes that.
--
-- Two select policies and nothing else. No new table, no new function, no new
-- order status — the delivery already exists, and this is only a third reader
-- of it. `orders` is untouched, as it has been throughout this phase.
--
-- Both are scoped to `state = 'picked_up'` — strictly the window in which the
-- order is out for delivery. Not `claimed`: a rider who has taken the job but
-- not yet reached the counter may still drop it, and a name that appears and
-- then changes is worse than one that arrives a few minutes later. Not
-- `delivered` either: the job is over, and a rider's personal phone number is
-- theirs again. (User decision, 2026-07-22.)

-- The delivery itself, to the customer whose order it is. Deliberately the same
-- shape as "staff read deliveries of their orders" — the only difference is
-- which column of `orders` answers "yours?", and the state window.
drop policy if exists "customers read the delivery of their order" on public.deliveries;
create policy "customers read the delivery of their order"
  on public.deliveries for select to authenticated
  using (
    deliveries.state = 'picked_up'
    and exists (
      select 1 from public.orders o
       where o.id = deliveries.order_id
         and o.user_id = auth.uid()::text
    )
  );

-- And the rider on it. `delivery_partners` is keyed by email, which is why this
-- cannot be a join the client writes itself: the customer may read the row, but
-- only by way of a delivery that is theirs and in flight. Every other rider's
-- name, number and email stay invisible, exactly as they are to the kitchen.
drop policy if exists "customers read the rider carrying their order" on public.delivery_partners;
create policy "customers read the rider carrying their order"
  on public.delivery_partners for select to authenticated
  using (
    exists (
      select 1
        from public.deliveries d
        join public.orders o on o.id = d.order_id
       where d.partner_email = delivery_partners.email
         and o.user_id = auth.uid()::text
         and d.state = 'picked_up'
    )
  );

-- No grants: `select` on both tables was already granted to `authenticated` in
-- 0025. A grant is who may ask; these policies are what they are told.
