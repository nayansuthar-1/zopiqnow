-- Step, migration 20: where to reach a kitchen that isn't looking.
--
-- Phase 7, the push half. Everything so far assumes the vendor is watching the
-- queue. This is for when it isn't — the app asleep in an apron pocket, the
-- tablet dark on the counter. A device that has signed in registers a Firebase
-- token here; when an order lands, the send side (an Edge Function, out of band)
-- reads the tokens for that restaurant and rings them.
--
-- The token is a routing address, not a secret and not an authority: holding one
-- lets the platform *notify* a device, nothing more. As everywhere, the vendor
-- writes only its own, through a function scoped to `staff_restaurant_id()`, and
-- never reads the table at all — only the service role (the sender) does.

-- ---------------------------------------------------------------------------
-- One row per device that can be woken, keyed by its Firebase token.
-- ---------------------------------------------------------------------------
-- The token is the primary key: it is unique per install, and a device that
-- re-registers (a refreshed token, a staff member signing into a different
-- kitchen) upserts its row rather than growing a second. `restaurant_id` is who
-- to ring for — the sender's whole query is "tokens for this restaurant".
create table if not exists public.device_tokens (
  token         text primary key,
  restaurant_id text not null references public.restaurants (id) on delete cascade,
  platform      text not null default 'android' check (platform in ('android', 'ios')),
  updated_at    timestamptz not null default now()
);

create index if not exists device_tokens_restaurant_idx
  on public.device_tokens (restaurant_id);

-- RLS on, and deliberately no policy for `authenticated`: a vendor never selects,
-- inserts, updates, or deletes this table directly. The two functions below are
-- the only doors, and the sender reads it as the service role, which bypasses RLS.
alter table public.device_tokens enable row level security;

-- ---------------------------------------------------------------------------
-- register: this device, for my kitchen.
-- ---------------------------------------------------------------------------
-- Upsert, so a token that already exists is simply re-pointed at the caller's
-- restaurant and its time bumped — the case where a shared tablet moves from one
-- of a chain's kitchens to another. Scoped to `staff_restaurant_id()`; a vendor
-- can only ever register a device to the restaurant it works at.
create or replace function public.register_device_token(
  p_token    text,
  p_platform text default 'android'
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

  if p_token is null or length(trim(p_token)) = 0 then
    return;
  end if;

  insert into public.device_tokens (token, restaurant_id, platform, updated_at)
  values (p_token, v_restaurant, coalesce(p_platform, 'android'), now())
  on conflict (token) do update
    set restaurant_id = excluded.restaurant_id,
        platform      = excluded.platform,
        updated_at    = now();
end;
$$;

grant execute on function public.register_device_token(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- unregister: this device is signing out, stop ringing it.
-- ---------------------------------------------------------------------------
-- Deletes by token alone. A token is unguessable and install-unique, so a caller
-- naming one is the device that holds it; there is nothing here to scope to a
-- restaurant, and a signed-out device should stop buzzing immediately.
create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_tokens where token = p_token;
$$;

grant execute on function public.unregister_device_token(text) to authenticated;
