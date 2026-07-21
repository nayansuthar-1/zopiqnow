-- Step 11, migration 27: a restaurant gains an id it did not have to be given,
-- and an address.
--
-- Two gaps, both of which only became visible once something other than a hand-
-- written seed file started creating restaurants.
--
-- The first: `restaurants.id` is a bare `text primary key` with no default. Every
-- row that has ever existed was seeded with an id ops chose ('r1'…'r8'), and that
-- was fine while a human wrote the insert. A console creating a restaurant has no
-- id to offer and must not invent one — 0010 made exactly this argument about
-- `menu_items.id` and moved the decision server-side. Same fix, same reason.
--
-- The second: the catalog has never known *where a restaurant is*. There is a
-- latitude and a longitude (0001, both nullable, both unset on every seeded row)
-- and a `distance_km` that is a typed-in number pretending to be computed. There
-- is no street, no city, no pincode, and no phone number for the kitchen. A rider
-- sent to collect an order has been navigating to a restaurant name.

-- ---------------------------------------------------------------------------
-- The database picks the id.
-- ---------------------------------------------------------------------------
-- The existing short ids stay exactly as they are. This changes what happens when
-- nobody supplies one, and nothing about the rows that already have theirs.
alter table public.restaurants
  alter column id set default gen_random_uuid()::text;

-- ---------------------------------------------------------------------------
-- Where it is, and who to call.
-- ---------------------------------------------------------------------------
-- All nullable, because the eight seeded restaurants have none of this and are
-- not going to be invented into having it. What makes these effectively required
-- is `admin_publish_restaurant` (0030), which refuses to put a restaurant in front
-- of customers until they are filled. That is the right place for the rule: a
-- draft is allowed to be incomplete, a live listing is not.
alter table public.restaurants
  add column if not exists owner_name   text,
  add column if not exists contact_phone text,
  add column if not exists address_line text,
  add column if not exists city         text,
  add column if not exists state        text,
  add column if not exists pincode      text;

-- Checked only when present — `null` passes, which is what lets a half-filled
-- draft exist at all. A check constraint is not null-hostile unless you make it so.
alter table public.restaurants
  drop constraint if exists restaurants_pincode_is_indian;
alter table public.restaurants
  add constraint restaurants_pincode_is_indian
  check (pincode is null or pincode ~ '^[1-9][0-9]{5}$');

alter table public.restaurants
  drop constraint if exists restaurants_contact_phone_is_indian_mobile;
alter table public.restaurants
  add constraint restaurants_contact_phone_is_indian_mobile
  check (contact_phone is null or contact_phone ~ '^[6-9][0-9]{9}$');

-- The customer app already selects `*` from this table and ignores what it does
-- not model, so these columns reach it as dead weight and nothing more. The
-- address becomes a rider's pickup destination in a later phase; today it exists
-- so that onboarding has somewhere to put what it collects.
