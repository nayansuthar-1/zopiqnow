-- ---------------------------------------------------------------------------
-- 0083 — an admin can vouch for a rider. (extends 0080 / audit RID-002)
-- ---------------------------------------------------------------------------
-- 0080 made documents the only route to work: `rider_is_verified` reads the
-- filed licence, insurance, ID and RC, and five paths refuse a rider who has
-- none. That was the point of the finding, and it stays the point.
--
-- It also left the platform with no way to put a rider on the road *today*. Every
-- rider on the roster the day 0080 shipped was blocked, and a real fleet has
-- people whose papers are on the way, whose scans are unreadable, or who were
-- taken on by somebody who knows them. An operator with no answer to that either
-- stops delivering or starts editing the database by hand, and the second is
-- worse than the thing the gate was protecting against.
--
-- So: an **override** — and deliberately not a second way of saying "verified".
--
--   * It is stored in its own columns, not by writing `status = 'verified'`. The
--     status column keeps meaning *somebody read the documents*, which is the
--     only thing that makes it worth reading.
--   * It **requires a reason**, in the admin's own words, the way a rejection
--     already does.
--   * It records **who** and **when**.
--   * It may carry an **expiry**. An override with no end is how a safety gate
--     quietly stops existing; `override_until` lets "he's bringing the licence on
--     Monday" actually mean Monday. Null is still allowed, because sometimes the
--     answer really is "this person is fine" — but it is a choice somebody makes,
--     not the default shape of the feature.
--   * It is **visible everywhere an admin looks**. The console shows a rider
--     working on an override differently from one working on papers, because the
--     day something goes wrong at a door, "who let this person work" needs an
--     answer that is on the screen rather than in the table.
--
-- What it does *not* do: it does not mark documents as seen, it does not clear a
-- rejection, and it does not survive being switched off. Turning it off puts the
-- rider back exactly where their documents leave them.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. The columns.
-- ---------------------------------------------------------------------------
alter table public.rider_legal
  add column if not exists override_reason text,
  add column if not exists override_by     text,
  add column if not exists override_at     timestamptz,
  add column if not exists override_until  date;

comment on column public.rider_legal.override_reason is
  'Why an admin let this rider work without the documents on file. Required '
  'while the override is on; cleared when it is switched off.';
comment on column public.rider_legal.override_until is
  'Last day the override applies. Null means it does not expire on its own.';

-- An override is on when there is a reason and it has not run out. One
-- expression, written once, because three functions below ask the same question
-- and three copies of it would eventually disagree.
create or replace function public.rider_override_active(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.rider_legal l
     where l.partner_email = p_email
       and nullif(trim(coalesce(l.override_reason, '')), '') is not null
       and (l.override_until is null or l.override_until >= current_date)
  );
$$;

revoke execute on function public.rider_override_active(text) from public, anon;
grant execute on function public.rider_override_active(text) to authenticated;

