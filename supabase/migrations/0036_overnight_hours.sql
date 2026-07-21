-- Step 11, migration 36: the kitchen that closes at 1am.
--
-- `restaurant_hours` has said since 0018 that a day's closing time must be after
-- its opening time:
--
--     constraint hours_open_before_close check (closes > opens)
--
-- which is true of a restaurant open 10:00–22:00 and false of a great many real
-- ones. A place serving until 1am cannot be described at all: 18:00–01:00 fails
-- the check, and the nearest expressible thing, 18:00–23:59, is a lie that closes
-- the kitchen an hour early every night and refuses orders it wants.
--
-- The constraint was not wrong so much as narrow — it encoded "a day" when what
-- the table holds is "a *window*, which starts on a day". This migration widens it
-- to that, which means two changes that have to land together:
--
--   1. `closes < opens` becomes legal, and means the window crosses midnight;
--   2. `restaurant_is_open_now` learns that such a window is still open at 00:30 —
--      on the *next* calendar day, under the *previous* day's row.
--
-- A third change lives outside this file: the vendor app's hours editor enforces
-- the same rule in Dart and would still refuse to save one. It is updated in the
-- same commit.

-- ---------------------------------------------------------------------------
-- The constraint, widened rather than dropped.
-- ---------------------------------------------------------------------------
-- `closes <> opens` still holds, because a window that starts and ends at the same
-- instant is not a description of anything. Without it, 10:00–10:00 would be
-- ambiguous between "closed all day" (which is the absence of a row) and "open all
-- day" (which nothing in the schema means).
alter table public.restaurant_hours
  drop constraint if exists hours_open_before_close;

alter table public.restaurant_hours
  drop constraint if exists hours_window_is_not_empty;
alter table public.restaurant_hours
  add constraint hours_window_is_not_empty check (closes <> opens);

-- ---------------------------------------------------------------------------
-- "Is it open right now?", asked properly.
-- ---------------------------------------------------------------------------
-- Two shapes of window, and the second is the new one:
--
--   closes > opens   a normal day.  Monday 10:00–22:00 is open on Monday between
--                    those times and never touches another day.
--
--   closes < opens   a window that crosses midnight. Monday 18:00–01:00 is open
--                    on *Monday* from 18:00 to the end of the day, and on
--                    *Tuesday* from the start of the day until 01:00 — but it is
--                    still Monday's row that says so. At 00:30 on Tuesday the
--                    question to ask is what *yesterday* opened.
--
-- Which is why `yesterday` is computed here rather than the query just checking
-- today: the row that makes a restaurant open at half past midnight is filed
-- under the day before.
--
-- One deliberate behaviour change while the logic is being rewritten: the window
-- is now half-open, `>= opens and < closes`, where 0018 used `between` and so
-- included the closing instant. A kitchen that closes at 22:00 is closed at 22:00.
-- That is what closing means, and the old version accepted an order at exactly
-- 22:00:00.
create or replace function public.restaurant_is_open_now(p_restaurant_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with clock as (
    select
      (now() at time zone 'Asia/Kolkata')::time                        as t,
      extract(isodow from (now() at time zone 'Asia/Kolkata'))::int    as today,
      extract(isodow from
        (now() at time zone 'Asia/Kolkata') - interval '1 day')::int   as yesterday
  )
  select case
    -- Unchanged from 0018, and still load-bearing: a restaurant that has never
    -- set its hours is treated as always open. Every seeded restaurant is in this
    -- state, and `admin_publish_restaurant` is what stops a *new* one from being
    -- listed that way by accident.
    when not exists (
      select 1 from public.restaurant_hours where restaurant_id = p_restaurant_id
    ) then true
    else exists (
      select 1
        from public.restaurant_hours h, clock c
       where h.restaurant_id = p_restaurant_id
         and (
           -- A window inside one day.
           (h.closes > h.opens
            and h.day_of_week = c.today
            and c.t >= h.opens and c.t < h.closes)
           or
           -- A window that crosses midnight, seen from either side of it.
           (h.closes < h.opens
            and (
              (h.day_of_week = c.today     and c.t >= h.opens)
              or
              (h.day_of_week = c.yesterday and c.t <  h.closes)
            ))
         )
    )
  end
$$;

grant execute on function public.restaurant_is_open_now(text) to anon, authenticated;

-- `place_order` calls this function by name and is unchanged — it asks "is this
-- restaurant open" and now gets a better answer to the same question.
