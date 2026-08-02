-- ---------------------------------------------------------------------------
-- 0071 — the order book gets an index. (Audit DAT-001)
-- ---------------------------------------------------------------------------
-- `orders` has carried four indexes since 0003: the primary key, `orders_user_idx`
-- for the customer's own history, and two narrow partial indexes for the accept
-- sweeper and the settlement rollup. **Nothing has ever indexed `restaurant_id`**,
-- and four of the busiest paths in the platform filter on exactly that:
--
--   * the vendor's live queue      (`.stream().eq('restaurant_id', …)`)
--   * the vendor's history window  (restaurant + status + a date range)
--   * the vendor's payments screen
--   * the admin console's all-orders page (0069)
--
-- Every one of those is a sequential scan of the whole order book, run on every
-- screen open, by every restaurant on the platform. It costs nothing today and
-- it is the first thing that stops working: at 10,000 orders a day the table
-- passes three and a half million rows inside a year, and a vendor tablet's
-- startup goes from milliseconds to seconds while the concurrent scans push
-- everything else out of shared buffers.
--
-- Three indexes, each aimed at one of those readings. Nothing else changes —
-- no column, no function, no policy. An index is the rare fix that is purely
-- additive: the wrong one costs write throughput and disk, and is dropped
-- without ceremony.
--
-- **`concurrently`, and therefore no transaction.** `create index concurrently`
-- cannot run inside a transaction block, which is why this migration contains
-- nothing else — a file that mixes it with ordinary DDL will fail on the first
-- statement or run unwrapped, and neither is a thing to discover in production.
-- It takes two table passes instead of one and does not hold a write lock, so
-- the kitchen keeps taking orders while it builds. On an empty-ish table today
-- it is instantaneous either way; the habit is what matters when it isn't.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. One kitchen's book, newest first.
-- ---------------------------------------------------------------------------
-- The general-purpose one, and the one that does the most work. `created_at desc`
-- matches the direction History reads in and lets the date-range filter become a
-- range scan rather than a filter applied after the fact. The live queue orders
-- *ascending* — a queue is a queue — but Postgres reads a b-tree backwards at the
-- same cost, so one index serves both.
create index concurrently if not exists orders_restaurant_recent_idx
  on public.orders (restaurant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- B. The live queue, and only the live queue.
-- ---------------------------------------------------------------------------
-- A partial index over the four statuses that mean "somebody in a kitchen still
-- has to do something about this". It stays small forever — a busy restaurant
-- has a handful of live tickets and tens of thousands of finished ones — so it
-- lives in cache and the queue's initial fetch is an index-only lookup.
--
-- The status list is exactly `OrderStatus.isOpen` in the vendor app — five
-- statuses, and `out_for_delivery` is one of them. The kitchen is finished
-- cooking by then, but the ticket stays on the queue carrying the rider's
-- progress, so an index that dropped it would go unused precisely when a busy
-- restaurant has the most rows.
--
-- Written out rather than as `not in ('delivered','cancelled','rejected')`
-- because a partial index predicate is matched against the query's own
-- predicate: the planner only reaches for this index when a query asks the same
-- question in the same shape.
create index concurrently if not exists orders_restaurant_live_idx
  on public.orders (restaurant_id, created_at)
  where status in ('placed', 'accepted', 'preparing',
                   'ready_for_pickup', 'out_for_delivery');

-- ---------------------------------------------------------------------------
-- C. The console's view of the floor.
-- ---------------------------------------------------------------------------
-- `admin_all_orders` (0069) reads across every restaurant, newest first, and has
-- had nothing to read with. This is the only index here that is not
-- restaurant-scoped, and the only one an ops screen uses.
create index concurrently if not exists orders_created_idx
  on public.orders (created_at desc);