-- ---------------------------------------------------------------------------
-- B. The gate learns about it.
-- ---------------------------------------------------------------------------
-- Same shape as 0080's, with the override as an alternative route rather than a
-- replacement for the document test. A rider with valid papers does not need it;
-- a rider with an override does not need papers. Nobody needs both.
create or replace function public.rider_is_verified(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.rider_override_active(p_email)
      or exists (
    select 1
      from public.delivery_partners p
      join public.rider_legal l on l.partner_email = p.email
     where p.email = p_email
       and l.status = 'verified'
       and (
         p.vehicle = 'bicycle'
         or (l.licence_expiry   >= current_date
         and l.insurance_expiry >= current_date)
       )
  );
$$;

-- And the sentence the rider reads. Checked first: an overridden rider is not
-- blocked, so none of the reasons below apply to them and returning one would be
-- telling somebody who can work that they cannot.
create or replace function public.rider_work_block(p_email text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_vehicle text;
  v_legal   public.rider_legal%rowtype;
begin
  select vehicle into v_vehicle
    from public.delivery_partners where email = p_email;

  if not found then
    return 'You are not a Zopiqnow delivery partner.';
  end if;

  if public.rider_override_active(p_email) then
    return null;
  end if;

  select * into v_legal
    from public.rider_legal where partner_email = p_email;

  if not found or v_legal.status = 'pending' then
    return 'Your documents are still being checked. You can start taking deliveries as soon as they are verified.';
  end if;

  if v_legal.status = 'rejected' then
    return coalesce(
      nullif(trim(v_legal.rejected_reason), ''),
      'Your documents were not accepted.'
    ) || ' Call Zopiqnow support to sort it out.';
  end if;

  if v_vehicle <> 'bicycle' then
    if v_legal.licence_expiry < current_date then
      return 'Your driving licence expired on '
             || to_char(v_legal.licence_expiry, 'DD Mon YYYY')
             || '. Send us the renewed one to start taking deliveries again.';
    end if;
    if v_legal.insurance_expiry < current_date then
      return 'Your insurance expired on '
             || to_char(v_legal.insurance_expiry, 'DD Mon YYYY')
             || '. Send us the renewed policy to start taking deliveries again.';
    end if;
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- C. Switching it on and off.
-- ---------------------------------------------------------------------------
-- Its own verb, not a flag on `admin_review_rider_kyc`. Reviewing documents and
-- deciding to do without them are different acts by different reasoning, and a
-- boolean bolted onto the review call is one mis-click away from verifying a
-- rider nobody checked.
--
-- Creates the `rider_legal` row if there is none, which is the ordinary case
-- here: the rider this exists for is precisely the one nothing has been filed
-- for.
create or replace function public.admin_override_rider_kyc(
  p_email  text,
  p_on     boolean,
  p_reason text default null,
  p_until  date default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text;
  v_admin  text;
  v_reason text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));
  v_admin := lower(auth.jwt() ->> 'email');

  if not exists (select 1 from public.delivery_partners where email = v_email) then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;

  if p_on then
    v_reason := nullif(trim(coalesce(p_reason, '')), '');
    if v_reason is null then
      raise exception 'Say why this rider can work without their documents.'
        using errcode = 'P0001';
    end if;

    -- A date already gone would switch the override on and off in the same
    -- statement, which reads as a bug rather than a refusal.
    if p_until is not null and p_until < current_date then
      raise exception 'That date has already passed.' using errcode = 'P0001';
    end if;

    insert into public.rider_legal (partner_email, override_reason, override_by,
                                    override_at, override_until)
    values (v_email, v_reason, v_admin, now(), p_until)
    on conflict (partner_email) do update
       set override_reason = excluded.override_reason,
           override_by     = excluded.override_by,
           override_at     = excluded.override_at,
           override_until  = excluded.override_until,
           updated_at      = now();
  else
    -- Off puts the rider back exactly where their documents leave them — which
    -- may well be blocked, and that is the point of switching it off.
    update public.rider_legal
       set override_reason = null,
           override_by     = null,
           override_at     = null,
           override_until  = null,
           updated_at      = now()
     where partner_email = v_email;
  end if;

  -- Told, not left to discover it. Wrapped for the same reason 0080 wraps its
  -- own: the decision is the event, the notification is a courtesy on top.
  begin
    insert into public.notifications (audience, partner_email, kind, title, body)
    values ('rider', v_email, 'account',
            case when p_on then 'You can start taking deliveries'
                 else 'Your temporary clearance has ended' end,
            case when p_on
                 then 'Zopiqnow has cleared you to work while your documents are sorted out.'
                      || case when p_until is null then ''
                              else ' This lasts until '
                                   || to_char(p_until, 'DD Mon YYYY') || '.' end
                 else 'Send us your documents to start taking deliveries again.' end);
  exception when others then
    null;
  end;
end;
$$;

revoke execute on function public.admin_override_rider_kyc(text, boolean, text, date)
  from public, anon;
grant execute on function public.admin_override_rider_kyc(text, boolean, text, date)
  to authenticated;

-- ---------------------------------------------------------------------------
-- D. The console has to be able to see it.
-- ---------------------------------------------------------------------------
-- Both readers gain columns, so both are dropped and recreated: `create or
-- replace` cannot change a function's return type. Dropping takes the grants
-- with it, so both are re-granted below — the thing SEC-002 was about, and the
-- easiest thing in the world to forget on a `drop`.
drop function if exists public.admin_get_rider_kyc(text);

create function public.admin_get_rider_kyc(p_email text)
returns table (
  partner_email      text,
  vehicle            text,
  licence_number     text,
  licence_expiry     date,
  licence_doc_path   text,
  insurance_policy   text,
  insurance_expiry   date,
  insurance_doc_path text,
  id_proof_kind      text,
  id_proof_number    text,
  id_proof_doc_path  text,
  vehicle_number     text,
  rc_doc_path        text,
  status             text,
  rejected_reason    text,
  reviewed_at        timestamptz,
  reviewed_by        text,
  blocked_reason     text,
  override_reason    text,
  override_by        text,
  override_at        timestamptz,
  override_until     date,
  override_active    boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  perform public.assert_admin();
  v_email := lower(trim(p_email));

  return query
    select p.email, p.vehicle,
           l.licence_number, l.licence_expiry, l.licence_doc_path,
           l.insurance_policy, l.insurance_expiry, l.insurance_doc_path,
           l.id_proof_kind, l.id_proof_number, l.id_proof_doc_path,
           l.vehicle_number, l.rc_doc_path,
           coalesce(l.status, 'pending'),
           l.rejected_reason, l.reviewed_at, l.reviewed_by,
           public.rider_work_block(p.email),
           l.override_reason, l.override_by, l.override_at, l.override_until,
           public.rider_override_active(p.email)
      from public.delivery_partners p
      left join public.rider_legal l on l.partner_email = p.email
     where p.email = v_email;
end;
$$;

revoke execute on function public.admin_get_rider_kyc(text) from public, anon;
grant execute on function public.admin_get_rider_kyc(text) to authenticated;

drop function if exists public.admin_list_riders();

create function public.admin_list_riders()
returns table (
  email            text,
  name             text,
  phone            text,
  vehicle          text,
  is_active        boolean,
  created_at       timestamptz,
  live_order_id    text,
  delivered_count  integer,
  kyc_status       text,
  kyc_blocked      boolean,
  kyc_overridden   boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select p.email, p.name, p.phone, p.vehicle, p.is_active, p.created_at,
           (select d.order_id
              from public.deliveries d
              join public.orders o on o.id = d.order_id
             where d.partner_email = p.email
               and d.state not in ('delivered', 'cancelled')
               and o.status not in ('delivered', 'cancelled', 'rejected')
             limit 1),
           (select count(*)::integer
              from public.deliveries d
             where d.partner_email = p.email
               and d.state = 'delivered'),
           coalesce(l.status, 'pending'),
           -- Not the same question as `status <> 'verified'`: a verified rider
           -- whose insurance lapsed last night is still 'verified' here and is
           -- still blocked, and the console needs to show the second thing.
           not public.rider_is_verified(p.email),
           -- And a third question again: *why* they are not blocked. A rider
           -- working on somebody's say-so should never be counted in the same
           -- breath as one whose papers were read.
           public.rider_override_active(p.email)
      from public.delivery_partners p
      left join public.rider_legal l on l.partner_email = p.email
     order by not public.rider_is_verified(p.email) desc,
              p.is_active desc, p.created_at;
end;
$$;

revoke execute on function public.admin_list_riders() from public, anon;
grant execute on function public.admin_list_riders() to authenticated;
