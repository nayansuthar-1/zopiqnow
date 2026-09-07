-- ---------------------------------------------------------------------------
-- 0163 — a private code stays private.
-- ---------------------------------------------------------------------------
-- Unticking "Listed publicly" on a coupon did nothing. The code went on being
-- advertised at checkout to every customer, which is the entire opposite of
-- what that tick means and the reason `is_public` was added.
--
-- ## Why the guard that exists did not hold
--
-- 0075 added `is_public` and enforced it **in a row-level policy**:
--
--     create policy "active public platform coupons are world-readable"
--       on public.coupons for select to anon, authenticated
--       using (is_active and restaurant_id is null and is_public);
--
-- That policy is correct and it still is. It simply never runs on the path the
-- app actually uses. `restaurant_offers` (0064) is `security definer` — it
-- executes as its owner, RLS is not applied to it, and its own `where` clause
-- has filtered on `is_active`, the end date and the restaurant since the day it
-- was written. `is_public` was added to the table a migration later and this
-- clause was never told about it.
--
-- **A `security definer` function is a hole in RLS by design.** That is what it
-- is for — 0064 moved this read into one so a customer could see a kitchen's own
-- offer without `coupons` being readable. The cost is that every rule the policy
-- expresses has to be restated here by hand, and a rule added to the policy
-- afterwards silently is not.
--
-- ## What changes
--
-- One predicate. A private code is still a real code: it validates, it applies,
-- and it is honoured — `validate_coupon` and `coupon_lock_and_price` never
-- looked at `is_public` and still do not, because "not advertised" and "not
-- accepted" are different things and a win-back code that a customer was sent
-- must work when they type it.
--
-- ## One thing this deliberately does not fix
--
-- The same clause filters `valid_until` and **not** `valid_from`, so an offer
-- scheduled to start next week is advertised today and answers "This offer
-- hasn't started yet" when it is applied. Same defect, one word away, and it is
-- not what was reported — left for its own change rather than folded in here.
-- ---------------------------------------------------------------------------

create or replace function public.restaurant_offers(p_restaurant_id text)
returns table (
  code         text,
  label        text,
  min_subtotal integer,
  is_exclusive boolean,
  valid_until  timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.code,
         case
           when c.free_delivery       then 'Free delivery'
           when c.flat_off is not null then '₹' || c.flat_off || ' off'
           else c.percent_off || '% off up to ₹' || c.max_off
         end,
         c.min_subtotal,
         c.restaurant_id is not null,
         c.valid_until
    from public.coupons c
   where c.is_active
     -- The tick on the console's coupon form, honoured at last (0075, 0163).
     -- This function is `security definer`, so the row policy that says the
     -- same thing does not run here and this is the only place it is enforced
     -- on the path the app reads.
     and c.is_public
     and (c.valid_until is null or c.valid_until > now())
     and (c.restaurant_id is null or c.restaurant_id = p_restaurant_id)
   order by c.restaurant_id is null, c.min_subtotal;
$$;

comment on function public.restaurant_offers(text) is
  'The offers a customer may be shown for one restaurant: the platform''s and '
  'that kitchen''s own, already worded. Never lists a code marked private — a '
  'private code still works when typed (0163).';

-- `create or replace` keeps the existing ACLs, so 0065's grants survive
-- untouched. Restated as an assertion rather than a change.
revoke all on function public.restaurant_offers(text) from public;
grant execute on function public.restaurant_offers(text) to anon, authenticated;

-- ---------------------------------------------------------------- verification
-- With a private code on the books:
--
--   select code, is_public from public.coupons where not is_public;
--   select * from public.restaurant_offers('<restaurant id>');
--   -- expected: the private code is absent from the second result
--
-- And it still works when typed, which is the whole point of "private":
--
--   set role authenticated;  -- inside a transaction, with request.jwt.claims set
--   select public.coupon_preview('<that code>', 300, '<restaurant id>');
--   -- expected: a discount, not a refusal
