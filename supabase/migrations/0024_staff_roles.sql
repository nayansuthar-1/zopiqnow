-- Phase 8a: not everyone who works at a restaurant is the restaurant.
--
-- Since 0009 there has been exactly one kind of vendor. A row in
-- `restaurant_staff` meant "you are this kitchen", and every policy written
-- since has asked the same single question — `staff_restaurant_id()` — and been
-- satisfied by any answer that was not null. That was right while a restaurant
-- was one person with one tablet. It stops being right the moment the owner
-- hands a second tablet to a cook, because the cook can then read what the
-- restaurant is paid.
--
-- So this migration splits the one kind of vendor into two, and the split is
-- drawn around money and around access itself:
--
--   * `owner`  — everything, including earnings, settlements, and who else may
--                sign in;
--   * `staff`  — the whole working day (queue, history, menu, hours, profile,
--                analytics) and neither of those two things.
--
-- Two roles and not four, deliberately. A role that gates nothing is a lie the
-- UI tells; these two each gate something real and enforced below in Postgres,
-- not merely hidden in the app. More roles can be added later by widening the
-- check constraint — no existing row changes meaning when they are.

-- ---------------------------------------------------------------------------
-- The column, and why its default is `owner`.
-- ---------------------------------------------------------------------------
-- Every row that exists today was written by ops onboarding a restaurant, which
-- means every one of them is the owner. Defaulting to `owner` therefore makes
-- the backfill correct rather than merely convenient: nobody loses access the
-- moment this migration runs, which is the only acceptable outcome for a change
-- that adds authorization to a system that had none.
--
-- It stays the default afterwards for the same reason — the next row ops inserts
-- by hand is the next restaurant's owner. Colleagues are added through the RPC
-- below, which names the role explicitly and never relies on this.
alter table public.restaurant_staff
  add column if not exists role text not null default 'owner';

alter table public.restaurant_staff
  drop constraint if exists restaurant_staff_role_is_known;
alter table public.restaurant_staff
  add constraint restaurant_staff_role_is_known
  check (role in ('owner', 'staff'));

-- ---------------------------------------------------------------------------
-- The second question every policy may now ask.
-- ---------------------------------------------------------------------------
-- The twin of `staff_restaurant_id()`, and for the same reasons: `security
-- definer` so it can read a table that is closed to the API, `stable` so an RLS
-- predicate evaluates it once per statement rather than once per row.
--
-- Null for a customer and for anyone who is not staff, which makes every
-- `staff_role() = 'owner'` test below false-by-unknown for them — the same
-- shape that has kept customers out of the vendor policies since 0009.
create or replace function public.staff_role() returns text
language sql
stable
security definer
set search_path = public
as $$
  select s.role
    from public.restaurant_staff s
   where s.email = lower(auth.jwt() ->> 'email')
$$;

grant execute on function public.staff_role() to authenticated;

-- ---------------------------------------------------------------------------
-- Money is the owner's.
-- ---------------------------------------------------------------------------
-- Narrowing 0017's policy. Everything else about it is unchanged: still
-- select-only, still scoped to the caller's own restaurant, still no
-- insert/update/delete grant anywhere. A settlement is what the platform owes
-- the business, and the business is the owner.
--
-- Note what this does *not* do: `orders` stays readable by all staff, because a
-- cook has to see the ticket to cook it, and a ticket carries a total. The line
-- being drawn is around the restaurant's earnings, not around the price of a
-- biryani.
drop policy if exists "staff read their restaurant's settlements" on public.settlements;
create policy "owners read their restaurant's settlements"
  on public.settlements for select to authenticated
  using (
    restaurant_id = public.staff_restaurant_id()
    and public.staff_role() = 'owner'
  );

-- The live earnings read behind the same screen. Redeclared whole — the body is
-- 0017's, unchanged — because the only way to add a guard to a function is to
-- write the function again.
create or replace function public.vendor_earnings_summary(
  p_from date,
  p_to   date
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_bps        integer;
  v_result     jsonb;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  if public.staff_role() <> 'owner' then
    raise exception 'Only the owner can see earnings.' using errcode = 'P0001';
  end if;

  select commission_bps into v_bps
    from public.restaurants where id = v_restaurant;

  with daily as (
    select
      o.created_at::date          as day,
      count(*)::integer           as orders,
      sum(o.subtotal)::integer    as gross
    from public.orders o
    where o.restaurant_id = v_restaurant
      and o.status = 'delivered'
      and o.created_at::date between p_from and p_to
    group by o.created_at::date
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'commission_bps', v_bps,
    'order_count',  coalesce(sum(d.orders), 0),
    'gross_sales',  coalesce(sum(d.gross), 0),
    'commission',   coalesce(round(sum(d.gross) * v_bps / 10000.0)::integer, 0),
    'net_earnings', coalesce(
                      sum(d.gross) - round(sum(d.gross) * v_bps / 10000.0)::integer,
                      0
                    ),
    'daily', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'day',    d.day,
          'orders', d.orders,
          'gross',  d.gross,
          'net',    d.gross - round(d.gross * v_bps / 10000.0)::integer
        ) order by d.day
      ) filter (where d.day is not null),
      '[]'::jsonb
    )
  ) into v_result
  from daily d;

  return v_result;
end;
$$;

