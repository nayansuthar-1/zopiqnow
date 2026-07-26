-- ---------------------------------------------------------------------------
-- 0053 — the hero stops being code.
-- ---------------------------------------------------------------------------
-- P2 of `presentation-tasks.md`. The customer home hero is 1111 lines of Dart
-- with six campaign slides written into a `const` list: copy, colours, and
-- artwork composed in-app. Changing "60% OFF" to "50% OFF" is currently a code
-- change, a build, and a store review. This makes it a row.
--
-- **Why the read is a table policy and not an RPC.** Every admin *write* in this
-- console goes through a `security definer` RPC and no table grants a write to
-- the browser (0030 onward, and the 0045 lesson about grants). The read is the
-- other way round, because the customer app is the reader and it is not an
-- admin: the app selects from this table directly over PostgREST, exactly as it
-- does for `restaurants`, and the policy below is what decides which slides
-- exist as far as any client is concerned.
--
-- That is deliberate and it is rule 3 of the slice. A slide scheduled for next
-- Tuesday must be *unreadable* today, not merely unrendered — a client-side
-- `starts_at` filter would ship next week's campaign to every phone a week
-- early, where anyone with a proxy could read it. The window is in the policy.
--
-- **Why `cta_target` is validated on write.** A hero is the most prominent
-- surface in the app. A slide pointing at a delisted restaurant is a dead end on
-- the first thing a customer sees, and the failure is silent — the tap simply
-- lands nowhere. So the target is checked against something that exists at the
-- moment it is saved, and the set of things it may be is closed.
--
-- Nothing here touches an existing table. The carousel keeps its in-Dart slides
-- as its empty state, so zero rows renders exactly what ships today.

-- ---------------------------------------------------------------------------
-- A. The table.
-- ---------------------------------------------------------------------------
-- `is_active` and the two timestamps are three switches with different jobs and
-- none of them is a substitute for another: `is_active` is "somebody wants this
-- on screen", `starts_at`/`ends_at` are "and only during this window". A
-- campaign is deactivated in a second by ops; it expires on its own at midnight.
--
-- `image_url` is `not null` on purpose, and stays that way when P4 adds a motion
-- loop beside it: the still is the poster, the reduce-motion fallback, and what
-- shows while anything else downloads. There is no slide without one.
--
-- `cta_target` is nullable, and null is the common case rather than an omission:
-- it means "the CTA does what it does today" — scroll the home feed down to the
-- restaurant list. A slide only names a target when it is sending the customer
-- somewhere specific.
create table if not exists public.hero_slides (
  id          uuid        primary key default gen_random_uuid(),
  title       text        not null,
  subtitle    text        not null default '',
  cta_label   text        not null default 'Order now',
  cta_target  text,
  image_url   text        not null,
  sort_order  integer     not null default 0,

  -- Created dark. A slide comes into existence invisible for the same reason a
  -- restaurant does (0030): the half-finished one somebody abandoned mid-form
  -- must not be on the home screen of every customer in the meantime.
  is_active   boolean     not null default false,
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,
  created_at  timestamptz not null default now(),

  constraint hero_slides_window check (ends_at is null or ends_at > starts_at),
  constraint hero_slides_sort_order check (sort_order >= 0)
);

-- ---------------------------------------------------------------------------
-- B. What a client can see.
-- ---------------------------------------------------------------------------
alter table public.hero_slides enable row level security;

-- The only select policy, and it is the same one for a signed-in customer and a
-- browsing guest — a hero is public marketing. Note what is *not* here: no
-- policy for admins. `admin_list_hero_slides` below is `security definer` and
-- returns the scheduled and deactivated rows an editor needs; a select policy
-- for admins would instead make every draft campaign readable through PostgREST
-- to anyone the console's anon key reaches, which is the trade 0040 refused for
-- the rider roster and this refuses too.
drop policy if exists hero_slides_live_are_public on public.hero_slides;
create policy hero_slides_live_are_public on public.hero_slides
  for select
  to anon, authenticated
  using (
    is_active
    and now() >= starts_at
    and now() < coalesce(ends_at, 'infinity'::timestamptz)
  );

-- Select, and then the writes taken away explicitly — which is not belt and
-- braces. Supabase's default privileges grant ALL on every new table in `public`
-- to `anon` and `authenticated`, so a fresh table arrives writable by the
-- browser and the only thing refusing an insert is the *absence* of an insert
-- policy. That works, and it is one `create policy` away from not working. With
-- these revokes the write is refused by the grant as well, so the RPCs below are
-- not merely the recommended path — they are the only one.
grant select on public.hero_slides to anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.hero_slides from anon, authenticated;

