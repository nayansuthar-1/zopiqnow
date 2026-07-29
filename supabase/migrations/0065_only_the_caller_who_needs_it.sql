-- ---------------------------------------------------------------------------
-- 0065 — only the caller who needs it. (Phase B6, closing 0062–0064's grants)
-- ---------------------------------------------------------------------------
-- 0045's lesson, and the one this project keeps having to re-learn: **Postgres
-- grants `execute` on every new function to `PUBLIC`**. So writing
--
--     grant execute on function public.vendor_save_offer(…) to authenticated;
--
-- adds nothing. The function was already executable by `authenticated` — and by
-- `anon`, and by anyone else who ever gets a role — the moment it was created.
-- The explicit grant reads like a decision and is in fact a no-op sitting on top
-- of a default that granted more.
--
-- Every function 0062, 0063 and 0064 introduced is revoked here and re-granted
-- to exactly the callers that need it. Nothing about behaviour changes for a
-- caller who was supposed to have it; what changes is that the sentence in the
-- migration is now true.
--
-- **The security-definer functions still refuse the wrong caller on their own.**
-- `submit_order_review` reads `auth.uid()`, `vendor_offers` reads
-- `staff_restaurant_id()`, and a signed-out call to either has always been
-- answered with a sentence rather than data. This is defence in depth, not the
-- only defence — but "an anonymous caller cannot invoke it at all" is a stronger
-- and much shorter thing to verify than "every branch inside it checks".

-- ===========================================================================
-- A. Internal only. Nothing outside the database calls these.
-- ===========================================================================
-- Three constants and two trigger bodies. A trigger function invoked directly
-- errors anyway (there is no `NEW` outside a trigger), and a constant is not a
-- secret — but an API surface is a list of things somebody has to reason about,
-- and these do not belong on it.
revoke all on function public.review_window_days() from public, anon, authenticated;
revoke all on function public.gst_rate_percent() from public, anon, authenticated;
revoke all on function public.financial_year(timestamptz) from public, anon, authenticated;
revoke all on function public.reviews_are_frozen_after_the_window() from public, anon, authenticated;
revoke all on function public.reviews_recompute_ratings() from public, anon, authenticated;
revoke all on function public.orders_issue_invoice() from public, anon, authenticated;

-- ===========================================================================
-- B. The customer's, and only once they are somebody.
-- ===========================================================================
-- Every one of these is about *this caller's own order*, so an anonymous caller
-- has nothing to ask about. `order_review_state` had `anon` in 0062 and loses it
-- here: it returns no rows for a null `auth.uid()`, so the grant bought a round
-- trip that could only ever answer "nothing".
revoke all on function public.submit_order_review(text, integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.submit_order_review(text, integer, integer, text)
  to authenticated;

revoke all on function public.my_order_review(text) from public, anon, authenticated;
grant execute on function public.my_order_review(text) to authenticated;

revoke all on function public.order_review_state(text) from public, anon, authenticated;
grant execute on function public.order_review_state(text) to authenticated;

revoke all on function public.order_invoice(text) from public, anon, authenticated;
grant execute on function public.order_invoice(text) to authenticated;

-- ===========================================================================
-- C. The kitchen's.
-- ===========================================================================
-- `authenticated` and not narrower, because SQL grants cannot express "a member
-- of this restaurant's staff" — that is what `staff_restaurant_id()` inside each
-- function is for, and what it has always been for.
revoke all on function public.vendor_reviews(integer) from public, anon, authenticated;
grant execute on function public.vendor_reviews(integer) to authenticated;

revoke all on function public.vendor_review_summary() from public, anon, authenticated;
grant execute on function public.vendor_review_summary() to authenticated;

revoke all on function public.vendor_offers() from public, anon, authenticated;
grant execute on function public.vendor_offers() to authenticated;

revoke all on function public.vendor_save_offer(text, integer, integer, integer, integer, timestamptz)
  from public, anon, authenticated;
grant execute on function public.vendor_save_offer(text, integer, integer, integer, integer, timestamptz)
  to authenticated;

revoke all on function public.vendor_set_offer_active(text, boolean)
  from public, anon, authenticated;
grant execute on function public.vendor_set_offer_active(text, boolean)
  to authenticated;

-- ===========================================================================
-- D. Genuinely public, and deliberately so.
-- ===========================================================================
-- Browsing a restaurant does not require an account — that is the whole shape of
-- this app (`_protectedPrefixes` in the customer router starts at `/checkout`).
-- The two things a signed-out browser can see about a restaurant are what people
-- said about it and what it is offering, so both keep `anon`.
--
-- `restaurant_reviews` publishes a first name and nothing else; `restaurant_offers`
-- publishes codes that are advertised anyway and that `validate_coupon` re-checks
-- the scope of before a paisa moves.
revoke all on function public.restaurant_reviews(text, integer)
  from public, anon, authenticated;
grant execute on function public.restaurant_reviews(text, integer)
  to anon, authenticated;

revoke all on function public.restaurant_offers(text) from public, anon, authenticated;
grant execute on function public.restaurant_offers(text) to anon, authenticated;

-- `validate_coupon` keeps `anon` for the reason 0003 gave it: a cart is open to
-- a signed-out user, and a coupon field that refuses to say what a code is worth
-- until you sign in is a coupon field nobody uses. `place_order` does not — it
-- has read the buyer from `auth.uid()` since 0004.
revoke all on function public.validate_coupon(text, integer, text)
  from public, anon, authenticated;
grant execute on function public.validate_coupon(text, integer, text)
  to anon, authenticated;

revoke all on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text, text
) from public, anon, authenticated;
grant execute on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision, text, text, text
) to authenticated;
