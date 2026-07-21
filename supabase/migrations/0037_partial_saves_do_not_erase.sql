-- Step 11, migration 37: not sending a field must not mean deleting it.
--
-- Found while verifying the bank step. `admin_set_bank` was written as a plain
-- upsert: every column in the payload is written, and a key that is absent from
-- the payload arrives as SQL null and is written *as* null. So this —
--
--     admin_set_bank(id, '{"bank_name": "ICICI"}')
--
-- — does not change the bank name. It changes the bank name and silently erases
-- the account number, the IFSC, and the account holder.
--
-- The console does exactly this. The bank step deliberately leaves the account
-- number field empty unless the admin means to replace it (the stored number is
-- never sent back to the browser — only its last four digits), and omits the key
-- when it is empty. Correct behaviour on the client, destructive on the server:
-- an admin correcting a typo in "ICICI Bank" would have wiped the account we pay
-- settlements to, and the only sign would be a publish gate that suddenly failed.
--
-- `admin_update_restaurant` got this right from the start (0030) by asking
-- `p_profile ? 'key'` — does the payload *contain* this key — rather than reading
-- its value and hoping. The distinction is the whole thing: **absent** means leave
-- it, **present and empty** means clear it. Both are legitimate and they are not
-- the same request. This migration brings the other two setters in line.
--
-- `admin_set_hours` is deliberately left alone. Its payload is the entire week by
-- design (0030), because a schedule saved a day at a time is how a Tuesday gets
-- left behind — there, replacing everything is the point.

-- ---------------------------------------------------------------------------
-- The bank account.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_bank(p_id text, p_bank jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account text;
  v_ifsc    text;
  v_exists  boolean;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;

  -- A null payload is a caller mistake, not an instruction to erase the row. It
  -- used to be the latter.
  if p_bank is null then
    raise exception 'No bank details were sent.' using errcode = 'P0001';
  end if;

  v_account := nullif(trim(coalesce(p_bank ->> 'account_number', '')), '');
  v_ifsc    := nullif(upper(trim(coalesce(p_bank ->> 'ifsc', ''))), '');

  if p_bank ? 'account_number' and v_account is not null
     and v_account !~ '^[0-9]{9,18}$' then
    raise exception 'An account number is 9 to 18 digits.' using errcode = 'P0001';
  end if;
  if p_bank ? 'ifsc' and v_ifsc is not null
     and v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$' then
    raise exception 'That IFSC code doesn''t look right.' using errcode = 'P0001';
  end if;

  select true into v_exists
    from public.restaurant_bank_accounts where restaurant_id = p_id;

  if v_exists is null then
    insert into public.restaurant_bank_accounts (
      restaurant_id, account_holder, account_number, ifsc, bank_name, updated_at
    ) values (
      p_id,
      nullif(trim(coalesce(p_bank ->> 'account_holder', '')), ''),
      v_account, v_ifsc,
      nullif(trim(coalesce(p_bank ->> 'bank_name', '')), ''),
      now()
    );
    return;
  end if;

  update public.restaurant_bank_accounts set
    account_holder = case when p_bank ? 'account_holder'
      then nullif(trim(coalesce(p_bank ->> 'account_holder', '')), '')
      else account_holder end,
    account_number = case when p_bank ? 'account_number'
      then v_account else account_number end,
    ifsc = case when p_bank ? 'ifsc' then v_ifsc else ifsc end,
    bank_name = case when p_bank ? 'bank_name'
      then nullif(trim(coalesce(p_bank ->> 'bank_name', '')), '')
      else bank_name end,
    -- Verification is a claim about a *specific* account. Writing a new number
    -- must retire it — somebody checked that account was real, not this one — but
    -- a payload that leaves the number alone leaves the flag alone too.
    verified = case
      when p_bank ? 'verified' then coalesce((p_bank ->> 'verified')::boolean, false)
      when p_bank ? 'account_number' and v_account is distinct from account_number
        then false
      else verified end,
    updated_at = now()
  where restaurant_id = p_id;
end;
$$;

revoke execute on function public.admin_set_bank(text, jsonb) from public;
grant execute on function public.admin_set_bank(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- The papers, for the same reason.
-- ---------------------------------------------------------------------------
-- Less dangerous today, because the legal step always sends every field it owns —
-- but only by accident of how that form is written, and a future screen that
-- saves "just the GST number" would erase an FSSAI licence exactly as readily.
create or replace function public.admin_set_legal(p_id text, p_legal jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.restaurants where id = p_id) then
    raise exception 'No such restaurant.' using errcode = 'P0001';
  end if;
  if p_legal is null then
    raise exception 'No licence details were sent.' using errcode = 'P0001';
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

  select true into v_exists
    from public.restaurant_legal where restaurant_id = p_id;

  if v_exists is null then
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
    );
    return;
  end if;

  update public.restaurant_legal set
    fssai_number = case when p_legal ? 'fssai_number'
      then nullif(trim(coalesce(p_legal ->> 'fssai_number', '')), '')
      else fssai_number end,
    fssai_expiry = case when p_legal ? 'fssai_expiry'
      then (p_legal ->> 'fssai_expiry')::date else fssai_expiry end,
    fssai_doc_path = case when p_legal ? 'fssai_doc_path'
      then nullif(trim(coalesce(p_legal ->> 'fssai_doc_path', '')), '')
      else fssai_doc_path end,
    gst_number = case when p_legal ? 'gst_number'
      then nullif(upper(trim(coalesce(p_legal ->> 'gst_number', ''))), '')
      else gst_number end,
    pan_number = case when p_legal ? 'pan_number'
      then nullif(upper(trim(coalesce(p_legal ->> 'pan_number', ''))), '')
      else pan_number end,
    pan_doc_path = case when p_legal ? 'pan_doc_path'
      then nullif(trim(coalesce(p_legal ->> 'pan_doc_path', '')), '')
      else pan_doc_path end,
    updated_at = now()
  where restaurant_id = p_id;
end;
$$;

revoke execute on function public.admin_set_legal(text, jsonb) from public;
grant execute on function public.admin_set_legal(text, jsonb) to authenticated;
