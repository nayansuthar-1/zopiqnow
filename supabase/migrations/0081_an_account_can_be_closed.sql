-- ---------------------------------------------------------------------------
-- 0081 — an account can be closed. (audit LEG-001)
-- ---------------------------------------------------------------------------
-- There has never been a way to delete a Zopiqnow account. Not a hard one, not
-- a hidden one — none. A customer who wanted to leave could sign out, and that
-- is all; their addresses, their phone number, their order history and their
-- push token stayed exactly where they were, indefinitely, with no route to
-- removing them short of emailing somebody who has no button to press either.
--
-- **This blocks the Play listing.** Google requires that an app which lets you
-- create an account lets you delete it, from inside the app, and also from a web
-- page reachable without installing anything. India's DPDP Act asks for the same
-- thing from the other direction — erasure on request, without the request
-- having to be argued for. Neither is satisfiable by a support inbox.
--
-- **Deletion here is immediate and irreversible.** No thirty-day grace period,
-- no "reactivate within a month". A grace period is a defensible design, but it
-- is a promise about data that is still being held, and holding it needs its own
-- disclosure, its own expiry job and its own way of explaining to somebody that
-- their deleted account is not deleted yet. The honest version is the simple one.
--
-- ---------------------------------------------------------------------------
-- What is deleted, and what is kept, and why
-- ---------------------------------------------------------------------------
-- **Gone entirely**, with the auth user: the login itself, its Google identity,
-- every session, the saved addresses and the saved restaurants (both already
-- cascade from `auth.users`), every push token, and every notification ever
-- addressed to this person. Nothing about them survives that has no reason to.
--
-- **Kept, with the person removed from it: their orders.** This is the part that
-- cannot be waved through, so it is worth being exact about. An order is not
-- only a customer's record — it is a tax record and it is a restaurant's income.
-- The GST invoice for it has been issued and counted; migration 0079's
-- settlement batch pays a restaurant on the strength of these rows, and 0077's
-- refund ledger reconciles against them. Deleting the row would take money off a
-- restaurant's statement for a delivery it actually made, and would quietly edit
-- a filed tax period. So the row stays and the person leaves it: the phone
-- number, the delivery address, the delivery note and the coordinates are
-- cleared, and the owning id becomes an opaque token.
--
-- **One token per deletion, not one shared sentinel and not null.** `user_id` is
-- `not null`, so null was never available. A single shared 'deleted' value would
-- collapse every departed customer into one, which loses the only property worth
-- keeping — that a restaurant's twelve orders from one now-departed account are
-- still visibly twelve orders from one account, which is what fraud review and
-- accounting need. The token is a fresh uuid with a prefix: it groups, and it
-- points at nobody.
--
-- **Reviews and coupon redemptions are re-keyed the same way.** A review stays
-- because a restaurant's rating was computed from it and pulling it would move
-- the restaurant's score for reasons the restaurant cannot see. It shows as
-- "Zopiqnow customer" the moment the auth user is gone — `restaurant_reviews`
-- (0070) left-joins and already coalesces to exactly that, so nothing there
-- needs changing. A redemption stays because a coupon's budget was spent.
--
-- **The review's rating stays; its words do not.** The star is a fact about the
-- restaurant and it is already counted into a public average. The comment is the
-- customer's own writing, and erasure that leaves somebody's sentences on a
-- public page is not erasure. So `comment` is cleared and `food_rating` is left
-- exactly where it was: the restaurant's score does not move by a hundredth.
--
-- ---------------------------------------------------------------------------
-- Two refusals
-- ---------------------------------------------------------------------------
-- **An order on the way.** A rider is holding somebody's dinner and steering by
-- an address this function is about to erase. The delete is refused, in a
-- sentence, until the order finishes or is cancelled — which is minutes, not a
-- policy.
--
-- **A staff, rider or admin login.** All three apps and the console sign in
-- through the same `auth.users`, and the vendor and rider ends key their people
-- by *email*, not by user id. Deleting the auth row of somebody who is also a
-- restaurant's manager would lock a kitchen out of its own tablet with nothing
-- anywhere explaining why. Those accounts are refused and told to contact
-- support, which is a person doing it deliberately rather than a customer doing
-- it by accident.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. The record that a deletion happened, with nobody in it.
-- ---------------------------------------------------------------------------
-- Proving that erasure requests are honoured is part of honouring them, and a
-- deletion that leaves no trace at all cannot be shown to have occurred. So one
-- row per deletion — and deliberately *not* an audit log: no email, no user id,
-- no name, nothing that would make this table the place the deleted data went
-- to live. The token is the same opaque one written onto the orders, so a
-- support question six months from now ("what happened to this order's
-- customer?") has an answer, and the answer is "they left on this date".
create table if not exists public.account_deletions (
  token       text primary key,
  deleted_at  timestamptz not null default now(),
  orders_kept integer     not null default 0
);

comment on table public.account_deletions is
  'One row per closed customer account. Holds no personal data by design — the '
  'token is opaque and the person it belonged to is unrecoverable.';

-- A new table arrives carrying whatever the schema's default grants say, which
-- since 0073 is the thing we check rather than assume. Nobody reads this but
-- the console and the function that writes it.
revoke all on public.account_deletions from public, anon, authenticated;

alter table public.account_deletions enable row level security;

-- No policy for anybody. `security definer` writes here and nothing else does;
-- RLS on with no policy is the strongest available statement of that.

-- ---------------------------------------------------------------------------
-- B. A closing account is not an edit — teaching the review freeze the difference.
-- ---------------------------------------------------------------------------
-- `reviews_freeze` (0062) is a `before update` trigger that does two things: it
-- refuses any change once `editable_until` has passed, and it restores the
-- columns an edit may not touch — `user_id` among them — from `old`.
--
-- Both of those aimed squarely at this migration's foot, and the first is the
-- dangerous one:
--
--   * The restore made the anonymisation a **silent no-op**. The update reported
--     a row changed and the review kept pointing at the deleted person. Caught
--     by the behaviour test, and only because it asserted the result rather than
--     the row count.
--   * The refusal is worse. A review older than its edit window — which is to
--     say very nearly every review — would `raise` inside `delete_my_account`
--     and abort the whole transaction. **Account deletion would have failed
--     outright for any customer who had ever rated an order**, with a message
--     about editing a review, which is not a thing they were trying to do.
--
-- The freeze exists to stop a customer rewriting their opinion after the window
-- has closed. It was never meant to pin a departed customer's id to a row
-- forever. So it learns one exception, narrow enough to state in a sentence: an
-- update that re-keys a review to a deletion token and leaves both ratings
-- untouched is an account closing, not an edit, and it passes.
create or replace function public.reviews_are_frozen_after_the_window()
returns trigger
language plpgsql
as $$
begin
  -- The exception, and it comes first — before the window check, because a
  -- closed window must not be able to refuse a deletion.
  if new.user_id is distinct from old.user_id
     and new.user_id like 'deleted:%'
     and old.user_id not like 'deleted:%'
     and new.food_rating  is not distinct from old.food_rating
     and new.rider_rating is not distinct from old.rider_rating
  then
    new.updated_at := now();
    return new;
  end if;

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

-- ---------------------------------------------------------------------------
-- C. Closing the account.
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid    uuid;
  v_uid_t  text;
  v_email  text;
  v_open   integer;
  v_token  text;
  v_orders integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'You need to be signed in to delete your account.'
      using errcode = 'P0001';
  end if;
  v_uid_t := v_uid::text;

  select lower(u.email) into v_email from auth.users u where u.id = v_uid;

  -- Refusal 1 — somebody is on their way to this address right now.
  select count(*) into v_open
    from public.orders o
   where o.user_id = v_uid_t
     and o.status in ('placed', 'accepted', 'preparing',
                      'ready_for_pickup', 'out_for_delivery');
  if v_open > 0 then
    raise exception
      'You have an order on the way. You can delete your account once it is delivered or cancelled.'
      using errcode = 'P0001';
  end if;

  -- Refusal 2 — this login is also a person who works here. Keyed by email
  -- because that is how the vendor and rider ends identify their people; the
  -- customer app's own users match none of these.
  if v_email is not null and (
       exists (select 1 from public.restaurant_staff  s where lower(s.email)         = v_email)
    or exists (select 1 from public.delivery_partners d where lower(d.email)         = v_email)
    or exists (select 1 from public.platform_admins   a where lower(a.email)         = v_email)
  ) then
    raise exception
      'This account is also used by a restaurant or delivery partner. Please contact support to close it.'
      using errcode = 'P0001';
  end if;

  v_token := 'deleted:' || gen_random_uuid()::text;

  -- The orders stay; the person leaves them. `delivery_to` is `not null`, so it
  -- is replaced rather than emptied — and replaced with a sentence, because this
  -- string is read by a human on a vendor tablet and an empty cell there looks
  -- like a bug rather than a choice.
  update public.orders
     set user_id        = v_token,
         user_phone     = '',
         delivery_to    = 'Address removed — account deleted',
         delivery_notes = null,
         delivery_lat   = null,
         delivery_lng   = null
   where user_id = v_uid_t;
  get diagnostics v_orders = row_count;

  -- The star stays and the sentences go. See the note above B on why the
  -- freeze trigger lets exactly this through and nothing else.
  update public.reviews
     set user_id = v_token,
         comment = null
   where user_id = v_uid_t;

  update public.coupon_redemptions set user_id = v_token where user_id = v_uid_t;

  -- No reason to keep either of these for a second longer.
  delete from public.device_tokens where user_id = v_uid_t;
  delete from public.notifications where user_id = v_uid_t;

  insert into public.account_deletions (token, orders_kept)
  values (v_token, v_orders);

  -- Last, because everything above is keyed off it and because the addresses
  -- and favourites go with it: both cascade from `auth.users`. Deleting this
  -- row also ends every session the account has open, on every device.
  delete from auth.users where id = v_uid;
end;
$$;

comment on function public.delete_my_account() is
  'Closes the calling customer''s account: deletes the login, its addresses, '
  'favourites, push tokens and notifications, and strips the person out of the '
  'orders, reviews and redemptions that must be kept. Irreversible.';

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
