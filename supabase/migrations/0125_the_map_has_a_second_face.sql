-- ---------------------------------------------------------------------------
-- 0125 — the tracking map has a second face, and the console paints it.
-- ---------------------------------------------------------------------------
-- An order in flight is the longest a customer ever looks at one screen, and
-- until now that screen has been a map and nothing else. This puts an ad beside
-- it: a round puck in the map's bottom-right corner that opens the advertiser's
-- artwork full-bleed, with the map collapsing into the same puck shape so the
-- two are always one tap apart.
--
-- **These are our ads, not a network's.** There is no SDK, no auction and no
-- third-party script — an admin uploads two images and the app draws them. That
-- is the whole reason this is a table rather than a dependency, and it is why
-- the customer app can keep its "no tracker in the binary" story.
--
-- **A CTA says where it goes by how it is written**, and there is no `cta_type`
-- column to disagree with it: a target starting `http` opens the phone's
-- browser, one starting `/` is a route inside the app, and an empty one means
-- the artwork has no button. Same reasoning as 0048's option groups — when the
-- value already answers the question, a second column only creates the chance
-- of two answers.

-- ---------------------------------------------------------------------------
-- A. The ads.
-- ---------------------------------------------------------------------------
create table if not exists public.order_ads (
  id          uuid primary key default gen_random_uuid(),

  -- Internal. The console's list reads this; a customer never sees it.
  name        text not null,

  -- The round puck: a logo on a solid ground, square, shown at 56px. Its own
  -- column rather than a crop of the creative, because the corner of a banner
  -- is never the brand mark.
  logo_url    text not null,

  -- The full-bleed artwork the puck opens. Tall — it fills a phone screen.
  image_url   text not null,

  -- Drawn over the artwork's foot, above the button. May be empty: a composed
  -- banner usually has its own words set into it, and a headline on top of
  -- those is the same sentence twice in two typefaces (0067 learned this on the
  -- home hero).
  headline    text not null default '',

  cta_label   text not null default '',
  cta_target  text not null default '',

  sort_order  integer not null default 0,
  is_active   boolean not null default false,
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,
  created_at  timestamptz not null default now(),

  constraint order_ads_window check (ends_at is null or ends_at > starts_at),
  constraint order_ads_sort_order check (sort_order >= 0),

  -- A button with no destination is a dead tap, and a destination with no button
  -- is unreachable. They arrive together or not at all.
  constraint order_ads_cta_is_whole
    check ((cta_label = '') = (cta_target = '')),

  -- The rule that replaces a type column. Anything else is a typo, and a typo
  -- here would be a button that silently does nothing on a customer's phone.
  constraint order_ads_target_is_reachable
    check (cta_target = '' or cta_target ~ '^(https?://|/)')
);

alter table public.order_ads enable row level security;

