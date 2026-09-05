-- ---------------------------------------------------------------------------
-- 0157 — one box that finds anything.
-- ---------------------------------------------------------------------------
-- The console has four search boxes and no search. The live board finds an order
-- by id or phone; All orders finds one by id, phone or invoice; People filters a
-- list it has already downloaded; the Riders roster has no box at all. Each one
-- searches the screen it is on, which means every lookup starts with a guess
-- about which screen the answer is on.
--
-- That guess is the whole problem. A phone number rings in and it belongs to a
-- customer, or to the rider carrying their order, or to the restaurant that has
-- not accepted it, and the person answering does not know which until they have
-- looked. Four boxes make that three wrong turns.
--
-- ## What it recognises
--
-- The query is not parsed into a grammar; every arm below is simply asked, and
-- the ones that match answer. Typing `ZPQ-1187` matches an order and nothing
-- else because nothing else looks like that. Typing `9358455193` matches the
-- customer, their orders, and any rider carrying that number — which is not
-- ambiguity to be resolved, it is the answer.
--
--   * **An order id**, exact or as a prefix.
--   * **A phone number**, on its last digits, with or without `+91`. Stripped to
--     digits on both sides, so `+91 93584 55193` and `9358455193` are one query.
--   * **An email**, anywhere in it.
--   * **A name** — a restaurant's, a rider's, or a customer's.
--
-- ## What it does not do
--
-- No menu items, no coupons, no gift shops. Those are catalogue lookups on
-- screens that already list everything they own; this is for the four things an
-- ops question is ever *about*. Adding a fifth kind is one `union all` when
-- somebody actually wants one.
--
-- ## The guard
--
-- Two characters minimum, and a digits-only arm that refuses an empty digit
-- string. Without the second, an all-letters query strips to `''` and
-- `phone like '%'` matches every person on the platform — the same trap
-- `admin_orders` documents, restated here because this function has four more
-- places to fall into it.
-- ---------------------------------------------------------------------------

create or replace function public.admin_search(p_query text)
returns table (
  -- What was found, which is also how the console knows where to send you.
  kind text,
  -- The thing to navigate to: an order id, a restaurant id, an email.
  id text,
  title text,
  subtitle text,
  -- The right-hand column: a status, a total, a date. Never the reason for the
  -- match — a search result that explains itself is a result that needed to.
  detail text
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_q      text;
  v_digits text;
begin
  perform public.assert_admin();

  v_q := nullif(trim(coalesce(p_query, '')), '');

  -- One character matches half the platform and is never what somebody meant.
  if v_q is null or length(v_q) < 2 then
    return;
  end if;

  v_digits := nullif(regexp_replace(v_q, '[^0-9]', '', 'g'), '');

  return query
  -- Orders first, always. Every other kind is a way of *getting* to an order.
  (
    select 'order', o.id, o.id,
           o.restaurant_name || ' · ' || o.delivery_to,
           to_char(o.created_at, 'DD Mon') || ' · ' || o.status
      from public.orders o
     where upper(o.id) like upper(v_q) || '%'
        or (v_digits is not null and o.user_phone like '%' || v_digits)
        or upper(coalesce(o.invoice_no, '')) = upper(v_q)
     order by o.created_at desc
     limit 6
  )
  union all
  (
    select 'restaurant', r.id, r.name,
           coalesce(r.address_line || ', ', '') || coalesce(r.city, ''),
           case
             when not r.is_active then 'delisted'
             when r.accepting_orders then 'open'
             else 'paused'
           end
      from public.restaurants r
     where r.name ilike '%' || v_q || '%'
        or r.city ilike '%' || v_q || '%'
        or (v_digits is not null and r.contact_phone like '%' || v_digits)
     order by r.name
     limit 5
  )
  union all
  (
    select 'rider', dp.email, dp.name,
           dp.email || coalesce(' · ' || dp.phone, ''),
           case when dp.is_active then
             case when dp.is_online then 'online' else 'offline' end
           else 'suspended' end
      from public.delivery_partners dp
     where dp.name ilike '%' || v_q || '%'
        or dp.email ilike '%' || v_q || '%'
        or (v_digits is not null and dp.phone like '%' || v_digits)
     order by dp.name
     limit 5
  )
  union all
  (
    -- People, minus the ones already answered above. A rider matched by name
    -- would otherwise appear twice — once as the rider they are on the road and
    -- once as the account they sign in with — and two rows for one person is a
    -- choice nobody wants to make.
    -- The email, not the uuid, for the same reason `rider` returns one: `id` on
    -- this function is "the handle the console navigates by", and the People
    -- screen finds a person by email, name or phone. A uuid is the one thing
    -- about a customer that no screen in the console can look up.
    select 'customer', coalesce(lower(u.email), nullif(u.phone, ''), u.id::text),
           coalesce(
             nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
             nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
             lower(u.email)),
           lower(u.email) || coalesce(' · ' || nullif(u.phone, ''), ''),
           case
             when u.banned_until is not null and u.banned_until > now() then 'blocked'
             else to_char(u.created_at, 'DD Mon YYYY')
           end
      from auth.users u
     where u.deleted_at is null
       and not exists (
         select 1 from public.delivery_partners d where lower(d.email) = lower(u.email)
       )
       and (
         lower(u.email) like '%' || lower(v_q) || '%'
         or u.raw_user_meta_data ->> 'full_name' ilike '%' || v_q || '%'
         or u.raw_user_meta_data ->> 'name' ilike '%' || v_q || '%'
         or (v_digits is not null and u.phone like '%' || v_digits)
         -- The phone a customer ordered with, which is often the only one they
         -- have — `auth.users.phone` is empty for anyone who signed in by email.
         or (v_digits is not null and exists (
              select 1 from public.orders o2
               where o2.user_id = u.id::text and o2.user_phone like '%' || v_digits
            ))
       )
     order by u.created_at desc
     limit 5
  );
end;
$fn$;

comment on function public.admin_search(text) is
  '0157: one query across orders, restaurants, riders and people. Matches an order id, a phone on its last digits, an email, or a name.';

-- Born executable by PUBLIC *and* with a default grant to `authenticated`
-- (0093). Shut both routes, then reopen the one the console signs in on.
revoke all on function public.admin_search(text) from public, anon, authenticated;
grant execute on function public.admin_search(text) to authenticated;
