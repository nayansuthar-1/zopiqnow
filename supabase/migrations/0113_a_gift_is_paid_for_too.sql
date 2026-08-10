-- ---------------------------------------------------------------------------
-- 0113 — a gift is paid for too. (B4, the gap the 2026-08-09 sweep named)
-- ---------------------------------------------------------------------------
-- 0085 made a food order prove its payment. Gifts were never brought under it,
-- and ZOMATO_PARITY.md has said so in bold since the sweep found it:
--
--   > `orders_require_verified_payment` is a trigger on `orders`; `gift_orders`
--   > has exactly one trigger and it is the audit one. `place_gift_order`
--   > requires a non-empty `p_payment_id` and takes it entirely on trust — it is
--   > never checked against `payment_intents` or against Razorpay.
--
-- Read off the live database on 2026-08-10 and still true: one trigger on
-- `gift_orders`, `gift_orders_audit_status`. So the one statement that arms the
-- food path —
--
--     update public.payment_settings set require_verified_payment = true;
--
-- — would have left the gift path exactly as open as it is today: a signed-in
-- customer typing `pay_anything` into `p_payment_id` and being sent a parcel.
-- This is the difference between *charging the right amount*, which 0112 fixed,
-- and *proving the amount was charged*, which is this one.
--
-- ## Why the same flag and not a second one
--
-- Because the failure this closes is a gap between two switches, not a missing
-- switch. Two booleans is two things to remember on the day the keys land, and
-- the one that gets forgotten is the one nobody is looking at. `payment_settings`
-- stays one row and one boolean, and the statement above now arms both paths at
-- once — which is what "armed with the rest rather than discovered afterwards"
-- was asking for.
--
-- ## Why the same table and not a `gift_payment_intents`
--
-- Because one payment must not buy both a dinner and a gift, and the only thing
-- that can enforce that is a single `status = 'consumed'` transition on a single
-- row. Two tables would be two ledgers with the same Razorpay payment id in
-- both, each satisfied, neither wrong on its own. `payment_intents` learns about
-- `gift_orders` instead — the schema question the parity note said this was.
--
-- ## Why a second column and not a reused `order_id`
--
-- `payment_intents.order_id` is read as `orders.id` by everyone who touches it,
-- and a `ZPG-…` sitting in it would join to nothing while looking like it should
-- — the quietest kind of wrong. The check constraint says the rest: an intent is
-- spent on one thing or the other, never both.
--
-- ## No `payment_method` branch, deliberately
--
-- 0085 skips non-UPI orders because `orders.payment_method` has more than one
-- legal value. `gift_orders.payment_method` is pinned to `'upi'` by a check
-- constraint (0096, following 0084 — nothing new is paid in cash), so the branch
-- would be dead code today. Leaving it out is also the safe direction: if a
-- future migration widens that constraint, the gate applies to the new method
-- until somebody decides otherwise, rather than silently exempting it.
--
-- Reversing this is dropping the trigger. The column is inert without it.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. What a gift intent is spent on.
-- ---------------------------------------------------------------------------
alter table public.payment_intents
  add column if not exists gift_order_id text;

comment on column public.payment_intents.gift_order_id is
  'Set when a gift order consumes this intent, as order_id is for a food order. Exactly one of the two is ever non-null.';

-- Not a foreign key, for 0085's reason about `order_id`: the trigger writes it
-- from inside the `gift_orders` insert that creates the row, so the referent
-- does not exist yet at the moment of writing.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.payment_intents'::regclass
       and conname  = 'payment_intents_one_order_check'
  ) then
    alter table public.payment_intents
      add constraint payment_intents_one_order_check
      check (order_id is null or gift_order_id is null);
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. The gate, in the same shape as 0085's.
-- ---------------------------------------------------------------------------
-- Deliberately a near-copy rather than a shared helper. The two differ in what
-- they lock, what they write back, and which column names the order — factoring
-- that into one function parameterised by table name means dynamic SQL inside a
-- `security definer` trigger on the money path, which is a worse trade than
-- forty duplicated lines that each read straight through.
create or replace function public.gift_orders_require_verified_payment()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_required boolean;
  v_intent   public.payment_intents%rowtype;
begin
  select require_verified_payment into v_required
    from public.payment_settings limit 1;

  if not coalesce(v_required, false) then
    return new;
  end if;

  select * into v_intent
    from public.payment_intents
   where razorpay_payment_id = new.payment_id
   for update;

  -- One sentence for every refusal, as 0085 has. The customer can do nothing
  -- differently in any of these cases, and telling an attacker which of "no such
  -- payment" and "already spent" they hit is telling them how far they got. The
  -- detail goes to the log.
  if not found then
    raise warning 'gift payment gate: no intent for payment_id %', new.payment_id;
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  if v_intent.status <> 'verified' then
    raise warning 'gift payment gate: intent % is %, not verified', v_intent.id, v_intent.status;
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  if v_intent.user_id is distinct from new.user_id then
    raise warning 'gift payment gate: intent % belongs to another customer', v_intent.id;
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  -- `>=`, not `=`, for 0085's reason: the gateway is asked for the quote
  -- (0112) and `place_gift_order` reprices the bag at insert. A price edited
  -- between the two can leave the customer a rupee ahead, which is a refund and
  -- not a reason to refuse them their parcel. A rupee short is the whole point.
  if v_intent.amount < new.total then
    raise warning 'gift payment gate: intent % paid % for a bag of %',
      v_intent.id, v_intent.amount, new.total;
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  -- Spent, in the same ledger a food order spends from. This is what stops one
  -- payment buying a dinner *and* a gift.
  update public.payment_intents
     set status = 'consumed', consumed_at = now(), gift_order_id = new.id
   where id = v_intent.id;

  return new;
end;
$$;

comment on function public.gift_orders_require_verified_payment() is
  'B4: a gift order must name a verified, unconsumed payment intent. Inert until payment_settings.require_verified_payment — the same flag that arms the food gate.';

-- 0093's rule: a trigger body is nobody's to call directly.
revoke all on function public.gift_orders_require_verified_payment()
  from public, anon, authenticated;

drop trigger if exists gift_orders_require_verified_payment on public.gift_orders;

create trigger gift_orders_require_verified_payment
  before insert on public.gift_orders
  for each row
  execute function public.gift_orders_require_verified_payment();
