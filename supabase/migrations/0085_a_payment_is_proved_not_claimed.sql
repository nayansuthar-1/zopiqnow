-- ---------------------------------------------------------------------------
-- 0085 — a payment is proved, not claimed. (launch C2, audit PAY-001)
-- ---------------------------------------------------------------------------
-- **Today the server takes any string as proof of payment.** `place_order`
-- checks that `p_payment_id` is non-empty and nothing else, so a customer who
-- can reach the RPC — which is every signed-in customer — can invent
-- `pay_anything` and be fed. That was survivable while the only way to reach
-- checkout was a build with a mock gateway in it; it is not survivable on a
-- public track, and it is what audit PAY-001 names.
--
-- This is the server half of launch C2. Two new tables and one trigger:
--
--   * `payment_intents` — one row per attempt to pay. Written by the
--     `razorpay-order` function when it creates a Razorpay order, moved to
--     `verified` by `razorpay-verify` once Razorpay's HMAC signature checks out,
--     and moved to `consumed` here when an order finally uses it.
--   * `payment_settings` — one row, one boolean. The switch.
--   * `orders_require_verified_payment` — a `before insert` trigger that, when
--     the switch is on, refuses a UPI order whose `payment_id` is not a
--     verified, unconsumed intent belonging to the same customer for at least
--     the order's total.
--
-- **Why a switch rather than always-on.** There are no Razorpay keys yet. Until
-- there are, the app pays through a mock that cannot produce a signature, and
-- turning enforcement on today would simply stop the product taking orders —
-- the exact outage 0082 just fixed. So it ships **off**, changing nothing, and
-- the day the keys are configured it is flipped:
--
--     update public.payment_settings set require_verified_payment = true;
--
-- One statement, reversible, and visible to anyone who looks at the table. That
-- is what "a fabricated reference stops working the moment keys are configured"
-- means in practice.
--
-- **Why a trigger and not a line in `place_order`.** Same argument as 0084, and
-- it has only got stronger: the function is 400 lines, `create or replace` takes
-- a whole body, and the repo's copy has drifted from the database more than once
-- (0082). A trigger is the rule stated once, under every path that can create an
-- order, and it cannot drift. The two guards now sit side by side.
--
-- **The amount check is `>=`, not `=`, on purpose.** The gateway is asked to
-- charge a bill the *client* computed; `place_order` then reprices the cart in
-- Postgres and its number is the one that counts. Those can legitimately differ
-- by a rupee — a coupon revalidated, a price edited between screens. Refusing an
-- order because the customer paid a rupee too much would be absurd; refusing one
-- because they paid less than it costs is the whole point. Overpayment is a
-- refund, and refunds already have a ledger (0076, 0077).
--
-- Reversing this is dropping the trigger. The tables are inert without it.
-- ---------------------------------------------------------------------------

-- One row per attempt to pay. `amount` is in whole rupees, like every other
-- price in this schema — Razorpay's paise conversion belongs to the adapter that
-- talks to Razorpay, not to the books.
create table if not exists public.payment_intents (
  id                  bigserial primary key,
  user_id             text not null,
  razorpay_order_id   text not null unique,
  -- Null until the customer actually pays: Razorpay issues the payment id at
  -- capture, not at order creation.
  razorpay_payment_id text unique,
  amount              integer not null check (amount > 0),
  status              text not null default 'created'
                        check (status in ('created', 'verified', 'consumed')),
  created_at          timestamptz not null default now(),
  verified_at         timestamptz,
  consumed_at         timestamptz,
  -- Set when an order consumes this intent. Not a foreign key on purpose: the
  -- trigger writes it from inside the `orders` insert that creates the row, so
  -- the referent does not exist yet at the moment of writing.
  order_id            text
);

comment on table public.payment_intents is
  'Launch C2 / audit PAY-001: one row per payment attempt. created -> verified (signature checked) -> consumed (an order used it).';

create index if not exists payment_intents_user_idx
  on public.payment_intents (user_id, created_at desc);

-- The client never touches this table. Both functions that write it use the
-- service key, and the trigger below is security definer. New tables arrive
-- writable, so say otherwise out loud rather than relying on RLS alone.
alter table public.payment_intents enable row level security;
revoke all on public.payment_intents from anon, authenticated;
revoke all on sequence public.payment_intents_id_seq from anon, authenticated;

-- One row, forever. The `check (id)` with a boolean primary key is the smallest
-- honest way to say "there is exactly one of these".
create table if not exists public.payment_settings (
  id                       boolean primary key default true check (id),
  require_verified_payment boolean not null default false,
  updated_at               timestamptz not null default now()
);

comment on table public.payment_settings is
  'Launch C2: one row. Flip require_verified_payment on the day Razorpay keys are configured.';

insert into public.payment_settings (id) values (true) on conflict (id) do nothing;

alter table public.payment_settings enable row level security;
revoke all on public.payment_settings from anon, authenticated;

create or replace function public.orders_require_verified_payment()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_required boolean;
  v_intent   public.payment_intents%rowtype;
begin
  -- Cash orders cannot be created at all since 0084, and an order paid any
  -- other way is not this guard's business.
  if new.payment_method <> 'upi' then
    return new;
  end if;

  select require_verified_payment into v_required
    from public.payment_settings limit 1;

  if not coalesce(v_required, false) then
    return new;
  end if;

  select * into v_intent
    from public.payment_intents
   where razorpay_payment_id = new.payment_id
   for update;

  -- Every refusal below says the same thing to the customer on purpose. They can
  -- do nothing differently in any of these cases, and the distinction between
  -- "no such payment" and "that payment was already spent" is one an attacker
  -- would find far more useful than they would. The detail goes to the log.
  if not found then
    raise warning 'payment gate: no intent for payment_id %', new.payment_id;
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  if v_intent.status <> 'verified' then
    raise warning 'payment gate: intent % is %, not verified', v_intent.id, v_intent.status;
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  if v_intent.user_id is distinct from new.user_id then
    raise warning 'payment gate: intent % belongs to another customer', v_intent.id;
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  if v_intent.amount < new.total then
    raise warning 'payment gate: intent % paid % for an order of %',
      v_intent.id, v_intent.amount, new.total;
    raise exception 'We couldn''t confirm your payment.' using errcode = 'P0001';
  end if;

  -- Spent. The unique index on razorpay_payment_id plus this state change is
  -- what stops one payment buying two dinners.
  update public.payment_intents
     set status = 'consumed', consumed_at = now(), order_id = new.id
   where id = v_intent.id;

  return new;
end;
$$;

comment on function public.orders_require_verified_payment() is
  'Launch C2 / audit PAY-001: a UPI order must name a verified, unconsumed payment intent. Inert until payment_settings.require_verified_payment.';

drop trigger if exists orders_require_verified_payment on public.orders;

create trigger orders_require_verified_payment
  before insert on public.orders
  for each row
  execute function public.orders_require_verified_payment();