-- ---------------------------------------------------------------------------
-- C. Where a slide may point.
-- ---------------------------------------------------------------------------
-- Rule 4 of the slice, enforced at the write. The set of destinations is closed
-- and every member of it is checked:
--
--   null                  the CTA scrolls the feed to the restaurant list
--   /restaurant/<id>      a specific kitchen — must exist and be listed
--   /gifts /orders
--   /favourites /         a tab the app actually has
--
-- Two paths the router does define are deliberately absent: `/dining` and
-- `/grocery` are placeholder screens, and pointing the home hero at a "coming
-- soon" page is the dead end this check exists to prevent.
--
-- Checked at save time, not at render time. A restaurant delisted *after* a
-- slide was published still leaves a dead CTA, and no write-time check can fix
-- that — but the customer app resolves `/restaurant/<id>` through the same
-- `is_active` policy the feed uses, so the menu screen answers "no longer
-- available" rather than crashing. The write-time check is what stops the
-- ordinary mistake: a typo, or a draft restaurant chosen from a list.
create or replace function public.assert_hero_cta(p_target text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_target text;
  v_id     text;
begin
  v_target := nullif(trim(coalesce(p_target, '')), '');
  if v_target is null then
    return;
  end if;

  if v_target in ('/', '/gifts', '/orders', '/favourites') then
    return;
  end if;

  v_id := substring(v_target from '^/restaurant/([A-Za-z0-9_-]+)$');
  if v_id is null then
    raise exception
      'A slide can point at a restaurant (/restaurant/<id>) or at /, /gifts, /orders or /favourites — not at "%".',
      v_target using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.restaurants r where r.id = v_id and r.is_active
  ) then
    raise exception
      'Restaurant % is not listed, so a hero pointing at it would be a dead end. Publish it first.',
      v_id using errcode = 'P0001';
  end if;
end;
$$;

