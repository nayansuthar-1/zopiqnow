-- Step 11, migration 38: admins can appoint admins.
--
-- 0026 created `platform_admins` with one row in it, inserted by the migration
-- itself, and said the roster would be read "through an RPC in a later migration,
-- so that read is a deliberate, audited surface rather than a policy someone
-- widens by accident". This is that migration.
--
-- What it is really for: today there is exactly one person who can create a
-- restaurant, and if that account is lost so is the ability to onboard anybody.
-- A second admin is not a convenience, it is the difference between an
-- inconvenience and a locked door.
--
-- Two rules, and both exist because of the same failure — a platform with nobody
-- who can administer it:
--
--   * you cannot remove yourself. Not because it would be wrong, but because it
--     is almost always a misclick, and the person best placed to undo it has just
--     removed their own ability to;
--   * you cannot remove the last admin. `is_admin()` returning false for everyone
--     means no restaurant can ever be created or published again, and there is no
--     screen anywhere that fixes it — only a migration.

create or replace function public.admin_list_admins()
returns table (email text, name text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select a.email, a.name, a.created_at
      from public.platform_admins a
     order by a.created_at;
end;
$$;

revoke execute on function public.admin_list_admins() from public;
grant execute on function public.admin_list_admins() to authenticated;

create or replace function public.admin_add_admin(p_email text, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'That doesn''t look like an email address.' using errcode = 'P0001';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    -- A roster of bare addresses is a roster nobody can audit six months later.
    raise exception 'Who is this? Add a name.' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.platform_admins where email = v_email) then
    raise exception '% is already an admin.', v_email using errcode = 'P0001';
  end if;

  -- Note what is *not* checked: whether this address belongs to a restaurant's
  -- staff or to a rider. Those are different tables answering different questions,
  -- and one person legitimately being both is not this function's business.
  insert into public.platform_admins (email, name)
  values (v_email, trim(p_name));
end;
$$;

revoke execute on function public.admin_add_admin(text, text) from public;
grant execute on function public.admin_add_admin(text, text) to authenticated;

create or replace function public.admin_remove_admin(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));

  if v_email = lower(auth.jwt() ->> 'email') then
    raise exception 'You can''t remove yourself.' using errcode = 'P0001';
  end if;

  -- Unreachable while the self-removal rule above holds, since removing the last
  -- admin means removing yourself. Kept anyway: it is one line, and it is the
  -- check that still holds if the rule above is ever relaxed.
  if (select count(*) from public.platform_admins) <= 1 then
    raise exception 'That is the last admin. The platform would have nobody to run it.'
      using errcode = 'P0001';
  end if;

  delete from public.platform_admins where email = v_email;
  if not found then
    raise exception '% is not an admin.', v_email using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_remove_admin(text) from public;
grant execute on function public.admin_remove_admin(text) to authenticated;
