-- Step 11, migration 26: the platform gets an admin.
--
-- Until now Zopiqnow has had exactly three kinds of authenticated caller: a
-- customer (owns their orders and addresses), someone who works at a restaurant
-- (`restaurant_staff`, 0009/0024), and a rider (`delivery_partners`, 0025). There
-- has never been anyone who can *create* a restaurant.
--
-- 0009 said why, and the reason still holds: a restaurant account is created by
-- ops, never by whoever happens to sign up first, "and until an admin dashboard
-- exists, that means a row inserted here by hand." This is that dashboard's half
-- of the bargain — the identity it authenticates as. Self-service onboarding is
-- still not being built, and must not be: the admin is the only party who can
-- bring a restaurant into existence.
--
-- The shape is the one every actor table in this schema already uses: keyed by
-- *email*, not by `auth.uid()`, because the grant is made before the person has
-- ever signed in and been issued a uid. What they prove, by receiving an OTP, is
-- that they control the address the grant was made to.

create table if not exists public.platform_admins (
  email      text primary key,
  name       text not null,
  created_at timestamptz not null default now(),

  -- Same normalisation as restaurant_staff and delivery_partners: the JWT carries
  -- whatever the user typed, so the lookup must never have to guess at case.
  constraint platform_admins_email_is_lowercase check (email = lower(email))
);

-- Closed to the API entirely, like `restaurant_staff`. The table answers "is the
-- caller an admin", and the function below answers that — for the caller, about
-- themselves. Nobody, admin included, enumerates it through PostgREST; the
-- console reads the roster through an RPC in a later migration, so that read is
-- a deliberate, audited surface rather than a policy someone widens by accident.
alter table public.platform_admins enable row level security;

-- ---------------------------------------------------------------------------
-- The question every admin RPC asks first.
-- ---------------------------------------------------------------------------
-- `security definer`, so it can read the closed table above. `stable`, so
-- Postgres evaluates it once per statement rather than once per row — the same
-- reason `staff_restaurant_id()` (0009) is stable.
--
-- Returns false, never null, for a customer or a vendor. `staff_restaurant_id()`
-- returns null deliberately, because it is used as an RLS predicate where
-- unknown-is-not-true does the work. This one is used in `if not ... then raise`,
-- where a null would make the guard *pass* on a caller who is not an admin. So it
-- coalesces, and the guard fails closed.
create or replace function public.is_admin() returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admins a
     where a.email = lower(auth.jwt() ->> 'email')
  )
$$;

grant execute on function public.is_admin() to authenticated;

-- The first admin. Every other one is added through the console by an admin who
-- is already here — which means this row is the root of that chain and cannot be
-- created from inside the app.
insert into public.platform_admins (email, name)
values ('manav@siteonlab.com', 'Manav')
on conflict (email) do nothing;
