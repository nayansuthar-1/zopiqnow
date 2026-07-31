-- ---------------------------------------------------------------------------
-- 0080 — a stranger at the door has papers. (audit RID-002)
-- ---------------------------------------------------------------------------
-- A rider is added by an admin typing a name, an email and a phone number
-- (`admin_add_rider`, 0040). Nothing else is asked and nothing else is kept. The
-- platform then sends that person to a stranger's home, at night, holding their
-- dinner and sometimes their cash — on the strength of an email address.
--
-- The audit calls this a legal and safety exposure rather than a feature gap and
-- it is right. What is missing is three separate things wearing one name:
--
--   1. **A record.** No licence number, no insurance policy, no ID, no vehicle
--      registration. When something goes wrong at a door there is nothing to
--      hand a police officer or an insurer.
--   2. **The documents themselves.** Nowhere to put a licence scan, and — this
--      matters — nowhere *safe*. See the bucket note below.
--   3. **A workflow.** No verified/rejected state, so nothing distinguishes a
--      rider whose papers were read from one whose papers were never asked for,
--      and nothing anywhere refuses work to the second.
--
-- All three, and the refusal has teeth: an unverified rider cannot go online,
-- sees an empty board, cannot claim, cannot accept an offer, and is not a
-- dispatch candidate.
--
-- **A licence expires.** So verification is not a flag somebody sets once. It is
-- recomputed on every read from the expiry dates, and a rider whose insurance
-- lapsed on Tuesday stops being offered work on Tuesday without anybody
-- remembering to go and switch them off.
--
-- **A bicycle has no licence, no insurance and no registration.** `vehicle`
-- has allowed 'bicycle' since the table was created. Requiring those three of a
-- bicycle rider would be requiring documents that do not exist, and the only way
-- to satisfy the requirement would be to write something untrue in the box. They
-- are asked for ID and nothing else.
--
-- **Who uploads.** The admin, in the console — the same shape as restaurant
-- onboarding (0028/0034) and the same reason: this platform has no self-service
-- onboarding of any kind. The rider app shows the rider their own *status* and
-- never their own documents, exactly as a vendor cannot read the scans of their
-- own FSSAI licence. What we hold on file about somebody is a fact about them;
-- it is not a document they hold the pen on.

-- ---------------------------------------------------------------------------
-- Somewhere private to put a licence scan — the rider's half of 0034.
-- ---------------------------------------------------------------------------
-- Everything in 0034's opening argument applies here and applies harder. A
-- restaurant's FSSAI certificate is a business licence; a rider's Aadhaar card is
-- a human being's identity document, and this fleet is the group least able to
-- absorb the consequences of it leaking. Cloudinary's unsigned preset — right for
-- a dish photo, which is *meant* to be public — would give each of these a
-- permanent unauthenticated URL cached at edge nodes we do not control, with no
-- way to revoke it afterwards.
--
-- So: a private bucket, an admin's own session or nothing, and the database holds
-- a *path*. The console turns a path into a link that dies in five minutes.
insert into storage.buckets (id, name, public)
values ('rider-docs', 'rider-docs', false)
on conflict (id) do nothing;

-- `storage.objects` has RLS on and is shared by every bucket, so each policy has
-- to name the bucket it speaks for — without `bucket_id = …` these would grant
-- admins the run of all storage.
drop policy if exists "admins read rider docs" on storage.objects;
create policy "admins read rider docs"
  on storage.objects for select to authenticated
  using (bucket_id = 'rider-docs' and public.is_admin());

drop policy if exists "admins upload rider docs" on storage.objects;
create policy "admins upload rider docs"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'rider-docs' and public.is_admin());

drop policy if exists "admins replace rider docs" on storage.objects;
create policy "admins replace rider docs"
  on storage.objects for update to authenticated
  using (bucket_id = 'rider-docs' and public.is_admin())
  with check (bucket_id = 'rider-docs' and public.is_admin());

drop policy if exists "admins delete rider docs" on storage.objects;
create policy "admins delete rider docs"
  on storage.objects for delete to authenticated
  using (bucket_id = 'rider-docs' and public.is_admin());

