-- Step 11, migration 31: the console writes a menu.
--
-- The vendor has been able to edit its own menu since 0010, through RLS policies
-- keyed on `staff_restaurant_id()`. An admin cannot use any of that: they do not
-- work at a restaurant, so `staff_restaurant_id()` is null for them and every one
-- of those policies is a no-op. They cannot even *read* a menu — the world-readable
-- policy is `using (is_available and category_available)`, which hides exactly the
-- rows an editor most needs to see.
--
-- Hence this file. Same operations, resolved by an explicit restaurant id and
-- gated on `is_admin()` instead.
--
-- The thing to understand about menus here: **a category is not a table.** It is a
-- string on `menu_items`, carried alongside `category_rank`, and a "section" is
-- the set of rows that happen to share it (0002). Nothing in the database keeps
-- two dishes in "Starters" agreeing on their `category_rank`, or stops a typo
-- creating a second section called "Startes" with one dish in it. That consistency
-- is the editor's job, which is why renaming and reordering are functions here
-- rather than something the console does with a loop of row updates.

-- ---------------------------------------------------------------------------
-- Read the whole menu, hidden rows included.
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_menu(p_id text)
returns table (
  id                 text,
  name               text,
  description        text,
  price              integer,
  is_veg             boolean,
  is_bestseller      boolean,
  image_url          text,
  category           text,
  category_rank      integer,
  item_rank          integer,
  is_available       boolean,
  category_available boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select m.id, m.name, m.description, m.price, m.is_veg, m.is_bestseller,
           m.image_url, m.category, m.category_rank, m.item_rank,
           m.is_available, m.category_available
      from public.menu_items m
     where m.restaurant_id = p_id
     -- The order the customer sees it in (0002's index), so the editor and the
     -- app never disagree about what "first" means.
     order by m.category_rank, m.item_rank, m.name;
end;
$$;

revoke execute on function public.admin_list_menu(text) from public;
grant execute on function public.admin_list_menu(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Add or edit one dish.
-- ---------------------------------------------------------------------------
-- An `id` in the payload means edit, its absence means add — and on add the id
-- comes from the column default (0010), never from the client. A client that names
-- a primary key is a client that can collide with, or guess at, another row's.
--
-- The ranks are worked out here rather than asked for. An admin typing a dish into
-- "Starters" is not thinking about integers, and if they were, the two of us would
-- eventually disagree: a new dish joins the end of its section, and a new section
-- joins the end of the menu.
create or replace function public.admin_upsert_menu_item(p_id text, p_item jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id  text := nullif(trim(coalesce(p_item ->> 'id', '')), '');
  v_name     text := trim(coalesce(p_item ->> 'name', ''));
  v_category text := trim(coalesce(p_item ->> 'category', ''));
  v_price    integer := coalesce((p_item ->> 'price')::integer, 0);
  v_cat_rank integer;
  v_item_rank integer;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;
  if v_name = '' then
    raise exception 'The dish needs a name.' using errcode = 'P0001';
  end if;
  if v_category = '' then
    raise exception 'Every dish belongs to a section. Pick one.' using errcode = 'P0001';
  end if;
  -- `price > 0` is a table constraint (0002). A free dish is not a price of zero,
  -- it is a combo or an offer, and neither of those is modelled here.
  if v_price <= 0 then
    raise exception 'A dish has to cost more than zero.' using errcode = 'P0001';
  end if;

  -- Where this section already sits, or the end of the menu if it is new.
  select m.category_rank into v_cat_rank
    from public.menu_items m
   where m.restaurant_id = p_id and m.category = v_category
   limit 1;
  if v_cat_rank is null then
    select coalesce(max(m.category_rank), -1) + 1 into v_cat_rank
      from public.menu_items m where m.restaurant_id = p_id;
  end if;

  if v_item_id is null then
    select coalesce(max(m.item_rank), -1) + 1 into v_item_rank
      from public.menu_items m
     where m.restaurant_id = p_id and m.category = v_category;

    insert into public.menu_items (
      restaurant_id, name, description, price, is_veg, is_bestseller,
      image_url, category, category_rank, item_rank, is_available
    ) values (
      p_id, v_name,
      trim(coalesce(p_item ->> 'description', '')),
      v_price,
      coalesce((p_item ->> 'is_veg')::boolean, false),
      coalesce((p_item ->> 'is_bestseller')::boolean, false),
      coalesce(p_item ->> 'image_url', ''),
      v_category, v_cat_rank, v_item_rank,
      coalesce((p_item ->> 'is_available')::boolean, true)
    ) returning id into v_item_id;

    return v_item_id;
  end if;

  update public.menu_items set
    name          = v_name,
    description   = trim(coalesce(p_item ->> 'description', '')),
    price         = v_price,
    is_veg        = coalesce((p_item ->> 'is_veg')::boolean, false),
    is_bestseller = coalesce((p_item ->> 'is_bestseller')::boolean, false),
    image_url     = coalesce(p_item ->> 'image_url', ''),
    category      = v_category,
    category_rank = v_cat_rank,
    is_available  = coalesce((p_item ->> 'is_available')::boolean, true)
  -- Scoped to the restaurant as well as the id: an id from another kitchen's menu
  -- matches nothing rather than being edited.
  where id = v_item_id and restaurant_id = p_id;

  if not found then
    raise exception 'That dish is not on this restaurant''s menu.' using errcode = 'P0001';
  end if;

  return v_item_id;
end;
$$;

revoke execute on function public.admin_upsert_menu_item(text, jsonb) from public;
grant execute on function public.admin_upsert_menu_item(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Delete a dish, or explain why it cannot be deleted.
-- ---------------------------------------------------------------------------
-- `order_items.menu_item_id` references this table without a cascade (0003), which
-- is what keeps a past order's history intact. A dish that has never been ordered
-- goes cleanly; one that appears on an order cannot go at all, and Postgres raises
-- a foreign-key violation saying so in its own language. Caught and translated,
-- because the answer an admin needs is not "23503" but what to do instead.
create or replace function public.admin_delete_menu_item(p_item_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  delete from public.menu_items where id = p_item_id;
  if not found then
    raise exception 'No such dish.' using errcode = 'P0001';
  end if;
exception
  when foreign_key_violation then
    raise exception 'This dish appears on past orders, so it can''t be deleted. Mark it unavailable instead.'
      using errcode = 'P0001';
end;
$$;

revoke execute on function public.admin_delete_menu_item(text) from public;
grant execute on function public.admin_delete_menu_item(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Reordering: sections and dishes, in one write.
-- ---------------------------------------------------------------------------
-- The payload is the menu's whole running order — every item with the rank it
-- should now have:
--   [{"id": "…", "category": "Starters", "category_rank": 0, "item_rank": 2}, …]
--
-- Whole, rather than the rows that moved, because ranks are only meaningful
-- relative to each other. Dragging one dish to the top renumbers everything below
-- it, and a client sending only "the thing I dragged" would be leaving the
-- database to guess the rest. One statement also means the menu is never briefly
-- half-reordered for a customer reading it mid-write.
create or replace function public.admin_reorder_menu(p_id text, p_order jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  update public.menu_items m set
    category      = e.category,
    category_rank = e.category_rank,
    item_rank     = e.item_rank
  from jsonb_to_recordset(coalesce(p_order, '[]'::jsonb))
    as e(id text, category text, category_rank integer, item_rank integer)
  where m.id = e.id and m.restaurant_id = p_id;
end;
$$;

revoke execute on function public.admin_reorder_menu(text, jsonb) from public;
grant execute on function public.admin_reorder_menu(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Sections.
-- ---------------------------------------------------------------------------
-- Renaming one means rewriting the string on every dish in it, which is the part
-- a console doing this row by row would eventually get half-right. Here it is one
-- statement: either the section is renamed or it is not.
create or replace function public.admin_rename_category(
  p_id   text,
  p_from text,
  p_to   text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_to text := trim(coalesce(p_to, ''));
begin
  perform public.assert_admin();

  if v_to = '' then
    raise exception 'A section needs a name.' using errcode = 'P0001';
  end if;
  -- Merging two sections by renaming one onto the other would silently interleave
  -- their `item_rank`s — two dishes at rank 0, and no way to tell which the vendor
  -- meant to be first. Refused rather than half-handled.
  if exists (
    select 1 from public.menu_items
     where restaurant_id = p_id and category = v_to
  ) and v_to <> p_from then
    raise exception 'There is already a section called %.', v_to using errcode = 'P0001';
  end if;

  update public.menu_items
     set category = v_to
   where restaurant_id = p_id and category = p_from;

  if not found then
    raise exception 'No section called %.', p_from using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_rename_category(text, text, text) from public;
grant execute on function public.admin_rename_category(text, text, text) to authenticated;

-- Hiding a whole section at once — the lunch menu at 9pm, the ice creams in
-- January. `category_available` (0016) is already half of the customer-facing
-- visibility rule, and it lives on every row of the section, so this sets them
-- together.
create or replace function public.admin_set_category_available(
  p_id        text,
  p_category  text,
  p_available boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  update public.menu_items
     set category_available = coalesce(p_available, true)
   where restaurant_id = p_id and category = p_category;

  if not found then
    raise exception 'No section called %.', p_category using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_set_category_available(text, text, boolean) from public;
grant execute on function public.admin_set_category_available(text, text, boolean) to authenticated;
