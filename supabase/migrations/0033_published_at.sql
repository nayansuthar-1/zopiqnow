-- Step 11, migration 33: the difference between "not yet" and "not any more".
--
-- `is_active = false` means a restaurant is not in front of customers, and until
-- now that was the whole story — there was one way to be inactive, because ops
-- delisting a vendor was the only thing that ever set it. 0030 added a second:
-- a restaurant that has never been published at all.
--
-- To the customer app these are identical and should stay identical. To the
-- console they are opposite kinds of work — one needs finishing, the other needs
-- a decision reversed — and a list that shows them with the same grey pill is a
-- list that tells an admin nothing about what to do next.
--
-- One nullable timestamp separates them:
--
--     is_active                       → Live (or Paused, if the kitchen said so)
--     not is_active, published_at null → Draft, never listed
--     not is_active, published_at set  → Delisted, was live until someone stopped it

alter table public.restaurants
  add column if not exists published_at timestamptz;

-- The eight seeded restaurants are live and have been since they were created.
-- Their `created_at` is the closest true answer available, and leaving them null
-- would file every one of them as a draft.
update public.restaurants
   set published_at = created_at
 where is_active and published_at is null;

-- ---------------------------------------------------------------------------
-- Publish records when it first happened.
-- ---------------------------------------------------------------------------
-- `coalesce(published_at, now())` — the *first* time, not the most recent. A
-- restaurant delisted for a week and brought back has not become new, and an
-- admin looking at the list wants to know it has been on the platform since
-- March, not since Tuesday.
--
-- Everything above the final update is unchanged from 0030; the function is
-- replaced whole because that is what `create or replace` requires, not because
-- the gate moved.
create or replace function public.admin_publish_restaurant(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.restaurants%rowtype;
  v_legal public.restaurant_legal%rowtype;
  v_bank  public.restaurant_bank_accounts%rowtype;
begin
  perform public.assert_admin();

  select * into r from public.restaurants where id = p_id;
  if not found then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  if coalesce(r.image_url, '') = '' then
    raise exception 'Add a cover photo before publishing.' using errcode = 'P0001';
  end if;
  if r.address_line is null or r.city is null or r.pincode is null then
    raise exception 'Add the full address before publishing.' using errcode = 'P0001';
  end if;
  if r.contact_phone is null then
    raise exception 'Add a contact phone number before publishing.' using errcode = 'P0001';
  end if;

  select * into v_legal from public.restaurant_legal where restaurant_id = p_id;
  if v_legal.fssai_number is null then
    raise exception 'Add the FSSAI licence before publishing.' using errcode = 'P0001';
  end if;
  if v_legal.fssai_expiry is null
     or v_legal.fssai_expiry < (now() at time zone 'Asia/Kolkata')::date then
    raise exception 'That FSSAI licence has expired. Publishing needs a valid one.'
      using errcode = 'P0001';
  end if;
  if v_legal.pan_number is null then
    raise exception 'Add the PAN before publishing.' using errcode = 'P0001';
  end if;

  select * into v_bank from public.restaurant_bank_accounts where restaurant_id = p_id;
  if v_bank.account_number is null or v_bank.ifsc is null then
    raise exception 'Add the bank account before publishing — settlements need somewhere to pay.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.restaurant_staff s
     where s.restaurant_id = p_id and s.role = 'owner'
  ) then
    raise exception 'Add the owner''s email before publishing — nobody can run this kitchen without it.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.restaurant_hours h where h.restaurant_id = p_id
  ) then
    raise exception 'Set the opening hours before publishing.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.menu_items m
     where m.restaurant_id = p_id and m.is_available and m.category_available
  ) then
    raise exception 'Add at least one dish before publishing.' using errcode = 'P0001';
  end if;

  update public.restaurants
     set is_active = true,
         published_at = coalesce(published_at, now())
   where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- The list carries it.
-- ---------------------------------------------------------------------------
-- Return types cannot be widened in place — `create or replace` refuses to change
-- a function's `returns table` shape — so this one is dropped and rebuilt.
drop function if exists public.admin_list_restaurants();

create or replace function public.admin_list_restaurants()
returns table (
  id               text,
  name             text,
  city             text,
  is_active        boolean,
  accepting_orders boolean,
  image_url        text,
  menu_item_count  integer,
  owner_email      text,
  published_at     timestamptz,
  created_at       timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select
      r.id, r.name, r.city, r.is_active, r.accepting_orders, r.image_url,
      (select count(*)::integer from public.menu_items m where m.restaurant_id = r.id),
      (select s.email from public.restaurant_staff s
        where s.restaurant_id = r.id and s.role = 'owner'
        order by s.created_at limit 1),
      r.published_at,
      r.created_at
    from public.restaurants r
    order by r.is_active, r.created_at desc;
end;
$$;

revoke execute on function public.admin_list_restaurants() from public;
grant execute on function public.admin_list_restaurants() to authenticated;
