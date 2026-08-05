-- ---------------------------------------------------------------------------
-- 0106 — a dish comes in sizes, and the console can say so.
-- ---------------------------------------------------------------------------
-- 0048 already models this and models it well: a size is not a special kind of
-- thing, it is an **option group** whose options carry a price delta. Small is
-- the base price, Large is "+₹80". `min_select`/`max_select` are the whole of
-- the behaviour — (1,1) is "must pick one", (0,1) is "may pick one".
--
-- So nothing here invents a size column, a variant table, or a second pricing
-- rule. `place_order` already prices options server-side and has since 0048:
--
--     unit price = menu_items.price + Σ(price_delta of chosen options)
--
-- **What was actually missing is that the admin console could not reach any of
-- it.** `set_menu_item_options` is scoped to `staff_restaurant_id()` — the
-- vendor app's own path — and a platform admin is not staff at any restaurant,
-- so calling it raises *"You do not work at a restaurant on Zopiqnow."* There
-- was also no way to read the groups back, which an editor needs before it can
-- offer to change them. Two functions, both admin-scoped, and no change to the
-- vendor's.
--
-- **Optional by default, deliberately.** The sizes the console writes are a
-- `(0, 1)` group unless the admin says otherwise: a customer may pick one and
-- may pick none, and picking none charges the dish's own price. That is what
-- "make them optional" asks for, and it is also the safer default — a required
-- group on an existing dish would change what every customer must do before
-- ordering something they used to be able to add in one tap.

-- ---------------------------------------------------------------------------
-- A. Reading them back.
-- ---------------------------------------------------------------------------
-- One jsonb document rather than two result sets, because the caller is an
-- editor that wants the whole shape at once and the nesting *is* the shape.
-- Groups in rank order, options in rank order inside them.
--
-- Every group is returned, not only the sizes. The console needs that: the
-- writer below replaces the lot, so an editor that had only asked for sizes
-- would delete a vendor's add-on groups the first time an admin saved a dish.
create or replace function public.admin_menu_item_options(p_item_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_out jsonb;
begin
  perform public.assert_admin();

  select coalesce(jsonb_agg(g order by g.rank, g.created_at), '[]'::jsonb)
    into v_out
    from (
      select
        grp.id,
        grp.name,
        grp.min_select,
        grp.max_select,
        grp.rank,
        grp.created_at,
        coalesce(
          (
            select jsonb_agg(
                     jsonb_build_object(
                       'id',           o.id,
                       'name',         o.name,
                       'price_delta',  o.price_delta,
                       'is_available', o.is_available,
                       'rank',         o.rank
                     )
                     order by o.rank, o.created_at
                   )
              from public.menu_options o
             where o.group_id = grp.id
          ),
          '[]'::jsonb
        ) as options
        from public.menu_option_groups grp
       where grp.menu_item_id = p_item_id
    ) g;

  return v_out;
end;
$$;

revoke execute on function public.admin_menu_item_options(text) from public;
grant execute on function public.admin_menu_item_options(text) to authenticated;

-- ---------------------------------------------------------------------------
-- B. Writing them.
-- ---------------------------------------------------------------------------
-- The vendor's `set_menu_item_options` with one difference: who is allowed to
-- call it. Everything else — delete the groups and reinsert, options cascading
-- with their group — is 0048's, and is restated rather than shared because the
-- two differ in exactly the line that matters and a shared body with a role
-- switch inside it is how a guard eventually gets edited out of one caller.
--
-- **Replace-the-lot is the contract, and the caller must respect it.** Passing
-- only the size group deletes every other group on that dish. The console reads
-- with the function above, swaps the one group it edits, and writes them all
-- back — which is why the reader returns every group rather than just sizes.
create or replace function public.admin_set_menu_item_options(
  p_item_id text,
  p_groups  jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group    jsonb;
  v_group_id text;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.menu_items where id = p_item_id) then
    raise exception 'No such dish.' using errcode = 'P0001';
  end if;

  -- Out with the old — options cascade with their group.
  delete from public.menu_option_groups where menu_item_id = p_item_id;

  -- In with the new.
  for v_group in select * from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb))
  loop
    insert into public.menu_option_groups
      (menu_item_id, name, min_select, max_select, rank)
    values (
      p_item_id,
      v_group ->> 'name',
      coalesce((v_group ->> 'min_select')::integer, 0),
      coalesce((v_group ->> 'max_select')::integer, 1),
      coalesce((v_group ->> 'rank')::integer, 0)
    )
    returning id into v_group_id;

    insert into public.menu_options
      (group_id, name, price_delta, is_available, rank)
    select
      v_group_id,
      o ->> 'name',
      coalesce((o ->> 'price_delta')::integer, 0),
      coalesce((o ->> 'is_available')::boolean, true),
      coalesce((o ->> 'rank')::integer, 0)
    from jsonb_array_elements(coalesce(v_group -> 'options', '[]'::jsonb)) as o;
  end loop;
end;
$$;

revoke execute on function public.admin_set_menu_item_options(text, jsonb) from public;
grant execute on function public.admin_set_menu_item_options(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- The two standing release checks (0087, 0089) must still return zero rows.
-- ---------------------------------------------------------------------------