-- Called only by the RPCs below, in their own definer context (the 0045 lesson).
revoke execute on function public.assert_hero_cta(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- D. The editor's read.
-- ---------------------------------------------------------------------------
-- Everything, including what no customer can see. That is the whole point of it
-- existing beside the policy in B: the row an editor most needs to find is the
-- expired campaign somebody has to switch back on or the draft nobody finished.
create or replace function public.admin_list_hero_slides()
returns table (
  id         uuid,
  title      text,
  subtitle   text,
  cta_label  text,
  cta_target text,
  image_url  text,
  sort_order integer,
  is_active  boolean,
  starts_at  timestamptz,
  ends_at    timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select s.id, s.title, s.subtitle, s.cta_label, s.cta_target, s.image_url,
           s.sort_order, s.is_active, s.starts_at, s.ends_at, s.created_at
      from public.hero_slides s
     -- The order the carousel will show them in, so the list on screen is the
     -- running order and not a second thing to reason about.
     order by s.sort_order, s.created_at;
end;
$$;

revoke execute on function public.admin_list_hero_slides() from public, anon;
grant execute on function public.admin_list_hero_slides() to authenticated;

-- ---------------------------------------------------------------------------
-- E. Writing one.
-- ---------------------------------------------------------------------------
-- Create and edit are one function because they are one form: a hero slide is
-- ten fields on one screen, all of them filled in every time. That is the
-- opposite of `admin_update_restaurant`, which writes only the keys present
-- because a six-step wizard saves a quarter of a restaurant at a time — the
-- reasoning there does not apply to a form with no steps.
--
-- `p_slide.id` null creates; present updates. A missing id on an update would
-- silently duplicate the slide, so the two cases are distinguished by presence
-- and never guessed at.
create or replace function public.admin_upsert_hero_slide(p_slide jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id        uuid;
  v_title     text;
  v_image     text;
  v_cta_label text;
  v_cta       text;
  v_sort      integer;
  v_starts    timestamptz;
  v_ends      timestamptz;
begin
  perform public.assert_admin();

  v_id    := nullif(p_slide->>'id', '')::uuid;
  v_title := trim(coalesce(p_slide->>'title', ''));
  v_image := trim(coalesce(p_slide->>'image_url', ''));

  if v_title = '' then
    raise exception 'A slide needs a headline.' using errcode = 'P0001';
  end if;

  -- The art is the slide. A hero with no image is a coloured band with words on
  -- it, which is what the in-Dart empty state already does better.
  if v_image = '' then
    raise exception 'A slide needs artwork. Upload an image first.' using errcode = 'P0001';
  end if;

  -- Rule 2: slide art is Cloudinary-hosted, never bundled and never hotlinked
  -- from somewhere that can go down or swap the picture underneath us. The
  -- console has exactly one upload path and it returns exactly this prefix, so
  -- anything else arriving here was pasted in by hand.
  if v_image not like 'https://res.cloudinary.com/%' then
    raise exception
      'Slide art has to be uploaded here — that is not a Cloudinary image URL.'
      using errcode = 'P0001';
  end if;

  v_cta := nullif(trim(coalesce(p_slide->>'cta_target', '')), '');
  perform public.assert_hero_cta(v_cta);

  v_cta_label := nullif(trim(coalesce(p_slide->>'cta_label', '')), '');
  v_sort      := coalesce((p_slide->>'sort_order')::integer, 0);
  v_starts    := coalesce((p_slide->>'starts_at')::timestamptz, now());
  v_ends      := nullif(p_slide->>'ends_at', '')::timestamptz;

  if v_sort < 0 then
    raise exception 'Position cannot be negative.' using errcode = 'P0001';
  end if;

  -- Caught here as well as by the table constraint, because "ends_at_check
  -- violated" is not a sentence anybody should be shown.
  if v_ends is not null and v_ends <= v_starts then
    raise exception 'The end has to come after the start.' using errcode = 'P0001';
  end if;

  if v_id is null then
    insert into public.hero_slides (
      title, subtitle, cta_label, cta_target, image_url,
      sort_order, is_active, starts_at, ends_at
    )
    values (
      v_title,
      trim(coalesce(p_slide->>'subtitle', '')),
      coalesce(v_cta_label, 'Order now'),
      v_cta,
      v_image,
      v_sort,
      coalesce((p_slide->>'is_active')::boolean, false),
      v_starts,
      v_ends
    )
    returning id into v_id;
  else
    update public.hero_slides
       set title      = v_title,
           subtitle   = trim(coalesce(p_slide->>'subtitle', '')),
           cta_label  = coalesce(v_cta_label, 'Order now'),
           cta_target = v_cta,
           image_url  = v_image,
           sort_order = v_sort,
           -- Not `is_active`. The list has its own switch for that, and folding
           -- it into the save would mean opening a slide to fix a typo and
           -- publishing it by pressing Save.
           starts_at  = v_starts,
           ends_at    = v_ends
     where id = v_id;

    if not found then
      raise exception 'That slide no longer exists.' using errcode = 'P0001';
    end if;
  end if;

  return v_id;
end;
$$;

revoke execute on function public.admin_upsert_hero_slide(jsonb) from public, anon;
grant execute on function public.admin_upsert_hero_slide(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- F. The switch.
-- ---------------------------------------------------------------------------
-- Separate from the save, so publishing is its own deliberate act and one click
-- rather than a round trip through a form. Switching a slide *on* re-checks its
-- CTA: the restaurant it points at may have been delisted since it was written,
-- and this is the last moment anybody looks before it reaches a home screen.
create or replace function public.admin_set_hero_slide_active(p_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cta text;
begin
  perform public.assert_admin();

  select cta_target into v_cta from public.hero_slides where id = p_id;
  if not found then
    raise exception 'That slide no longer exists.' using errcode = 'P0001';
  end if;

  if p_active then
    perform public.assert_hero_cta(v_cta);
  end if;

  update public.hero_slides set is_active = p_active where id = p_id;
end;
$$;

revoke execute on function public.admin_set_hero_slide_active(uuid, boolean) from public, anon;
grant execute on function public.admin_set_hero_slide_active(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- G. Removing one.
-- ---------------------------------------------------------------------------
-- A real delete, unlike a restaurant (0044) or a rider (0040). Nothing has a
-- foreign key to a hero slide and no history hangs off it: an expired campaign
-- carries no orders and answers no question a year later. Deactivation is still
-- the right move for a campaign that will come back, which is why the switch
-- above exists — but a slide made by mistake should be removable.
create or replace function public.admin_delete_hero_slide(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  delete from public.hero_slides where id = p_id;

  if not found then
    raise exception 'That slide no longer exists.' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_delete_hero_slide(uuid) from public, anon;
grant execute on function public.admin_delete_hero_slide(uuid) to authenticated;
