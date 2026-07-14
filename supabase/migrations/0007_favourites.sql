-- Step 7, migration 7: favourites — the last dead tap on the Account tab.
--
-- A join table, and deliberately nothing more. A favourite is a *fact that a
-- user liked a restaurant*: it has no state, no ordering the customer chose, and
-- nothing to update. So the row is the whole record, the pair is the key, and
-- there is no `update` policy below because there is nothing an update could
-- mean.
--
-- Same shape as `addresses` (0006), and the same reasoning: the client may write
-- this because nothing here costs anything. `place_order` owns writes where money
-- is decided; a heart is not money.

create table if not exists public.favourites (
  user_id       uuid not null references auth.users (id) on delete cascade,
  restaurant_id text not null references public.restaurants (id) on delete cascade,
  created_at    timestamptz not null default now(),

  -- The composite key *is* the de-duplication. Tapping the heart twice in a
  -- flaky-network second must not save two favourites, and a client that retries
  -- an insert it never saw succeed must not be punished for it — with this key
  -- the retry is a conflict, not a duplicate, and `on conflict do nothing` makes
  -- saving a favourite idempotent.
  primary key (user_id, restaurant_id)
);

-- "My favourites, newest first" is the only query this table serves.
create index if not exists favourites_user_idx
  on public.favourites (user_id, created_at desc);

alter table public.favourites enable row level security;

drop policy if exists "customers read their own favourites" on public.favourites;
create policy "customers read their own favourites"
  on public.favourites for select to authenticated
  using (user_id = auth.uid());

-- `with check`: on an insert there is no existing row to test, and what must be
-- asserted is that the row *about to be written* is the caller's own. Without
-- it, a signed-in customer could favourite a restaurant on someone else's behalf.
drop policy if exists "customers add their own favourites" on public.favourites;
create policy "customers add their own favourites"
  on public.favourites for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "customers remove their own favourites" on public.favourites;
create policy "customers remove their own favourites"
  on public.favourites for delete to authenticated
  using (user_id = auth.uid());

-- No update policy, and no update grant: there is no such thing as editing a
-- favourite. You have one or you do not.
grant select, insert, delete on public.favourites to authenticated;
