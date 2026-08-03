-- 0088 - every person on the platform, and the power to shut one out
--
-- Closes audit ADM-001 ("there is no customer management at all"), which the
-- ship plan had deferred until after launch and which was pulled forward.
--
-- There is no `users` table in this schema and there should not be one. A person
-- is a row in `auth.users`; what they are *allowed* to do lives in three
-- separate tables keyed by email - `platform_admins`, `restaurant_staff`,
-- `delivery_partners` - and a customer is simply somebody in none of them. So
-- "list every user with their role" is a join, not a new table, and it stays
-- correct when somebody is made staff tomorrow.
--
-- Roles are reported most-privileged-first: a person who is both an admin and
-- restaurant staff is shown as an admin, because that is the answer that matters
-- when you are deciding whether to block them.
--
-- **On blocking.** The honest place to block somebody is `auth.users.banned_until`:
-- GoTrue refuses to issue or refresh a token for a banned user, so the block
-- survives a reinstall and does not depend on any client behaving. Two things it
-- does not do on its own, both handled here:
--
--   * An access token already in someone's pocket stays valid until it expires.
--     So blocking also deletes their sessions, and a `before insert` trigger on
--     `orders` refuses a blocked user outright. Belt and braces, because the
--     window is otherwise up to an hour of a blocked person still ordering.
--   * It records nothing. Every block and unblock writes a row to
--     `user_blocks`, which is append-only - the ledger the ship plan's S8 asks
--     for, started here because this is the first destructive power the console
--     has over a person rather than a row.
--
-- Two rails, deliberately not configurable: **an admin cannot block themselves**,
-- and **an admin cannot block another platform admin.** The first stops the
-- obvious accident. The second stops the console being used to win an argument,
-- and means locking everyone out takes deliberate SQL rather than one click.
--
-- `banned_until` is set far enough out to mean "indefinitely" rather than using
-- a sentinel: GoTrue compares it to now(), so a timestamp is the only vocabulary
-- it has.

create table if not exists public.user_blocks (
  id          bigserial primary key,
  user_id     uuid        not null,
  user_email  text,
  action      text        not null check (action in ('block', 'unblock')),
  reason      text,
  actor_email text        not null,
  created_at  timestamptz not null default now()
);

comment on table public.user_blocks is
  'Append-only ledger of every block and unblock. Never updated, never deleted - '
  'a moderation record whose value is that it disagrees with the current state.';

create index if not exists user_blocks_user_idx
  on public.user_blocks (user_id, created_at desc);

alter table public.user_blocks enable row level security;
-- No policy on purpose: RLS with no policy is deny-all, and this is read solely
-- through the SECURITY DEFINER functions below.

-- Everyone on the platform, with the counts the console lists them by.
--
-- The three counts are three different stories and are not collapsed into one:
-- `delivered` is a completed sale, `rejected` is a restaurant refusing the
-- order, `cancelled` is the order being called off. Someone with ten orders and
-- nine cancellations is a different person from someone with ten and nine
-- deliveries, and the list exists to tell them apart.
create or replace function public.admin_list_users()
returns table (
  user_id         uuid,
  email           text,
  phone           text,
  name            text,
  role            text,
  created_at      timestamptz,
  last_sign_in_at timestamptz,
  is_blocked      boolean,
  blocked_until   timestamptz,
  total_orders    bigint,
  delivered_orders bigint,
  rejected_orders bigint,
  cancelled_orders bigint,
  total_spend     bigint
)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  perform public.assert_admin();

  return query
  select
    u.id,
    lower(u.email),
    coalesce(nullif(u.phone, ''), o.user_phone),
    coalesce(
      pa.name,
      dp.name,
      nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(u.raw_user_meta_data ->> 'name'), '')
    ),
    case
      when pa.email is not null then 'admin'
      when rs.email is not null then 'vendor'
      when dp.email is not null then 'rider'
      else 'customer'
    end,
    u.created_at,
    u.last_sign_in_at,
    (u.banned_until is not null and u.banned_until > now()),
    u.banned_until,
    coalesce(o.total_orders, 0),
    coalesce(o.delivered_orders, 0),
    coalesce(o.rejected_orders, 0),
    coalesce(o.cancelled_orders, 0),
    coalesce(o.total_spend, 0)
  from auth.users u
  left join public.platform_admins   pa on lower(pa.email) = lower(u.email)
  left join public.restaurant_staff  rs on lower(rs.email) = lower(u.email)
  left join public.delivery_partners dp on lower(dp.email) = lower(u.email)
  -- `ord` is aliased and every column qualified because this function's OUT
  -- parameters (`user_id`, `total_spend`, ...) are PL/pgSQL variables, and an
  -- unqualified `user_id` here resolves to the variable rather than the column.
  left join lateral (
    select
      count(*)                                             as total_orders,
      count(*) filter (where ord.status = 'delivered')     as delivered_orders,
      count(*) filter (where ord.status = 'rejected')      as rejected_orders,
      count(*) filter (where ord.status = 'cancelled')     as cancelled_orders,
      coalesce(sum(ord.total) filter (where ord.status = 'delivered'), 0)
                                                           as total_spend,
      max(ord.user_phone)                                  as user_phone
    from public.orders ord
    where ord.user_id = u.id::text
  ) o on true
  where u.deleted_at is null
  order by u.created_at desc;
end;
$$;

