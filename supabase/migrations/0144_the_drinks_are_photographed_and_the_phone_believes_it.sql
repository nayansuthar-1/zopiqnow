-- ---------------------------------------------------------------------------
-- 0144 — the drinks are photographed, and the phone believes it.
-- ---------------------------------------------------------------------------
-- The real packshots went up over the drawings on 29 August and did not appear
-- in the app. Nothing was wrong with the upload: all eight are on Cloudinary at
-- 600×600, `HTTP 200 image/jpeg`, and the Coca Cola is a photograph of the
-- actual Indian pack. The app was drawing month-old bytes.
--
-- ## Why an "invalidate" that worked did not help
--
-- 0140 stored the **un-versioned** URL on purpose —
--
--     https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/coca-cola.jpg
--
-- — so that replacing the artwork would be a re-run of `seed_beverages.mjs`
-- with no `UPDATE` and no migration. The upload sets `invalidate=true`, and the
-- seeder says in as many words that this "is what makes the un-versioned URL
-- safe to cache."
--
-- **That reasoning stops one layer short.** `invalidate` purges *Cloudinary's*
-- CDN. It cannot reach `ZopiqImageStore` — zopiq_ui's own on-disk cache, which
-- keys on the URL string, holds entries for **30 days** (`_maxAge`) and never
-- revalidates. There is no `If-None-Match`, no `HEAD`, no TTL from the server:
-- a URL that has been fetched once is answered from disk until it ages out or
-- the OS reclaims the cache directory. So every phone that opened a menu while
-- the drawn bottles were live is pinned to those bytes for a month, and the
-- one thing that cannot change what it draws is replacing the file behind the
-- URL.
--
-- Worse than showing the old art: the first drawing pass shipped SVG source
-- Flutter cannot decode, and those undecodable bytes cache exactly as happily.
-- `ZopiqNetworkImage` then falls through to `errorBuilder` → the gradient
-- placeholder — which is *no image at all*, which is what was reported.
--
-- ## The fix is the version segment, which is what it is for
--
-- Cloudinary returns `secure_url` carrying `/v<version>/`, and the version
-- changes on every overwrite. That is precisely a cache key that moves when the
-- bytes move, and it invalidates all three layers at once — CDN, Flutter's
-- in-memory `ImageCache`, and the disk store — because they all key on the URL.
-- 0140 read that changing segment as noise to be stripped; it is the signal.
--
-- The cost 0140 was avoiding is real and is simply paid: replacing a packshot
-- now needs the URL written down as well as uploaded. `seed_beverages.mjs` does
-- both from this commit, so it is still one command, and the versions below are
-- the ones live on Cloudinary as of this migration.
--
-- Nothing else about the rows moves — same 192 items, same prices, same slabs.
-- ---------------------------------------------------------------------------

update public.menu_items set image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/v1788010611/zopiqnow/beverages/coca-cola.jpg'
 where image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/coca-cola.jpg';

update public.menu_items set image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/v1788010613/zopiqnow/beverages/thums-up.jpg'
 where image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/thums-up.jpg';

update public.menu_items set image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/v1788010614/zopiqnow/beverages/sprite.jpg'
 where image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/sprite.jpg';

update public.menu_items set image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/v1788010616/zopiqnow/beverages/limca.jpg'
 where image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/limca.jpg';

update public.menu_items set image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/v1788010619/zopiqnow/beverages/fanta.jpg'
 where image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/fanta.jpg';

update public.menu_items set image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/v1788010620/zopiqnow/beverages/mirinda.jpg'
 where image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/mirinda.jpg';

update public.menu_items set image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/v1788010622/zopiqnow/beverages/7up.jpg'
 where image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/7up.jpg';

update public.menu_items set image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/v1788010623/zopiqnow/beverages/maaza.jpg'
 where image_url = 'https://res.cloudinary.com/w69i7qes/image/upload/zopiqnow/beverages/maaza.jpg';

