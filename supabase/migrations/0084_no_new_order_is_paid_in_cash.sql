-- ---------------------------------------------------------------------------
-- 0084 — no new order is paid in cash. (launch C1)
-- ---------------------------------------------------------------------------
-- The launch is UPI-only. Checkout stopped offering cash on delivery in the
-- same commit as this migration, and this is the half that makes it true rather
-- than merely displayed: the app is one client of `place_order`, not the only
-- possible one, and a build with the old screen in it keeps working until it is
-- updated.
--
-- **What this does not do.** Cash orders that already exist stay exactly as they
-- are, and every screen that renders them keeps rendering them. The vendor and
-- rider apps still show "collect ₹460", the rider's cash-in-hand ledger from
-- BIZ-002 still balances, and the invoice still says "Paid by cash on delivery"
-- where that is what happened. This is a gate on *creation* and nothing else —
-- which is why it is a `before insert` trigger and not a check constraint. A
-- constraint, even `not valid`, is re-checked on every `update`, so the next
-- status change on any of the 1044 existing orders would fail.
--
-- **Why a trigger and not a line in `place_order`.** `place_order` is the only
-- thing that can insert an order today — the table has no insert policy, so
-- `authenticated` cannot reach it directly. But the function is 400 lines,
-- `create or replace` takes a whole body, and the repo's copy of it has drifted
-- from the database more than once (see 0082). Restating it to add one `if`
-- risks reverting something live to say something the app is not going to send
-- anyway. The trigger is four lines, sits under every path including a future
-- one, and cannot drift.
--
-- The message is written to be read by a customer, and raised as P0001, because
-- that is the only code the customer app surfaces verbatim — the whole lesson of
-- 0082. Nobody should ever see it; if somebody does, it should say something.
--
-- Reversing this is dropping the trigger. Nothing else here is one-way.
-- ---------------------------------------------------------------------------

create or replace function public.orders_reject_new_cash()
returns trigger
language plpgsql
as $$
begin
  if new.payment_method = 'cod' then
    raise exception 'Cash on delivery isn''t available. Please pay by UPI.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

comment on function public.orders_reject_new_cash() is
  'Launch C1: UPI-only. Refuses new cash orders; existing ones are untouched.';

drop trigger if exists orders_reject_new_cash on public.orders;

create trigger orders_reject_new_cash
  before insert on public.orders
  for each row
  execute function public.orders_reject_new_cash();
