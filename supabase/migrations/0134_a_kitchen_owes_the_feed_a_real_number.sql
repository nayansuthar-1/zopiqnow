-- ---------------------------------------------------------------------------
-- 0134 — a kitchen owes the feed a real number.
-- ---------------------------------------------------------------------------
-- Four of the nine published kitchens read **0 min** on the customer feed:
-- Bharkadevi Ice Cream, Celebration Cakes And Pastries, Mamaji Snacks Fast Food
-- and Purohit Bakers. Not a rendering bug — `restaurants.eta_minutes` is
-- literally zero on those rows, and `restaurant_card.dart` prints it.
--
-- **How they got there.** 0101 took prep time off the admin's Storefront step,
-- on the reasoning that the kitchen answers it better per order when it accepts.
-- That reasoning holds for the *order's* ETA and only for it. What it missed is
-- that the same column is also the only number the **feed** has, and the feed is
-- read long before any order exists — so removing the one place it could be
-- filled in left the browsing customer reading a promise of no time at all.
--
-- 0101 defaulted the column to 30 and backfilled the zeros it could see. Both
-- were correct and neither was enough: the check constraint had already been
-- relaxed to `>= 0` by 0044, so nothing stopped a later row from landing on 0
-- again, and four of them did.
--
-- **The decision (user, 2026-08-21):** the number comes back under human
-- control, in *both* consoles — the admin console Storefront step and the
-- vendor's own Edit profile — and the feed stops treating it as the whole
-- answer. The card now reads it as the **kitchen's** share of the wait and adds
-- the ride from that kitchen to this address, which is why one restaurant can
-- honestly read longer than another with the same cook.
--
-- Nothing here changes `place_order`. The ETA it stamps on an order is still
-- this column, still a placeholder for the minutes before a kitchen accepts, and
-- `accept_order` still overwrites it with the number a cook actually chose.

-- ===========================================================================
-- A. The zeros.
-- ===========================================================================
-- 30 is the same placeholder 0101 chose and the same one the column defaults
-- to. It is a starting value, not an answer — the point of this migration is
-- that a human can now replace it from either console.
update public.restaurants
   set eta_minutes = 30
 where eta_minutes <= 0;

-- ===========================================================================
-- B. The gate that should have stopped them.
-- ===========================================================================
-- 0044 loosened this to `>= 0` so a half-filled draft could exist before anyone
-- had guessed a prep time. That need is gone: the column has defaulted to 30
-- since 0101, so a draft created without one is born with a usable number
-- rather than a zero, and there is no longer any state in which 0 is the honest
-- value. `> 0` matches what both write paths already enforce — the vendor form's
-- validator and `admin_update_restaurant`'s `<= 0` rejection — so this closes
-- the direct-SQL hole the four rows above came through.
--
-- Restated by name from the live constraint rather than from 0001, which is a
-- different predicate than the one actually on the table.
alter table public.restaurants
  drop constraint if exists restaurants_eta_minutes_check;
alter table public.restaurants
  add constraint restaurants_eta_minutes_check check (eta_minutes > 0);

-- ===========================================================================
-- C. What the column means now.
-- ===========================================================================
-- 0101's comment said "Not admin-editable since 0101". That is no longer true,
-- and a comment that lies about who owns a column is worse than none.
comment on column public.restaurants.eta_minutes is
  'The kitchen''s own share of the wait, in minutes — cooking and packing, not the ride. Set by the admin console (Storefront step) or by the vendor (Edit profile); both reject anything <= 0. The customer feed adds travel time from this kitchen to the delivery address on top of it. Also the placeholder ETA place_order stamps on an order until accept_order replaces it with the number the cook chose.';
