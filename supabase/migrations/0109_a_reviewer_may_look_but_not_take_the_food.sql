-- A demo rider that Google's reviewer can sign into, and that dispatch will
-- never hand a real customer's dinner to.
--
-- Play's App access form requires working credentials for anything behind a
-- login, so both staff apps need an account a stranger can use. On the vendor
-- side that is harmless — a demo restaurant marked inactive is invisible to
-- customers and receives nothing. On the rider side it is not, and the reason
-- is in `offer_delivery`:
--
--     and (not cand.has_fix or (cand.in_area and cand.km <= v_radius))
--
-- A rider with no GPS fix is *not* excluded, only outranked — deliberately, so
-- that idle riders (who report no position) still get offered work. Which means
-- a verified demo account sitting in the app is a candidate for every live
-- order, and wins outright the moment nobody nearer is online. The reviewer
-- would be assigned somebody's food and would, quite reasonably, never deliver
-- it.
--
-- Keeping the account unverified would also prevent that, at the cost of the
-- reviewer landing on a "your documents are being checked" wall and seeing
-- nothing of the app they are meant to be approving. So: verified papers, and a
-- flag that takes it out of dispatch.
--
-- **Why the flag lands in `rider_is_verified` rather than in `offer_delivery`.**
-- That predicate is the single gate every work path already passes through —
-- 0080 put it in dispatch, in claiming, and in the board — so one clause here
-- closes all of them at once, and no future work path can be added that forgets
-- about demo accounts. Editing `offer_delivery` would have closed exactly one.
--
-- The rider app is unaffected: `my_kyc` reads `rider_legal` directly, so the
-- profile screen still shows verified. The account can look at everything and
-- take nothing, which is precisely what a reviewer needs.

alter table public.delivery_partners
  add column if not exists is_demo boolean not null default false;

comment on column public.delivery_partners.is_demo is
  'Store-review account. Signs in and reads, never dispatched real work.';

create or replace function public.rider_is_verified(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
      select 1 from public.delivery_partners p
       where p.email = p_email and p.is_demo
    )
    and (
      public.rider_override_active(p_email)
      or exists (
        select 1
          from public.delivery_partners p
          join public.rider_legal l on l.partner_email = p.email
         where p.email = p_email
           and l.status = 'verified'
           and (
             p.vehicle = 'bicycle'
             or (l.licence_expiry   >= current_date
             and l.insurance_expiry >= current_date)
           )
      )
    );
$$;

-- 0080's grants do not survive `create or replace` losing them, but they are
-- restated because this repo has been bitten by a function coming back
-- PUBLIC-executable more than once. Belt and braces, and cheap.
revoke execute on function public.rider_is_verified(text) from public, anon;
grant execute on function public.rider_is_verified(text) to authenticated;
