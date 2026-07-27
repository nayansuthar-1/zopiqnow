-- ---------------------------------------------------------------------------
-- 0054 — the hero can move.
-- ---------------------------------------------------------------------------
-- P4 of `presentation-tasks.md`. A column beside `image_url`, not a feature
-- from scratch: 0053 already made the hero content, and this lets a slide carry
-- a short silent loop over its still.
--
-- **No new dependency, and that is the whole shape of this.** The obvious route
-- is the `video_player` package, which would be a version-freeze item. Instead
-- the admin uploads an MP4, Cloudinary transcodes it to an **animated WebP** on
-- delivery, and the phone receives it through the same `Image.network` path the
-- still already uses. Flutter decodes and loops animated WebP natively. Nothing
-- in `pubspec.yaml` changes.
--
-- **Why this column holds the derived WebP URL and not the uploaded MP4.** The
-- console builds the transformation, then fetches the result to measure it, and
-- stores the URL it measured. So the number an admin is shown before saving is
-- the number a customer downloads — the same bytes from the same URL — rather
-- than an estimate of them. It also means the phone never has to know
-- Cloudinary's grammar: `motion_url` is a URL to an image, exactly like
-- `image_url`. The cost is that changing the transformation later means
-- re-saving slides, which is the right way round for something whose delivered
-- size is the thing being controlled.
--
-- `image_url` stays `not null`, as 0053 said it would. The still is the poster,
-- the reduce-motion fallback, and what shows while the loop downloads. Rule 1
-- of the slice: every failure path lands on the still.

-- ---------------------------------------------------------------------------
-- A. The column.
-- ---------------------------------------------------------------------------
-- Nullable, and null is the ordinary case: most slides are a photograph. A
-- loop is an enhancement to a slide that already works without it.
alter table public.hero_slides
  add column if not exists motion_url text;

comment on column public.hero_slides.motion_url is
  'Cloudinary delivery URL for the slide''s looping animated WebP, derived from '
  'an uploaded MP4 by the admin console. Null means the slide is a still. The '
  'still in image_url is always present and is what shows under, before, and '
  'instead of this.';

-- ---------------------------------------------------------------------------
-- B. What may go in it.
-- ---------------------------------------------------------------------------
-- Three checks, and the third one is the reason this function exists rather
-- than the two lines of `like` the image gets inline.
--
--   1. Cloudinary-hosted — rule 2 of the slice, same as `image_url`.
--   2. A `/video/upload/` delivery URL ending `.webp`. A raw `.mp4` URL pasted
--      in here would be stored happily and then hand `Image.network` a file it
--      cannot decode: the loop would simply never appear, with nothing on
--      screen or in a log to say why.
--   3. It carries `fl_awebp`.
--
-- The third is not fussiness about a flag name. Cloudinary answers all four of
-- these with HTTP 200 and `Content-Type: image/webp`:
--
--   f_webp,fl_animated,fl_awebp,w_720,q_auto:eco,du_8,fps_12  → 1,137,876 bytes
--   f_webp,fl_animated,fl_awebp,w_800,q_auto:eco,du_6         → 2,458,744 bytes
--   f_webp,fl_animated,w_400                                  →     7,000 bytes
--   f_auto:animated,w_400                                     →     7,000 bytes
--
-- (measured against `demo/video/upload/dog`, 2026-07-27.) The last two are a
-- **single still frame**. Without `fl_awebp` the animation is dropped and what
-- comes back is a valid WebP image of the first frame — so the slide would show
-- a motionless picture on top of a motionless picture, look entirely correct,
-- and be broken. That is the exact failure this feature is most likely to ship
-- with, and it is one `position()` to refuse.
create or replace function public.assert_hero_motion(p_url text)
returns void
language plpgsql
immutable
security definer
set search_path = public
as $$
declare
  v_url text;
begin
  v_url := nullif(trim(coalesce(p_url, '')), '');
  if v_url is null then
    return;
  end if;

  if v_url not like 'https://res.cloudinary.com/%' then
    raise exception
      'A motion loop has to be uploaded here — that is not a Cloudinary URL.'
      using errcode = 'P0001';
  end if;

  if position('/video/upload/' in v_url) = 0 or v_url not like '%.webp' then
    raise exception
      'A motion loop has to be the delivered animated WebP (a /video/upload/ URL ending .webp), not the uploaded video.'
      using errcode = 'P0001';
  end if;

  if position('fl_awebp' in v_url) = 0 then
    raise exception
      'That URL would deliver a single still frame, not a loop. The transformation needs fl_awebp.'
      using errcode = 'P0001';
  end if;
end;
$$;

-- Called only by the RPC below, in its own definer context (the 0045 lesson).
revoke execute on function public.assert_hero_motion(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- C. The editor's read grows a column.
-- ---------------------------------------------------------------------------
-- Dropped and recreated rather than replaced. `create or replace function`
-- cannot change a function's return type, and adding a column to a `returns
-- table` is changing it — Postgres refuses with "cannot change return type of
-- existing function". Dropping first is the documented route.
--
-- Note this is a *drop*, not the overload trap ([[zopiqnow-postgres-function-overloads]]):
-- the argument list is unchanged, so there is only ever one of these and the
-- console cannot bind to a stale signature.
drop function if exists public.admin_list_hero_slides();

create or replace function public.admin_list_hero_slides()
returns table (
  id         uuid,
  title      text,
  subtitle   text,
  cta_label  text,
  cta_target text,
  image_url  text,
  motion_url text,
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
           s.motion_url, s.sort_order, s.is_active, s.starts_at, s.ends_at,
           s.created_at
      from public.hero_slides s
     order by s.sort_order, s.created_at;
end;
$$;

revoke execute on function public.admin_list_hero_slides() from public, anon;
grant execute on function public.admin_list_hero_slides() to authenticated;

-- ---------------------------------------------------------------------------
-- D. And so does the write.
-- ---------------------------------------------------------------------------
-- Replaced, not dropped: the argument list is `(jsonb)` before and after, so
-- there is no second signature for the console to bind to.
--
-- `motion_url` is written on both branches, and on update it is written
-- unconditionally — including to null. Removing a loop from a slide has to be
-- possible, and a form that writes every field every time (0053's reasoning)
-- is what makes clearing one an ordinary save rather than a special action.
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
  v_motion    text;
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

  -- The loop is optional and checked only if there is one. There is
  -- deliberately no "a slide with a loop must also have a still" rule, because
  -- the still is required of every slide already — rule 1 holds by construction
  -- rather than by a second check that could drift out of step with the first.
  v_motion := nullif(trim(coalesce(p_slide->>'motion_url', '')), '');
  perform public.assert_hero_motion(v_motion);

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
      title, subtitle, cta_label, cta_target, image_url, motion_url,
      sort_order, is_active, starts_at, ends_at
    )
    values (
      v_title,
      trim(coalesce(p_slide->>'subtitle', '')),
      coalesce(v_cta_label, 'Order now'),
      v_cta,
      v_image,
      v_motion,
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
           motion_url = v_motion,
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
