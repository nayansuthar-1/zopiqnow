-- ---------------------------------------------------------------------------
-- 0118 — the console owns the gift catalogue.
-- ---------------------------------------------------------------------------
-- `gift_shops` and `gift_items` have been read-only since 0022, by design: the
-- migration's own header says "seeded and world-readable, nothing more", and
-- 0096 restated the reasoning — a curated catalogue of a few dozen items does
-- not need a seller-facing app before there is a seller.
--
-- That was an argument against a **vendor** app, and it still holds. It was
-- never an argument against the *admin* console, and the gap it left is real:
-- every price, name and photo in the Gifts tab today can only be changed by
-- someone with a psql prompt. Fifteen products are live on alpha priced ₹999
-- each, in a shop called "Handmade Art Studio", because changing either needs a
-- migration or a hand-typed UPDATE against production.
--
-- So: full CRUD, admin-only, through this file. Nothing here grants a write to
-- a browser — every function is `security definer`, calls `assert_admin()`
-- first, and the tables keep their zero grants. Same shape as 0031/0068/0108
-- built for restaurants and menus, applied to the second catalogue.
--
-- ## What "every control" turned out to mean
--
--   shops    create, edit, delist, delete
--   items    create, edit, price, tax slab, availability, delete
--   photos   a gallery, not one image — `image_urls` has been there since 0023
--            and nothing has ever been able to write it
--   order    drag an item, move a section, rename a section, delete a section
--   fee      `gift_settings.delivery_fee`, which 0096 left at 0 and reachable
--            only by UPDATE
--
-- ## Three things the food side does that this deliberately does not
--
-- **Deleting a gift item is a real delete.** `menu_items` refuses when a dish
-- appears on a past order, because `order_items.menu_item_id` is a foreign key.
-- `gift_order_items.gift_item_id` is **not** one — 0096 chose that on purpose so
-- "a receipt has to survive the shop deleting the item", and copied every field
-- the line needs beside it. So there is nothing to protect here and no refusal
-- to write: the receipt is already independent.
--
-- **Deleting a gift shop can still be refused**, and by the database rather than
-- by us: `gift_orders.shop_id` is a plain reference with no `on delete` clause.
-- Postgres raises `foreign_key_violation`; caught below and restated, because
-- "violates foreign key constraint gift_orders_shop_id_fkey" is not a sentence
-- anybody can act on. Delisting is what that admin actually wants.
--
-- **Ids are slugs, not uuids.** `gift_items.id` is `text` with no default and
-- the seed filled it with `gs1-kamdhenu-cow`. `menu_items` defaults to a uuid;
-- copying that here would leave the catalogue half readable and half not, and
-- the readable half is the one somebody debugging a gift order is reading. New
-- rows get a slug of the name, prefixed by the shop, suffixed only on collision.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. A slug, and a free one.
-- ---------------------------------------------------------------------------
-- Lowercase, alphanumerics and single hyphens, trimmed. A name that survives
-- none of that (an emoji, a name in Devanagari) leaves an empty slug, so the
-- caller passes a fallback rather than getting a bare `-` or a primary-key
-- violation. `p_prefix` is the shop for an item and empty for a shop itself.
create or replace function public.gift_slug(
  p_text     text,
  p_prefix   text default '',
  p_fallback text default 'item'
)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_slug text;
begin
  v_slug := lower(trim(coalesce(p_text, '')));
  -- `unaccent` is an extension this database does not carry, so accented
  -- letters fall to the same bucket as everything else non-ascii: dropped.
  v_slug := regexp_replace(v_slug, '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug);
  -- A primary key is not the place for a 200-character product description
  -- somebody pasted into the name field.
  v_slug := left(v_slug, 48);
  v_slug := trim(both '-' from v_slug);

  if v_slug = '' then
    v_slug := p_fallback;
  end if;

  if coalesce(p_prefix, '') <> '' then
    v_slug := p_prefix || '-' || v_slug;
  end if;

  return v_slug;
end;
$$;

revoke execute on function public.gift_slug(text, text, text) from public, anon, authenticated;

comment on function public.gift_slug(text, text, text) is
  'A readable primary key from a name. Used by the admin gift RPCs; the seed''s ids follow the same shape.';

-- Which *picture* a Cloudinary delivery URL points at, ignoring how it is being
-- delivered. Everything from the version segment on is the asset; everything
-- before it is a transformation — a width, a quality, a crop.
--
--   …/upload/f_auto,q_auto,w_600,c_limit/v1784653811/zopiqnow/oj3d….jpg
--   …/upload/f_auto,q_auto,w_1200,c_limit/v1784653811/zopiqnow/oj3d….jpg
--                                        └──────────── both return this ────┘
--
-- Null for a URL with no version segment, which is every URL we did not put in
-- Cloudinary ourselves. Two nulls must not compare equal, so callers use
-- `is not distinct from` only where that is intended — here they do not.
create or replace function public.gift_asset_key(p_url text)
returns text
language sql
immutable
set search_path = public
as $$
  select substring(coalesce(p_url, '') from '/v[0-9]+/.*$')
$$;

revoke execute on function public.gift_asset_key(text) from public, anon, authenticated;

comment on function public.gift_asset_key(text) is
  'The asset half of a Cloudinary delivery URL — what two renditions of one photo share. Null when the URL is not one of ours.';

-- ---------------------------------------------------------------------------
-- B. Reading the catalogue, including what a customer cannot see.
-- ---------------------------------------------------------------------------
-- The world-readable policies are `is_active` on shops and `is_available` on
-- items, which hide exactly what an editor most needs: the delisted shop and the
-- sold-out product somebody has to switch back on. Both functions are definer
-- and bypass them.
--
-- `item_count` on the shop row is what turns "delete this shop" from a guess
-- into a decision — 0022's cascade takes every product with it.
create or replace function public.admin_gift_shops()
returns table (
  id           text,
  name         text,
  tagline      text,
  description  text,
  image_url    text,
  rating       numeric,
  rating_count integer,
  is_active    boolean,
  created_at   timestamptz,
  item_count   integer,
  order_count  integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select s.id, s.name, s.tagline, s.description, s.image_url,
           s.rating, s.rating_count, s.is_active, s.created_at,
           (select count(*)::integer from public.gift_items i where i.shop_id = s.id),
           -- Not decoration: this is the number that decides whether a delete
           -- will be refused, and showing it beside the button is cheaper than
           -- letting somebody find out by pressing it.
           (select count(*)::integer from public.gift_orders o where o.shop_id = s.id)
      from public.gift_shops s
     order by s.is_active desc, s.name;
end;
$$;

revoke execute on function public.admin_gift_shops() from public, anon;
grant execute on function public.admin_gift_shops() to authenticated;

create or replace function public.admin_gift_items(p_shop_id text)
returns table (
  id            text,
  shop_id       text,
  name          text,
  description   text,
  price         integer,
  image_url     text,
  image_urls    text[],
  category      text,
  category_rank integer,
  item_rank     integer,
  is_available  boolean,
  gst_rate_bps  integer,
  created_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select i.id, i.shop_id, i.name, i.description, i.price,
           i.image_url, i.image_urls, i.category, i.category_rank,
           i.item_rank, i.is_available, i.gst_rate_bps, i.created_at
      from public.gift_items i
     where i.shop_id = p_shop_id
     order by i.category_rank, i.item_rank, i.name;
end;
$$;

revoke execute on function public.admin_gift_items(text) from public, anon;
grant execute on function public.admin_gift_items(text) to authenticated;

-- ---------------------------------------------------------------------------
-- C. Writing a shop.
-- ---------------------------------------------------------------------------
-- One function for insert and update, keyed on whether an id came with the
-- payload — the same shape `admin_upsert_menu_item` uses, and for the same
-- reason: the fields are identical and two functions would drift.
--
-- `rating` and `rating_count` are **not writable here**, deliberately, and the
-- argument is 0108's about dish ratings one step further. Nothing on the
-- platform computes a gift shop's rating yet, and a number an admin types into
-- a rating is not a rating — it is fabricated social proof sitting exactly where
-- a customer reads other people's opinion. When gift reviews exist they write
-- these columns through a trigger, the way `reviews` does for restaurants
-- (0062). Until then the column stays null and the app shows "unrated", which
-- is honest.
create or replace function public.admin_upsert_gift_shop(p_shop jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id    text := nullif(trim(coalesce(p_shop ->> 'id', '')), '');
  v_name  text := trim(coalesce(p_shop ->> 'name', ''));
  v_slug  text;
  v_try   integer := 1;
begin
  perform public.assert_admin();

  if v_name = '' then
    raise exception 'The shop needs a name.' using errcode = 'P0001';
  end if;

  if v_id is null then
    -- `gs` is the seed's prefix and stays the fallback, so a shop named only in
    -- a script this slug cannot represent still lands as `gs`, `gs-2`, `gs-3`.
    v_slug := public.gift_slug(v_name, '', 'gs');
    v_id := v_slug;
    while exists (select 1 from public.gift_shops s where s.id = v_id) loop
      v_try := v_try + 1;
      v_id := v_slug || '-' || v_try;
    end loop;

    insert into public.gift_shops (
      id, name, tagline, description, image_url, is_active
    ) values (
      v_id, v_name,
      trim(coalesce(p_shop ->> 'tagline', '')),
      trim(coalesce(p_shop ->> 'description', '')),
      coalesce(p_shop ->> 'image_url', ''),
      coalesce((p_shop ->> 'is_active')::boolean, true)
    );

    return v_id;
  end if;

  update public.gift_shops set
    name        = v_name,
    tagline     = trim(coalesce(p_shop ->> 'tagline', '')),
    description = trim(coalesce(p_shop ->> 'description', '')),
    image_url   = coalesce(p_shop ->> 'image_url', ''),
    is_active   = coalesce((p_shop ->> 'is_active')::boolean, true)
  where id = v_id;

  if not found then
    raise exception 'No such gift shop.' using errcode = 'P0001';
  end if;

  return v_id;
end;
$$;

revoke execute on function public.admin_upsert_gift_shop(jsonb) from public, anon;
grant execute on function public.admin_upsert_gift_shop(jsonb) to authenticated;

create or replace function public.admin_delete_gift_shop(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  delete from public.gift_shops where id = p_id;

  if not found then
    raise exception 'No such gift shop.' using errcode = 'P0001';
  end if;

-- The refusal is the database's, restated. `gift_orders.shop_id` has no
-- `on delete` clause, so a shop somebody has bought from cannot be removed —
-- which is the right answer, because the order screen joins the shop for its
-- name. Delisting achieves what the admin wanted and keeps the receipts whole.
exception
  when foreign_key_violation then
    raise exception
      'This shop has orders against it, so it cannot be deleted — the receipts read its name. Switch it off instead and it disappears from the app.'
      using errcode = 'P0001';
end;
$$;

revoke execute on function public.admin_delete_gift_shop(text) from public, anon;
grant execute on function public.admin_delete_gift_shop(text) to authenticated;

-- ---------------------------------------------------------------------------
-- D. Writing an item.
-- ---------------------------------------------------------------------------
-- **`image_url` is not an independent field and is not treated as one.** 0023
-- set the convention — `image_url` is the card thumbnail and by convention it is
-- `image_urls[1]` — and then nothing was ever able to write the array, so the
-- convention has held only because the seed obeyed it. A console that offered
-- two free-text fields would let an admin set a card photo that appears nowhere
-- in the gallery it opens into, and nobody would find out until a customer
-- tapped it.
--
-- **But "the same photo" is not "the same URL", and the live rows prove it.**
-- The seeded catalogue stores one asset at two widths:
--
--   image_url      …/f_auto,q_auto,w_600,c_limit/v1784653811/zopiqnow/oj3d….jpg
--   image_urls[1]  …/f_auto,q_auto,w_1200,c_limit/v1784653811/zopiqnow/oj3d….jpg
--
-- That is deliberate and it is load-bearing: the seller's originals are ~8 MB at
-- 5712×4284, the grid draws fifteen of them at once, and the floor is an
-- Android 10 phone on mobile data. Deriving the thumbnail by *copying*
-- `image_urls[1]` would quietly double every card on the Gifts tab.
--
-- So the rule enforced is the real one — **the card must show the first gallery
-- photo** — and it is enforced on the *asset*, not the string. A caller may send
-- its own `image_url`; it is accepted only if it points at the same Cloudinary
-- asset as the first gallery entry, which is exactly what a narrower rendition
-- of it does. Anything else is ignored and the gallery entry is used.
--
-- An item with an empty gallery keeps an empty `image_url`, which the customer
-- app already handles with the branded gradient every catalogue falls back to.
create or replace function public.admin_upsert_gift_item(p_shop_id text, p_item jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id   text := nullif(trim(coalesce(p_item ->> 'id', '')), '');
  v_name      text := trim(coalesce(p_item ->> 'name', ''));
  v_category  text := trim(coalesce(p_item ->> 'category', ''));
  v_price     integer := coalesce(nullif(trim(coalesce(p_item ->> 'price', '')), '')::integer, 0);
  -- Not null with a default of 1800 (0096), so an omitted key is 18% — the
  -- commonest non-food slab and what every gift on the platform is charged.
  v_gst       integer := coalesce(
                           nullif(trim(coalesce(p_item ->> 'gst_rate_bps', '')), '')::integer,
                           1800);
  -- Absent, null and [] all arrive as an empty array. Blank strings inside it
  -- are dropped rather than stored: an empty entry in a gallery is a page in a
  -- swipeable PageView that renders nothing.
  --
  -- **`with ordinality` and an explicit `order by`, because this is a gallery.**
  -- `array_agg` has no defined order without one; it happens to come out in
  -- input order today, and the day it does not, the photos an admin arranged
  -- are silently shuffled and `image_urls[1]` becomes a different picture.
  v_urls      text[] := coalesce(
                          (select array_agg(t.u order by t.ord)
                             from jsonb_array_elements_text(
                                    case jsonb_typeof(p_item -> 'image_urls')
                                      when 'array' then p_item -> 'image_urls'
                                      else '[]'::jsonb
                                    end) with ordinality as t(u, ord)
                            where trim(coalesce(t.u, '')) <> ''),
                          '{}'::text[]);
  -- The caller's proposed thumbnail, honoured only if it is a rendition of the
  -- same picture as the first gallery entry. See the header.
  v_sent_thumb   text := trim(coalesce(p_item ->> 'image_url', ''));
  v_thumb        text;
  v_cat_rank     integer;
  v_item_rank    integer;
  v_old_category text;
  v_slug         text;
  v_try          integer := 1;
begin
  perform public.assert_admin();

  -- The thumbnail, decided before anything is written. A sent one wins only
  -- when `gift_asset_key` says it is the same picture as the gallery's first
  -- entry — which a `w_600` rendition of a `w_1200` gallery photo is, and a URL
  -- pointing at some other asset is not. Both keys null (neither is a
  -- Cloudinary URL) is not a match: `=` on nulls is null, deliberately, so an
  -- unrecognised pair falls through to the gallery entry rather than trusting a
  -- string we cannot check.
  v_thumb := case
               when v_urls[1] is null then ''
               when v_sent_thumb <> ''
                and public.gift_asset_key(v_sent_thumb)
                  = public.gift_asset_key(v_urls[1]) then v_sent_thumb
               else v_urls[1]
             end;

  if not exists (select 1 from public.gift_shops where id = p_shop_id) then
    raise exception 'No such gift shop.' using errcode = 'P0001';
  end if;
  if v_name = '' then
    raise exception 'The gift needs a name.' using errcode = 'P0001';
  end if;
  if v_category = '' then
    raise exception 'Every gift sits on a shelf. Pick one.' using errcode = 'P0001';
  end if;
  if v_price <= 0 then
    raise exception 'A gift has to cost more than zero.' using errcode = 'P0001';
  end if;
  -- The table's check is the whole 0–10000 range (0096). This is narrower on
  -- purpose: those five are the GST slabs that exist, and a rate typed as 15%
  -- would pass the constraint and produce an invoice no accountant can defend.
  if v_gst not in (0, 500, 1200, 1800, 2800) then
    raise exception 'GST has to be one of 0%%, 5%%, 12%%, 18%% or 28%%.' using errcode = 'P0001';
  end if;

  -- A shelf keeps the rank it already has; a new one joins the end. Same rule
  -- as the menu (0108), and the reason is the same: `category_rank` lives on
  -- every row and nothing in the database keeps two items in one shelf agreeing.
  select i.category_rank into v_cat_rank
    from public.gift_items i
   where i.shop_id = p_shop_id and i.category = v_category
   limit 1;
  if v_cat_rank is null then
    select coalesce(max(i.category_rank), -1) + 1 into v_cat_rank
      from public.gift_items i where i.shop_id = p_shop_id;
  end if;

  if v_item_id is null then
    select coalesce(max(i.item_rank), -1) + 1 into v_item_rank
      from public.gift_items i
     where i.shop_id = p_shop_id and i.category = v_category;

    v_slug := public.gift_slug(v_name, p_shop_id, 'gift');
    v_item_id := v_slug;
    while exists (select 1 from public.gift_items i where i.id = v_item_id) loop
      v_try := v_try + 1;
      v_item_id := v_slug || '-' || v_try;
    end loop;

    insert into public.gift_items (
      id, shop_id, name, description, price, image_url, image_urls,
      category, category_rank, item_rank, is_available, gst_rate_bps
    ) values (
      v_item_id, p_shop_id, v_name,
      trim(coalesce(p_item ->> 'description', '')),
      v_price, v_thumb, v_urls,
      v_category, v_cat_rank, v_item_rank,
      coalesce((p_item ->> 'is_available')::boolean, true),
      v_gst
    );

    return v_item_id;
  end if;

  -- Moving shelf has to move the rank with it. The old `item_rank` was the
  -- position of this item *within its old shelf*, and carrying it across means
  -- two items on the destination shelf claim the same slot — which sorts by
  -- whatever the planner picks and reads as a random reshuffle on the next
  -- load. An item that stays put keeps its position untouched.
  select i.category into v_old_category
    from public.gift_items i
   where i.id = v_item_id and i.shop_id = p_shop_id;

  if v_old_category is null then
    raise exception 'That gift is not in this shop.' using errcode = 'P0001';
  end if;

  if v_old_category is distinct from v_category then
    select coalesce(max(i.item_rank), -1) + 1 into v_item_rank
      from public.gift_items i
     where i.shop_id = p_shop_id and i.category = v_category;
  end if;

  update public.gift_items set
    name         = v_name,
    description  = trim(coalesce(p_item ->> 'description', '')),
    price        = v_price,
    image_url    = v_thumb,
    image_urls   = v_urls,
    category     = v_category,
    category_rank = v_cat_rank,
    item_rank    = coalesce(v_item_rank, item_rank),
    is_available = coalesce((p_item ->> 'is_available')::boolean, true),
    gst_rate_bps = v_gst
  where id = v_item_id and shop_id = p_shop_id;

  return v_item_id;
end;
$$;

revoke execute on function public.admin_upsert_gift_item(text, jsonb) from public, anon;
grant execute on function public.admin_upsert_gift_item(text, jsonb) to authenticated;

-- A real delete, and the header says why: `gift_order_items` copied every field
-- it needs and holds no reference back.
create or replace function public.admin_delete_gift_item(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  delete from public.gift_items where id = p_id;

  if not found then
    raise exception 'No such gift.' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_delete_gift_item(text) from public, anon;
grant execute on function public.admin_delete_gift_item(text) to authenticated;

-- The one-tap switch the list needs. `admin_upsert_gift_item` can do this too,
-- but only by resending every field — and a list row that has to round-trip a
-- gallery to mark something sold out is a list row that will eventually send a
-- stale one back.
create or replace function public.admin_set_gift_item_available(
  p_id        text,
  p_available boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  update public.gift_items
     set is_available = coalesce(p_available, true)
   where id = p_id;

  if not found then
    raise exception 'No such gift.' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_set_gift_item_available(text, boolean) from public, anon;
grant execute on function public.admin_set_gift_item_available(text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- E. Shelves, and the order things sit in.
-- ---------------------------------------------------------------------------
-- A shelf is not a row anywhere — it is the set of items sharing a `category`
-- string, exactly as a menu section is (0002). So the three operations a shelf
-- has all rewrite every row in it, and reordering sends the catalogue's whole
-- running order rather than the rows that moved. Sending only the moved rows is
-- what lets two ranks end up equal, and equal ranks sort by whatever the planner
-- felt like that afternoon.
create or replace function public.admin_reorder_gift_items(
  p_shop_id text,
  p_order   jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  update public.gift_items i set
    category      = e.category,
    category_rank = e.category_rank,
    item_rank     = e.item_rank
  from jsonb_to_recordset(p_order)
       as e(id text, category text, category_rank integer, item_rank integer)
  where i.id = e.id
    -- The shop is part of the predicate, not just the lookup: without it a
    -- payload naming somebody else's item would happily reorder it.
    and i.shop_id = p_shop_id;
end;
$$;

revoke execute on function public.admin_reorder_gift_items(text, jsonb) from public, anon;
grant execute on function public.admin_reorder_gift_items(text, jsonb) to authenticated;

create or replace function public.admin_rename_gift_category(
  p_shop_id text,
  p_from    text,
  p_to      text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_to   text := trim(coalesce(p_to, ''));
  v_rank integer;
begin
  perform public.assert_admin();

  if v_to = '' then
    raise exception 'A shelf needs a name.' using errcode = 'P0001';
  end if;
  if v_to = p_from then
    return;
  end if;

  -- Renaming onto a shelf that already exists is a merge, and it has to be an
  -- intentional one: the arriving items take the destination's rank, or the
  -- shop ends up with one shelf name carrying two different `category_rank`
  -- values and the app draws it twice.
  select i.category_rank into v_rank
    from public.gift_items i
   where i.shop_id = p_shop_id and i.category = v_to
   limit 1;

  update public.gift_items
     set category = v_to,
         category_rank = coalesce(v_rank, category_rank)
   where shop_id = p_shop_id and category = p_from;

  if not found then
    raise exception 'No shelf by that name in this shop.' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_rename_gift_category(text, text, text) from public, anon;
grant execute on function public.admin_rename_gift_category(text, text, text) to authenticated;

create or replace function public.admin_delete_gift_category(
  p_shop_id  text,
  p_category text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  perform public.assert_admin();

  delete from public.gift_items
   where shop_id = p_shop_id and category = p_category;

  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    raise exception 'No shelf by that name in this shop.' using errcode = 'P0001';
  end if;

  return v_deleted;
end;
$$;

revoke execute on function public.admin_delete_gift_category(text, text) from public, anon;
grant execute on function public.admin_delete_gift_category(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- F. The courier fee.
-- ---------------------------------------------------------------------------
-- 0096 built `gift_settings` as "one knob, so a courier fee never needs a
-- migration" and then left the knob with nothing attached to it — the table has
-- no grants and no function, so the only way to charge for delivery has been an
-- UPDATE typed against production. `gift_bag_quote` already reads it, so this is
-- the last wire.
create or replace function public.admin_gift_settings()
returns table (delivery_fee integer, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();
  return query select g.delivery_fee, g.updated_at from public.gift_settings g where g.id;
end;
$$;

revoke execute on function public.admin_gift_settings() from public, anon;
grant execute on function public.admin_gift_settings() to authenticated;

create or replace function public.admin_set_gift_delivery_fee(p_fee integer)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if p_fee is null or p_fee < 0 then
    raise exception 'A delivery fee cannot be negative.' using errcode = 'P0001';
  end if;
  -- Not a rule the table has. A four-figure courier fee on a ₹999 gift is a
  -- typo every time, and it would be charged to a real customer before anybody
  -- noticed — the quote reads this column with no ceiling of its own.
  if p_fee > 1000 then
    raise exception 'That is more than ₹1000 — if the courier really costs that, change it in SQL.'
      using errcode = 'P0001';
  end if;

  update public.gift_settings
     set delivery_fee = p_fee, updated_at = now()
   where id;

  return p_fee;
end;
$$;

revoke execute on function public.admin_set_gift_delivery_fee(integer) from public, anon;
grant execute on function public.admin_set_gift_delivery_fee(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- G. The trail.
-- ---------------------------------------------------------------------------
-- 0092's rule: every deletion is recorded, because nothing here can be undone
-- from inside the product. Both tables join that list now that a button exists
-- to delete from them — until this migration neither could be reached without a
-- psql prompt, which is why they were not in 0092's original set.
--
-- One line each, exactly as 0092 promised. `record_admin_action` reads the
-- primary key out of `to_jsonb(row)` by the name given here.
drop trigger if exists gift_shops_audit_delete on public.gift_shops;
create trigger gift_shops_audit_delete after delete on public.gift_shops
  for each row execute function public.record_admin_action('id');

drop trigger if exists gift_items_audit_delete on public.gift_items;
create trigger gift_items_audit_delete after delete on public.gift_items
  for each row execute function public.record_admin_action('id');

-- ---------------------------------------------------------------------------
-- H. The standing checks (0087, 0089).
-- ---------------------------------------------------------------------------
-- Both of these must return zero rows before every release, and this migration
-- creates eleven functions and touches no table grants — so the second is
-- unchanged and the first is the one to read. Run them:
--
--   -- 0087: a function PUBLIC can execute
--   select p.proname
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname like 'admin_gift%'
--      and has_function_privilege('public', p.oid, 'execute');
--
--   -- and the one that matters, per 0118's own surface: every function here is
--   -- reachable by `authenticated` and refuses a non-admin at its first line.
--   select p.proname, has_function_privilege('authenticated', p.oid, 'execute')
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and (p.proname like 'admin_gift%' or p.proname like 'admin_%gift%');
--
-- `gift_slug` is the exception and is granted to nobody: it is a helper the
-- definer functions call, not an entry point, and 0100's lesson is that a chain
-- evaluated as the *definer* needs no grant on its links.
