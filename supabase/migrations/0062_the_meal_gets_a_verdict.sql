-- ---------------------------------------------------------------------------
-- 0062 — the meal gets a verdict. (Phase B6, ratings and reviews)
-- ---------------------------------------------------------------------------
-- `restaurants.rating` has been a column since 0001 and a *fiction* since 0001:
-- a number typed into a seed file, next to a `rating_count` that has been 0 on
-- every row this platform has ever served. Every card in the customer app has
-- been showing a figure nobody earned. This migration makes that number mean
-- something, and the way it does it is the only interesting decision here:
--
--   **No app ever writes a rating.** Not the customer app, not the vendor app,
--   not an admin. A rating is an aggregate, and an aggregate that a client can
--   set is not an aggregate — it is a claim. `reviews` is the only writable
--   thing, `submit_order_review` is the only way to write it, and the number on
--   the restaurant card is recomputed by a trigger from the rows underneath.
--   There is no code path anywhere that can raise a restaurant's rating without
--   a delivered order behind it.
--
-- **One review per delivered order, and a window.** The primary key is the
-- order id — not `(user, restaurant)` — so reviewing is something you do to a
-- *meal*, not to a place you once visited. Ten orders earn ten reviews; one
-- order never earns two. The review may be edited for an hour and is frozen
-- after that, because a review a vendor has already read and replied to should
-- not be able to become a different review, and because "I'll fix it later"
-- is not a promise a public record should keep.
--
-- **The rider is rated separately, and optionally.** Food and delivery are two
-- different people's work and one star for both would blame a kitchen for a
-- slow bike. `rider_rating` is nullable: an order carried by nobody (or by
-- someone the customer would rather not judge) still gets its food rated.
--
-- **The seeded numbers are not overwritten.** A restaurant with no reviews
-- keeps the rating it was seeded with rather than dropping to 0.0 — a brand new
-- kitchen showing "0.0 ★" would be a lie in the opposite direction. The moment
-- the first real review lands, the real average takes over and never gives the
-- seed back.

-- ===========================================================================
-- A. The rider gains the two columns the restaurant has had since 0001.
-- ===========================================================================
-- Same shape, same constraints, same reason: the app shows a figure and the
-- database owns it. `0` with a count of `0` reads as "not rated yet" and the
-- rider app renders it as exactly that — not as a one-star partner.
alter table public.delivery_partners
  add column if not exists rating       numeric(2,1) not null default 0,
  add column if not exists rating_count integer      not null default 0;

alter table public.delivery_partners
  drop constraint if exists delivery_partners_rating_is_out_of_five;
alter table public.delivery_partners
  add constraint delivery_partners_rating_is_out_of_five
  check (rating >= 0 and rating <= 5);

alter table public.delivery_partners
  drop constraint if exists delivery_partners_rating_count_is_positive;
alter table public.delivery_partners
  add constraint delivery_partners_rating_count_is_positive
  check (rating_count >= 0);

-- ===========================================================================
-- B. The review.
-- ===========================================================================
create table if not exists public.reviews (
  -- The order, not a serial. One meal, one verdict — enforced by the key rather
  -- than by a unique index bolted on beside a surrogate id, because there is no
  -- second review of the same order that we would ever want to store.
  order_id       text primary key references public.orders (id) on delete cascade,

  -- Denormalised from the order at write time, all three. The order is the
  -- source and it cannot change, so these can never drift — and copying them
  -- means the recompute trigger and the vendor's read never have to join back
  -- through `orders`, a table neither of them is allowed to select from.
  user_id        text not null,
  restaurant_id  text not null references public.restaurants (id),
  partner_email  text references public.delivery_partners (email),

  food_rating    smallint not null check (food_rating between 1 and 5),

  -- Null is a real answer: no rider carried this, or the customer rated the
  -- food and left the delivery alone. It is *not* zero — a zero would drag an
  -- average down for an opinion nobody offered.
  rider_rating   smallint check (rider_rating between 1 and 5),

  comment        text check (comment is null or length(comment) <= 500),

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- The hour. Stored rather than derived from `created_at` so that the rule is
  -- readable in the row itself: a screen can grey out the edit button by
  -- reading a timestamp instead of re-implementing an interval the database
  -- also implements. The two can never disagree because only the trigger below
  -- enforces it, and it reads this column.
  editable_until timestamptz not null default now() + interval '1 hour'
);

