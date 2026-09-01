-- An admin is made with a password, not a promise.
--
-- `admin_add_admin` (0038) inserted one row into `platform_admins` and stopped
-- there. That was the whole of "add an admin" — and since 0026 authority *is*
-- that row, it looked complete. It was not.
--
-- Being allowed in and being able to get in are two different facts. The console
-- signs people in with `signInWithPassword` against `auth.users`, and 0038 never
-- touched `auth.users`. So an address added from Settings was authorised and
-- could not authenticate: it had no account to authenticate *with*. Whoever was
-- added typed their address into the sign-in screen, was told "That email and
-- password don't match", and had no way forward that did not involve somebody
-- opening psql. The console's own copy made it worse by describing the OTP door
-- that 0026's successor had already replaced — "they sign in with a code sent to
-- that address" — which had not been true for some time.
--
-- This closes it: adding an admin creates the account, with a password the
-- adding admin sets and hands over.
--
-- **What this deliberately will not do: set a password on an account that
-- already exists.** An address that has signed in before — a customer, a
-- restaurant's owner, a rider — keeps the password it has, and adding it here
-- only grants it the admin row. Anything else would make this function a way to
-- take over any account on the platform by address: set a password on a
-- stranger's email, then sign into the customer app as them. An admin can
-- already read a great deal about a person (0088); becoming one is a different
-- power and is not on offer here. Asking for a password on an existing account
-- is refused out loud rather than ignored, because an admin who typed one
-- believes they set one.
--
-- **The empty strings are load-bearing.** GoTrue reads
-- `confirmation_token`, `recovery_token`, `email_change`,
-- `email_change_token_new` and friends into Go `string`s, which cannot hold
-- NULL. A row written by hand with those left null passes every check here,
-- stores fine, and then fails at sign-in with an HTTP 500 whose body is `{}` —
-- no message, no column named, nothing to search for. Every one of them is set
-- to '' below. The unique indexes on those columns are partial
-- (`WHERE token !~ '^[0-9 ]*$'`) and '' matches that pattern, so every account
-- can carry '' without colliding.
--
-- **`auth.identities` is not optional either.** GoTrue resolves a password
-- sign-in through the identity row for the `email` provider; the two accounts
-- that work today both have one, with `provider_id` equal to the user id. A user
-- row without it is a user nothing can find.
--
-- `extensions.crypt` and `extensions.gen_salt` are schema-qualified because
-- `search_path` is pinned to `public` and pgcrypto lives in `extensions`. Cost
-- 10 matches what GoTrue itself writes.

-- The argument list changes, so the old signature has to go rather than gain an
-- overload beside it. A two-argument `admin_add_admin` left in place would keep
-- being the one PostgREST picks for the console's existing call, and the fix
-- would appear to have done nothing.
drop function if exists public.admin_add_admin(text, text);
-- And the new signature too, so re-running this file is not an error. The CLI's
-- ledger and this database have disagreed before; a migration that only applies
-- to a schema in exactly one state is a migration that has to be hand-edited the
-- day that happens.
drop function if exists public.admin_add_admin(text, text, text);

create function public.admin_add_admin(
  p_email    text,
  p_name     text,
  p_password text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text;
  v_name    text;
  v_user_id uuid;
begin
  perform public.assert_admin();

  v_email := lower(trim(coalesce(p_email, '')));
  v_name  := trim(coalesce(p_name, ''));

  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'That doesn''t look like an email address.' using errcode = 'P0001';
  end if;
  if v_name = '' then
    -- A roster of bare addresses is a roster nobody can audit six months later.
    raise exception 'Who is this? Add a name.' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.platform_admins where email = v_email) then
    raise exception '% is already an admin.', v_email using errcode = 'P0001';
  end if;

  -- Does this address already have an account? `deleted_at` is checked because a
  -- soft-deleted row still holds the address and would collide on insert while
  -- being useless to sign in with.
  select u.id into v_user_id
    from auth.users u
   where lower(u.email) = v_email
     and u.deleted_at is null
   limit 1;

  if v_user_id is not null then
    if coalesce(p_password, '') <> '' then
      raise exception
        '% already has a Zopiqnow account. Leave the password blank — they sign in with the one they already have, and this screen cannot change it.',
        v_email
        using errcode = 'P0001';
    end if;

    -- Note what is *not* checked: whether this address belongs to a restaurant's
    -- staff or to a rider. Those are different tables answering different
    -- questions, and one person legitimately being both is not this function's
    -- business.
    insert into public.platform_admins (email, name)
    values (v_email, v_name);

    return v_name || ' can now open the console, signing in with the Zopiqnow password they already have.';
  end if;

  -- No account. One is made here, or nothing is.
  if coalesce(p_password, '') = '' then
    raise exception
      '% has never signed in to Zopiqnow, so there is no account to grant. Set a password to create one.',
      v_email
      using errcode = 'P0001';
  end if;

  if length(p_password) < 10 then
    -- Ten, not GoTrue's six. This password opens a console that reads every bank
    -- account and licence number on the platform, and nothing else in the
    -- product gates on it — there is no second factor and no lockout.
    raise exception 'That password is too short. Use at least 10 characters.'
      using errcode = 'P0001';
  end if;
  if p_password <> trim(p_password) then
    -- Almost always a copy-and-paste that took the whitespace with it. Stored as
    -- typed it hashes fine and then fails to match anything anybody types back.
    raise exception 'That password starts or ends with a space. Remove it.'
      using errcode = 'P0001';
  end if;

  v_user_id := gen_random_uuid();

  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    -- Confirmed on the spot. The address was typed by an admin who is handing
    -- the password over in person; a confirmation mail would be a link sent to
    -- somebody who is already standing there, and an unconfirmed account cannot
    -- sign in at all.
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    -- The five that make GoTrue answer `{}` if they are null.
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    email_change_token_current,
    phone_change,
    phone_change_token,
    reauthentication_token
  ) values (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
    now(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object('email', v_email, 'email_verified', true, 'phone_verified', false),
    now(),
    now(),
    '', '', '', '', '', '', '', ''
  );

  -- `auth.identities.email` is a *generated* column reading
  -- `identity_data->>'email'`, so it is set by putting the address in the JSON
  -- and never by naming the column — writing to it directly is an error, not a
  -- redundancy.
  insert into auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    created_at,
    updated_at
  ) values (
    v_user_id::text,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
    'email',
    now(),
    now()
  );

  insert into public.platform_admins (email, name)
  values (v_email, v_name);

  return 'Account created for ' || v_name || '. They sign in at this console with ' || v_email || ' and the password you just set. Hand it over in person — it is not mailed to them, and this screen cannot show it again.';
end;
$$;

comment on function public.admin_add_admin(text, text, text) is
  'Grants console access, creating the auth account when the address has none. '
  'Refuses to set a password on an account that already exists - that would be a '
  'way to take over any address on the platform.';

-- Born PUBLIC-executable and granted to `authenticated` by default, both of
-- which have to be taken back before the grant below means anything.
revoke all on function public.admin_add_admin(text, text, text) from public, anon;
grant execute on function public.admin_add_admin(text, text, text) to authenticated;
