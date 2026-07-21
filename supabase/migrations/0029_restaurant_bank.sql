-- Step 11, migration 29: somewhere to send the money.
--
-- 0017 built settlements. It groups a period's delivered orders, subtracts the
-- commission, and writes a `net_payable` — a rupee figure, per restaurant, that
-- the platform owes. It has never had a destination. The whole settlement pipeline
-- ends at a number on a screen, and the actual payment happens in somebody's
-- banking tab against details held somewhere that is not this database.
--
-- Separate table, same reason as the licence papers (0028): `restaurants` is
-- world-readable and selects `*`.

create table if not exists public.restaurant_bank_accounts (
  restaurant_id  text primary key
    references public.restaurants (id) on delete cascade,

  account_holder text,
  account_number text,
  ifsc           text,
  bank_name      text,

  -- Set by a human who has confirmed the account is real — a penny-drop, a
  -- cancelled cheque, a phone call. Nothing automated sets this today; it exists
  -- so "we have details" and "we have *checked* the details" stay separate claims,
  -- because paying the wrong account is not a mistake you undo.
  verified       boolean not null default false,

  updated_at     timestamptz not null default now(),

  -- Four letters, a mandatory 0, then six alphanumerics. RBI's format.
  constraint bank_ifsc_is_well_formed
    check (ifsc is null or ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  -- Indian account numbers run 9–18 digits depending on the bank, so the only
  -- honest check is the shape, not the length.
  constraint bank_account_number_is_digits
    check (account_number is null or account_number ~ '^[0-9]{9,18}$')
);

-- No policy, by the same argument as 0028 — and more forcefully. This is the
-- table that says where money goes. It is reachable only through
-- `admin_set_bank` / `admin_get_bank` (0030), behind `is_admin()`.
--
-- The account number is stored as typed. That is a deliberate limit rather than a
-- claim of safety: there is no tokenisation here and no encryption at rest beyond
-- what the database itself provides. What protects it is that nothing but a
-- security-definer function owned by us can read the row, and the console never
-- shows more than the last four digits back.
alter table public.restaurant_bank_accounts enable row level security;
