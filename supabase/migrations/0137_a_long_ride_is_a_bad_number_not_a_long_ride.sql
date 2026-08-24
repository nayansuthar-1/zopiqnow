-- A ride that long is a bad number, not a long ride.
--
-- BUGFIX_QUEUE P11. `rider_pay_quote` (0097) is `base_fee + round(km × per_km_fee)`
-- with nothing bounding `km`. `claim_delivery` freezes that number onto the
-- delivery, `run_rider_payout_batch` sums what is frozen, and the console pays
-- what it sums — so a single bad coordinate is an unbounded payout and nothing
-- between the map and the bank account ever disagrees with it. On 2026-08-12 the
-- worst quote on the platform was **4,387.5 km → ₹21,962**: three orders carried
-- a delivery point of `41.03, 28.98`, which is Istanbul, against a kitchen in
-- Rajasthan. An emulator default, saved as a real address, priced as a real ride.
--
-- **The live picture on 2026-08-24 is not the one the queue describes, and the
-- difference is the more interesting half.** Those orders have since been
-- deleted. `deliveries` now holds 15 rows whose worst pay is ₹45 over 4.00 km,
-- and the 24 surviving orders average 1.96 km. But `rider_payouts` **15** still
-- says 4 deliveries, ₹22,737 — and exactly one delivery worth ₹25 still points
-- at it. `deliveries_order_id_fkey` is `on delete cascade`, so deleting the
-- orders took the deliveries with them and left the aggregate standing. The
-- money survived; the evidence for it did not.
--
-- So this migration does three things: bounds the quote, stops a delivery being
-- erased out from under a payout that has already counted it, and reconciles the
-- one row where that already happened.
--
-- ---------------------------------------------------------------------------
-- A. The ceiling is a distance, not a rupee amount.
-- ---------------------------------------------------------------------------
--
-- Capping the *pay* at a fixed number of rupees looks simpler and is worse: the
-- console can already change `base_fee` and `per_km_fee`
-- (`admin_set_rider_pay_rates`), so a rupee cap silently turns into a distance
-- cap at whatever distance the current rate happens to make it. Raise the rate
-- to ₹20/km and a ₹175 ceiling starts biting at 8.75 km — quietly underpaying
-- real rides. A distance ceiling stays correct under every rate change, and it
-- states the actual belief plainly: no delivery in this operation is 30 km long,
-- and a number that says otherwise is a broken measurement, not a long ride.
--
-- **Why 30.** Measured off the live service areas rather than picked. The town
-- lock (0126) means a kitchen serves its own town, with Ranakpur sharing Sadri's
-- catalogue — so the longest legitimate ride is Sadri↔Ranakpur: 8.50 km centre to
-- centre plus both radii (6.00 + 5.00) = **19.50 km** of crow flight at the
-- geometric extreme. `route_km` is road distance, which runs roughly 1.4× crow
-- flight in this terrain, so ~27 km bounds the worst ride the current three-town
-- footprint can physically produce. 30 clears that, and refuses the 4,387 km
-- class by three orders of magnitude. The real maximum today is 4.00 km.
--
-- It lives on `rider_pay_rates` because it is a rate, and because a fourth town
-- is an `update`, not a release. `admin_set_rider_pay_rates` is deliberately
-- *not* widened to edit it here: adding a third argument creates an overload
-- rather than replacing the function, and a safety rail that only bites at 30 km
-- does not need a weekly knob. Changing it is one statement in psql until the
-- console earns the field.

alter table public.rider_pay_rates
  add column if not exists max_km numeric not null default 30;

alter table public.rider_pay_rates
  drop constraint if exists rider_pay_rates_max_km_positive;
alter table public.rider_pay_rates
  add constraint rider_pay_rates_max_km_positive check (max_km > 0);

comment on column public.rider_pay_rates.max_km is
  'Longest distance a single delivery is ever paid for. Not a business limit on '
  'how far a rider may ride — a refusal to believe a measurement above it. See '
  'migration 0137.';

-- ---------------------------------------------------------------------------
-- B. The quote clamps what it prices, and still reports what it measured.
-- ---------------------------------------------------------------------------
--
-- `ride_km` is returned unclamped on purpose. It is a measurement, and rewriting
-- a measurement so the arithmetic beside it reconciles is the worse lie — the
-- clamped case is exactly the one where somebody should see 4,387 km sitting
-- next to ₹175 and go looking for the coordinate. 0097's note that a rider must
-- be able to reproduce the fee from the distance printed next to it holds for
-- every ride under the ceiling, which is all of them.
--
-- Signature unchanged — same four columns, same one argument — so this replaces
-- 0097's function rather than overloading it, and every caller
-- (`offer_delivery`, `claim_delivery`, `available_deliveries`, and the two
-- boards) keeps binding to the same thing.

