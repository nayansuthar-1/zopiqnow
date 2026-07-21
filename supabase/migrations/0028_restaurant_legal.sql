-- Step 11, migration 28: the papers that make a food business legal.
--
-- An FSSAI licence is not optional decoration — it is the thing that makes
-- listing a kitchen lawful, it expires, and when it expires the restaurant has to
-- come off the platform. None of it has been recorded anywhere until now.
--
-- Its own table rather than seven more columns on `restaurants`, for one reason
-- that matters: `restaurants` is world-readable. The customer-facing policy is
-- `using (is_active)` and it selects the whole row, so a licence number added
-- there would be published to every anonymous browser on the internet. A separate
-- table is the difference between "the admin can see it" and "everyone can".

create table if not exists public.restaurant_legal (
  restaurant_id text primary key
    references public.restaurants (id) on delete cascade,

  -- 14 digits, issued by FSSAI. Nullable like everything else here: a draft is
  -- allowed to be half-filled, and `admin_publish_restaurant` is what refuses to
  -- list a restaurant whose papers are missing.
  fssai_number  text,
  fssai_expiry  date,
  fssai_doc_url text,

  -- 15 characters: 2-digit state code, the holder's PAN, an entity number, 'Z',
  -- and a checksum character. Not every kitchen is GST-registered — a small one
  -- under the threshold legitimately has none — so this stays nullable even at
  -- publish time.
  gst_number    text,

  pan_number    text,
  pan_doc_url   text,

  updated_at    timestamptz not null default now(),

  constraint legal_fssai_is_fourteen_digits
    check (fssai_number is null or fssai_number ~ '^[0-9]{14}$'),
  constraint legal_gst_is_well_formed
    check (gst_number is null
           or gst_number ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$'),
  constraint legal_pan_is_well_formed
    check (pan_number is null or pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$')
);

-- RLS on, and *no policy at all* — not for a customer, not for a vendor, not even
-- for the restaurant these papers belong to. The table is unreachable through
-- PostgREST by anyone, and the only way in is `admin_set_legal` / `admin_get_legal`
-- (0030), which check `is_admin()` first.
--
-- The vendor exclusion is deliberate and worth stating plainly: a kitchen editing
-- its own recorded licence number is a kitchen that can keep operating on a licence
-- that lapsed. What a restaurant *has* is a fact about them, not a field they own.
alter table public.restaurant_legal enable row level security;