-- Live means active *and* inside its window — enforced here rather than in the
-- app, so a campaign scheduled for next week is unreadable rather than merely
-- undrawn. A client-side filter would ship it to every phone a week early
-- (0053's lesson, restated because it is the whole point of the policy).
drop policy if exists "live ads are world-readable" on public.order_ads;
create policy "live ads are world-readable"
  on public.order_ads for select
  to anon, authenticated
  using (
    is_active
    and now() >= starts_at
    and now() < coalesce(ends_at, 'infinity'::timestamptz)
  );

-- Tables are born writable (0089): the grants below are the refusal, and RLS is
-- only the second lock. Everything that writes an ad goes through an admin RPC.
revoke insert, update, delete, truncate on public.order_ads from anon, authenticated;

-- ---------------------------------------------------------------------------
-- B. What happened to them.
-- ---------------------------------------------------------------------------
-- One row per view and per click. `order_id` is what makes a view countable:
-- the tracking screen rebuilds on every rider ping, so an un-keyed insert would
-- count a five-minute wait as fifty impressions.
create table if not exists public.ad_events (
  id         bigint generated always as identity primary key,
  ad_id      uuid not null references public.order_ads (id) on delete cascade,
  kind       text not null check (kind in ('view', 'click')),

  -- Null once the order is deleted; the count it contributed stays. Support can
  -- remove an order (0069) and an advertiser's totals must not move when it does.
  order_id   text references public.orders (id) on delete set null,

  created_at timestamptz not null default now()
);

create index if not exists ad_events_ad_idx on public.ad_events (ad_id, kind);

-- **One view per ad per order.** The honest number is "how many orders saw
-- this", not "how many times a widget rebuilt". A click has no such index: two
-- taps are two taps, and an advertiser is paying for the second one too.
create unique index if not exists ad_events_one_view_per_order
  on public.ad_events (ad_id, order_id)
  where kind = 'view' and order_id is not null;

alter table public.ad_events enable row level security;
-- No select policy at all. This is the advertiser's report, not the customer's,
-- and it is read only through the admin function at the bottom of this file.
revoke insert, update, delete, truncate on public.ad_events from anon, authenticated;

-- ---------------------------------------------------------------------------
-- C. The customer records one.
-- ---------------------------------------------------------------------------
-- Security definer because the table refuses every direct write above. It
-- deliberately does **not** check that the order belongs to the caller: the
-- worst a forged order id buys is one extra impression on a counter, and the
-- alternative — reading `orders` on every map rebuild — costs a query per ping
-- to defend a number nobody bills on.
--
-- Silent about everything. An analytics ping that raises inside a build is a
-- crash on the tracking screen, which is the one screen that must never blink.
create or replace function public.record_ad_event(
  p_ad_id    uuid,
  p_kind     text,
  p_order_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_kind not in ('view', 'click') then
    return;
  end if;

  -- Only a live ad counts. An expired campaign still sitting on a phone that
  -- has not refreshed must not keep billing.
  if not exists (
    select 1 from public.order_ads a
     where a.id = p_ad_id
       and a.is_active
       and now() >= a.starts_at
       and now() < coalesce(a.ends_at, 'infinity'::timestamptz)
  ) then
    return;
  end if;

  insert into public.ad_events (ad_id, kind, order_id)
  values (p_ad_id, p_kind, p_order_id)
  on conflict do nothing;
exception
  when others then
    return;
end;
$$;

-- Functions are born PUBLIC-executable *and* granted to `authenticated` by
-- default (0087/0089) — so both have to go before the one grant that is meant.
revoke execute on function public.record_ad_event(uuid, text, text) from public;
revoke execute on function public.record_ad_event(uuid, text, text) from anon;
grant execute on function public.record_ad_event(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- D. The console.
-- ---------------------------------------------------------------------------
-- Every ad, live or not, with its totals. The console is the only caller and it
-- wants the whole list at once — there will be single figures of these, not
-- pages of them.
create or replace function public.admin_list_order_ads()
returns table (
  id         uuid,
  name       text,
  logo_url   text,
  image_url  text,
  headline   text,
  cta_label  text,
  cta_target text,
  sort_order integer,
  is_active  boolean,
  starts_at  timestamptz,
  ends_at    timestamptz,
  created_at timestamptz,
  views      bigint,
  clicks     bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select a.id, a.name, a.logo_url, a.image_url, a.headline,
           a.cta_label, a.cta_target, a.sort_order, a.is_active,
           a.starts_at, a.ends_at, a.created_at,
           count(e.id) filter (where e.kind = 'view')  as views,
           count(e.id) filter (where e.kind = 'click') as clicks
      from public.order_ads a
      left join public.ad_events e on e.ad_id = a.id
     group by a.id
     order by a.sort_order, a.created_at;
end;
$$;

revoke execute on function public.admin_list_order_ads() from public;
revoke execute on function public.admin_list_order_ads() from anon;
grant execute on function public.admin_list_order_ads() to authenticated;

-- Create (no id) or edit (with one). Every field every time, like the hero
-- slide writer it is modelled on: a partial save is how a campaign ends up with
-- last month's end date.
create or replace function public.admin_upsert_order_ad(p_ad jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := nullif(p_ad ->> 'id', '')::uuid;
begin
  perform public.assert_admin();

  if coalesce(p_ad ->> 'name', '') = '' then
    raise exception 'An ad needs a name.' using errcode = 'P0001';
  end if;
  if coalesce(p_ad ->> 'logo_url', '') = '' then
    raise exception 'An ad needs a logo for the map corner.' using errcode = 'P0001';
  end if;
  if coalesce(p_ad ->> 'image_url', '') = '' then
    raise exception 'An ad needs its full-screen artwork.' using errcode = 'P0001';
  end if;

  if v_id is null then
    insert into public.order_ads
      (name, logo_url, image_url, headline, cta_label, cta_target,
       sort_order, is_active, starts_at, ends_at)
    values (
      p_ad ->> 'name',
      p_ad ->> 'logo_url',
      p_ad ->> 'image_url',
      coalesce(p_ad ->> 'headline', ''),
      coalesce(p_ad ->> 'cta_label', ''),
      coalesce(p_ad ->> 'cta_target', ''),
      coalesce((p_ad ->> 'sort_order')::integer, 0),
      coalesce((p_ad ->> 'is_active')::boolean, false),
      coalesce((p_ad ->> 'starts_at')::timestamptz, now()),
      nullif(p_ad ->> 'ends_at', '')::timestamptz
    )
    returning id into v_id;
  else
    update public.order_ads set
      name       = p_ad ->> 'name',
      logo_url   = p_ad ->> 'logo_url',
      image_url  = p_ad ->> 'image_url',
      headline   = coalesce(p_ad ->> 'headline', ''),
      cta_label  = coalesce(p_ad ->> 'cta_label', ''),
      cta_target = coalesce(p_ad ->> 'cta_target', ''),
      sort_order = coalesce((p_ad ->> 'sort_order')::integer, 0),
      is_active  = coalesce((p_ad ->> 'is_active')::boolean, false),
      starts_at  = coalesce((p_ad ->> 'starts_at')::timestamptz, now()),
      ends_at    = nullif(p_ad ->> 'ends_at', '')::timestamptz
     where id = v_id;

    if not found then
      raise exception 'No such ad.' using errcode = 'P0001';
    end if;
  end if;

  return v_id;
end;
$$;

revoke execute on function public.admin_upsert_order_ad(jsonb) from public;
revoke execute on function public.admin_upsert_order_ad(jsonb) from anon;
grant execute on function public.admin_upsert_order_ad(jsonb) to authenticated;

-- Taking an ad down is the common act and must not need the editor.
create or replace function public.admin_set_order_ad_active(
  p_id     uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();
  update public.order_ads set is_active = p_active where id = p_id;
  if not found then
    raise exception 'No such ad.' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_set_order_ad_active(uuid, boolean) from public;
revoke execute on function public.admin_set_order_ad_active(uuid, boolean) from anon;
grant execute on function public.admin_set_order_ad_active(uuid, boolean) to authenticated;

-- Deleting takes the ad's events with it (cascade), and with them the numbers
-- the advertiser was shown. Deactivating is the reversible act; this one is not.
create or replace function public.admin_delete_order_ad(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();
  delete from public.order_ads where id = p_id;
  if not found then
    raise exception 'No such ad.' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.admin_delete_order_ad(uuid) from public;
revoke execute on function public.admin_delete_order_ad(uuid) from anon;
grant execute on function public.admin_delete_order_ad(uuid) to authenticated;

-- Deletes land in the audit trail with the admin who did them (0092), the same
-- as every other row an admin can remove.
drop trigger if exists order_ads_audit_delete on public.order_ads;
create trigger order_ads_audit_delete
  after delete on public.order_ads
  for each row execute function public.record_admin_action('id');

-- ---------------------------------------------------------------------------
-- The two standing release checks (0087, 0089) must still return zero rows.
-- ---------------------------------------------------------------------------