create or replace function public.rider_pay_quote(p_order_id text)
returns table (
  ride_km    numeric,
  pay_base   integer,
  pay_per_km numeric,
  rider_pay  integer
)
language sql
stable
set search_path = public
as $fn$
  select km.value,
         rt.base_fee,
         rt.per_km_fee,
         -- `least` after `coalesce`, not before: a null distance means the
         -- kitchen has no coordinates on file, which 0097 prices as the base fee
         -- and nothing more. `least(null, 30)` would be null and would take the
         -- whole fee down with it.
         rt.base_fee
           + round(least(coalesce(km.value, 0), rt.max_km) * rt.per_km_fee)::integer
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
    cross join public.rider_pay_rates rt
    cross join lateral (
      select round(
               coalesce(
                 o.route_km,
                 public.delivery_distance_km(r.latitude, r.longitude,
                                             o.delivery_lat, o.delivery_lng)
               ),
               2
             ) as value
    ) km
   where o.id = p_order_id
     and rt.id = 1;
$fn$;

-- 0089's rule, restated because `create or replace` is not the same act as
-- `create` and it is cheap to be sure: this database carries an
-- `alter default privileges` granting execute on new functions to
-- `authenticated` by name, so revoking PUBLIC alone leaves that standing. The
-- callers are all `security definer` and owned by this function's owner, so
-- nothing needs the grant. Verified with `has_function_privilege`, not by
-- reading this line back.
revoke execute on function public.rider_pay_quote(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- C. A delivery a payout has counted cannot be deleted.
-- ---------------------------------------------------------------------------
--
-- This is the mechanism that produced payout 15, and it is not the one the queue
-- suspected. `admin_delete_order` already refuses to delete an order with money
-- owed back to a customer — *"₹X is still owed back on Y. Pay or decline the
-- refund before deleting the order."* — and then deletes the delivery, which may
-- carry money owed to a **rider**, without asking. The same principle, missing on
-- the other side of the ledger.
--
-- The guard is a trigger rather than another check inside `admin_delete_order`
-- because the console is demonstrably not the only way rows leave this table:
-- `admin_order_deletions` holds 8 rows, the newest from 2026-08-08, while the
-- order count has fallen from 55 to 24. Most of those deletions went round the
-- function. A trigger catches the cascade, the console, a seed cleanup and a
-- hand-typed `delete` alike.
--
-- Deliberately narrow. A delivery with `payout_id is null` — the overwhelming
-- majority, including every cancelled one — still deletes freely; only the six
-- rows that a payout has already summed are held, and only until that payout is
-- dealt with. It fails loudly, in the same voice as the refund guard, rather
-- than adjusting the payout behind somebody's back: a payout quietly shrinking
-- because an order was tidied up is how the number stopped meaning anything in
-- the first place.

create or replace function public.deliveries_refuse_delete_when_paid_out()
returns trigger
language plpgsql
set search_path = public
as $fn$
declare
  v_status text;
begin
  select p.status into v_status
    from public.rider_payouts p where p.id = old.payout_id;

  raise exception
    'Delivery % (order %) is on rider payout % — %. Detach or settle the payout '
    'before deleting it, or the payout keeps the money and loses the evidence.',
    old.id, old.order_id, old.payout_id,
    case v_status when 'paid' then 'already paid' else 'awaiting payment' end
    using errcode = 'P0001';
end;
$fn$;

drop trigger if exists deliveries_no_delete_when_paid_out on public.deliveries;
create trigger deliveries_no_delete_when_paid_out
  before delete on public.deliveries
  for each row
  when (old.payout_id is not null)
  execute function public.deliveries_refuse_delete_when_paid_out();

-- ---------------------------------------------------------------------------
-- D. Reconcile the payout that already lost its evidence.
-- ---------------------------------------------------------------------------
--
-- Written as a reconciliation over every pending payout rather than an update to
-- row 15, because the honest statement is "a pending payout is worth the
-- deliveries that point at it" and that statement is checkable afterwards. Today
-- it moves exactly one row: **15**, from 4 deliveries / ₹22,737 to 1 / ₹25.
--
-- `pending` only. A `paid` payout that lost deliveries is a different problem —
-- money has left the bank and the row is the record of that — and rewriting it
-- to match what survived would falsify the bank line rather than correct it.
-- There are none today; if one ever appears it wants a human, not this.
--
-- `cash_withheld` is left exactly as it stands. It is discharged by a matching
-- `rider_cash_ledger` row (`run_rider_payout_batch` writes the pair), so
-- recomputing it here would put the ledger and the payout out of step and net
-- the same cash twice. `amount` is re-derived from the gross so
-- `payout_nets_the_cash` continues to hold, and `greatest(…, 0)` keeps
-- `rider_payouts_amount_check` satisfied in the case where the withheld cash now
-- exceeds a shrunken gross — the rider is then owed nothing this week and still
-- carries the balance, which is the truth.
--
-- Status is untouched, so `rider_payouts_audit_status` does not fire and no
-- admin is recorded as having done this. That is correct: it was a migration,
-- and this comment is its audit trail.

with actual as (
  select p.id,
         count(d.id)::integer                   as delivery_count,
         coalesce(sum(d.rider_pay), 0)::integer as gross_amount
    from public.rider_payouts p
    left join public.deliveries d on d.payout_id = p.id
   where p.status = 'pending'
   group by p.id
)
update public.rider_payouts p
   set delivery_count = a.delivery_count,
       gross_amount   = a.gross_amount,
       amount         = greatest(a.gross_amount - p.cash_withheld, 0)
  from actual a
 where p.id = a.id
   and (p.delivery_count is distinct from a.delivery_count
        or p.gross_amount is distinct from a.gross_amount);
