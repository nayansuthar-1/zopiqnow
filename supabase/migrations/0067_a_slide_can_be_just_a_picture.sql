-- ---------------------------------------------------------------------------
-- 0067 — a slide can be just a picture.
-- ---------------------------------------------------------------------------
-- 0053 required a headline and gave `cta_label` a default of 'Order now', which
-- between them made every campaign the same shape: words over a photograph, with
-- a white pill under them. That is one kind of campaign. The other kind is a
-- piece of artwork that already says what it says — a designed banner with the
-- offer set into the image — and on that one the app's headline lands on top of
-- lettering that is already there, and the button covers the part the designer
-- put at the bottom.
--
-- So both become optional. **Empty string is the absence**, not null, because
-- `subtitle` has meant exactly that since 0053 (`not null default ''`, and the
-- app renders it only `if (s.subtitle.isNotEmpty)`). A third convention for the
-- same idea in the same table would be a coin-toss at every read site.
--
-- What stays required is the artwork, and more firmly than before: a slide with
-- no image, no headline and no button would be nothing at all, and the check
-- that refuses it is the same one 0053 already wrote.
--
-- **Sequencing, and it matters.** A customer build older than this migration
-- draws `Text('')` and a white pill with no words in it — not a crash, but an
-- empty button on a live campaign. The rows this enables are written by hand in
-- the console, so the rule is a human one rather than a constraint: **do not
-- publish a slide with an empty headline or an empty button until the customer
-- build that tolerates them is on phones.** Nothing already published changes —
-- every existing row has both, and this migration writes to none of them.

-- The default is dropped rather than changed. A column that defaults to
-- 'Order now' means *omitting* the field asks for a button, so the day some
-- other caller writes a row without naming a label it gets a button it never
-- asked for. There is exactly one writer (`admin_upsert_hero_slide`) and it
-- always names the value; the default was only ever a way of not deciding.
alter table public.hero_slides alter column cta_label drop default;

comment on column public.hero_slides.title is
  'The headline drawn over the artwork. Empty means the slide shows no headline — '
  'the artwork carries its own. Never null; empty string is the absence, as with subtitle.';

comment on column public.hero_slides.cta_label is
  'What the button says. Empty means the slide has no button, and the whole slide '
  'becomes the tap target instead. Never null.';

-- ---------------------------------------------------------------------------
-- The writer.
-- ---------------------------------------------------------------------------
-- Same argument list, so this replaces rather than overloads (0051's lesson).
create or replace function public.admin_upsert_hero_slide(p_slide jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id        uuid;
  v_title     text;
  v_subtitle  text;
  v_image     text;
  v_motion    text;
  v_cta_label text;
  v_cta       text;
  v_sort      integer;
  v_starts    timestamptz;
  v_ends      timestamptz;
begin
  perform public.assert_admin();

  v_id       := nullif(p_slide->>'id', '')::uuid;
  v_title    := trim(coalesce(p_slide->>'title', ''));
  v_subtitle := trim(coalesce(p_slide->>'subtitle', ''));
  v_image    := trim(coalesce(p_slide->>'image_url', ''));

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

  -- New in 0067: no coalesce to 'Order now'. An empty label is a slide with no
  -- button, and it is stored as the empty string the app tests for.
  v_cta_label := trim(coalesce(p_slide->>'cta_label', ''));

  -- A sub-line under a headline that is not there reads as a headline in the
  -- wrong size. Refused rather than silently promoted, because promoting it
  -- would mean the row no longer says what the admin typed.
  if v_title = '' and v_subtitle <> '' then
    raise exception 'A sub-line needs a headline above it. Put the text in the headline instead.'
      using errcode = 'P0001';
  end if;

  -- A destination with nothing to tap would be dead configuration — except that
  -- it is not, since 0067: a slide with no button makes the *whole slide* the
  -- tap target, so a target without a label is the ordinary way to ship a
  -- designed banner that opens a restaurant. Nothing to check here, and this
  -- comment exists so the next reader does not add a check.

  v_sort   := coalesce((p_slide->>'sort_order')::integer, 0);
  v_starts := coalesce((p_slide->>'starts_at')::timestamptz, now());
  v_ends   := nullif(p_slide->>'ends_at', '')::timestamptz;

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
      v_title, v_subtitle, v_cta_label, v_cta, v_image, v_motion, v_sort,
      coalesce((p_slide->>'is_active')::boolean, false),
      v_starts, v_ends
    )
    returning id into v_id;
  else
    update public.hero_slides
       set title      = v_title,
           subtitle   = v_subtitle,
           cta_label  = v_cta_label,
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

-- Re-stated, because `create or replace` keeps the existing grants and a reader
-- should not have to go and check that. 0065's rule: revoke from everybody, then
-- give it back to the caller that needs it.
revoke all on function public.admin_upsert_hero_slide(jsonb) from public, anon, authenticated;
grant execute on function public.admin_upsert_hero_slide(jsonb) to authenticated;