-- ---------------------------------------------------------------------------
-- What we hold on file about a rider.
-- ---------------------------------------------------------------------------
-- Deliberately its own table rather than columns on `delivery_partners`, for the
-- reason 0028 gave for `restaurant_legal`: that table is read on the hot path by
-- the dispatcher, by the customer's tracking screen and by every vendor looking
-- at a live order, and none of them have any business being one typo away from a
-- rider's Aadhaar number.
create table if not exists public.rider_legal (
  partner_email     text primary key
                      references public.delivery_partners(email) on delete cascade,

  -- The licence. `expiry` is the column the gate actually reads; the number is
  -- what gets quoted to an insurer or a police officer.
  licence_number    text,
  licence_expiry    date,
  licence_doc_path  text,

  -- Third-party motor insurance is compulsory in India for a motorised vehicle,
  -- and the platform carrying no record of it is the exposure the finding names.
  insurance_policy  text,
  insurance_expiry  date,
  insurance_doc_path text,

  -- Identity. Either is accepted; a rider without a PAN is common and a rider
  -- without an Aadhaar is not, so refusing one of them would be refusing riders.
  id_proof_kind     text,
  id_proof_number   text,
  id_proof_doc_path text,

  -- The bike itself, so an incident can be traced to a vehicle and not only to a
  -- person.
  vehicle_number    text,
  rc_doc_path       text,

  status            text not null default 'pending',
  rejected_reason   text,
  reviewed_at       timestamptz,
  reviewed_by       text,
  updated_at        timestamptz not null default now()
);

