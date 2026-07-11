-- Step 7, migration 2: menus.
--
-- This is where price authority moves server-side. Today the cart totals what
-- the client says a dish costs; once orders land (migration 3), the order
-- service recomputes every line against `menu_items.price` and ignores whatever
-- the client claimed. That is only possible because the price lives here.

create table if not exists public.menu_items (
  id             text primary key,
  restaurant_id  text not null references public.restaurants (id) on delete cascade,

  name           text    not null,
  description    text    not null default '',
  price          integer not null check (price > 0),
  is_veg         boolean not null default false,
  is_bestseller  boolean not null default false,

  -- Null when the dish has too few ratings to show one. Not 0 — "unrated" and
  -- "rated zero" are different claims.
  rating         numeric(2,1) check (rating >= 0 and rating <= 5),

  -- Empty when the vendor never uploaded a photo. A real and common case, which
  -- is why the UI has a fallback and this column has a default rather than a
  -- not-null-with-a-placeholder lie.
  image_url      text    not null default '',

  -- The menu is a list of named sections in a deliberate order ("Recommended"
  -- first), and dishes within a section are ordered too. Both ranks are the
  -- vendor's merchandising decision, so they are data, not a sort on price.
  category       text    not null,
  category_rank  integer not null default 0,
  item_rank      integer not null default 0,

  -- A sold-out dish disappears from the menu without deleting the orders that
  -- reference it.
  is_available   boolean not null default true,
  created_at     timestamptz not null default now()
);

create index if not exists menu_items_restaurant_idx
  on public.menu_items (restaurant_id, category_rank, item_rank);

alter table public.menu_items enable row level security;

drop policy if exists "available menu items are world-readable" on public.menu_items;
create policy "available menu items are world-readable"
  on public.menu_items
  for select
  to anon, authenticated
  using (is_available);
