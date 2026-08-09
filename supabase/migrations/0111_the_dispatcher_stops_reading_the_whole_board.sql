-- ---------------------------------------------------------------------------
-- 0111 — the dispatcher stops reading the whole board.
-- ---------------------------------------------------------------------------
-- Written against a question rather than a bug: *what breaks when a thousand
-- people order at once?* Nothing here is failing today, and that is precisely
-- why it is worth writing down — both problems below are invisible at 52 orders
-- and structural at 100,000.
--
-- **Measured, not guessed.** `pg_stat_statements` on the live database says the
-- two largest consumers of database time on this project are not customers:
--
--     realtime WAL poller     212,123 calls   7.10 ms   25 min total
--     dispatch_deliveries()    54,912 calls   9.50 ms    8.7 min total
--     process_order_routes()   24,008 calls  11.62 ms    4.6 min total
--     expire_unaccepted_orders 21,312 calls   4.23 ms    1.5 min total
--
-- Three pg_cron jobs and a WAL poller, running flat out against an idle
-- pre-launch database. `place_order` itself is 95 ms mean / 229 ms max and is
-- not the problem.
--
-- ## 1. The dispatcher sorts the entire live board, every twenty seconds
--
-- `dispatch_deliveries()` (0056) drives off this query, and asks for 50 rows:
--
--     where status in ('preparing','ready_for_pickup')
--       and delivery_lat is not null and delivery_lng is not null
--       and not exists (a live delivery) and not exists (a live offer)
--     order by (status = 'ready_for_pickup') desc, created_at
--     limit 50
--
-- The plan read off the live database before this migration:
--
--     Limit
--       -> Sort
--            Sort Key: ((status = 'ready_for_pickup')) DESC, created_at
--            -> Bitmap Heap Scan on orders
--                 -> Bitmap Index Scan on orders_restaurant_live_idx
--
-- **The `limit 50` is applied after the sort, so it saves nothing.** Every
-- matching row is fetched and sorted before 50 are taken, and the index it
-- leans on covers *five* statuses rather than the two asked for, so the bitmap
-- is wider than the question. At 52 orders that is 9.5 ms. At a thousand
-- concurrent live orders it is a thousand-row sort every twenty seconds, on an
-- instance with **60 connections**, while every one of those orders' customers
-- is also holding a realtime subscription.
--
-- The index below matches the `order by` exactly — same expression, same
-- direction, same trailing key — and carries the two `is not null` tests in its
-- predicate, so the planner can walk it in order and stop at the 50th row. The
-- sort disappears rather than getting faster.
--
-- The two `not exists` clauses are deliberately *not* indexed here: they are
-- anti-joins against `deliveries_one_live_per_order` and
-- `delivery_offers_one_live_per_order`, both of which already exist and are
-- exactly the right shape. Once the driving scan is bounded to 50 candidates,
-- they are 50 index lookups.
--
-- ## 2. pg_cron has been keeping every run since the day it was switched on
--
-- `cron.job_run_details` is **100,255 rows and 17 MB** — larger than every
-- table in `public` combined, and growing by 7,194 rows a day (1,440 + 1,440 +
-- 4,314 from the three per-minute-or-faster jobs). pg_cron does not prune it;
-- the manual says so and leaves it to the operator, and nobody has been the
-- operator. It is not read by anything except a human debugging a failed job,
-- for which a week is generous.
--
-- Left alone this is 2.6 million rows a year of pure exhaust in the same
-- instance the orders live in.
--
-- **Both changes are additive.** No function is redefined, so 0051's overload
-- rule is not in play, and no table gains or loses a grant.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The dispatcher's driving index.
-- ---------------------------------------------------------------------------
-- The leading key is the *expression* the query sorts on, not `status`. Sorting
-- by `status` would put 'preparing' before 'ready_for_pickup' alphabetically —
-- the wrong way round — which is why 0056 wrote the boolean in the first place.
-- An index that does not restate it cannot serve the sort.
--
-- `concurrently` is deliberately NOT used: it cannot run inside a transaction,
-- and this project applies migrations as one. On a 52-row table the exclusive
-- lock is measured in milliseconds. Should this ever need re-creating against a
-- large `orders`, do it by hand and out of band.
create index if not exists orders_dispatchable_idx
  on public.orders (((status = 'ready_for_pickup')) desc, created_at)
  where status in ('preparing', 'ready_for_pickup')
    and delivery_lat is not null
    and delivery_lng is not null;

comment on index public.orders_dispatchable_idx is
  'Drives dispatch_deliveries() (0056). Matches its order by exactly — the '
  'boolean expression first, descending, then created_at — so the limit 50 '
  'stops an index scan instead of truncating a sort of the whole live board.';

-- ---------------------------------------------------------------------------
-- 2. pg_cron history, pruned.
-- ---------------------------------------------------------------------------
-- The backlog first. `end_time is null` is a run still in flight, and deleting
-- one would lose the record of a job that is currently executing, so it is
-- excluded rather than swept with the rest.
delete from cron.job_run_details
 where end_time < now() - interval '7 days';

-- Then the standing job, so this migration is not something somebody has to
-- remember to run again. 03:15 UTC is 08:45 IST — off the top of the hour, and
-- nowhere near the Monday 00:30/01:00 payout and settlement batches.
--
-- `cron.schedule` on an existing name updates it in place, so re-running this
-- migration does not create a second copy.
select cron.schedule(
  'prune-cron-history',
  '15 3 * * *',
  $prune$
    delete from cron.job_run_details
     where end_time < now() - interval '7 days'
  $prune$
);

-- ---------------------------------------------------------------------------
-- Verification — both must hold before this counts as applied.
-- ---------------------------------------------------------------------------
-- 1. The sort is gone from the dispatcher's plan. Expect an `Index Scan using
--    orders_dispatchable_idx` and NO `Sort` node:
--
--      explain (costs off)
--      select ord.id from public.orders ord
--       where ord.status in ('preparing','ready_for_pickup')
--         and ord.delivery_lat is not null and ord.delivery_lng is not null
--       order by (ord.status = 'ready_for_pickup') desc, ord.created_at
--       limit 50;
--
--    **What actually happens today, checked in a rolled-back transaction:** the
--    planner picks a *bitmap* index scan on this index and keeps the Sort. That
--    is correct on 52 rows — a bitmap scan never returns rows in order, and
--    sorting 52 of them is cheaper than the random heap I/O an ordered walk
--    costs. It is not a failed index. With `set enable_bitmapscan = off` the
--    plan collapses to exactly the intended shape and the Sort disappears:
--
--      Limit
--        ->  Index Scan using orders_dispatchable_idx on orders ord
--
--    which is the proof that the index matches the ordering. The planner will
--    choose it unaided once the table is big enough for the sort to cost more
--    than the walk — which is the only situation in which any of this matters.
--    Note it is `enable_bitmapscan`, not `enable_seqscan`, that has to come off
--    to see it: turning off seq scans alone still leaves the bitmap plan.
--
-- 2. The history is bounded:
--
--      select count(*) from cron.job_run_details;                  -- « 100,255
--      select jobname from cron.job where jobname = 'prune-cron-history';
--
-- And the two standing release checks (0087, 0089) must still return zero rows.
-- This migration creates no function and no table, so neither can have moved.
-- ---------------------------------------------------------------------------