-- One person, in full: everything the list has plus the things too long to put
-- in a row - their saved addresses, and the moderation history that explains why
-- they are or are not blocked today.
create or replace function public.admin_get_user(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_user jsonb;
begin
  perform public.assert_admin();

  select to_jsonb(x) into v_user
    from public.admin_list_users() x
   where x.user_id = p_user_id;

  if v_user is null then
    raise exception 'No such user.' using errcode = 'P0001';
  end if;

  return v_user || jsonb_build_object(
    'addresses', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at desc)
        from public.addresses a
       where a.user_id = p_user_id
    ), '[]'::jsonb),
    'restaurants', coalesce((
      select jsonb_agg(jsonb_build_object('restaurant_id', rs.restaurant_id,
                                          'role', rs.role,
                                          'name', r.name))
        from public.restaurant_staff rs
        left join public.restaurants r on r.id = rs.restaurant_id
       where lower(rs.email) = (v_user ->> 'email')
    ), '[]'::jsonb),
    'moderation', coalesce((
      select jsonb_agg(to_jsonb(b) order by b.created_at desc)
        from public.user_blocks b
       where b.user_id = p_user_id
    ), '[]'::jsonb)
  );
end;
$$;

-- Every order this person has placed, newest first, with its lines.
--
-- Reads `orders` directly rather than through the customer-facing policies,
-- which is the whole point of a console: the customer's own RLS would show an
-- admin nothing at all.
create or replace function public.admin_user_orders(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  perform public.assert_admin();

  return coalesce((
    select jsonb_agg(
      to_jsonb(o) || jsonb_build_object(
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'name', oi.name,
                   'quantity', oi.quantity,
                   'unit_price', oi.unit_price
                 ) order by oi.id)
            from public.order_items oi
           where oi.order_id = o.id
        ), '[]'::jsonb)
      )
      order by o.created_at desc
    )
    from public.orders o
    where o.user_id = p_user_id::text
  ), '[]'::jsonb);
end;
$$;

-- Shut somebody out, or let them back in.
--
-- One function for both directions because they are one decision with a sign,
-- and splitting them would duplicate every rail below.
create or replace function public.admin_set_user_blocked(
  p_user_id uuid,
  p_blocked boolean,
  p_reason  text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_actor  text;
  v_email  text;
  v_is_admin boolean;
begin
  perform public.assert_admin();

  v_actor := lower(auth.jwt() ->> 'email');

  select lower(u.email) into v_email from auth.users u where u.id = p_user_id;
  if v_email is null then
    raise exception 'No such user.' using errcode = 'P0001';
  end if;

  if p_blocked then
    if v_email = v_actor then
      raise exception 'You cannot block yourself.' using errcode = 'P0001';
    end if;

    select true into v_is_admin
      from public.platform_admins pa
     where lower(pa.email) = v_email;

    if v_is_admin then
      raise exception
        'This person is a Zopiqnow admin. Remove their admin access first.'
        using errcode = 'P0001';
    end if;
  end if;

  update auth.users
     set banned_until = case when p_blocked
                             then now() + interval '100 years'
                             else null
                        end
   where id = p_user_id;

  -- A ban stops new tokens; it does not reach into a phone that already holds
  -- one. Dropping the sessions is what makes the next refresh fail.
  if p_blocked then
    delete from auth.sessions where user_id = p_user_id;
  end if;

  insert into public.user_blocks (user_id, user_email, action, reason, actor_email)
  values (
    p_user_id,
    v_email,
    case when p_blocked then 'block' else 'unblock' end,
    nullif(trim(coalesce(p_reason, '')), ''),
    coalesce(v_actor, 'unknown')
  );
end;
$$;

-- The block has to bite before the token expires.
--
-- Same shape as 0084's cash refusal and 0085's payment guard: a `before insert`
-- on `orders`, so no client version and no stale access token can get an order
-- past it. Without this, blocking somebody mid-session leaves them ordering for
-- up to an hour.
create or replace function public.orders_reject_blocked_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if exists (
    select 1 from auth.users u
     where u.id::text = new.user_id
       and u.banned_until is not null
       and u.banned_until > now()
  ) then
    raise exception 'This account has been blocked. Contact support@zopiqnow.com.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_reject_blocked_user on public.orders;
create trigger orders_reject_blocked_user
  before insert on public.orders
  for each row execute function public.orders_reject_blocked_user();

-- Grants.
--
-- Every function here is executable by `authenticated` and guards itself with
-- `assert_admin` in its own body, which is how the rest of this console works:
-- PostgREST will happily let any signed-in customer call an `admin_` function,
-- so the check has to be inside it. The sweep in 0087 confirmed all 70-odd of
-- them do; these four keep that true.
--
-- And each one is revoked from PUBLIC explicitly, because functions in this
-- database are *born* executable by PUBLIC and `alter default privileges` does
-- not prevent it. See 0087 - that is a standing rule, not a flourish.

revoke execute on function public.admin_list_users() from public;
revoke execute on function public.admin_get_user(uuid) from public;
revoke execute on function public.admin_user_orders(uuid) from public;
revoke execute on function public.admin_set_user_blocked(uuid, boolean, text) from public;
revoke execute on function public.orders_reject_blocked_user() from public;

grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.admin_get_user(uuid) to authenticated;
grant execute on function public.admin_user_orders(uuid) to authenticated;
grant execute on function public.admin_set_user_blocked(uuid, boolean, text) to authenticated;