create index if not exists reviews_restaurant_idx
  on public.reviews (restaurant_id, created_at desc);

create index if not exists reviews_partner_idx
  on public.reviews (partner_email, created_at desc)
  where partner_email is not null;

alter table public.reviews enable row level security;

-- 0061's lesson, applied again. Supabase's default privileges hand `anon` and
-- `authenticated` insert/update/delete on every new table in `public`, so this
-- table arrived writable and RLS-with-no-policy is a *weaker* guarantee than
-- no grant at all: the next migration to add one policy for one purpose would
-- silently open all three verbs. Revoke first, grant nothing, and let the
-- functions below be the only door.
revoke all on public.reviews from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The window, enforced where it cannot be skipped.
-- ---------------------------------------------------------------------------
-- A trigger and not a check inside `submit_order_review`, because a check
-- inside the function is a rule that a *second* function — the one somebody
-- writes next year to "fix a typo for support" — would not inherit. The row
-- refuses to change. That is a property of the row, so it lives on the row.
create or replace function public.reviews_are_frozen_after_the_window()
returns trigger
language plpgsql
as $$
begin
  if now() > old.editable_until then
    raise exception 'This review can no longer be changed.' using errcode = 'P0001';
  end if;

  -- What an edit may touch: the opinion. Not who wrote it, not which order it
  -- is about, and not the deadline itself — a writable `editable_until` would
  -- be an edit window that edits its own edit window.
  new.order_id       := old.order_id;
  new.user_id        := old.user_id;
  new.restaurant_id  := old.restaurant_id;
  new.partner_email  := old.partner_email;
  new.created_at     := old.created_at;
  new.editable_until := old.editable_until;
  new.updated_at     := now();

  return new;
end;
$$;

drop trigger if exists reviews_freeze on public.reviews;
create trigger reviews_freeze
  before update on public.reviews
  for each row execute function public.reviews_are_frozen_after_the_window();

-- A review is a record of something that happened, and nothing deletes it —
-- but that is enforced by the *absence* of a delete grant and of any function
-- that deletes, not by a trigger that raises. A `before delete` guard here
-- would also fire on the `on delete cascade` from `orders` and turn "this order
-- was removed" into an error nobody could clear.

-- ===========================================================================
-- C. The recompute. The only writer of either `rating` column.
-- ===========================================================================
-- Recomputed from scratch — `avg()` over the rows — rather than nudged
-- incrementally from the old average. An incremental update is faster and is
-- wrong the first time anything else touches the table: a backfill, a support
-- correction, a cascade delete. A full average over the reviews of one
-- restaurant is an index scan of a few hundred rows, and it is *always* the
-- truth about what is stored.
create or replace function public.reviews_recompute_ratings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_partners   text[];
begin
  -- `OLD` is unassigned on an insert and `NEW` on a delete, and reading the
  -- wrong one is an error rather than a null. Hence the explicit branch.
  if tg_op = 'DELETE' then
    v_restaurant := old.restaurant_id;
    v_partners   := array_remove(array[old.partner_email]::text[], null);
  elsif tg_op = 'UPDATE' then
    v_restaurant := new.restaurant_id;
    -- Both sides of an edit: a customer who moves their rider rating from one
    -- delivery to another must leave the first rider's average correct too.
    v_partners   := array_remove(
      array[new.partner_email, old.partner_email]::text[], null
    );
  else
    v_restaurant := new.restaurant_id;
    v_partners   := array_remove(array[new.partner_email]::text[], null);
  end if;

  -- `agg.n > 0` is the seed clause: the update simply does not fire for a
  -- restaurant with no reviews, so a seeded rating survives until a real one
  -- replaces it, and can never come back once it has.
  update public.restaurants r
     set rating       = agg.avg_rating,
         rating_count = agg.n
    from (
      select round(avg(food_rating)::numeric, 1) as avg_rating,
             count(*)                            as n
        from public.reviews
       where restaurant_id = v_restaurant
    ) agg
   where r.id = v_restaurant
     and agg.n > 0;

  -- Correlated subqueries and not a grouped join, because a `group by` produces
  -- no row for a rider whose last rating just went away — and no row means no
  -- update, which means a score that outlives the reviews behind it.
  update public.delivery_partners p
     set rating = coalesce((
           select round(avg(rv.rider_rating)::numeric, 1)
             from public.reviews rv
            where rv.partner_email = p.email
              and rv.rider_rating is not null
         ), 0),
         rating_count = (
           select count(*)
             from public.reviews rv
            where rv.partner_email = p.email
              and rv.rider_rating is not null
         )
   where p.email = any (v_partners);

  return null;
