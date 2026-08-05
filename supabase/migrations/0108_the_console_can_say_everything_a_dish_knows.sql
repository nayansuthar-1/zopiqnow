-- ---------------------------------------------------------------------------
-- 0108 — the console can say everything a dish already knows.
-- ---------------------------------------------------------------------------
-- **No new columns.** Every field here has existed since 0068 or 0078; what was
-- missing is that the admin console could neither read nor write them. Its
-- editor has been the seven fields of 0031 while the table has had twelve, so an
-- admin onboarding a restaurant could not set a strike-through price, a serving
-- window, a prep time, or a tax slab — and could not see one a vendor had set.
--
--   `original_price`      a former price, shown struck through (0068)
--   `prep_minutes`        how long this dish takes (0068, feeding 0015's sheet)
--   `serve_from`/`_to`    breakfast is not sold at 9pm (0068)
--   `unavailable_reason`  why it is off; kitchen-facing, never shown to a
--                         customer, because RLS removed the dish they'd read
--                         it on (0068)
--   `gst_rate_bps`        the slab this line is taxed at (0078)
--   `hsn_code`            what it is taxed *as*, on the invoice (0078)
--
-- **Every one of them stays optional**, which is the requirement and also the
-- only defensible default: a console that demanded an HSN code before a dish
-- could be saved would stop an onboarding over a field the restaurant does not
-- know yet. Absent, null, and empty-string all mean "not set" and all write
-- null — `''::integer` is an error and `0` is a lie, so the coercion happens
-- here rather than in a browser.
--
-- **`gst_rate_bps` is the exception, and it is not really one.** The column is
-- `not null default 500`, so "unset" is 5% — the rate every restaurant dish on
-- the platform is charged. An omitted key means 500 rather than null, so a CSV
-- import that has never heard of tax keeps producing correctly-taxed dishes.
--
-- **`rating` is deliberately not here.** It is the one nullable column on
-- `menu_items` left out, because nothing on the platform computes it and a
-- number an admin types into a dish rating is not a rating — it is fabricated
-- social proof, sitting next to the star a customer reads as other people's
-- opinion. Same argument as 0068's on `original_price`, one step further: that
-- one at least the restaurant owns and can defend. If dish ratings should be
-- real, they come from `reviews` (0062) through a trigger, not from a text box.

-- ---------------------------------------------------------------------------
-- A. Reading them back.
-- ---------------------------------------------------------------------------
-- Dropped, not replaced: `create or replace function` cannot change a function's
-- return type, and this adds seven columns to the table it returns. Postgres
-- would answer "cannot change return type of existing function" — the same wall
-- `db push --include-all` hit on 0053.
drop function if exists public.admin_list_menu(text);

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
  category_available boolean,
  original_price     integer,
  prep_minutes       integer,
  serve_from         text,
  serve_to           text,
  unavailable_reason text,
  gst_rate_bps       integer,
  hsn_code           text
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
           m.is_available, m.category_available,
           m.original_price, m.prep_minutes,
           -- `HH:MM` rather than a `time`. The console's field is an
           -- `<input type="time">`, which speaks exactly that and nothing else;
           -- PostgREST would otherwise hand it `18:00:00` and the field would
           -- silently render empty.
           to_char(m.serve_from, 'HH24:MI'),
           to_char(m.serve_to,   'HH24:MI'),
           m.unavailable_reason, m.gst_rate_bps, m.hsn_code
      from public.menu_items m
     where m.restaurant_id = p_id
     order by m.category_rank, m.item_rank, m.name;
end;
$$;

revoke execute on function public.admin_list_menu(text) from public;
grant execute on function public.admin_list_menu(text) to authenticated;

-- ---------------------------------------------------------------------------
-- B. Writing them.
-- ---------------------------------------------------------------------------
-- The signature is unchanged, so this is a genuine replace and no overload is
-- created — the trap where an old signature survives and the app binds to it.
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
  -- Absent, null and '' all collapse to null here. `nullif(…, '')` before the
  -- cast is the whole of it: `''::integer` raises, and doing it in the browser
  -- would mean every caller had to remember.
  v_original integer := nullif(trim(coalesce(p_item ->> 'original_price', '')), '')::integer;
  v_prep     integer := nullif(trim(coalesce(p_item ->> 'prep_minutes',   '')), '')::integer;
  v_from     time    := nullif(trim(coalesce(p_item ->> 'serve_from',     '')), '')::time;
  v_to       time    := nullif(trim(coalesce(p_item ->> 'serve_to',       '')), '')::time;
  v_reason   text    := trim(coalesce(p_item ->> 'unavailable_reason', ''));
  v_hsn      text    := nullif(trim(coalesce(p_item ->> 'hsn_code', '')), '');
  -- Not null, so an omitted key is 5% — what every restaurant dish is charged.
  -- A CSV import that has never heard of tax keeps working.
  v_gst      integer := coalesce(
                          nullif(trim(coalesce(p_item ->> 'gst_rate_bps', '')), '')::integer,
                          500);
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
  if v_price <= 0 then
    raise exception 'A dish has to cost more than zero.' using errcode = 'P0001';
  end if;

  -- The table's own constraints (0068) would refuse all three of these, in
  -- Postgres's words. Said here in the admin's instead, because "violates check
  -- constraint menu_item_original_price_is_higher" is not a sentence anybody can
  -- act on.
  if v_original is not null and v_original <= v_price then
    raise exception 'A struck-through price has to be higher than the price you charge.'
      using errcode = 'P0001';
  end if;
  if v_prep is not null and (v_prep <= 0 or v_prep > 240) then
    raise exception 'Prep time has to be between 1 and 240 minutes.' using errcode = 'P0001';
  end if;
  if (v_from is null) <> (v_to is null) then
    raise exception 'A serving window needs both a start and an end time.'
      using errcode = 'P0001';
  end if;
  if v_from is not null and v_from = v_to then
    raise exception 'A serving window that starts and ends at the same time serves nothing.'
      using errcode = 'P0001';
  end if;
  if v_gst not in (0, 500, 1200, 1800) then
    raise exception 'GST has to be one of 0%%, 5%%, 12%% or 18%%.' using errcode = 'P0001';
  end if;

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
      image_url, category, category_rank, item_rank, is_available,
      original_price, prep_minutes, serve_from, serve_to,
      unavailable_reason, gst_rate_bps, hsn_code
    ) values (
      p_id, v_name,
      trim(coalesce(p_item ->> 'description', '')),
      v_price,
      coalesce((p_item ->> 'is_veg')::boolean, false),
      coalesce((p_item ->> 'is_bestseller')::boolean, false),
      coalesce(p_item ->> 'image_url', ''),
      v_category, v_cat_rank, v_item_rank,
      coalesce((p_item ->> 'is_available')::boolean, true),
      v_original, v_prep, v_from, v_to, v_reason, v_gst, v_hsn
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
    is_available  = coalesce((p_item ->> 'is_available')::boolean, true),
    original_price     = v_original,
    prep_minutes       = v_prep,
    serve_from         = v_from,
    serve_to           = v_to,
    unavailable_reason = v_reason,
    gst_rate_bps       = v_gst,
    hsn_code           = v_hsn
  where id = v_item_id and restaurant_id = p_id;

  if not found then
    raise exception 'That dish is not on this restaurant''s menu.' using errcode = 'P0001';
  end if;

  return v_item_id;
end;
$$;

revoke execute on function public.admin_upsert_menu_item(text, jsonb) from public;
grant execute on function public.admin_upsert_menu_item(text, jsonb) to authenticated;
