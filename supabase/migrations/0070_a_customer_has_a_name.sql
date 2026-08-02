-- 0070 — a customer has a name, and it is theirs to set
--
-- The customer profile has been a lie since it was drawn. `CustomerProfile` was
-- an in-memory `StateNotifier` seeded with 'Zopiq user' and '+91 9876543210';
-- "Save Changes" ran `Future.delayed(seconds: 1)`, showed "Profile updated
-- successfully", and lost everything on the next cold start. The avatar was an
-- icon with a camera badge painted on it and no `onTap`.
--
-- The fix is almost entirely client-side, and deliberately so: **there is no new
-- table here.** The customer's profile lives in `auth.users.raw_user_meta_data`,
-- because that is already where half of it lives and a second home would make
-- the halves disagree.
--
--   * The delivery number is already there, under `delivery_phone`, written by
--     `AuthRepository.setPhone` at checkout and read back as `AuthUser.phone`,
--     which `checkout_page.dart` hands to `place_order` as `p_user_phone`. Put
--     the profile's "Mobile Number" field anywhere else and a customer could
--     correct their number in Account while the rider kept being given the old
--     one. That is not a sync bug to be managed; it is a second source of truth
--     not to be created.
--   * The name is already read from there — by this very function, below.
--
-- **Why new keys rather than `full_name` and `avatar_url`.** Those two belong to
-- the identity provider: Google supplies `name`, `full_name`, `avatar_url` and
-- `picture` in its claims, and gotrue merges provider claims into
-- `raw_user_meta_data`. A customer who signs in with Google, renames themselves,
-- and signs in with Google again would be renamed back by the provider — and
-- silently, because nothing anywhere would report it. So what the *customer*
-- types goes under keys no provider writes:
--
--     zopiq_full_name · zopiq_avatar_url · zopiq_dob · zopiq_gender
--
-- and every reader coalesces ours first, the provider's second. That ordering is
-- the whole rule: **the provider's value is a default, the customer's is an
-- answer.** It holds whether or not gotrue actually re-syncs on every sign-in,
-- which is precisely why it is written this way rather than tested for.
--
-- Nothing else in the schema reads a customer's name. `restaurant_reviews` is
-- the only function, and it is the only thing this migration changes.

-- ---------------------------------------------------------------------------
-- The reviewer's first name, now that a customer can actually set one.
-- ---------------------------------------------------------------------------
-- Identical to 0062's in every other respect — same signature, same return
-- table, same `security definer`, same first-name-only projection, same
-- 'Zopiqnow customer' fallback for somebody who never set one. The argument list
-- is unchanged on purpose: a changed one creates an overload rather than a
-- replacement, and PostgREST would then bind to whichever it liked (0051).
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
             -- What the customer set for themselves, first.
             u.raw_user_meta_data ->> 'zopiq_full_name',
             -- Then whatever Google told us when they signed in.
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

-- Not done here, and named so it is a decision rather than an oversight: the
-- GST invoice (0063) builds its `buyer` object from `orders.user_phone` and
-- `orders.delivery_to` and carries **no buyer name**. Now that a customer has a
-- real name, printing it is defensible — but an invoice is a statutory document
-- issued out of a gapless series, and changing what one says is not a change to
-- make in passing while fixing an account screen.
