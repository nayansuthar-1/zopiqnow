-- ---------------------------------------------------------------------------
-- 0104 — the queue still takes new orders. (Repairs 0103.)
-- ---------------------------------------------------------------------------
-- 0103 gave `order_route_jobs` a second kind of job and moved its primary key
-- from `(order_id)` to `(order_id, kind)`. It did not look at who else was
-- relying on the old one, and somebody was: 0046's `enqueue_order_route`, the
-- `after insert` trigger that asks for a route the moment an order is placed,
-- ends with
--
--     on conflict (order_id) do nothing
--
-- There is no longer a unique index on `order_id` alone, so that clause matches
-- nothing and Postgres raises *"there is no unique or exclusion constraint
-- matching the ON CONFLICT specification"*.
--
-- **And the raise would have been silent, which is the part worth writing down.**
-- 0046 wrapped that insert in `exception when others then null` on purpose — a
-- queue insert must never be the reason a customer's checkout fails — so the
-- failure mode of 0103 was not an error anybody would see. It was: every new
-- order from that moment on quietly gets no route job, therefore no `route_km`
-- and no `route_polyline`, therefore a map with no road on it, a straight-line
-- ETA, and a **rider paid from a haversine distance instead of the road**. The
-- exception handler that protects checkout is exactly what would have hidden it.
--
-- Found by reading the callers of the constraint that changed rather than by
-- anything failing, which is the only way this one was ever going to be found.
--
-- The fix is one clause. The insert now names the kind it is enqueuing, which
-- it should have said all along — `'quote'` was only ever implicit because it
-- was the sole kind there was.
create or replace function public.enqueue_order_route()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.delivery_lat is not null and new.delivery_lng is not null then
    begin
      insert into public.order_route_jobs (order_id, kind)
      values (new.id, 'quote')
      on conflict (order_id, kind) do nothing;
    exception when others then
      -- A queue insert must never be the reason a customer's order fails.
      null;
    end;
  end if;
  return new;
end;
$$;

revoke execute on function public.enqueue_order_route() from public;
