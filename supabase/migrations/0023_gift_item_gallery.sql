-- Migration 23: a gift can have more than one photo.
--
-- Handmade products are bought on their detail: the front, the side, the mirror
-- work up close. One `image_url` (0022) could only ever show the first of those.
-- `image_urls` carries the whole set, in display order, so the detail screen can
-- offer a swipeable gallery.
--
-- `image_url` stays as the card thumbnail — the single image a grid cell shows —
-- and by convention it is `image_urls[1]` (the primary). Keeping both means the
-- card and every existing query keep working untouched; only the detail screen
-- reads the array.

alter table public.gift_items
  add column if not exists image_urls text[] not null default '{}';