grant execute on function public.vendor_earnings_summary(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Managing the roster: four functions, one shared guard.
-- ---------------------------------------------------------------------------
-- `restaurant_staff` is still not readable through the API and still has no
-- write grant. 0009's reasoning holds exactly: a table anyone could select would
-- let anyone enumerate which address runs which kitchen, and a table anyone
-- could insert into would let the first person to type an email claim a
-- restaurant. Both stay shut. These functions answer narrow questions about the
-- caller's own restaurant and write nothing outside it.
--
-- The guard every one of them opens with, stated once here so the bodies can be
-- read for what they actually do:
--
--   * the caller must be staff somewhere (else: not a partner);
--   * the caller must be an owner (else: refused);
--   * the target must already work at the caller's own restaurant — which is
--     also why no function takes a restaurant id. There is nothing to pass. An
--     owner's authority is over one kitchen and the function derives which.
--
-- And one rule that carries more weight than it looks like it does: **an owner
-- may not act on themselves.** It is written to stop the obvious footgun — the
-- sole owner demoting or deleting themselves and locking the restaurant out of
-- its own earnings with no way back short of a support ticket — but it also
-- quietly guarantees the property you would otherwise have to check for
-- separately: since the caller is always an owner, and the caller is always
-- untouchable, no sequence of these calls can ever leave a restaurant with zero
-- owners. Co-owners can still remove each other; nobody can remove the last one.

create or replace function public.list_restaurant_staff()
returns table (email text, role text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_restaurant text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  if public.staff_role() <> 'owner' then
    raise exception 'Only the owner can manage staff.' using errcode = 'P0001';
  end if;

  return query
    select s.email, s.role, s.created_at
      from public.restaurant_staff s
     where s.restaurant_id = v_restaurant
     -- Owners first, then oldest first: the people who run the place at the top,
     -- and below them the roster in the order it was built.
     order by (s.role = 'owner') desc, s.created_at;
end;
$$;

grant execute on function public.list_restaurant_staff() to authenticated;

-- Add a colleague.
--
-- This is the one function that creates authority rather than adjusting it, so
-- it is worth being precise about why it does not reopen the hole 0009 closed.
-- 0009 refused *self-service* — a stranger typing a restaurant's email and
-- becoming that restaurant. Here the caller already holds the authority being
-- granted, and can only grant it inside the one restaurant they already run.
-- Nothing is claimed; something already owned is shared.
--
-- `email` is the primary key of the table globally, so a person works at exactly
-- one restaurant. An address already on someone else's roster is refused rather
-- than moved: silently reassigning it would let any owner walk a rival's manager
-- off their books, which is precisely the enumeration-and-capture problem in a
-- different coat.
create or replace function public.add_restaurant_staff(
  p_email text,
  p_role  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_email      text;
  v_existing   text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  if public.staff_role() <> 'owner' then
    raise exception 'Only the owner can manage staff.' using errcode = 'P0001';
  end if;

  -- The JWT carries whatever the user typed, and the table's own constraint
  -- demands lowercase. Normalise here so a stray capital is not a failed insert
  -- shown to a human as a database error.
  v_email := lower(trim(p_email));

  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'That doesn''t look like an email address.'
      using errcode = 'P0001';
  end if;

  if p_role not in ('owner', 'staff') then
    raise exception 'Unknown role: %.', p_role using errcode = 'P0001';
  end if;

  select s.restaurant_id into v_existing
    from public.restaurant_staff s where s.email = v_email;

  if v_existing = v_restaurant then
    raise exception '% already works here.', v_email using errcode = 'P0001';
  elsif v_existing is not null then
    -- Deliberately vague about *where*. Which restaurant a given address works
    -- at is exactly the fact 0009 keeps unreadable.
    raise exception '% is already on another restaurant''s team.', v_email
      using errcode = 'P0001';
  end if;

  insert into public.restaurant_staff (email, restaurant_id, role)
  values (v_email, v_restaurant, p_role);
end;
$$;

grant execute on function public.add_restaurant_staff(text, text) to authenticated;

-- Promote or demote someone already on the roster.
create or replace function public.set_staff_role(
  p_email text,
  p_role  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_email      text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  if public.staff_role() <> 'owner' then
    raise exception 'Only the owner can manage staff.' using errcode = 'P0001';
  end if;

  v_email := lower(trim(p_email));

  if p_role not in ('owner', 'staff') then
    raise exception 'Unknown role: %.', p_role using errcode = 'P0001';
  end if;

  if v_email = lower(auth.jwt() ->> 'email') then
    raise exception 'You can''t change your own role.' using errcode = 'P0001';
  end if;

  update public.restaurant_staff
     set role = p_role
   where email = v_email
     and restaurant_id = v_restaurant;

  if not found then
    -- Not "no such person": whether an address is staff anywhere is not this
    -- caller's business unless it is staff *here*.
    raise exception '% is not on your team.', v_email using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.set_staff_role(text, text) to authenticated;

-- Take someone off the roster.
--
-- Their auth account survives — this app never deletes users — and so does any
-- order they touched. All that goes is the row that answers "do you work here",
-- so the next `staff_restaurant_id()` returns null and they land on the
-- not-a-partner screen the app has had since 0009.
create or replace function public.remove_restaurant_staff(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_email      text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  if public.staff_role() <> 'owner' then
    raise exception 'Only the owner can manage staff.' using errcode = 'P0001';
  end if;

  v_email := lower(trim(p_email));

  if v_email = lower(auth.jwt() ->> 'email') then
    raise exception 'You can''t remove yourself.' using errcode = 'P0001';
  end if;

  delete from public.restaurant_staff
   where email = v_email
     and restaurant_id = v_restaurant;

  if not found then
    raise exception '% is not on your team.', v_email using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.remove_restaurant_staff(text) to authenticated;