do $$
begin
  -- Written as guarded `alter`s rather than inline in the `create` so that a
  -- re-run against a database that already has the table still lands them.
  if not exists (select 1 from pg_constraint where conname = 'rider_legal_status_check') then
    alter table public.rider_legal add constraint rider_legal_status_check
      check (status in ('pending', 'verified', 'rejected'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'rider_legal_id_proof_kind_check') then
    alter table public.rider_legal add constraint rider_legal_id_proof_kind_check
      check (id_proof_kind is null or id_proof_kind in ('aadhaar', 'pan'));
  end if;

  -- Twelve digits for an Aadhaar, and the PAN pattern `restaurant_legal` already
  -- uses. Checked against the *kind*, because a twelve-digit PAN is as wrong as a
  -- ten-character Aadhaar and a column-blind regex would accept both.
  if not exists (select 1 from pg_constraint where conname = 'rider_legal_id_proof_number_check') then
    alter table public.rider_legal add constraint rider_legal_id_proof_number_check
      check (
        id_proof_number is null
        or (id_proof_kind = 'aadhaar' and id_proof_number ~ '^[0-9]{12}$')
        or (id_proof_kind = 'pan'     and id_proof_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$')
      );
  end if;

  -- A registration plate: two letters of state, one or two of RTO, an optional
  -- series, four digits. Deliberately loose at the series — the format has been
  -- revised enough times that a tight pattern would reject real plates, and this
  -- is a record we keep rather than a key we look anything up by.
  if not exists (select 1 from pg_constraint where conname = 'rider_legal_vehicle_number_check') then
    alter table public.rider_legal add constraint rider_legal_vehicle_number_check
      check (vehicle_number is null or vehicle_number ~ '^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}$');
  end if;

  -- No pattern on the licence number on purpose. A driving licence number in
  -- India is state-issued and the formats genuinely differ; every tight regex
  -- published for it rejects somebody's real licence. Length is the honest
  -- check, and a human is reading the scan anyway — that is the whole point of
  -- the workflow below.
  if not exists (select 1 from pg_constraint where conname = 'rider_legal_licence_number_check') then
    alter table public.rider_legal add constraint rider_legal_licence_number_check
      check (licence_number is null or length(licence_number) between 8 and 20);
  end if;
end $$;

alter table public.rider_legal enable row level security;

-- No policy, for anyone. Not the rider, not the vendor, not the customer: every
-- read of this table goes through a `security definer` function below, and the
-- one a rider can call returns a status and two dates and never a number or a
-- path. 0034 made the same call for `restaurant_legal` and named the reason.
--
-- The revoke is not decoration. A new table arrives carrying whatever
-- `alter default privileges` hands out, and 0073 closed those for `public` and
-- `anon` but not for `authenticated` — so without this line every signed-in
-- customer of this platform could select the fleet's Aadhaar numbers, RLS or no
-- RLS, the moment they thought to try.
revoke all on public.rider_legal from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Is this rider allowed to work?
-- ---------------------------------------------------------------------------
-- One function, five call sites. Recomputed on every read rather than stored,
-- so an expiry takes effect on the day it falls due and not on the day somebody
-- notices.
create or replace function public.rider_is_verified(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
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

revoke execute on function public.rider_is_verified(text) from public, anon;
grant execute on function public.rider_is_verified(text) to authenticated;

-- The same question, answered in a sentence the rider can act on. Null means
-- "nothing is stopping you".
--
-- Separate from the boolean above rather than folded into it because the two
-- have different jobs: the dispatcher needs a fast predicate it can put in a
-- `where` clause, and a rider standing in the street needs to be told which
-- document and which date.
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

revoke execute on function public.rider_work_block(text) from public, anon;
grant execute on function public.rider_work_block(text) to authenticated;

-- ---------------------------------------------------------------------------
-- What the rider sees about themselves.
-- ---------------------------------------------------------------------------
-- Status, the two dates that can take it away, and the sentence. No numbers, no
-- paths: a rider knowing their licence is on file is the point, and a rider's
-- phone holding a copy of their own Aadhaar number is a liability we can decline
-- to create.
--
-- `days_to_expiry` rather than a bare date so the app can warn *before* the
-- morning somebody's shift does not start.
create or replace function public.my_kyc()
returns table(
  status          text,
  blocked_reason  text,
  licence_expiry  date,
  insurance_expiry date,
  days_to_expiry  integer,
  documents_needed boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rider text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  return query
    select coalesce(l.status, 'pending'),
           public.rider_work_block(v_rider),
           case when p.vehicle = 'bicycle' then null else l.licence_expiry end,
           case when p.vehicle = 'bicycle' then null else l.insurance_expiry end,
           case
             when p.vehicle = 'bicycle' then null
             else (least(l.licence_expiry, l.insurance_expiry) - current_date)::integer
           end,
           l.partner_email is null
      from public.delivery_partners p
      left join public.rider_legal l on l.partner_email = p.email
     where p.email = v_rider;
end;
$$;

revoke execute on function public.my_kyc() from public, anon;
grant execute on function public.my_kyc() to authenticated;

-- ---------------------------------------------------------------------------
-- The gate, on all five doors.
-- ---------------------------------------------------------------------------
-- Not one door. `delivery_partner_email()` would have been the single choke
-- point and is the wrong place: it gates reads as well as writes, and a rider
-- waiting on verification must still be able to sign in, see why, and look at
-- what they earned last week. So the check goes on the five paths that lead to
-- *work*, and nowhere near the ones that lead to information.
--
-- A rider already carrying a bag when their insurance lapses keeps that job.
-- Only new work is refused — `set_rider_online` has refused to let anyone go
-- offline holding somebody's dinner since 0049, and stranding a live order at a
-- kerb would be a worse answer to an expired policy than finishing it.

-- 1 of 5 — going on shift.
create or replace function public.set_rider_online(p_online boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider text;
  v_live  integer;
  v_block text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  if p_online is null then
    raise exception 'Online or offline — not neither.' using errcode = 'P0001';
  end if;

  -- New in 0080. Only on the way *on*: a rider whose papers lapse mid-shift must
  -- still be able to go offline, and refusing that would trap them online.
  if p_online then
    v_block := public.rider_work_block(v_rider);
    if v_block is not null then
      raise exception '%', v_block using errcode = 'P0001';
    end if;
  end if;

  -- You may not end a shift holding somebody's dinner. The order would be off
  -- the board (the partial unique index keeps it there) with nobody looking at
  -- it and no screen anywhere able to fix that — the same trap 0040 guards for
  -- deactivation, arriving here for the same reason.
  if not p_online then
    select count(*) into v_live
      from public.deliveries
     where partner_email = v_rider
       and state in ('claimed', 'arrived_at_restaurant',
                     'picked_up', 'arrived_at_customer');

    if v_live > 0 then
      raise exception
        'Finish or drop your % live job(s) before going offline.', v_live
        using errcode = 'P0001';
    end if;
  end if;

  update public.delivery_partners
     set is_online = p_online
   where email = v_rider;
end;
$$;

revoke execute on function public.set_rider_online(boolean) from public, anon;
grant execute on function public.set_rider_online(boolean) to authenticated;

-- 2 of 5 — the board.
create or replace function public.available_deliveries()
returns table(order_id text, restaurant_name text, restaurant_lat double precision,
              restaurant_lng double precision, deliver_to text, total integer,
              payment_method text, status text, route_km numeric, rider_pay integer,
              ready_by timestamp with time zone, placed_at timestamp with time zone)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base     integer;
  v_per_km   numeric(6,2);
  v_email    text;
  v_headroom integer;
  v_block    text;
begin
  v_email := public.delivery_partner_email();
  if v_email is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- New in 0080. Raised rather than returning nothing: an empty board reads as
  -- "no work right now", which is a different and much worse thing to tell
  -- somebody whose documents are sitting unverified in a queue.
  v_block := public.rider_work_block(v_email);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;

  -- How much more cash this rider may be holding. Computed once here rather
  -- than per row: it does not change while the query runs.
  v_headroom := public.rider_cash_cap() - public.rider_cash_in_hand(v_email);

  return query
    select o.id, r.name, r.latitude, r.longitude, o.delivery_to, o.total,
           o.payment_method, o.status,
           km.value,
           v_base + round(coalesce(km.value, 0) * v_per_km)::integer,
           o.ready_by, o.created_at
      from public.orders o
      join public.restaurants r on r.id = o.restaurant_id
      cross join lateral (
        select coalesce(
                 o.route_km,
                 public.delivery_distance_km(r.latitude, r.longitude,
                                             o.delivery_lat, o.delivery_lng)
               ) as value
      ) km
     where o.status in ('preparing', 'ready_for_pickup')
       and (o.payment_method <> 'cod' or o.total <= v_headroom)
       and not exists (
         select 1 from public.deliveries d
          where d.order_id = o.id and d.state <> 'cancelled'
       )
       and not exists (
         select 1 from public.delivery_offers off
          where off.order_id = o.id
            and off.state = 'offered'
            and off.expires_at > now()
       )
     order by (o.status = 'ready_for_pickup') desc, o.created_at;
end;
$$;

revoke execute on function public.available_deliveries() from public, anon;
grant execute on function public.available_deliveries() to authenticated;

-- 3 of 5 — the claim. Also covers `accept_offer`, which calls straight into it.
create or replace function public.claim_delivery(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_online   boolean;
  v_status   text;
  v_id       bigint;
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_d_lat    double precision;
  v_d_lng    double precision;
  v_route_km numeric(6,2);
  v_base     integer;
  v_per_km   numeric(6,2);
  v_distance numeric(6,2);
  v_method   text;
  v_total    integer;
  v_cash     integer;
  v_cap      integer;
  v_block    text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  -- New in 0080. Before the online check, because "your licence expired" is the
  -- more useful sentence of the two when both are true.
  v_block := public.rider_work_block(v_rider);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  select is_online into v_online
    from public.delivery_partners where email = v_rider;

  if not coalesce(v_online, false) then
    raise exception 'You are offline. Go online to take deliveries.'
      using errcode = 'P0001';
  end if;

  select o.status, r.latitude, r.longitude, o.delivery_lat, o.delivery_lng,
         o.route_km, o.payment_method, o.total
    into v_status, v_r_lat, v_r_lng, v_d_lat, v_d_lng,
         v_route_km, v_method, v_total
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found then
    raise exception 'That order no longer exists.' using errcode = 'P0001';
  end if;

  if v_status not in ('preparing', 'ready_for_pickup') then
    raise exception 'That order is no longer available.' using errcode = 'P0001';
  end if;

  if v_method = 'cod' then
    v_cash := public.rider_cash_in_hand(v_rider);
    v_cap  := public.rider_cash_cap();

    if v_cash + v_total > v_cap then
      raise exception
        'You''re holding ₹% in cash and this order collects ₹%, which is over the ₹% limit. Deposit what you''re carrying to take cash orders again.',
        v_cash, v_total, v_cap
        using errcode = 'P0001';
    end if;
  end if;

  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;

  -- The road distance if we have it; the straight line if we do not.
  v_distance := coalesce(
    v_route_km,
    public.delivery_distance_km(v_r_lat, v_r_lng, v_d_lat, v_d_lng)
  );

  insert into public.deliveries (
    order_id, partner_email,
    distance_km, pay_base, pay_per_km, rider_pay
  )
  values (
    p_order_id,
    v_rider,
    v_distance,
    v_base,
    v_per_km,
    v_base + round(coalesce(v_distance, 0) * v_per_km)::integer
  )
  on conflict do nothing
  returning id into v_id;

  -- The index decided it, not us. Write the codes only for the winner.
  if v_id is null then
    raise exception 'Another partner just took that one.' using errcode = 'P0001';
  end if;

  insert into public.delivery_codes (order_id, pickup_code, delivery_code)
  values (
    p_order_id,
    lpad((floor(random() * 10000))::integer::text, 4, '0'),
    lpad((floor(random() * 10000))::integer::text, 4, '0')
  )
  on conflict (order_id) do update
     set pickup_code       = excluded.pickup_code,
         delivery_code     = excluded.delivery_code,
         pickup_attempts   = 0,
         delivery_attempts = 0,
         updated_at        = now();
end;
$$;

revoke execute on function public.claim_delivery(text) from public, anon;
grant execute on function public.claim_delivery(text) to authenticated;

-- 4 of 5 — accepting an offer.
--
-- `claim_delivery` above would already refuse it, but the offer row would have
-- been marked `accepted` first and the job would be dead in the water: off the
-- board, nobody carrying it, and the sweeper unable to re-offer it because it is
-- no longer 'offered'. Checked before the update, not after.
create or replace function public.accept_offer(p_order_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider text;
  v_block text;
begin
  v_rider := public.delivery_partner_email();
  if v_rider is null then
    raise exception 'You are not a Zopiqnow delivery partner.'
      using errcode = 'P0001';
  end if;

  v_block := public.rider_work_block(v_rider);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'P0001';
  end if;

  update public.delivery_offers
     set state = 'accepted', responded_at = now()
   where order_id = p_order_id
     and partner_email = v_rider
     and state = 'offered'
     and expires_at > now();

  if not found then
    raise exception 'That offer has expired.' using errcode = 'P0001';
  end if;

  perform public.claim_delivery(p_order_id);
end;
$$;

revoke execute on function public.accept_offer(text) from public, anon;
grant execute on function public.accept_offer(text) to authenticated;

-- 5 of 5 — the dispatcher's candidate list.
--
-- The only change is one line in the `where` — everything else is 0057's
-- function verbatim. An unverified rider is not a candidate, so they are never
-- offered a job and never woken by a push for one.
create or replace function public.offer_delivery(p_order_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider    text;
  v_dist     numeric(6,2);
  v_r_lat    double precision;
  v_r_lng    double precision;
  v_name     text;
  v_status   text;
  v_pay      integer;
  v_base     integer;
  v_per_km   numeric(6,2);
  v_route    numeric(6,2);
  v_method   text;
  v_total    integer;
  v_cap      integer;
begin
  -- The order still has to be one that wants a rider. Checked here as well as
  -- in the sweeper because `decline_offer` calls straight into this function,
  -- and an order cancelled between the offer and the decline must not be
  -- handed to somebody else.
  select o.status, r.name, r.latitude, r.longitude,
         coalesce(
           o.route_km,
           public.delivery_distance_km(r.latitude, r.longitude,
                                       o.delivery_lat, o.delivery_lng)
         ),
         o.payment_method, o.total
    into v_status, v_name, v_r_lat, v_r_lng, v_route, v_method, v_total
    from public.orders o
    join public.restaurants r on r.id = o.restaurant_id
   where o.id = p_order_id;

  if not found or v_status not in ('preparing', 'ready_for_pickup') then
    return null;
  end if;

  if exists (
    select 1 from public.deliveries d
     where d.order_id = p_order_id and d.state <> 'cancelled'
  ) then
    return null;
  end if;

  -- What the job pays, at today's rate and this order's distance. Shown in the
  -- offer, and deliberately computed the same way `claim_delivery` will compute
  -- it a moment later — a fee quoted in the offer that differs from the fee on
  -- the accepted job is the single fastest way to lose a fleet's trust.
  select base_fee, per_km_fee into v_base, v_per_km
    from public.rider_pay_rates where id = 1;
  v_pay := v_base + round(coalesce(v_route, 0) * v_per_km)::integer;

  v_cap := public.rider_cash_cap();

  select cand.email, cand.km
    into v_rider, v_dist
    from (
      select p.email,
             public.delivery_distance_km(l.lat, l.lng, v_r_lat, v_r_lng) as km,
             (select count(*) from public.deliveries d
               where d.partner_email = p.email
                 and d.state in ('claimed', 'arrived_at_restaurant',
                                 'picked_up', 'arrived_at_customer')
             ) as live_jobs
        from public.delivery_partners p
        left join public.rider_locations l on l.partner_email = p.email
       where p.is_active
         and p.is_online
         -- New in 0080. A `sql` function over an indexed primary key, inlinable
         -- by the planner, on a fleet of hundreds — the same order of cost as
         -- the cash check that has sat beside it since 0076.
         and public.rider_is_verified(p.email)
         -- Evaluated per candidate, which is a sum over one rider's ledger rows
         -- on an indexed column, and only for a cash order. A fleet is hundreds
         -- of rows, not millions.
         and (v_method <> 'cod'
              or public.rider_cash_in_hand(p.email) + v_total <= v_cap)
    ) cand
   where cand.live_jobs < 3
     and not exists (
       select 1 from public.delivery_offers o
        where o.order_id = p_order_id and o.partner_email = cand.email
     )
     and not exists (
       select 1 from public.delivery_offers o
        where o.partner_email = cand.email
          and o.state = 'offered'
          and o.expires_at > now()
     )
   -- Idle riders first, then nearest. `nulls last` is what keeps a rider whose
   -- app has never reported a position from being treated as zero kilometres
   -- away and winning every job in the city.
   order by cand.live_jobs, cand.km nulls last, cand.email
   limit 1;

  if v_rider is null then
    return null;
  end if;

  insert into public.delivery_offers
    (order_id, partner_email, distance_km, expires_at)
  values
    (p_order_id, v_rider, v_dist, now() + public.delivery_offer_window())
  -- Two sweeper ticks overlapping, or a decline racing the sweep. The index is
  -- what decides it; losing simply means somebody else's offer is already live.
  on conflict do nothing;

  if not found then
    return null;
  end if;

  -- The push. `data` carries the numbers so the sheet can draw itself from the
  -- notification alone — a rider woken by this is on a lock screen, and a sheet
  -- that has to round-trip before it can show a countdown has already spent the
  -- seconds it is counting.
  begin
    insert into public.notifications
      (audience, partner_email, kind, title, body, order_id, data)
    values
      ('rider', v_rider, 'job_offer',
       'New delivery — ₹' || v_pay,
       'Pick up from ' || v_name ||
         case when v_dist is null then ''
              else ' · ' || v_dist || ' km away' end,
       p_order_id,
       jsonb_build_object(
         'order_id',    p_order_id,
         'restaurant',  v_name,
         'pay',         v_pay,
         'route_km',    v_route,
         'to_pickup_km', v_dist,
         'expires_at',  to_char(
                          (now() + public.delivery_offer_window())
                            at time zone 'UTC',
                          'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                        )
       ));
  exception when others then
    -- 0021's rule, kept: the offer is the event, the push is a courtesy on top
    -- of it. A rider who missed the buzz still finds the offer in the app.
    null;
  end;

  return v_rider;
end;
$$;

revoke execute on function public.offer_delivery(text) from public, anon;
grant execute on function public.offer_delivery(text) to authenticated;

-- ---------------------------------------------------------------------------
-- The console's side.
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_rider_kyc(p_email text)
returns table(
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
  blocked_reason     text
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
           public.rider_work_block(p.email)
      from public.delivery_partners p
      left join public.rider_legal l on l.partner_email = p.email
     where p.email = v_email;
end;
$$;

revoke execute on function public.admin_get_rider_kyc(text) from public, anon;
grant execute on function public.admin_get_rider_kyc(text) to authenticated;

-- Saving a document sends the rider back to 'pending'.
--
-- This is the part that makes the workflow mean anything. If an admin could
-- swap the licence scan on a verified rider without the status moving, then
-- "verified" would record that *something* was once approved rather than that
-- what is on file now was. Every edit is re-reviewed, including the admin's own
-- typo fix — which is a small cost paid to keep the word honest.
create or replace function public.admin_set_rider_kyc(p_email text, p_kyc jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_kind  text;
  v_num   text;
  v_plate text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));
  if not exists (select 1 from public.delivery_partners where email = v_email) then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;

  v_kind  := nullif(trim(coalesce(p_kyc ->> 'id_proof_kind', '')), '');
  v_num   := nullif(upper(trim(coalesce(p_kyc ->> 'id_proof_number', ''))), '');
  v_plate := nullif(upper(regexp_replace(coalesce(p_kyc ->> 'vehicle_number', ''), '[^A-Za-z0-9]', '', 'g')), '');

  -- The sentences, rather than letting a check constraint answer. A constraint
  -- violation reaches the console as `23514` and a stack trace; an admin holding
  -- a scan in their hand needs to be told which box is wrong.
  if v_num is not null and v_kind is null then
    raise exception 'Say whether that is an Aadhaar or a PAN.' using errcode = 'P0001';
  end if;
  if v_kind = 'aadhaar' and v_num is not null and v_num !~ '^[0-9]{12}$' then
    raise exception 'An Aadhaar number is 12 digits.' using errcode = 'P0001';
  end if;
  if v_kind = 'pan' and v_num is not null and v_num !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' then
    raise exception 'That PAN doesn''t look right.' using errcode = 'P0001';
  end if;
  if v_plate is not null and v_plate !~ '^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}$' then
    raise exception 'That registration number doesn''t look right.' using errcode = 'P0001';
  end if;

  insert into public.rider_legal (
    partner_email,
    licence_number, licence_expiry, licence_doc_path,
    insurance_policy, insurance_expiry, insurance_doc_path,
    id_proof_kind, id_proof_number, id_proof_doc_path,
    vehicle_number, rc_doc_path,
    status, rejected_reason, reviewed_at, reviewed_by, updated_at
  ) values (
    v_email,
    nullif(upper(trim(coalesce(p_kyc ->> 'licence_number', ''))), ''),
    (p_kyc ->> 'licence_expiry')::date,
    nullif(trim(coalesce(p_kyc ->> 'licence_doc_path', '')), ''),
    nullif(upper(trim(coalesce(p_kyc ->> 'insurance_policy', ''))), ''),
    (p_kyc ->> 'insurance_expiry')::date,
    nullif(trim(coalesce(p_kyc ->> 'insurance_doc_path', '')), ''),
    v_kind, v_num,
    nullif(trim(coalesce(p_kyc ->> 'id_proof_doc_path', '')), ''),
    v_plate,
    nullif(trim(coalesce(p_kyc ->> 'rc_doc_path', '')), ''),
    'pending', null, null, null, now()
  )
  on conflict (partner_email) do update set
    licence_number     = excluded.licence_number,
    licence_expiry     = excluded.licence_expiry,
    licence_doc_path   = excluded.licence_doc_path,
    insurance_policy   = excluded.insurance_policy,
    insurance_expiry   = excluded.insurance_expiry,
    insurance_doc_path = excluded.insurance_doc_path,
    id_proof_kind      = excluded.id_proof_kind,
    id_proof_number    = excluded.id_proof_number,
    id_proof_doc_path  = excluded.id_proof_doc_path,
    vehicle_number     = excluded.vehicle_number,
    rc_doc_path        = excluded.rc_doc_path,
    status             = 'pending',
    rejected_reason    = null,
    reviewed_at        = null,
    reviewed_by        = null,
    updated_at         = now();
end;
$$;

revoke execute on function public.admin_set_rider_kyc(text, jsonb) from public, anon;
grant execute on function public.admin_set_rider_kyc(text, jsonb) to authenticated;

-- Verify, or reject with a reason.
--
-- The completeness check lives here rather than in the console, because the
-- console is a screen and this is the rule. An admin cannot verify a rider whose
-- licence scan is missing however many times they click the button.
create or replace function public.admin_review_rider_kyc(
  p_email text, p_verified boolean, p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text;
  v_vehicle text;
  v_legal   public.rider_legal%rowtype;
  v_admin   text;
begin
  perform public.assert_admin();

  v_email := lower(trim(p_email));
  v_admin := lower(auth.jwt() ->> 'email');

  select vehicle into v_vehicle
    from public.delivery_partners where email = v_email;
  if not found then
    raise exception '% is not a rider.', v_email using errcode = 'P0001';
  end if;

  select * into v_legal
    from public.rider_legal where partner_email = v_email;
  if not found then
    raise exception 'Nothing has been filed for this rider yet.' using errcode = 'P0001';
  end if;

  if p_verified then
    -- Identity is asked of everybody, including a bicycle rider.
    if v_legal.id_proof_number is null or v_legal.id_proof_doc_path is null then
      raise exception 'An ID proof and its scan are needed before verifying.'
        using errcode = 'P0001';
    end if;

    if v_vehicle <> 'bicycle' then
      if v_legal.licence_number is null or v_legal.licence_expiry is null
         or v_legal.licence_doc_path is null then
        raise exception 'A licence number, its expiry and its scan are needed before verifying.'
          using errcode = 'P0001';
      end if;
      if v_legal.insurance_policy is null or v_legal.insurance_expiry is null
         or v_legal.insurance_doc_path is null then
        raise exception 'An insurance policy, its expiry and its scan are needed before verifying.'
          using errcode = 'P0001';
      end if;
      if v_legal.vehicle_number is null or v_legal.rc_doc_path is null then
        raise exception 'A registration number and the RC scan are needed before verifying.'
          using errcode = 'P0001';
      end if;

      -- Verifying something already expired would put a rider on the road today
      -- and take them off it again on the next read, which looks like a bug and
      -- is worse than a refusal.
      if v_legal.licence_expiry < current_date then
        raise exception 'That licence expired on %.',
          to_char(v_legal.licence_expiry, 'DD Mon YYYY') using errcode = 'P0001';
      end if;
      if v_legal.insurance_expiry < current_date then
        raise exception 'That insurance expired on %.',
          to_char(v_legal.insurance_expiry, 'DD Mon YYYY') using errcode = 'P0001';
      end if;
    end if;

    update public.rider_legal
       set status = 'verified', rejected_reason = null,
           reviewed_at = now(), reviewed_by = v_admin
     where partner_email = v_email;
  else
    if trim(coalesce(p_reason, '')) = '' then
      raise exception 'Say why, so the rider knows what to fix.' using errcode = 'P0001';
    end if;

    update public.rider_legal
       set status = 'rejected', rejected_reason = trim(p_reason),
           reviewed_at = now(), reviewed_by = v_admin
     where partner_email = v_email;
  end if;

  -- Told, not left to discover it by tapping Go online. Wrapped, because 0021's
  -- rule holds here too: the decision is the event and the notification is a
  -- courtesy on top of it.
  begin
    insert into public.notifications (audience, partner_email, kind, title, body)
    values ('rider', v_email, 'account',
            case when p_verified then 'You''re verified' else 'Documents not accepted' end,
            case when p_verified
                 then 'Your documents have been checked. You can go online and start taking deliveries.'
                 else trim(p_reason) end);
  exception when others then
    null;
  end;
end;
$$;

revoke execute on function public.admin_review_rider_kyc(text, boolean, text) from public, anon;
grant execute on function public.admin_review_rider_kyc(text, boolean, text) to authenticated;

-- The list grows two columns, so the console can show the queue without asking
-- per rider. Dropped rather than replaced: the return type changes, and
-- `create or replace` refuses that.
drop function if exists public.admin_list_riders();

create function public.admin_list_riders()
returns table(email text, name text, phone text, vehicle text, is_active boolean,
              created_at timestamp with time zone, live_order_id text,
              delivered_count integer, kyc_status text, kyc_blocked boolean)
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
           not public.rider_is_verified(p.email)
      from public.delivery_partners p
      left join public.rider_legal l on l.partner_email = p.email
     -- Whoever needs attention first: blocked before clear, then paused
     -- accounts, then oldest.
     order by not public.rider_is_verified(p.email) desc,
              p.is_active desc, p.created_at;
end;
$$;

revoke execute on function public.admin_list_riders() from public, anon;
grant execute on function public.admin_list_riders() to authenticated;
