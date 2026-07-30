-- ---------------------------------------------------------------------------
-- 0072 — the hero plays the video itself.
-- ---------------------------------------------------------------------------
-- 0054 made a slide able to move, and paid for it with resolution. The whole
-- design there was "no new dependency": the admin uploaded an MP4, Cloudinary
-- transcoded it to an **animated WebP**, and the phone decoded it through the
-- same `Image.network` path a still uses. Nothing in `pubspec.yaml` moved, and
-- the price was `w_720,fps_12` — a downscaled, twelve-frame stutter — because
-- animated WebP has **no interframe compression**. Every frame is a separate
-- still image, so quality costs bytes linearly and there is no way to have both.
--
-- Measured on `demo/video/upload/dog` (854×480, 29.97fps) on 2026-07-30, eight
-- seconds delivered in each case:
--
--   f_webp,fl_animated,fl_awebp,w_720,q_auto:eco,du_8,fps_12   → 1,137,876 B   (0054)
--   f_webp,fl_animated,fl_awebp,w_720,q_auto:good,du_8,fps_24  → 2,552,176 B
--   f_webp,fl_animated,fl_awebp,q_auto:good,du_8,fps_24        → 3,252,700 B
--   f_webp,fl_animated,fl_awebp,q_90,du_8,fps_30               → 9,085,966 B
--   f_mp4,vc_h264,ac_none,w_1080,c_limit,q_auto:best,du_8      →   599,018 B   (video)
--
-- (`du_8` on every row so the comparison is like-for-like. **The live transform has
-- no `du_` at all** — the whole clip plays and loops, which the same 13.4-second
-- source delivers in 1,128,474 B. Eight seconds was 0054's cap, and it existed
-- because animated WebP paid for length linearly in bytes the phone had to download
-- before showing a single frame. h.264 does not, and `video_player` streams, so the
-- cap was a property of the old format rather than of hero loops.)
--
-- Read the first and last lines together, because they are the entire argument
-- for this migration. **Real video at source resolution and the source frame
-- rate is a little over half the size of the downscaled twelve-frame WebP it
-- replaces.** The no-dependency route was not a cheap way to get motion; it was
-- an expensive way to get bad motion. h.264 spends its bytes on what changed
-- between frames, which is exactly what a hero loop mostly does not.
--
-- So the column now holds an `.mp4` delivery URL and the customer app plays it
-- with `video_player` (2.13.0), which is a deliberate, approved exception to the
-- version freeze rather than a drive-by addition. It resolved without moving a
-- single existing pin.
--
-- **What `fl_awebp` was for, and why it goes.** 0054 refused any URL without
-- that flag, and it was the best check in the file: without it Cloudinary answers
-- 200 with `Content-Type: image/webp` and a *single still frame*, so the slide
-- would look entirely correct and never move. That failure does not exist for a
-- video — an `.mp4` that does not play does not render either, and lands on the
-- still by the ordinary route. The check is not being relaxed out of laziness;
-- the thing it caught cannot happen any more.
--
-- **Sequencing, and it is safe in both directions.** A customer build older than
-- this hands the `.mp4` to `Image.network`, fails to decode it, and runs its
-- `errorBuilder` — which returns `SizedBox.shrink()`, leaving the still artwork
-- underneath on screen. That is rule 1 of the slice working as designed rather
-- than a lucky accident. It is also moot today: `hero_slides` holds **zero rows**
-- (verified against the live database, 2026-07-30), so no published campaign
-- changes shape and there is no `.webp` URL anywhere to migrate.
--
-- Which is also why this is `.mp4`-only rather than "either extension". There is
-- no legacy row to be tolerant of, and tolerating one would mean the app carried
-- two playback paths for ever, branching on a file extension, with the WebP one
-- exercised by nothing.

-- ---------------------------------------------------------------------------
-- What may go in the column.
-- ---------------------------------------------------------------------------
-- `create or replace`, and the argument list is `(text)` before and after — so
-- this replaces the one function rather than adding a second signature beside it
-- ([[zopiqnow-postgres-function-overloads]]).
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

  -- Rule 2, unchanged since 0053: slide media is Cloudinary-hosted, never
  -- hotlinked from somewhere that can go down or swap the file underneath us.
  if v_url not like 'https://res.cloudinary.com/%' then
    raise exception
      'A motion loop has to be uploaded here — that is not a Cloudinary URL.'
      using errcode = 'P0001';
  end if;

  if position('/video/upload/' in v_url) = 0 then
    raise exception
      'A motion loop has to be a Cloudinary /video/upload/ URL.'
      using errcode = 'P0001';
  end if;

  -- Named separately from the generic failure below, because this is the one
  -- wrong URL somebody will actually produce: a `.webp` loop URL from a 0054-era
  -- console, or copied out of an old row. "Not an mp4" would leave them looking
  -- for the mistake in a URL that used to be correct.
  if v_url like '%.webp' then
    raise exception
      'That is a 0054 animated-WebP URL. The hero plays real video now — re-upload the clip and save the .mp4 URL the console returns.'
      using errcode = 'P0001';
  end if;

  -- The extension is what decides the delivered format, so it is the whole check
  -- and there is nothing softer to fall back on: `video_player` is handed this
  -- string directly, and anything that is not an h.264 MP4 is a loop that
  -- silently never appears.
  if v_url not like '%.mp4' then
    raise exception
      'A motion loop has to be the delivered MP4 (a /video/upload/ URL ending .mp4).'
      using errcode = 'P0001';
  end if;
end;
$$;

-- Restated rather than assumed. `create or replace` keeps the existing grants,
-- and 0054's point stands: this is called only by `admin_upsert_hero_slide`, in
-- that function's own definer context (the 0045 lesson).
revoke all on function public.assert_hero_motion(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- What the column means.
-- ---------------------------------------------------------------------------
comment on column public.hero_slides.motion_url is
  'Cloudinary /video/upload/ delivery URL for the slide''s silent looping MP4 '
  '(h.264, source resolution to a 1080px limit, whole clip — no duration cap), '
  'derived from the admin''s upload by the console. Played by video_player on the '
  'phone, which streams it. Null means '
  'the slide is a still. The still in image_url is always present and is what shows '
  'under, before, and instead of this — including on any customer build that '
  'predates 0072, which cannot decode an MP4 and falls back to the artwork.';
