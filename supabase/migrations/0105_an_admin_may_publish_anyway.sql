-- ---------------------------------------------------------------------------
-- 0105 — an admin may publish anyway.
-- ---------------------------------------------------------------------------
-- 0030's gate refuses to publish a restaurant until eleven things are true, and
-- it raises at the first one that is not. That is the right default and it is
-- now not the only path: the operator asked to be able to publish a kitchen
-- whose paperwork is not finished, on their own judgement.
--
-- **This was asked for with the consequences stated, and they are real.** Two
-- of the eleven checks are not paperwork:
--
--   * *at least one dish customers can order* — publish without it and a
--     customer opens a restaurant with an empty menu, which reads as a broken
--     app rather than as a kitchen that has not finished onboarding;
--   * *a valid FSSAI licence* — an Indian food aggregator listing a kitchen
--     with no licence on file is a legal exposure, not an untidy record (audit
--     LEG-001).
--
-- The decision was to waive all of them and let the admin judge. So the gate
-- still refuses by default, and forcing is a separate, deliberate argument
-- rather than a check that quietly got weaker.
--
-- **What forcing does not do is happen quietly.** Every forced publish writes
-- its own row to `admin_actions` (0092) naming *which* checks were outstanding
-- at the moment it went live, plus whatever the admin typed as a reason. The
-- `is_active` trigger from 0092 already records that the row changed; this
-- records why, and what was known at the time — which is the question anybody
-- will actually ask afterwards.
--
-- **Dropped and recreated rather than overloaded.** Adding defaulted arguments
-- to an existing function leaves the old `(text)` signature in place and makes
-- every one-argument call ambiguous — the trap this schema has hit before. The
-- old signature goes first, and the grant is restated because dropping takes
-- privileges with it.
drop function if exists public.admin_publish_restaurant(text);

create or replace function public.admin_publish_restaurant(
  p_id     text,
  p_force  boolean default false,
  p_reason text    default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r        public.restaurants%rowtype;
  v_legal  public.restaurant_legal%rowtype;
  v_bank   public.restaurant_bank_accounts%rowtype;
  v_missing text[] := '{}';
begin
  perform public.assert_admin();

  select * into r from public.restaurants where id = p_id;
  if not found then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  select * into v_legal from public.restaurant_legal where restaurant_id = p_id;
  select * into v_bank  from public.restaurant_bank_accounts where restaurant_id = p_id;

  -- Every condition, gathered rather than raised at. The sentences are 0030's,
  -- word for word, because they are what the console shows and an admin has
  -- read them before.
  --
  -- 0044's cost-for-two and prep-time checks stood here. Removed in 0101: the
  -- admin is no longer asked for either, so requiring them would make every
  -- restaurant unpublishable.
  if coalesce(r.image_url, '') = '' then
    v_missing := array_append(v_missing, 'Add a cover photo before publishing.');
  end if;
  if r.address_line is null or r.city is null or r.pincode is null then
    v_missing := array_append(v_missing, 'Add the full address before publishing.');
  end if;
  if r.latitude is null or r.longitude is null then
    v_missing := array_append(v_missing, 'Set the map location before publishing — riders are paid by distance from the kitchen.');
  end if;
  if r.contact_phone is null then
    v_missing := array_append(v_missing, 'Add a contact phone number before publishing.');
  end if;
  if v_legal.fssai_number is null then
    v_missing := array_append(v_missing, 'Add the FSSAI licence before publishing.');
  end if;
  if v_legal.fssai_expiry is null
     or v_legal.fssai_expiry < (now() at time zone 'Asia/Kolkata')::date then
    v_missing := array_append(v_missing, 'That FSSAI licence has expired. Publishing needs a valid one.');
  end if;
  if v_legal.pan_number is null then
    v_missing := array_append(v_missing, 'Add the PAN before publishing.');
  end if;
  if v_bank.account_number is null or v_bank.ifsc is null then
    v_missing := array_append(v_missing, 'Add the bank account before publishing — settlements need somewhere to pay.');
  end if;
  if not exists (
    select 1 from public.restaurant_staff s
     where s.restaurant_id = p_id and s.role = 'owner'
  ) then
    v_missing := array_append(v_missing, 'Add the owner''s email before publishing — nobody can run this kitchen without it.');
  end if;
  if not exists (
    select 1 from public.restaurant_hours h where h.restaurant_id = p_id
  ) then
    v_missing := array_append(v_missing, 'Set the opening hours before publishing.');
  end if;
  if not exists (
    select 1 from public.menu_items m
     where m.restaurant_id = p_id and m.is_available and m.category_available
  ) then
    v_missing := array_append(v_missing, 'Add at least one dish before publishing.');
  end if;

  -- The default path, unchanged: the first outstanding sentence, raised. The
  -- console has always shown exactly this and shows it still.
  if array_length(v_missing, 1) is not null and not coalesce(p_force, false) then
    raise exception '%', v_missing[1] using errcode = 'P0001';
  end if;

  update public.restaurants
     set is_active = true,
         published_at = coalesce(published_at, now())
   where id = p_id;

  -- Only a publish that skipped something is worth a row of its own. A forced
  -- publish of a restaurant that was complete anyway is an ordinary publish.
  if array_length(v_missing, 1) is not null then
    insert into public.admin_actions
      (actor_email, action, target_type, target_id, detail)
    values (
      coalesce(
        lower(nullif(trim(coalesce(auth.jwt() ->> 'email', '')), '')),
        'system'
      ),
      'publish_forced',
      'restaurants',
      p_id,
      jsonb_build_object(
        'missing', to_jsonb(v_missing),
        'reason',  nullif(trim(coalesce(p_reason, '')), ''),
        'name',    r.name
      )
    );
  end if;
end;
$$;

revoke execute on function public.admin_publish_restaurant(text, boolean, text) from public;
grant execute on function public.admin_publish_restaurant(text, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The two standing release checks (0087, 0089) must still return zero rows, and
-- there must be exactly one `admin_publish_restaurant` when this is done.
-- ---------------------------------------------------------------------------
