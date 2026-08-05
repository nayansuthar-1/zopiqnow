-- ---------------------------------------------------------------------------
-- 0107 — a section, or a whole menu, can be taken down at once.
-- ---------------------------------------------------------------------------
-- 0031 gave the console one delete: a single dish. Clearing a section meant
-- deleting its dishes one at a time, and clearing a menu meant doing that for
-- every section — dozens of round trips, each of which can fail on its own and
-- leave the menu halfway between two states. These are the same delete with a
-- wider WHERE, done in one statement so it either happens or it doesn't.
--
-- **The rule they inherit is 0031's, and it is not negotiable.**
-- `order_items.menu_item_id` references `menu_items` without a cascade (0003),
-- which is what keeps a past order's history readable: the row that says what
-- was ordered still points at the dish. So a dish that has ever been ordered
-- cannot be deleted, and neither can a section or a menu containing one.
--
-- Refused **whole**, rather than deleting what can go and reporting the rest.
-- A partial delete leaves a section that still exists but is now only its
-- oldest dishes, which is a worse state than the one the admin started in and
-- not one they asked for. The answer for a section that has been ordered from
-- is `admin_set_category_available` — it disappears for customers and the
-- history stays intact.
--
-- Ranks are left with gaps. `sectionsOf` in the console sorts by rank and never
-- reads the numbers themselves, and `admin_upsert_menu_item` puts a new section
-- at max + 1, so a missing rank costs nothing and renumbering every surviving
-- row would be a second write for no one's benefit.
--
-- Deletes on `menu_items` are already audited row by row (0092), so every dish
-- that goes here lands in `admin_actions` with the admin who did it. Nothing to
-- add for that.

-- ---------------------------------------------------------------------------
-- A. The dishes standing in the way.
-- ---------------------------------------------------------------------------
-- Shared by both functions below. Returns the names of the dishes in the given
-- scope that appear on an order — the ones an admin needs named, because "this
-- can't be deleted" without saying which dish is an answer they can't act on.
-- Null when nothing is in the way.
--
-- Capped at five names. A menu where forty dishes have been ordered is not a
-- menu anyone is about to delete, and a forty-name error message is a wall.
create or replace function public.admin_menu_delete_blockers(
  p_id       text,
  p_category text default null
) returns text
language sql
stable
security definer
set search_path = public
as $$
  select string_agg(name, ', ')
    from (
      select m.name
        from public.menu_items m
       where m.restaurant_id = p_id
         and (p_category is null or m.category = p_category)
         and exists (
           select 1 from public.order_items oi where oi.menu_item_id = m.id
         )
       order by m.name
       limit 5
    ) blocked;
$$;

-- Not callable from the outside at all: it is the two functions below talking
-- to themselves, and it would otherwise be a way to ask which dishes a kitchen
-- has actually sold.
revoke execute on function public.admin_menu_delete_blockers(text, text) from public;
revoke execute on function public.admin_menu_delete_blockers(text, text) from authenticated;
revoke execute on function public.admin_menu_delete_blockers(text, text) from anon;

-- ---------------------------------------------------------------------------
-- B. Delete one section.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_category(
  p_id       text,
  p_category text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_blocked text;
  v_count   integer;
begin
  perform public.assert_admin();

  select count(*) into v_count
    from public.menu_items
   where restaurant_id = p_id and category = p_category;

  if v_count = 0 then
    raise exception 'No section called %.', p_category using errcode = 'P0001';
  end if;

  v_blocked := public.admin_menu_delete_blockers(p_id, p_category);
  if v_blocked is not null then
    raise exception
      'This section can''t be deleted — % % already on past orders. Hide the section instead.',
      v_blocked, case when v_blocked like '%,%' then 'are' else 'is' end
      using errcode = 'P0001';
  end if;

  delete from public.menu_items
   where restaurant_id = p_id and category = p_category;

  return v_count;
exception
  -- The check above is the message an admin can act on. This is the net under
  -- it: an order placed between the check and the delete would land here, and
  -- so would any future table that references a dish.
  when foreign_key_violation then
    raise exception 'This section can''t be deleted — one of its dishes is on a past order. Hide the section instead.'
      using errcode = 'P0001';
end;
$$;

revoke execute on function public.admin_delete_category(text, text) from public;
grant execute on function public.admin_delete_category(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- C. Delete the whole menu.
-- ---------------------------------------------------------------------------
-- The same function with the category dropped. Worth its own entry point rather
-- than a null category on the one above: "delete every dish this restaurant
-- has" is the most destructive thing the menu editor can do, and it should not
-- be reachable by leaving an argument out.
create or replace function public.admin_delete_menu(p_id text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_blocked text;
  v_count   integer;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  select count(*) into v_count
    from public.menu_items where restaurant_id = p_id;

  v_blocked := public.admin_menu_delete_blockers(p_id, null);
  if v_blocked is not null then
    raise exception
      'This menu can''t be deleted — % % already on past orders. Hide those dishes instead.',
      v_blocked, case when v_blocked like '%,%' then 'are' else 'is' end
      using errcode = 'P0001';
  end if;

  delete from public.menu_items where restaurant_id = p_id;

  return v_count;
exception
  when foreign_key_violation then
    raise exception 'This menu can''t be deleted — one of its dishes is on a past order. Hide those dishes instead.'
      using errcode = 'P0001';
end;
$$;

revoke execute on function public.admin_delete_menu(text) from public;
grant execute on function public.admin_delete_menu(text) to authenticated;
