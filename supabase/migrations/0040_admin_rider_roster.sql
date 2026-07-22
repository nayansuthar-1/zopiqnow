-- Migration 40: riders are onboarded by an admin, not by a seed file.
--
-- 8b-2 seeded the first delivery partner with a SQL file and DELIVERY_PLAN.md
-- said the honest thing about it: fine for the first ten, untenable at a
-- hundred. This closes that the same way restaurant onboarding was closed — a
-- `security definer` RPC gated on `is_admin()`, never a table write granted to
-- the browser.
--
-- Nothing is added to `delivery_partners` and nothing about the rider app
-- changes. `is_active` was always the ops switch (0025); this is the first
-- screen that can reach it.
--
-- Note there is no `admin_remove_rider`. `deliveries.partner_email` is a foreign
-- key, so deleting a rider who has ever carried an order would either fail or
-- take the delivery history with it — and "who delivered this" is a question
-- worth being able to answer a year later. Deactivation is the removal, and it
-- is reversible, which suits a switch that will sometimes be flipped by mistake.

-- ---------------------------------------------------------------------------
-- The roster.
-- ---------------------------------------------------------------------------
-- `live_order_id` is the whole reason this returns more than the table's own
-- columns: a rider mid-delivery must not be deactivated (see below), and a
-- console that disables the switch has to be able to say why.
create or replace function public.admin_list_riders()
returns table (
  email           text,
  name            text,
  phone           text,
  vehicle         text,
  is_active       boolean,
  created_at      timestamptz,
  live_order_id   text,
  delivered_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select p.email, p.name, p.phone, p.vehicle, p.is_active, p.created_at,
           (select d.order_id
              from public.deliveries d
             where d.partner_email = p.email
               and d.state in ('claimed', 'picked_up')
             limit 1),
           (select count(*)::integer
              from public.deliveries d
             where d.partner_email = p.email
               and d.state = 'delivered')
      from public.delivery_partners p
     order by p.is_active desc, p.created_at;
end;
$$;

revoke execute on function public.admin_list_riders() from public;
grant execute on function public.admin_list_riders() to authenticated;

-- ---------------------------------------------------------------------------
-- Onboarding one.
-- ---------------------------------------------------------------------------
-- Keyed by email, and that address is the rider's login — 0025 keyed the table
-- this way precisely so ops could add somebody days before they first open the
-- app. There is no account to create here and no password to set: the rider
-- signs in with a code sent to this address, and the row is what makes them a
-- rider when they do.
create or replace function public.admin_add_rider(
  p_email   text,
  p_name    text,
  p_phone   text,
  p_vehicle text default 'bike'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_phone text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'That doesn''t look like an email address.' using errcode = 'P0001';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Who is this? Add a name.' using errcode = 'P0001';
  end if;

  -- Ten digits, because this is the number a customer rings when their food is
  -- twenty minutes late and the number a manager rings when a bag has been on
  -- the counter for ten. A rider who cannot be reached is not on the fleet.
  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if length(v_phone) <> 10 then
    raise exception 'A rider needs a 10-digit phone number.' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.delivery_partners where email = v_email) then
    raise exception '% is already a rider.', v_email using errcode = 'P0001';
  end if;

  -- Deliberately not checked: whether this address is also a restaurant's staff
  -- or a platform admin. Those are different tables answering different
  -- questions — the same reasoning 0038 gave for admins.
  insert into public.delivery_partners (email, name, phone, vehicle)
  values (v_email, trim(p_name), v_phone, coalesce(nullif(trim(p_vehicle), ''), 'bike'));
end;
$$;

revoke execute on function public.admin_add_rider(text, text, text, text) from public;
grant execute on function public.admin_add_rider(text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Correcting one.
-- ---------------------------------------------------------------------------
-- The email is the key and so cannot be edited: changing it would not rename a
-- rider, it would orphan every delivery they have ever made. A rider with a new
-- address is a new row and a deactivated old one.
create or replace function public.admin_update_rider(
  p_email   text,
  p_name    text,
  p_phone   text,
  p_vehicle text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_phone text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Who is this? Add a name.' using errcode = 'P0001';
  end if;

  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if length(v_phone) <> 10 then
    raise exception 'A rider needs a 10-digit phone number.' using errcode = 'P0001';
  end if;

  update public.delivery_partners
     set name    = trim(p_name),
         phone   = v_phone,
         vehicle = coalesce(nullif(trim(p_vehicle), ''), 'bike')
   where email = v_email;

  if not found then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_update_rider(text, text, text, text) from public;
grant execute on function public.admin_update_rider(text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The switch — and the one thing it must refuse.
-- ---------------------------------------------------------------------------
-- Deactivating a rider who is *carrying an order* strands that order, and does
-- it quietly. `delivery_partner_email()` returns null for a deactivated rider,
-- so every rider RPC stops answering them: they cannot confirm the pickup and
-- they cannot mark it delivered. Nor does the job return to the board — the
-- partial unique index treats anything that is not `cancelled` as live, so no
-- other rider can claim it either. The food is in a bag on a bike and there is
-- no screen anywhere that can finish the delivery.
--
-- So: refuse, and say what to do instead. The rider drops the job from their own
-- app (`abandon_delivery`), which returns it to the board, and then they can be
-- switched off. That is one extra step for ops and it is the difference between
-- a rider going offline and an order disappearing.
create or replace function public.admin_set_rider_active(p_email text, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text;
  v_order  text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));

  if not p_active then
    select d.order_id into v_order
      from public.deliveries d
     where d.partner_email = v_email
       and d.state in ('claimed', 'picked_up')
     limit 1;

    if v_order is not null then
      raise exception
        'They are carrying order %. They must drop it in the rider app first, or the order cannot be delivered by anyone.',
        v_order using errcode = 'P0001';
    end if;
  end if;

  update public.delivery_partners
     set is_active = p_active
   where email = v_email;

  if not found then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_set_rider_active(text, boolean) from public;
grant execute on function public.admin_set_rider_active(text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- The admin's read of the roster.
-- ---------------------------------------------------------------------------
-- The functions above are `security definer` and so do not need a policy — but
-- `admin_list_riders` is the only way an admin sees this table, and that is on
-- purpose. No select policy is added for admins here: a policy would make every
-- rider's address readable through PostgREST by anyone the console's anon key
-- reaches, and the RPC already answers the one question worth asking.
