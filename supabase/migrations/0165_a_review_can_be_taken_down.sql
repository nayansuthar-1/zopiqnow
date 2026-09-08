-- ---------------------------------------------------------------------------
-- 0165 — a review can be taken down.
-- ---------------------------------------------------------------------------
-- `reviews` has existed since 0062 and the console has only ever seen the
-- average it computes. The vendor reads their own sentences (`vendor_reviews`),
-- a customer reads a kitchen's (`restaurant_reviews`), and the platform — the
-- one party a complaint about a review is addressed to — reads nothing.
--
-- A review that names a rider, carries abuse, or is retaliation for a refused
-- refund has to be removable, and removing it has to leave the ratings honest.
--
-- ## Removal is a delete, not a hidden flag
--
-- A `hidden_at` column would be the softer choice and the wrong one here: three
-- readers already select from this table (`restaurant_reviews`, `vendor_reviews`
-- and 0154's order page), each would have to learn the flag, and the day one of
-- them is written without it the removed review is back in front of customers.
-- A delete is true everywhere at once.
--
-- Nothing is lost by it. This migration puts the standard audit trigger on the
-- table first, so a removed review's whole row is kept in `admin_actions`
-- forever — where 0164's screen now reads it — and `admin_delete_review` writes
-- a second, named row carrying the reason and the sentence that was removed.
-- The trigger also catches the review that goes when an order is deleted, which
-- until now vanished silently.
--
-- ## The ratings, and the one case the trigger cannot answer
--
-- `reviews_recompute_ratings` (0062) already fires on delete and fixes both the
-- restaurant's average and the rider's. It has one deliberate hole: the
-- restaurant update is guarded by `agg.n > 0`, so that a **seeded** rating
-- survives until a real review replaces it. Removing a kitchen's only review
-- therefore leaves the average it computed standing with nothing behind it —
-- one abusive 1★, taken down, would be that kitchen's permanent score.
--
-- So this function finishes the job the trigger deliberately does not: when the
-- last review of a restaurant is removed, the rating goes back to `0.0` with a
-- count of `0`, which is exactly the state eleven of the twelve kitchens are in
-- today and which the apps already render as "not rated". The trigger itself is
-- left alone — its guard is right for the customer path it was written for.
--
-- ⚠️ **The same hole is still open on `delete_my_account` (0081)**, which
-- deletes a customer's reviews without this correction. Named rather than fixed:
-- it is a different path with different rules about what a departing customer
-- may take with them, and folding it in here would decide that quietly.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- The trail, first — so that nothing below can remove a review off the record.
-- ---------------------------------------------------------------------------
-- `order_id` is this table's primary key, which is what the generic recorder
-- wants told (0092).
drop trigger if exists reviews_audit_delete on public.reviews;
create trigger reviews_audit_delete after delete on public.reviews
  for each row execute function public.record_admin_action('order_id');

-- ---------------------------------------------------------------------------
-- The queue.
-- ---------------------------------------------------------------------------
-- Newest first, because this is a moderation queue and not a report: what
-- arrived while nobody was looking is the thing to look at.
--
-- The refund status rides along because it is the context for the review this
-- screen exists to catch — "one star, and there is a refused refund on the same
-- order" is one fact, and an admin who has to open another screen to learn the
-- second half of it will judge the first half alone.
create or replace function public.admin_reviews(
  p_restaurant_id text default null,
  p_min_rating    integer default null,
  p_max_rating    integer default null,
  p_with_comment  boolean default false,
  p_limit         integer default 50,
  p_offset        integer default 0
)
returns table (
  order_id        text,
  restaurant_id   text,
  restaurant_name text,
  food_rating     smallint,
  rider_rating    smallint,
  comment         text,
  customer_name   text,
  customer_phone  text,
  rider_name      text,
  partner_email   text,
  refund_status   text,
  order_total     integer,
  created_at      timestamptz,
  total_count     bigint
)
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  v_restaurant text;
  v_limit      integer;
begin
  perform public.assert_admin();

  v_restaurant := nullif(trim(coalesce(p_restaurant_id, '')), '');
  v_limit      := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  with matched as (
    select rv.order_id, rv.restaurant_id, rv.food_rating, rv.rider_rating,
           rv.comment, rv.partner_email, rv.user_id, rv.created_at
      from public.reviews rv
     where (v_restaurant   is null or rv.restaurant_id = v_restaurant)
       and (p_min_rating   is null or rv.food_rating >= p_min_rating)
       and (p_max_rating   is null or rv.food_rating <= p_max_rating)
       -- `false` means "don't narrow", not "only those without a comment" —
       -- a review with nothing written on it is still a rating and still
       -- belongs in the list.
       and (not coalesce(p_with_comment, false)
            or nullif(trim(coalesce(rv.comment, '')), '') is not null)
  )
  select m.order_id, m.restaurant_id, r.name, m.food_rating, m.rider_rating,
         m.comment,
         -- What the People screen calls this customer, by the same rules (0070).
         nullif(trim(coalesce(
           u.raw_user_meta_data ->> 'full_name',
           u.raw_user_meta_data ->> 'name', '')), ''),
         o.user_phone,
         dp.name,
         m.partner_email,
         -- The newest refund on the order, if any. One review, one order, so
         -- there is no aggregate to take — only a most-recent state.
         (select rf.status from public.refunds rf
           where rf.order_id = m.order_id
           order by rf.created_at desc limit 1),
         o.total,
         m.created_at,
         count(*) over () as total_count
    from matched m
    join public.restaurants r        on r.id = m.restaurant_id
    left join public.orders o        on o.id = m.order_id
    -- `user_id` is text on `reviews` and a uuid on `auth.users`; the cast goes
    -- on the uuid side so a row whose user_id is not a uuid cannot raise.
    left join auth.users u           on u.id::text = m.user_id
    left join public.delivery_partners dp on dp.email = m.partner_email
   order by m.created_at desc, m.order_id desc
   limit v_limit offset greatest(coalesce(p_offset, 0), 0);
end;
$fn$;

comment on function public.admin_reviews(text, integer, integer, boolean, integer, integer) is
  '0165: the review queue — every review with its restaurant, customer, rider and the order''s refund state, newest first. `total_count` is the size of the whole match.';

revoke all on function public.admin_reviews(text, integer, integer, boolean, integer, integer)
  from public, anon, authenticated;
grant execute on function public.admin_reviews(text, integer, integer, boolean, integer, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Are reviews arriving at all?
-- ---------------------------------------------------------------------------
-- The question this screen answers before it answers any other. Four reviews on
-- one restaurant out of twelve is not a moderation problem, it is a product
-- fact, and a page that opens on a nearly-empty list without saying so reads as
-- a broken page.
create or replace function public.admin_review_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  v jsonb;
begin
  perform public.assert_admin();

  select jsonb_build_object(
    'reviews',            count(*),
    'with_comment',       count(*) filter (
                            where nullif(trim(coalesce(comment, '')), '') is not null),
    'rider_rated',        count(*) filter (where rider_rating is not null),
    'avg_food',           round(avg(food_rating)::numeric, 1),
    'avg_rider',          round(avg(rider_rating)::numeric, 1),
    'restaurants_rated',  count(distinct restaurant_id),
    'first_at',           min(created_at),
    'latest_at',          max(created_at),
    -- The denominator, and the point: a delivered order is one that could have
    -- been reviewed. Reviews over that is the arrival rate.
    'reviewable_orders',  (select count(*) from public.orders
                            where status = 'delivered')
  ) into v
    from public.reviews;

  return v;
end;
$fn$;

comment on function public.admin_review_summary() is
  '0165: how many reviews exist, how many carry a sentence, the averages, and how many delivered orders could have been reviewed.';

revoke all on function public.admin_review_summary() from public, anon, authenticated;
grant execute on function public.admin_review_summary() to authenticated;

-- ---------------------------------------------------------------------------
-- Taking one down.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_review(
  p_order_id text,
  p_reason   text default ''
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_review     public.reviews%rowtype;
  v_restaurant public.restaurants%rowtype;
  v_reason     text;
  v_actor      text;
  v_left       integer;
begin
  perform public.assert_admin();

  v_reason := left(trim(coalesce(p_reason, '')), 200);
  if v_reason = '' then
    -- The only record of why a customer's words were removed. A blank one turns
    -- the trail into a list of disappearances.
    raise exception 'Say why this review is being removed.' using errcode = 'P0001';
  end if;

  select * into v_review from public.reviews where order_id = p_order_id;
  if not found then
    raise exception 'No review was left on %.', p_order_id using errcode = 'P0001';
  end if;

  select * into v_restaurant
    from public.restaurants where id = v_review.restaurant_id;

  v_actor := coalesce(
    lower(nullif(trim(coalesce(auth.jwt() ->> 'email', '')), '')), 'system');

  -- The named row: why, and what it said. The `reviews_audit_delete` trigger
  -- writes the whole row beside it a moment later, so the trail carries both
  -- the account and the evidence.
  insert into public.admin_actions
    (actor_email, action, target_type, target_id, detail)
  values (
    v_actor, 'review_removed', 'reviews', v_review.order_id,
    jsonb_build_object(
      'reason', v_reason,
      'restaurant', coalesce(v_restaurant.name, v_review.restaurant_id),
      'food_rating', v_review.food_rating,
      'rider_rating', v_review.rider_rating,
      'said', coalesce(v_review.comment, ''))
  );

  -- 0062's trigger recomputes the restaurant's average and the rider's on the
  -- way out.
  delete from public.reviews where order_id = v_review.order_id;

  select count(*)::integer into v_left
    from public.reviews where restaurant_id = v_review.restaurant_id;

  if v_left = 0 then
    -- The case the trigger's `agg.n > 0` guard deliberately skips. Unrated is a
    -- state the apps already draw; a score with no review behind it is not.
    update public.restaurants
       set rating = 0, rating_count = 0
     where id = v_review.restaurant_id;

    return format(
      'The review on %s is removed. %s now has no reviews and shows as unrated.',
      v_review.order_id, coalesce(v_restaurant.name, v_review.restaurant_id));
  end if;

  return format(
    'The review on %s is removed. %s is now %s from %s review%s.',
    v_review.order_id,
    coalesce(v_restaurant.name, v_review.restaurant_id),
    (select rating from public.restaurants where id = v_review.restaurant_id),
    v_left,
    case when v_left = 1 then '' else 's' end);
end;
$fn$;

comment on function public.admin_delete_review(text, text) is
  '0165: removes one review, with a reason that is required and recorded. The ratings are recomputed, and a restaurant left with no reviews goes back to unrated rather than keeping an average with nothing behind it.';

revoke all on function public.admin_delete_review(text, text) from public, anon, authenticated;
grant execute on function public.admin_delete_review(text, text) to authenticated;
