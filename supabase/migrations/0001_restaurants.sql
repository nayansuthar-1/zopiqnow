-- Step 7, migration 1: the restaurant catalog.
--
-- The first table we move off a mock. It is deliberately the *read-only* half
-- of the app: no money, no identity, so a mistake here costs a wrong list, not
-- a wrong charge. Orders and coupons follow once this proves the seam holds.

-- Trigram matching for search: "birani" should still find "Biryani".
create extension if not exists pg_trgm;

create table if not exists public.restaurants (
  id             text primary key,
  name           text        not null,
  cuisines       text[]      not null default '{}',
  rating         numeric(2,1) not null check (rating >= 0 and rating <= 5),
  rating_count   integer     not null default 0 check (rating_count >= 0),
  eta_minutes    integer     not null check (eta_minutes > 0),
  price_for_two  integer     not null check (price_for_two > 0),
  is_veg         boolean     not null default false,
  image_url      text        not null,
  promo_text     text,

  -- Where the restaurant actually is. The feed's "2.1 km away" is derived from
  -- this and the customer's address once delivery zones land; until then the
  -- client has no origin to measure from, so `distance_km` below is carried as
  -- a plain column rather than pretending to be computed.
  latitude       double precision,
  longitude      double precision,
  distance_km    numeric(4,1) not null default 0,

  -- A delisted restaurant stops being served without deleting its orders.
  is_active      boolean     not null default true,
  created_at     timestamptz not null default now()
);

-- What search matches against: searching "biryani" must hit both the name and
-- the cuisine tag.
--
-- Maintained by a trigger rather than declared `generated always as` —
-- `array_to_string` is only STABLE (its output depends on type output
-- functions), and Postgres requires generation expressions to be IMMUTABLE.
-- The trigger fires on every write, so the column still cannot drift.
alter table public.restaurants
  add column if not exists search_text text not null default '';

create or replace function public.restaurants_set_search_text()
returns trigger
language plpgsql
as $$
begin
  new.search_text := new.name || ' ' || array_to_string(new.cuisines, ' ');
  return new;
end;
$$;

drop trigger if exists restaurants_search_text_sync on public.restaurants;
create trigger restaurants_search_text_sync
  before insert or update of name, cuisines on public.restaurants
  for each row execute function public.restaurants_set_search_text();

-- Backfill any rows written before the trigger existed.
update public.restaurants
  set search_text = name || ' ' || array_to_string(cuisines, ' ')
  where search_text = '';

create index if not exists restaurants_search_text_idx
  on public.restaurants using gin (search_text gin_trgm_ops);

-- The catalog is public: browsing does not require a phone number (that is the
-- product decision the auth guard already encodes). Writes are closed to
-- everyone — only the service role, from a server, may change the menu.
alter table public.restaurants enable row level security;

drop policy if exists "active restaurants are world-readable" on public.restaurants;
create policy "active restaurants are world-readable"
  on public.restaurants
  for select
  to anon, authenticated
  using (is_active);
