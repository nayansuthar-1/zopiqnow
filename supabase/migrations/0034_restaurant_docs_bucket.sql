-- Step 11, migration 34: somewhere private to put a licence scan.
--
-- Every image the platform has stored so far — restaurant covers, dishes, gift
-- photos — lives on Cloudinary behind an unsigned upload preset. That is right for
-- those: they are meant to be seen by everyone, the CDN is the point, and the
-- preset carries no secret worth stealing.
--
-- An FSSAI certificate and a PAN card are not that. A PAN scan is identity
-- documentation; put one on a public CDN and the URL is permanent, unauthenticated,
-- cached at edge nodes outside our control, and uploadable-to by anyone who reads
-- the preset name out of a JavaScript bundle. There is no revoking it afterwards.
--
-- So: a private bucket, reachable only by an admin's own session, and the database
-- stores a *path* rather than a URL. The console turns a path into a signed link
-- that expires; nothing anywhere holds a permanent public address for these files.

insert into storage.buckets (id, name, public)
values ('restaurant-docs', 'restaurant-docs', false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Only admins, and only this bucket.
-- ---------------------------------------------------------------------------
-- `storage.objects` already has RLS on and is shared by every bucket, so each
-- policy has to name the bucket it speaks for — without `bucket_id = …` these
-- would grant admins the run of all storage.
--
-- Note who is *not* here: the restaurant. A vendor cannot read the scans of their
-- own licence, for the same reason `restaurant_legal` has no policy for them
-- (0028) — what a restaurant has on file is a fact about them, not a document
-- they hold the pen on.
drop policy if exists "admins read restaurant docs" on storage.objects;
create policy "admins read restaurant docs"
  on storage.objects for select to authenticated
  using (bucket_id = 'restaurant-docs' and public.is_admin());

drop policy if exists "admins upload restaurant docs" on storage.objects;
create policy "admins upload restaurant docs"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'restaurant-docs' and public.is_admin());

drop policy if exists "admins replace restaurant docs" on storage.objects;
create policy "admins replace restaurant docs"
  on storage.objects for update to authenticated
  using (bucket_id = 'restaurant-docs' and public.is_admin())
  with check (bucket_id = 'restaurant-docs' and public.is_admin());

drop policy if exists "admins delete restaurant docs" on storage.objects;
create policy "admins delete restaurant docs"
  on storage.objects for delete to authenticated
  using (bucket_id = 'restaurant-docs' and public.is_admin());

-- ---------------------------------------------------------------------------
-- The columns say what they hold.
-- ---------------------------------------------------------------------------
-- 0028 named these `*_doc_url` when the plan was still a public CDN. They now hold
-- a bucket path — `<restaurant-id>/fssai-<timestamp>.pdf` — and a column called
-- `url` holding a path is the kind of small lie that costs somebody an afternoon
-- a year from now. Renamed rather than repurposed, and it is free to do: the table
-- is four days old and has no rows.
alter table public.restaurant_legal
  drop column if exists fssai_doc_url,
  drop column if exists pan_doc_url;

alter table public.restaurant_legal
  add column if not exists fssai_doc_path text,
  add column if not exists pan_doc_path   text;

-- `admin_set_legal` replaced to match. Everything else about it is unchanged.
create or replace function public.admin_set_legal(p_id text, p_legal jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  if nullif(trim(coalesce(p_legal ->> 'fssai_number', '')), '') is not null
     and trim(p_legal ->> 'fssai_number') !~ '^[0-9]{14}$' then
    raise exception 'An FSSAI licence number is 14 digits.' using errcode = 'P0001';
  end if;
  if nullif(trim(coalesce(p_legal ->> 'gst_number', '')), '') is not null
     and upper(trim(p_legal ->> 'gst_number'))
         !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$' then
    raise exception 'That GST number doesn''t look right.' using errcode = 'P0001';
  end if;
  if nullif(trim(coalesce(p_legal ->> 'pan_number', '')), '') is not null
     and upper(trim(p_legal ->> 'pan_number')) !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' then
    raise exception 'That PAN doesn''t look right.' using errcode = 'P0001';
  end if;

  insert into public.restaurant_legal (
    restaurant_id, fssai_number, fssai_expiry, fssai_doc_path,
    gst_number, pan_number, pan_doc_path, updated_at
  ) values (
    p_id,
    nullif(trim(coalesce(p_legal ->> 'fssai_number', '')), ''),
    (p_legal ->> 'fssai_expiry')::date,
    nullif(trim(coalesce(p_legal ->> 'fssai_doc_path', '')), ''),
    nullif(upper(trim(coalesce(p_legal ->> 'gst_number', ''))), ''),
    nullif(upper(trim(coalesce(p_legal ->> 'pan_number', ''))), ''),
    nullif(trim(coalesce(p_legal ->> 'pan_doc_path', '')), ''),
    now()
  )
  on conflict (restaurant_id) do update set
    fssai_number   = excluded.fssai_number,
    fssai_expiry   = excluded.fssai_expiry,
    fssai_doc_path = excluded.fssai_doc_path,
    gst_number     = excluded.gst_number,
    pan_number     = excluded.pan_number,
    pan_doc_path   = excluded.pan_doc_path,
    updated_at     = now();
end;
$$;

revoke execute on function public.admin_set_legal(text, jsonb) from public;
grant execute on function public.admin_set_legal(text, jsonb) to authenticated;
