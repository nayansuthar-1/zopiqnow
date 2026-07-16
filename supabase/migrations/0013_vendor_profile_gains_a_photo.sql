-- Step 10, migration 13: the restaurant's cover photo joins its editable profile.
--
-- 0012 gave the vendor six columns it could edit through update_restaurant_profile.
-- Photo upload was the one thing it left out, because there was no CDN to upload to
-- (PM §6). There is now — Cloudinary — so `image_url` becomes the seventh column the
-- vendor owns, and it rides the exact same door as the other six: no update grant on
-- `restaurants`, one function, a fixed set of columns.
--
-- The image itself is not here and never will be. The app uploads the photo straight
-- to Cloudinary and stores only the URL it gets back — a reference, the same way
-- `image_url` has always held one. The bytes live on the CDN; the string lives here.

-- The 6-argument version is replaced outright rather than left as an overload — a
-- second signature of the same name is a second thing to keep in step, and one of
-- them would drift.
drop function if exists public.update_restaurant_profile(
  text, text[], integer, boolean, text, integer
);

create or replace function public.update_restaurant_profile(
  p_name          text,
  p_cuisines      text[],
  p_price_for_two integer,
  p_is_veg        boolean,
  p_promo_text    text,
  p_eta_minutes   integer,
  p_image_url     text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Your restaurant needs a name.' using errcode = 'P0001';
  end if;
  if p_price_for_two is null or p_price_for_two <= 0 then
    raise exception 'The cost for two has to be more than zero.'
      using errcode = 'P0001';
  end if;
  if p_eta_minutes is null or p_eta_minutes <= 0 then
    raise exception 'The prep time has to be more than zero minutes.'
      using errcode = 'P0001';
  end if;

  update public.restaurants
     set name          = trim(p_name),
         cuisines      = coalesce(p_cuisines, '{}'),
         price_for_two = p_price_for_two,
         is_veg        = coalesce(p_is_veg, false),
         promo_text    = nullif(trim(coalesce(p_promo_text, '')), ''),
         eta_minutes   = p_eta_minutes,
         -- `restaurants.image_url` is not-null with a '' default (0001). A vendor
         -- who has not set a photo passes null, which coalesces to '' — the empty
         -- string the customer app already reads as "no photo, draw the fallback".
         image_url     = coalesce(p_image_url, '')
   where id = v_restaurant;
end;
$$;

grant execute on function public.update_restaurant_profile(
  text, text[], integer, boolean, text, integer, text
) to authenticated;