end;
$$;

drop trigger if exists reviews_sync_ratings on public.reviews;
create trigger reviews_sync_ratings
  after insert or update or delete on public.reviews
  for each row execute function public.reviews_recompute_ratings();

-- ===========================================================================
-- D. Writing one.
-- ===========================================================================
-- How long a meal stays reviewable. Long enough that "I'll do it tomorrow"
-- works, short enough that a rating is about food somebody can still remember.
create or replace function public.review_window_days()
returns integer language sql immutable as $$ select 14 $$;

-- `integer` arguments and not `smallint`: PostgREST binds a JSON number to
-- `integer` and would refuse the call outright on a `smallint` parameter. The
-- column is still `smallint` — the narrowing happens on the way in, where the
-- range check also lives.
create or replace function public.submit_order_review(
  p_order_id     text,
  p_food_rating  integer,
  p_rider_rating integer default null,
  p_comment      text    default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      text;
  v_order     public.orders;
  v_partner   text;
  v_delivered timestamptz;
  v_comment   text;
  v_rider     integer;
begin
  v_user := auth.uid()::text;
  if v_user is null then
    raise exception 'Please sign in to leave a review.' using errcode = 'P0001';
  end if;

  select * into v_order from public.orders where id = p_order_id;

  -- One sentence for "no such order" and for "somebody else's order". A
  -- different message for each would turn this function into a way to ask
  -- whether an order id exists.
  if not found or v_order.user_id <> v_user then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  if v_order.status <> 'delivered' then
    raise exception 'You can review an order once it has been delivered.'
      using errcode = 'P0001';
  end if;

  if p_food_rating is null or p_food_rating not between 1 and 5 then
    raise exception 'Please pick a rating from 1 to 5.' using errcode = 'P0001';
  end if;

  -- Who carried it, and when it landed. A cancelled delivery is excluded: the
  -- rider who dropped the job halfway is not the rider being rated.
  select d.partner_email, d.delivered_at
    into v_partner, v_delivered
    from public.deliveries d
   where d.order_id = p_order_id
     and d.state = 'delivered'
   order by d.delivered_at desc
   limit 1;

  -- `created_at` as the fallback for an order marked delivered without a rider
  -- row behind it. It is the wrong timestamp by an hour and the right one by a
  -- fortnight, which is the resolution this window is measured at.
  if now() > coalesce(v_delivered, v_order.created_at)
             + (public.review_window_days() || ' days')::interval then
    raise exception 'This order is too old to review.' using errcode = 'P0001';
  end if;

  -- A rider rating with no rider is discarded rather than refused: the customer
  -- did nothing wrong, and there is simply nobody for the star to land on.
  v_rider := case when v_partner is null then null else p_rider_rating end;
  if v_rider is not null and v_rider not between 1 and 5 then
    raise exception 'Please rate your rider from 1 to 5.' using errcode = 'P0001';
  end if;

  v_comment := nullif(trim(coalesce(p_comment, '')), '');
  if length(v_comment) > 500 then
    raise exception 'Please keep your review under 500 characters.'
      using errcode = 'P0001';
  end if;

  insert into public.reviews (
    order_id, user_id, restaurant_id, partner_email,
    food_rating, rider_rating, comment
  ) values (
    p_order_id, v_user, v_order.restaurant_id, v_partner,
    p_food_rating::smallint, v_rider::smallint, v_comment
  )
  -- An edit, not a second review. The freeze trigger fires on this path and is
  -- what turns "you may change your mind" into "for an hour".
  on conflict (order_id) do update
     set food_rating  = excluded.food_rating,
         rider_rating = excluded.rider_rating,
         comment      = excluded.comment;

  -- The kitchen hears about it. Wrapped for 0047's reason: the review is the
  -- thing that matters and a failed courtesy must never roll it back.
  begin
    insert into public.notifications
      (audience, restaurant_id, order_id, kind, title, body)
    values (
      'restaurant', v_order.restaurant_id, p_order_id, 'review',
      p_food_rating || '★ review',
      coalesce(v_comment, 'A customer rated order ' || p_order_id || '.')
    );
  exception when others then
    null;
  end;
end;
$$;

grant execute on function public.submit_order_review(text, integer, integer, text)
  to authenticated;

-- The `kind` set grows by one. Every app maps an unknown kind to a neutral row
-- (0047), so a vendor build that predates this shows the review as a plain
-- notification rather than crashing on it.
alter table public.notifications
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check
    check (kind in (
      'new_order',      -- vendor: a customer placed an order (0021)
      'system',         -- anyone: a catch-all notice
      'order_update',   -- customer: their order changed status (0047)
      'order_live',     -- customer: silent tick for the live card (0052)
      'job_offer',      -- rider: this job is yours if you take it now (0056)
      'job_available',  -- rider: a delivery reached the open board
      'job_cancelled',  -- rider: a job they were holding was called off (0051)
      'payout',         -- rider: a payout was paid
      'account',        -- rider: their partner account was activated/deactivated
      'settlement',     -- vendor: a weekly settlement was paid
      'message',        -- customer/rider: the other one said something (0061)
      'review'          -- vendor: a customer reviewed one of its orders (0062)
    ));

-- ===========================================================================
-- E. Reading them back.
-- ===========================================================================
-- The customer's own, so the screen can show "you rated this 4★" and offer the
-- edit while the hour lasts. `editable_until` goes out with it — the button is
-- greyed from the timestamp, and the trigger is what actually refuses.
create or replace function public.my_order_review(p_order_id text)
returns table (
  food_rating    smallint,
  rider_rating   smallint,
  comment        text,
  created_at     timestamptz,
  editable_until timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select r.food_rating, r.rider_rating, r.comment, r.created_at, r.editable_until
    from public.reviews r
   where r.order_id = p_order_id
     and r.user_id = auth.uid()::text;
$$;

grant execute on function public.my_order_review(text) to authenticated;

-- Whether this order is *reviewable* — the one question the order screen asks
-- before it shows anything at all. Answered in the database and not in Dart,
-- because "delivered, mine, inside the window" is three rules that already have
-- one home, and a second copy on a phone is a copy that goes stale on the day
-- the window changes.
create or replace function public.order_review_state(p_order_id text)
returns table (
  can_review   boolean,
  has_rider    boolean,
  rider_name   text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user      text;
  v_order     public.orders;
  v_partner   text;
  v_delivered timestamptz;
begin
  v_user := auth.uid()::text;
  if v_user is null then
    return;
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.user_id <> v_user or v_order.status <> 'delivered' then
    return;
  end if;

  select d.partner_email, d.delivered_at
    into v_partner, v_delivered
    from public.deliveries d
   where d.order_id = p_order_id
     and d.state = 'delivered'
   order by d.delivered_at desc
   limit 1;

  return query
    select now() <= coalesce(v_delivered, v_order.created_at)
                    + (public.review_window_days() || ' days')::interval,
           v_partner is not null,
           (select p.name from public.delivery_partners p where p.email = v_partner);
end;
$$;

grant execute on function public.order_review_state(text) to anon, authenticated;

-- The public wall on a restaurant page. `anon` too: browsing a restaurant does
-- not require an account, and the reviews are the most useful thing on it.
--
-- What deliberately does *not* come out: the order id, the user id, the rider's
-- rating and the rider's name. A public list keyed by order id would let anyone
-- correlate a review with a delivery; the rider's score is between the rider
-- and us. The reviewer is a first name, because "Priya" is a person and
-- "priya.k.1994@gmail.com" is an identity we were not asked to publish.
create or replace function public.restaurant_reviews(
  p_restaurant_id text,
  p_limit         integer default 20
) returns table (
  reviewer    text,
  food_rating smallint,
  comment     text,
  created_at  timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
           nullif(split_part(trim(coalesce(
             u.raw_user_meta_data ->> 'full_name',
             u.raw_user_meta_data ->> 'name',
             ''
           )), ' ', 1), ''),
           'Zopiqnow customer'
         ),
         r.food_rating,
         r.comment,
         r.created_at
    from public.reviews r
    left join auth.users u on u.id::text = r.user_id
   where r.restaurant_id = p_restaurant_id
   order by r.created_at desc
   limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

grant execute on function public.restaurant_reviews(text, integer)
  to anon, authenticated;

-- The kitchen's own room. Everything the public list withholds *except* the
-- customer's identity: a vendor gets the order id (so it can look the meal up
-- in its own history) and the rider's score (so "the food was cold" can be read
-- next to a 2★ delivery), and still never learns who wrote it.
create or replace function public.vendor_reviews(p_limit integer default 50)
returns table (
  order_id     text,
  food_rating  smallint,
  rider_rating smallint,
  comment      text,
  created_at   timestamptz
)
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
    raise exception 'You are not signed in to a restaurant.' using errcode = 'P0001';
  end if;

  return query
    select r.order_id, r.food_rating, r.rider_rating, r.comment, r.created_at
      from public.reviews r
     where r.restaurant_id = v_restaurant
     order by r.created_at desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

grant execute on function public.vendor_reviews(integer) to authenticated;

-- The kitchen's headline figures, for the top of that room. A separate call
-- rather than a sum done on the phone, because "4.3 from 128" must be the same
-- number the customer sees on the card, and there is one place that is true.
create or replace function public.vendor_review_summary()
returns table (
  rating       numeric,
  rating_count integer,
  five_star    integer,
  four_star    integer,
  three_star   integer,
  two_star     integer,
  one_star     integer
)
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
    raise exception 'You are not signed in to a restaurant.' using errcode = 'P0001';
  end if;

  return query
    select coalesce(round(avg(r.food_rating)::numeric, 1), 0)::numeric,
           count(*)::integer,
           count(*) filter (where r.food_rating = 5)::integer,
           count(*) filter (where r.food_rating = 4)::integer,
           count(*) filter (where r.food_rating = 3)::integer,
           count(*) filter (where r.food_rating = 2)::integer,
           count(*) filter (where r.food_rating = 1)::integer
      from public.reviews r
     where r.restaurant_id = v_restaurant;
end;
$$;

grant execute on function public.vendor_review_summary() to authenticated;

-- The rider's own score needs no function at all: 0025 already lets a partner
-- select their own row, and the two columns added at the top of this file ride
-- along on the read the profile screen already makes. "Not rated yet" is a
-- `rating_count` of 0, which the app renders as a dash rather than as 0.0.
