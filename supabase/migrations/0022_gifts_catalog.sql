-- Migration 22: the Gifts catalog — a second marketplace beside food.
--
-- Gifts are not food. They are handcrafted and curated things one person buys to
-- give another — pottery, candles, personalised mugs, plants, wall art — and the
-- sellers are not restaurants. So this is a *separate* seller model (`gift_shops`)
-- with its own products (`gift_items`), not a `category` bolted onto restaurants.
-- Keeping them apart is what lets the customer app carry a distinct Gifts tab, and
-- (later) a distinct gift cart, without a food query ever having to remember to
-- exclude a vase.
--
-- Read-only half, exactly like the restaurant catalog was (0001): no money, no
-- identity here. Vendor-side management (a gift seller adding its own items) is a
-- later task; today these tables are seeded and world-readable, nothing more.

-- A dedicated gift seller. Deliberately leaner than `restaurants`: no ETA, no
-- price-for-two, no veg flag — none of those mean anything for a gift shop.
create table if not exists public.gift_shops (
  id            text primary key,
  name          text        not null,

  -- One-line shop pitch shown under the name ("Handcrafted homeware & decor").
  tagline       text        not null default '',
  description   text        not null default '',

  -- Empty when the seller never uploaded a cover. The customer app has a branded
  -- gradient fallback, the same one restaurants and dishes use.
  image_url     text        not null default '',

  -- Null when the shop has too few ratings to show one — "unrated" is not "rated
  -- zero", the same distinction menu_items draws.
  rating        numeric(2,1) check (rating >= 0 and rating <= 5),
  rating_count  integer     not null default 0 check (rating_count >= 0),

  -- A delisted shop stops being served without deleting anything it sold.
  is_active     boolean     not null default true,
  created_at    timestamptz not null default now()
);

-- A single giftable product.
create table if not exists public.gift_items (
  id            text primary key,
  shop_id       text        not null references public.gift_shops (id) on delete cascade,

  name          text        not null,
  description   text        not null default '',

  -- Whole rupees. Price authority stays server-side for the same reason it does
  -- for menu_items (0002): when a gift cart and gift orders land, the order
  -- service will recompute every line against this and ignore the client.
  price         integer     not null check (price > 0),

  image_url     text        not null default '',

  -- The shelf a product sits on ("Home Decor", "Candles & Fragrance",
  -- "Personalised"). Plain text, ordered by rank — the same shape menu_items uses
  -- for its sections, so the Gifts browse screen can group by it.
  category      text        not null,
  category_rank integer     not null default 0,
  item_rank     integer     not null default 0,

  -- A sold-out gift disappears from the storefront without deleting orders that
  -- reference it.
  is_available  boolean     not null default true,
  created_at    timestamptz not null default now()
);

create index if not exists gift_items_shop_idx
  on public.gift_items (shop_id, category_rank, item_rank);

-- Both catalogs are public: browsing gifts requires no phone number, exactly the
-- product decision the food catalog already encodes. Writes are closed to
-- everyone — only the service role, from a server, seeds or edits them today.
alter table public.gift_shops enable row level security;
alter table public.gift_items enable row level security;

drop policy if exists "active gift shops are world-readable" on public.gift_shops;
create policy "active gift shops are world-readable"
  on public.gift_shops
  for select
  to anon, authenticated
  using (is_active);

drop policy if exists "available gift items are world-readable" on public.gift_items;
create policy "available gift items are world-readable"
  on public.gift_items
  for select
  to anon, authenticated
  using (is_available);
